import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/app_colors.dart' show eventIsCancelled;
import '../../../core/services/notif_read_store.dart';
import '../../../core/services/student_notif_prefs.dart';
import '../../../core/services/supabase_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The student's feed — announcements, their registrations and the
// notifications built from both. The Home bell number and the Notifications
// screen load it through the same code, so they always agree.
// ─────────────────────────────────────────────────────────────────────────────

enum StudentNotifType {
  announcement,
  checkIn,
  selfieRequired,
  photoSubmitted,
  rejected,
  eventCancelled,
  eventUpdated,
}

class StudentNotif {
  final String           id;
  final StudentNotifType type;
  final String           title;
  final String           preview;   // truncated for list card
  final String           fullBody;  // full text for detail sheet
  final DateTime         time;
  final String?          orgName;

  const StudentNotif({
    required this.id,
    required this.type,
    required this.title,
    required this.preview,
    required this.fullBody,
    required this.time,
    this.orgName,
  });

  bool get isRead => NotifReadStore.isRead(id);
}

class StudentFeed {
  /// Newest first; each row carries its author's name under '_org'.
  final List<Map<String, dynamic>> announcements;
  /// The student's registrations, newest first, with their event under 'events'.
  final List<Map<String, dynamic>> registrations;
  /// Newest first, notification preferences applied.
  final List<StudentNotif> notifications;

  const StudentFeed({
    required this.announcements,
    required this.registrations,
    required this.notifications,
  });

  static const empty =
      StudentFeed(announcements: [], registrations: [], notifications: []);
}

class StudentNotifications {
  StudentNotifications._();

  static const announcementLimit = 50;

  static Future<StudentFeed> load() async {
    final client = SupabaseService.client;
    final user   = client.auth.currentUser;
    if (user == null) return StudentFeed.empty;

    final annFuture = client
        .from('announcements')
        .select('id, title, message, created_by, created_at')
        .order('created_at', ascending: false)
        .limit(announcementLimit);
    // events(*) — not named columns — so this still works before the
    // cancellation / change-request migrations add their columns.
    final regFuture = client
        .from('registrations')
        .select('*, events(*)')
        .eq('student_user_id', user.id)
        .order('registered_at', ascending: false);
    final prefsFuture = StudentNotifPrefs.disabled(user.id);

    final annRows = List<Map<String, dynamic>>.from(await annFuture as List);
    final regRows = List<Map<String, dynamic>>.from(await regFuture as List);
    final disabled = await prefsFuture;
    final orgNames = await _authorNames(annRows);

    return StudentFeed(
      announcements: [
        for (final a in annRows)
          {...a, '_org': orgNames[a['created_by'] as String? ?? ''] ?? '—'},
      ],
      registrations: regRows,
      notifications: build(
        announcements: annRows,
        registrations: regRows,
        orgNames: orgNames,
        disabledCategories: disabled,
      ),
    );
  }

  // Students can't read the organizers table; organizer_directory exposes
  // just names (202610140001_organizer_directory.sql).
  static Future<Map<String, String>> _authorNames(
      List<Map<String, dynamic>> announcements) async {
    final uids = announcements
        .map((a) => a['created_by'] as String?)
        .whereType<String>()
        .toSet()
        .toList();
    if (uids.isEmpty) return {};
    try {
      final rows = List<Map<String, dynamic>>.from(
        await SupabaseService.client
            .from('organizer_directory')
            .select('user_id, full_name')
            .in_('user_id', uids),
      );
      return {
        for (final o in rows)
          o['user_id'] as String: o['full_name'] as String? ?? '—',
      };
    } catch (e) {
      debugPrint('Announcement author lookup failed: $e');
      return {};
    }
  }

  /// The notification list from already-loaded rows. Selfie requests,
  /// submitted photos, declines, cancellations and schedule changes are
  /// always included; announcements and check-in confirmations follow the
  /// student's preferences.
  static List<StudentNotif> build({
    required List<Map<String, dynamic>> announcements,
    required List<Map<String, dynamic>> registrations,
    Map<String, String> orgNames = const {},
    Set<String> disabledCategories = const {},
  }) {
    final items = <StudentNotif>[];

    // ── Announcements ─────────────────────────────────────────────────────
    for (final ann in announcements) {
      final id      = ann['id']?.toString() ?? '';
      final raw     = ann['created_at'] as String?;
      final message = ann['message'] as String? ?? '';
      items.add(StudentNotif(
        id:       'ann_$id',
        type:     StudentNotifType.announcement,
        title:    ann['title'] as String? ?? '—',
        preview:  _preview(message),
        fullBody: message,
        time:     raw != null
            ? (DateTime.tryParse(raw)?.toLocal() ?? DateTime.now())
            : DateTime.now(),
        orgName:  orgNames[ann['created_by'] as String? ?? ''],
      ));
    }

    // ── Cancelled events the student registered for ──────────────────────
    // One per event; always shown (like selfie requests — it's something
    // the student needs to know, not an optional category).
    final cancelledSeen = <String>{};
    for (final reg in registrations) {
      final ev      = reg['events'] as Map<String, dynamic>?;
      final eventId = reg['event_id'] as String?;
      if (ev == null || eventId == null || !eventIsCancelled(ev)) continue;
      if (!cancelledSeen.add(eventId)) continue;
      final title  = ev['title'] as String? ?? reg['event_title'] as String? ?? 'an event';
      final reason = (ev['cancel_reason'] as String?)?.trim() ?? '';
      final body = reason.isNotEmpty
          ? '"$title" has been cancelled by the organizer.\n\nReason: $reason'
          : '"$title" has been cancelled by the organizer.';
      final at = ev['cancelled_at'] as String? ?? ev['updated_at'] as String?;
      items.add(StudentNotif(
        id:       cancelledNotifId(eventId),
        type:     StudentNotifType.eventCancelled,
        title:    'Event cancelled',
        preview:  _preview(body.replaceAll('\n\n', ' ')),
        fullBody: body,
        time:     DateTime.tryParse(at ?? '')?.toLocal() ?? DateTime.now(),
      ));
    }

    // ── Date / time / venue changed (admin-approved change request) ─────
    final updatedSeen = <String>{};
    for (final reg in registrations) {
      final id = updatedNotifIdFor(reg);
      if (id == null || !updatedSeen.add(id)) continue;
      final ev    = reg['events'] as Map;
      final title = ev['title'] as String? ?? reg['event_title'] as String? ?? 'An event';
      final when  = _fmtEventStart(ev);
      final venue = (ev['location'] as String?)?.trim() ?? '';
      final now   = [when, venue].where((s) => s.isNotEmpty).join(' · ');
      final was   = (ev['schedule_change_note'] as String?)?.trim() ?? '';
      final head  = '"$title" moved to $now';
      final body  = [
        head,
        if (was.isNotEmpty) 'Previously: $was',
        'Your registration still stands — no need to register again.',
      ].join('\n\n');
      items.add(StudentNotif(
        id:       id,
        type:     StudentNotifType.eventUpdated,
        title:    'Event updated',
        preview:  _preview(head),
        fullBody: body,
        time:     DateTime.tryParse(ev['schedule_changed_at'] as String)?.toLocal()
            ?? DateTime.now(),
      ));
    }

    // ── Registration status changes ───────────────────────────────────────
    for (final reg in registrations) {
      final rid     = reg['id']             as String? ?? '';
      final status  = reg['status']         as String? ?? '';
      // The event's current name — the registration keeps the one from sign-up.
      final evTitle = ((reg['events'] as Map?)?['title'] as String?)?.trim();
      final event   = evTitle != null && evTitle.isNotEmpty
          ? evTitle
          : reg['event_title'] as String? ?? 'an event';
      // When the organizer asked for the photo, the student sent it or the
      // organizer decided: status_changed_at (set by the database, migration
      // 202610270002). Registrations from before that keep the check-in or
      // registration time.
      final rawChanged = reg['status_changed_at'] as String?;
      final rawCi   = reg['checked_in_at']  as String?;
      final rawReg  = reg['registered_at']  as String?;
      final timeRaw = rawChanged ?? rawCi ?? rawReg ?? '';

      StudentNotifType notifType;
      String title, body;

      if (status == 'checked_in') {
        notifType = StudentNotifType.checkIn;
        title     = 'Check-in confirmed! ✓';
        body      = 'You\'ve been successfully checked in to "$event". Enjoy the event!';
      } else if (status == 'photo_required') {
        notifType = StudentNotifType.selfieRequired;
        title     = 'Selfie required';
        body      = 'Your organizer needs a selfie to verify your attendance at "$event".';
      } else if (status == 'photo_submitted') {
        notifType = StudentNotifType.photoSubmitted;
        title     = 'Photo received';
        body      = 'Your selfie for "$event" was submitted — awaiting organizer confirmation.';
      } else if (status == 'rejected') {
        final reason = reg['rejection_reason'] as String?;
        notifType = StudentNotifType.rejected;
        title     = 'Registration declined';
        body      = reason != null && reason.isNotEmpty
            ? 'Your registration for "$event" was declined: $reason'
            : 'Your registration for "$event" was not approved by the organizer.';
      } else {
        continue;
      }

      items.add(StudentNotif(
        id:       'reg_${rid}_$status',
        type:     notifType,
        title:    title,
        preview:  body,
        fullBody: body,
        time:     timeRaw.isNotEmpty
            ? (DateTime.tryParse(timeRaw)?.toLocal() ?? DateTime.now())
            : DateTime.now(),
      ));
    }

    // Sort newest first
    items.sort((a, b) => b.time.compareTo(a.time));

    // Respect per-user preferences (Profile → Notifications). Verification
    // items (selfie required / photo submitted) are never filtered.
    if (disabledCategories.isNotEmpty) {
      items.removeWhere((n) =>
          (disabledCategories.contains(StudentNotifPrefs.announcements) &&
              n.type == StudentNotifType.announcement) ||
          (disabledCategories.contains(StudentNotifPrefs.checkins) &&
              n.type == StudentNotifType.checkIn));
    }
    return items;
  }
}

String _preview(String s) =>
    s.length > 110 ? '${s.substring(0, 110)}…' : s;

const _kMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Oct 25, 1:00 PM" from an event's date + start time — same shape as the
/// schedule_change_note the database writes for the previous schedule.
String _fmtEventStart(Map ev) {
  final d = DateTime.tryParse(ev['event_date'] as String? ?? '');
  if (d == null) return '';
  var out = '${_kMonths[d.month - 1]} ${d.day}';
  final parts = (ev['start_time'] as String? ?? '').split(':');
  final h = int.tryParse(parts.first);
  final m = parts.length > 1 ? int.tryParse(parts[1]) : null;
  if (h != null && m != null) {
    out += ', ${h % 12 == 0 ? 12 : h % 12}:${m.toString().padLeft(2, '0')} ${h >= 12 ? 'PM' : 'AM'}';
  }
  return out;
}

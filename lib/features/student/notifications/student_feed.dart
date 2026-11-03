import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/app_colors.dart' show eventIsCancelled;
import '../../../core/services/notif_read_store.dart';
import '../../../core/services/student_notif_prefs.dart';
import '../../../core/services/supabase_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The student's feed — announcements, their registrations and the
// notifications built from the registrations. Announcements are shown on Home
// (and its See all page), so the bell only lists what happened to the
// student's own events; Home loads both through this code.
// ─────────────────────────────────────────────────────────────────────────────

enum StudentNotifType {
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
  final String           body;
  final DateTime         time;

  const StudentNotif({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.time,
  });

  bool get isRead => NotifReadStore.isRead(id);
}

class StudentFeed {
  /// Newest first; each row carries its author's name under '_org'.
  final List<Map<String, dynamic>> announcements;
  /// The student's registrations, newest first, with their event under 'events'.
  final List<Map<String, dynamic>> registrations;
  /// The bell's list: newest first, notification preferences applied.
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

    final annFuture = announcements();
    // events(*) — not named columns — so this still works before the
    // cancellation / change-request migrations add their columns.
    final regFuture = client
        .from('registrations')
        .select('*, events(*)')
        .eq('student_user_id', user.id)
        .order('registered_at', ascending: false);
    final prefsFuture = StudentNotifPrefs.disabled(user.id);

    final regRows = List<Map<String, dynamic>>.from(await regFuture as List);
    final disabled = await prefsFuture;

    return StudentFeed(
      announcements: await annFuture,
      registrations: regRows,
      notifications: build(
        registrations: regRows,
        disabledCategories: disabled,
      ),
    );
  }

  /// The latest announcements, newest first, each with its author's name
  /// under '_org'.
  static Future<List<Map<String, dynamic>>> announcements() async {
    final rows = List<Map<String, dynamic>>.from(await SupabaseService.client
        .from('announcements')
        .select('id, title, message, created_by, created_at')
        .order('created_at', ascending: false)
        .limit(announcementLimit) as List);
    final orgNames = await _authorNames(rows);
    return [
      for (final a in rows)
        {...a, '_org': orgNames[a['created_by'] as String? ?? ''] ?? '—'},
    ];
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

  /// The bell's list from already-loaded registrations. Selfie requests,
  /// submitted photos, declines, cancellations and schedule changes are
  /// always included; check-in confirmations follow the student's
  /// preferences. Announcements aren't in it — they're on Home.
  static List<StudentNotif> build({
    required List<Map<String, dynamic>> registrations,
    Set<String> disabledCategories = const {},
  }) {
    final items = <StudentNotif>[];

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
        id:    cancelledNotifId(eventId),
        type:  StudentNotifType.eventCancelled,
        title: 'Event cancelled',
        body:  body,
        time:  DateTime.tryParse(at ?? '')?.toLocal() ?? DateTime.now(),
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
        id:    id,
        type:  StudentNotifType.eventUpdated,
        title: 'Event updated',
        body:  body,
        time:  DateTime.tryParse(ev['schedule_changed_at'] as String)?.toLocal()
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
        id:    'reg_${rid}_$status',
        type:  notifType,
        title: title,
        body:  body,
        time:  timeRaw.isNotEmpty
            ? (DateTime.tryParse(timeRaw)?.toLocal() ?? DateTime.now())
            : DateTime.now(),
      ));
    }

    // Sort newest first
    items.sort((a, b) => b.time.compareTo(a.time));

    // Respect per-user preferences (Profile → Notifications). Verification
    // items (selfie required / photo submitted) are never filtered.
    if (disabledCategories.contains(StudentNotifPrefs.checkins)) {
      items.removeWhere((n) => n.type == StudentNotifType.checkIn);
    }
    return items;
  }
}

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

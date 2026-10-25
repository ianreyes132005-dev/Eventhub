import 'package:flutter/material.dart';

import '../app_colors.dart'
    show approvalStatusOf, eventWindow, organizerCanEditEvent, pendingPastStart, rejectionReasonOf;
import 'supabase_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// What the admin decided about an organizer's work — shared by the organizer
// web bell (web_shell.dart) and the mobile notification sheet
// (organizer_dashboard.dart), so both show the same items with the same ids.
//
//   • event approved / rejected     events.approval_status + reviewed_at
//   • changes approved / rejected   event_revisions (edits to a live event)
//   • announcement removed          notifications (admin_delete_announcement)
//   • events archived / restored    notifications (notify_archive_changes)
//   • event deleted (nothing kept)  notifications (admin_delete_unused_event)
//
// Announcements don't go through approval — they're live as soon as they're
// posted; the admin's only decision is removing one, with a reason.
// ─────────────────────────────────────────────────────────────────────────────

enum OrgNoticeKind {
  eventApproved,
  eventRejected,
  changesApproved,
  changesRejected,
  announcementRemoved,
  eventArchived,
  eventRestored,
  eventDeleted,
}

/// One admin decision, ready for the organizer's notification list.
class OrgNotice {
  /// Stable per decision: read state survives reloads, and a later decision
  /// on the same event (rejected again after a resubmit) shows up as new.
  final String id;
  final OrgNoticeKind kind;
  final String title;
  final String message;
  final DateTime at;

  const OrgNotice({
    required this.id,
    required this.kind,
    required this.title,
    required this.message,
    required this.at,
  });

  bool get isApproval =>
      kind == OrgNoticeKind.eventApproved || kind == OrgNoticeKind.changesApproved;

  IconData get icon => switch (kind) {
        OrgNoticeKind.eventApproved => Icons.check_circle_rounded,
        OrgNoticeKind.eventRejected => Icons.cancel_rounded,
        OrgNoticeKind.changesApproved => Icons.published_with_changes_rounded,
        OrgNoticeKind.changesRejected => Icons.edit_off_rounded,
        OrgNoticeKind.announcementRemoved => Icons.campaign_outlined,
        OrgNoticeKind.eventArchived => Icons.inventory_2_outlined,
        OrgNoticeKind.eventRestored => Icons.unarchive_outlined,
        OrgNoticeKind.eventDeleted => Icons.delete_outline_rounded,
      };

  Color get color => switch (kind) {
        OrgNoticeKind.eventArchived || OrgNoticeKind.eventRestored =>
          const Color(0xFF6366F1), // the Archives indigo
        _ => isApproval ? const Color(0xFF10B981) : const Color(0xFFEF4444),
      };
}

class OrganizerNotices {
  OrganizerNotices._();

  /// How long an admin decision stays in the list.
  static const window = Duration(days: 14);
  static const maxItems = 10;

  /// Admin decisions on [organizerId]'s events, change requests and
  /// announcements, newest first. [events] are the organizer's events as the
  /// caller already loaded them (with approval_status, rejection_reason,
  /// reviewed_at). Each source loads on its own, so one failing (e.g. a
  /// migration not installed yet) doesn't hide the others.
  static Future<List<OrgNotice>> load({
    required String organizerId,
    required List<Map<String, dynamic>> events,
  }) async {
    final now = DateTime.now();
    final since = now.subtract(window).toUtc().toIso8601String();
    final client = SupabaseService.client;
    final notices = <OrgNotice>[...eventDecisions(events, now: now)];

    try {
      final rows = await client
          .from('event_revisions')
          .select('id, event_id, status, rejection_reason, reviewed_at')
          .eq('organizer_id', organizerId)
          .in_('status', const ['approved', 'rejected'])
          .gte('reviewed_at', since)
          .order('reviewed_at', ascending: false)
          .limit(maxItems);
      notices.addAll(changeDecisions(
          List<Map<String, dynamic>>.from(rows as List), events, now: now));
    } catch (e) {
      debugPrint('Change-request decisions failed to load: $e');
    }

    try {
      final rows = await client
          .from('notifications')
          .select('id, title, message, created_at, notification_type')
          .eq('user_type', 'organizer')
          .eq('user_id', organizerId)
          .in_('notification_type', _adminNoticeTypes.keys.toList())
          .gte('created_at', since)
          .order('created_at', ascending: false)
          .limit(maxItems);
      notices.addAll(adminNotices(List<Map<String, dynamic>>.from(rows as List)));
    } catch (e) {
      debugPrint('Admin notices failed to load: $e');
    }

    return newestFirst(notices);
  }

  /// Approved / rejected events, from the events themselves.
  static List<OrgNotice> eventDecisions(
    List<Map<String, dynamic>> events, {
    required DateTime now,
  }) {
    final cutoff = now.subtract(window);
    final out = <OrgNotice>[];
    for (final e in events) {
      final status = approvalStatusOf(e, now: now);
      if (status != 'approved' && status != 'rejected') continue;
      // Nobody reviewed it before it started: rejected at its start time,
      // the same time the database saves (reject_unreviewed_events).
      final at = _time(e['reviewed_at']) ??
          (pendingPastStart(e, now: now) ? eventWindow(e)?.start : null);
      if (at == null || at.isBefore(cutoff)) continue;
      final name = _quoted(e['title'], or: 'Your event');
      final id = '${e['event_id']}_${at.millisecondsSinceEpoch}';
      if (status == 'approved') {
        out.add(OrgNotice(
          id: 'event_approved_$id',
          kind: OrgNoticeKind.eventApproved,
          title: 'Event approved',
          message: '$name was approved and is now visible to students.',
          at: at,
        ));
      } else {
        // Point to the fix while the event can be edited (a rejected one
        // always can, unless archived) — with a new date once the old one
        // has passed.
        final start = eventWindow(e)?.start;
        final next = !organizerCanEditEvent(e)
            ? ''
            : start != null && !now.isBefore(start)
                ? ' Edit it with a new date and resubmit it for review.'
                : ' Edit the event and resubmit it for review.';
        out.add(OrgNotice(
          id: 'event_rejected_$id',
          kind: OrgNoticeKind.eventRejected,
          title: 'Event rejected',
          message: '$name was rejected.${_reason(rejectionReasonOf(e, now: now))}$next',
          at: at,
        ));
      }
    }
    return out;
  }

  /// Approved / rejected change requests (edits to a live event).
  static List<OrgNotice> changeDecisions(
    List<Map<String, dynamic>> revisions,
    List<Map<String, dynamic>> events, {
    required DateTime now,
  }) {
    final cutoff = now.subtract(window);
    final titles = {for (final e in events) e['event_id']: e['title']};
    final out = <OrgNotice>[];
    for (final r in revisions) {
      final status = r['status'] as String?;
      if (status != 'approved' && status != 'rejected') continue;
      final at = _time(r['reviewed_at']);
      if (at == null || at.isBefore(cutoff)) continue;
      if (!titles.containsKey(r['event_id'])) continue; // event since deleted
      final name = _quoted(titles[r['event_id']], or: 'your event');
      out.add(status == 'approved'
          ? OrgNotice(
              id: 'change_approved_${r['id']}',
              kind: OrgNoticeKind.changesApproved,
              title: 'Changes approved',
              message: 'Your changes to $name were approved. Students now see '
                  'the updated details.',
              at: at,
            )
          : OrgNotice(
              id: 'change_rejected_${r['id']}',
              kind: OrgNoticeKind.changesRejected,
              title: 'Changes rejected',
              message: 'Your changes to $name were rejected.'
                  '${_reason(r['rejection_reason'])} The event keeps its current details.',
              at: at,
            ));
    }
    return out;
  }

  /// The notifications rows the bell shows: notification_type → (kind, id
  /// prefix, fallback title, fallback message). The database writes the
  /// title and message.
  static const _adminNoticeTypes = <String, (OrgNoticeKind, String, String, String)>{
    'announcement_deleted': (OrgNoticeKind.announcementRemoved, 'announcement_removed',
        'Announcement removed', 'An administrator removed one of your announcements.'),
    'event_archived': (OrgNoticeKind.eventArchived, 'event_archived',
        'Event archived', 'The administrator moved one of your events to Archives.'),
    'event_restored': (OrgNoticeKind.eventRestored, 'event_restored',
        'Event restored', 'The administrator restored one of your events from Archives.'),
    'event_deleted': (OrgNoticeKind.eventDeleted, 'event_deleted',
        'Event deleted', 'The administrator deleted one of your events.'),
  };

  /// Admin actions saved as notifications: announcement removals (with the
  /// reason), events archived, restored, or deleted with nothing to keep.
  static List<OrgNotice> adminNotices(List<Map<String, dynamic>> rows) => [
        for (final r in rows)
          if (_time(r['created_at']) case final at?)
            if (_adminNoticeTypes[r['notification_type'] ?? 'announcement_deleted']
                case (final kind, final prefix, final title, final message))
              OrgNotice(
                id: '${prefix}_${r['id']}',
                kind: kind,
                title: _text(r['title']) ?? title,
                message: _text(r['message']) ?? message,
                at: at,
              ),
      ];

  /// Announcements an admin removed (the reason is in the message).
  static List<OrgNotice> announcementRemovals(List<Map<String, dynamic>> rows) =>
      adminNotices([for (final r in rows) {...r, 'notification_type': 'announcement_deleted'}]);

  static List<OrgNotice> newestFirst(List<OrgNotice> notices) =>
      (List<OrgNotice>.of(notices)..sort((a, b) => b.at.compareTo(a.at)))
          .take(maxItems)
          .toList();

  static DateTime? _time(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;

  static String? _text(Object? v) {
    final s = (v as String?)?.trim();
    return s == null || s.isEmpty ? null : s;
  }

  static String _quoted(Object? title, {required String or}) {
    final t = _text(title);
    return t == null ? or : '“$t”';
  }

  /// " Reason: …." — or nothing when the admin gave none.
  static String _reason(Object? reason) {
    final r = _text(reason);
    if (r == null) return '';
    final normalized = r.replaceFirst(RegExp(r'\.{2,}$'), '.');
    final end = RegExp(r'[.!?]$').hasMatch(normalized) ? '' : '.';
    return ' Reason: $normalized$end';
  }
}

/// "Just now", "5m ago", "3h ago", "Yesterday", "4d ago", "Oct 5".
String noticeTimeAgo(DateTime at, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(at);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  if (d.inDays == 1) return 'Yesterday';
  if (d.inDays < 7) return '${d.inDays}d ago';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[at.month - 1]} ${at.day}';
}

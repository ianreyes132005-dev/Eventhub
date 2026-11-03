import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/services/notif_read_store.dart';
import '../../../shared/widgets/notification_sheet.dart';
import 'student_feed.dart';

/// The Home bell: the same sheet as the organizer app's bell — one list of
/// announcements and updates about the student's own events.
///
/// [notifs] is Home's live list, so a selfie request or a cancellation that
/// arrives while the sheet is open shows up in it.
Future<void> showStudentNotifications(
  BuildContext context,
  ValueListenable<List<StudentNotif>> notifs, {
  ValueChanged<String>? onOpenEvent,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => ValueListenableBuilder<List<StudentNotif>>(
      valueListenable: notifs,
      builder: (_, items, _) => NotificationSheet(
        items: [for (final n in items) studentNotificationItem(n)],
        isUnread: (id) => !NotifReadStore.isRead(id),
        onRead: (ids) {
          final fresh = ids.where((id) => !NotifReadStore.isRead(id)).toList();
          if (fresh.isNotEmpty) NotifReadStore.markAll(fresh);
        },
        onActivate: (item) {
          final eventId = item.eventId;
          if (eventId != null) onOpenEvent?.call(eventId);
        },
        emptyHint: 'Announcements and updates about your events show up here.',
      ),
    ),
  );
}

/// How each kind of update looks under the bell.
NotificationItem studentNotificationItem(StudentNotif n) {
  final (icon, color) = switch (n.type) {
    StudentNotifType.announcement => (
      Icons.campaign_outlined,
      const Color(0xFFB7791F),
    ),
    StudentNotifType.newEvent => (
      Icons.event_available_rounded,
      const Color(0xFF2979C8),
    ),
    StudentNotifType.checkIn => (
      Icons.check_circle_outline_rounded,
      const Color(0xFF16A34A),
    ),
    StudentNotifType.selfieRequired => (
      Icons.camera_alt_outlined,
      const Color(0xFF9333EA),
    ),
    StudentNotifType.photoSubmitted => (
      Icons.photo_camera_outlined,
      const Color(0xFF2979C8),
    ),
    StudentNotifType.rejected => (
      Icons.cancel_outlined,
      const Color(0xFFDC2626),
    ),
    StudentNotifType.eventCancelled => (
      Icons.event_busy_rounded,
      const Color(0xFFDC2626),
    ),
    StudentNotifType.eventUpdated => (
      Icons.edit_calendar_rounded,
      const Color(0xFF2979C8),
    ),
  };
  return NotificationItem(
    id: n.id,
    title: n.title,
    // Line breaks without the blank line between them, so a reason or a
    // previous date fits the row.
    message: n.body.replaceAll('\n\n', '\n'),
    icon: icon,
    color: color,
    at: n.time,
    eventId: n.eventId,
  );
}

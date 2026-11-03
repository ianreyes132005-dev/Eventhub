import 'package:eventhub/features/student/notifications/notifications_sheet.dart';
import 'package:eventhub/features/student/notifications/student_feed.dart';
import 'package:eventhub/shared/widgets/notification_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The bell's sheet, shared by the organizer and student apps: one list of
// messages (no tabs, no page), read by tapping a row or Mark all as read.
// The student's bell lists announcements and updates about their own events.

Widget _sheet({
  required List<NotificationItem> items,
  required Set<String> unread,
  void Function(Iterable<String>)? onRead,
  ValueChanged<NotificationItem>? onActivate,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: StatefulBuilder(
          builder: (context, setState) => NotificationSheet(
            items: items,
            isUnread: unread.contains,
            onRead: (ids) {
              unread.removeAll(ids.toList());
              onRead?.call(ids);
            },
            emptyHint: 'Check-in updates show up here.',
            onActivate: onActivate,
          ),
        ),
      ),
    ),
  );
}

void main() {
  final now = DateTime.now();
  final items = [
    NotificationItem(
      id: 'a',
      title: 'Event cancelled',
      message:
          '"Science Fair" has been cancelled by the organizer.\nReason: Rain',
      icon: Icons.event_busy_rounded,
      color: const Color(0xFFDC2626),
      at: now.subtract(const Duration(minutes: 5)),
    ),
    NotificationItem(
      id: 'b',
      title: 'Selfie required',
      message: 'Your organizer needs a selfie.',
      icon: Icons.camera_alt_outlined,
      color: const Color(0xFF9333EA),
      at: now.subtract(const Duration(hours: 2)),
    ),
  ];

  testWidgets('shows every message in one list, with no tabs', (tester) async {
    await tester.pumpWidget(_sheet(items: items, unread: {'a', 'b'}));
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('2 new'), findsOneWidget);
    expect(find.text('Event cancelled'), findsOneWidget);
    // The reason is shown in full, not cut to a preview.
    expect(find.textContaining('Reason: Rain'), findsOneWidget);
    expect(find.text('5m ago'), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
  });

  testWidgets('tapping a row reads it; Mark all as read reads the rest', (
    tester,
  ) async {
    final read = <String>[];
    await tester.pumpWidget(
      _sheet(items: items, unread: {'a', 'b'}, onRead: read.addAll),
    );

    await tester.tap(find.text('Selfie required'));
    await tester.pumpAndSettle();
    expect(read, ['b']);
    expect(find.text('1 new'), findsOneWidget);

    await tester.tap(find.text('Mark all as read'));
    await tester.pumpAndSettle();
    expect(read, ['b', 'a']);
    expect(find.text('All read'), findsOneWidget);
  });

  testWidgets('tapping an event notification opens its event destination', (
    tester,
  ) async {
    final opened = <String>[];
    final eventItem = NotificationItem(
      id: 'checked-in-r1',
      title: 'Check-in confirmed!',
      message: 'You are checked in.',
      icon: Icons.check_circle_outline_rounded,
      color: const Color(0xFF16A34A),
      eventId: 'event-1',
    );
    await tester.pumpWidget(
      _sheet(
        items: [eventItem],
        unread: {'checked-in-r1'},
        onActivate: (item) => opened.add(item.eventId!),
      ),
    );

    await tester.tap(find.text('Check-in confirmed!'));
    await tester.pumpAndSettle();

    expect(opened, ['event-1']);
  });

  testWidgets('nothing to show: all caught up', (tester) async {
    await tester.pumpWidget(_sheet(items: const [], unread: {}));
    expect(find.text("You're all caught up!"), findsOneWidget);
    expect(find.text('Check-in updates show up here.'), findsOneWidget);
  });

  test('the student bell lists event updates for their own registrations', () {
    final reg = <String, dynamic>{
      'id': 'r1',
      'event_id': 'e1',
      'status': 'rejected',
      'rejection_reason': 'Not in the class list',
      'registered_at': '2026-10-24T08:00:00Z',
      'events': <String, dynamic>{
        'title': 'Science Fair',
        'event_status': 'upcoming',
      },
    };
    final notifs = StudentNotifications.build(registrations: [reg]);
    final row = studentNotificationItem(notifs.single);
    expect(row.title, 'Registration declined');
    expect(row.message, contains('Not in the class list'));
    expect(row.at, isNotNull); // shown in full, with when it happened
  });

  test(
    'announcements appear in the student bell using Home read-state IDs',
    () {
      final announcement = <String, dynamic>{
        'id': 'a1',
        'title': 'Campus update',
        'message': 'The library closes early today.',
        'created_at': '2026-10-24T08:00:00Z',
      };
      final notif = StudentNotifications.build(
        announcements: [announcement],
        registrations: const [],
      ).single;
      final row = studentNotificationItem(notif);
      expect(notif.id, 'ann_a1');
      expect(row.title, 'Campus update');
      expect(row.message, 'The library closes early today.');
      expect(row.at, DateTime.utc(2026, 10, 24, 8).toLocal());
    },
  );

  test('new event notices carry the event ID and approval time', () {
    final event = <String, dynamic>{
      'event_id': 'event-1',
      'title': 'Science Fair',
      'reviewed_at': '2026-10-24T08:00:00Z',
    };
    final notification = StudentNotifications.build(
      publishedEvents: [event],
      registrations: const [],
    ).single;
    expect(notification.type, StudentNotifType.newEvent);
    expect(notification.eventId, 'event-1');
    expect(notification.time, DateTime.utc(2026, 10, 24, 8).toLocal());
  });

  test(
    'check-in notices carry their event ID for event-specific navigation',
    () {
      final registration = <String, dynamic>{
        'id': 'r1',
        'event_id': 'event-1',
        'status': 'checked_in',
        'checked_in_at': '2026-10-24T08:00:00Z',
        'events': <String, dynamic>{
          'title': 'Science Fair',
          'event_status': 'ongoing',
        },
      };
      final notification = StudentNotifications.build(
        registrations: [registration],
      ).single;
      expect(notification.type, StudentNotifType.checkIn);
      expect(notification.eventId, 'event-1');
    },
  );

  test(
    'a cancelled event\'s reason sits on the next line, without a blank one',
    () {
      final reg = <String, dynamic>{
        'id': 'r1',
        'event_id': 'e1',
        'status': 'registered',
        'registered_at': '2026-10-24T08:00:00Z',
        'events': <String, dynamic>{
          'title': 'Science Fair',
          'event_status': 'cancelled',
          'cancel_reason': 'Rain',
        },
      };
      final cancelled = StudentNotifications.build(
        registrations: [reg],
      ).singleWhere((n) => n.type == StudentNotifType.eventCancelled);
      expect(
        studentNotificationItem(cancelled).message,
        '"Science Fair" has been cancelled by the organizer.\nReason: Rain',
      );
    },
  );
}

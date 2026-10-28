import 'package:eventhub/features/student/notifications/student_feed.dart';
import 'package:flutter_test/flutter_test.dart';

// A check-in step's notification shows when it happened — status_changed_at,
// set by the database (migration 202610270002) — not when the student
// registered, so a selfie request made a minute ago doesn't read "3d ago".
void main() {
  final announcement = <String, dynamic>{
    'id': 1,
    'title': 'Assembly moved',
    'message': 'See you in the gym.',
    'created_at': '2026-10-27T09:00:00Z',
  };

  Map<String, dynamic> reg({String? statusChangedAt}) => {
        'id': 'r1',
        'event_id': 'e1',
        'status': 'photo_required',
        'registered_at': '2026-10-24T08:00:00Z',
        'status_changed_at': ?statusChangedAt,
        'events': <String, dynamic>{'title': 'Science Fair', 'event_status': 'upcoming'},
      };

  test('a selfie request shows when it was made, and comes first', () {
    final items = StudentNotifications.build(
      announcements: [announcement],
      registrations: [reg(statusChangedAt: '2026-10-27T09:59:00Z')],
    );
    expect(items.first.title, 'Selfie required');
    expect(items.first.time, DateTime.utc(2026, 10, 27, 9, 59).toLocal());
  });

  test('registrations from before the migration keep the registration time', () {
    final items = StudentNotifications.build(
      announcements: [announcement],
      registrations: [reg()],
    );
    final selfie = items.singleWhere((n) => n.title == 'Selfie required');
    expect(selfie.time, DateTime.utc(2026, 10, 24, 8).toLocal());
    expect(items.first.title, 'Assembly moved');
  });
}

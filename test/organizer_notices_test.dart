import 'package:eventhub/core/services/organizer_notices.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 19, 12);
  String ago(Duration d) => now.subtract(d).toUtc().toIso8601String();

  Map<String, dynamic> event(String id, String status,
          {String? reviewedAt, String? reason, String date = '2099-01-10'}) =>
      {
        'event_id': id,
        'title': 'Science Fair',
        'approval_status': status,
        'rejection_reason': reason,
        'reviewed_at': reviewedAt,
        'event_date': date,
        'start_time': '09:00:00',
        'end_time': '12:00:00',
        'event_status': 'upcoming',
      };

  group('event decisions', () {
    test('approved and rejected events become notices', () {
      final notices = OrganizerNotices.eventDecisions([
        event('a', 'approved', reviewedAt: ago(const Duration(hours: 2))),
        event('b', 'rejected',
            reviewedAt: ago(const Duration(hours: 1)), reason: 'Venue is booked'),
      ], now: now);

      expect(notices.map((n) => n.kind),
          [OrgNoticeKind.eventApproved, OrgNoticeKind.eventRejected]);
      expect(notices.first.message,
          '“Science Fair” was approved and is now visible to students.');
      expect(notices.last.message,
          '“Science Fair” was rejected. Reason: Venue is booked. '
          'Edit the event and resubmit it for review.');
    });

    test('a later decision on the same event gets a new id', () {
      final first = OrganizerNotices.eventDecisions(
          [event('a', 'rejected', reviewedAt: ago(const Duration(days: 3)))], now: now);
      final second = OrganizerNotices.eventDecisions(
          [event('a', 'rejected', reviewedAt: ago(const Duration(hours: 1)))], now: now);
      expect(first.single.id, isNot(second.single.id));
    });

    test('no "resubmit" hint once the event can no longer be edited', () {
      final n = OrganizerNotices.eventDecisions([
        event('a', 'rejected', reviewedAt: ago(const Duration(hours: 1)), date: '2020-01-10'),
      ], now: now);
      expect(n.single.message, '“Science Fair” was rejected.');
    });

    test('pending, unreviewed and old decisions are left out', () {
      final n = OrganizerNotices.eventDecisions([
        event('a', 'pending', reviewedAt: ago(const Duration(hours: 1))),
        event('b', 'approved'),
        event('c', 'approved', reviewedAt: ago(const Duration(days: 20))),
      ], now: now);
      expect(n, isEmpty);
    });
  });

  test('change-request decisions name the event and keep the reason', () {
    final events = [event('a', 'approved', reviewedAt: ago(const Duration(days: 30)))];
    final n = OrganizerNotices.changeDecisions([
      {'id': 'r1', 'event_id': 'a', 'status': 'rejected',
       'rejection_reason': 'Keep the original room', 'reviewed_at': ago(const Duration(hours: 3))},
      {'id': 'r2', 'event_id': 'a', 'status': 'approved', 'reviewed_at': ago(const Duration(hours: 1))},
      {'id': 'r3', 'event_id': 'gone', 'status': 'approved', 'reviewed_at': ago(const Duration(hours: 1))},
    ], events, now: now);

    expect(n.map((x) => x.id), ['change_rejected_r1', 'change_approved_r2']);
    expect(n.first.message,
        'Your changes to “Science Fair” were rejected. Reason: Keep the original room. '
        'The event keeps its current details.');
  });

  test('announcement removals keep the admin’s message', () {
    final n = OrganizerNotices.announcementRemovals([
      {'id': 7, 'title': 'Announcement removed',
       'message': 'Your announcement "Hi" was removed. Reason: Duplicate',
       'created_at': ago(const Duration(minutes: 5))},
    ]);
    expect(n.single.id, 'announcement_removed_7');
    expect(n.single.kind, OrgNoticeKind.announcementRemoved);
  });

  test('newest first, capped', () {
    final list = [
      for (var i = 0; i < 15; i++)
        OrgNotice(id: '$i', kind: OrgNoticeKind.eventApproved, title: '', message: '',
            at: now.subtract(Duration(hours: i))),
    ]..shuffle();
    final sorted = OrganizerNotices.newestFirst(list);
    expect(sorted.length, OrganizerNotices.maxItems);
    expect(sorted.first.id, '0');
  });

  test('time labels', () {
    expect(noticeTimeAgo(now.subtract(const Duration(seconds: 20)), now: now), 'Just now');
    expect(noticeTimeAgo(now.subtract(const Duration(minutes: 5)), now: now), '5m ago');
    expect(noticeTimeAgo(now.subtract(const Duration(hours: 3)), now: now), '3h ago');
    expect(noticeTimeAgo(now.subtract(const Duration(days: 1)), now: now), 'Yesterday');
    expect(noticeTimeAgo(now.subtract(const Duration(days: 4)), now: now), '4d ago');
    expect(noticeTimeAgo(DateTime(2026, 10, 5), now: now), 'Oct 5');
  });
}

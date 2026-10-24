import 'package:eventhub/core/app_colors.dart';
import 'package:eventhub/core/services/notif_read_store.dart';
import 'package:eventhub/features/organizer/mobile/dashboard/dashboard_metrics.dart';
import 'package:eventhub/shared/widgets/event_phase_pill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _d(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Map<String, dynamic> _event({
  String id = 'e1',
  required DateTime day,
  String start = '09:00:00',
  String end = '12:00:00',
  String approval = 'approved',
  bool cancelled = false,
}) => {
  'event_id': id,
  'title': 'Event $id',
  'event_date': _d(day),
  'start_time': start,
  'end_time': end,
  'approval_status': approval,
  'event_status': cancelled ? 'cancelled' : 'upcoming',
};

void main() {
  // A fixed "now": Oct 19, 2026, 10:00.
  final now = DateTime(2026, 10, 19, 10);
  final today = DateTime(2026, 10, 19);

  group('student registrations', () {
    Map<String, dynamic> reg(
      Map<String, dynamic> ev, {
      String status = 'pending',
    }) => {'status': status, 'events': ev};

    test('upcoming: not cancelled, not declined, until check-in closes', () {
      // Ended at 09:00 today → check-in open until 11:00.
      final endedRecently = _event(
        day: today,
        start: '07:00:00',
        end: '09:00:00',
      );
      expect(registrationIsUpcoming(reg(endedRecently), now: now), isTrue);
      expect(
        registrationIsUpcoming(
          reg(_event(day: today.add(const Duration(days: 3)))),
          now: now,
        ),
        isTrue,
      );
      expect(
        registrationIsUpcoming(
          reg(_event(day: today, cancelled: true)),
          now: now,
        ),
        isFalse,
      );
      expect(
        registrationIsUpcoming(
          reg(_event(day: today), status: 'rejected'),
          now: now,
        ),
        isFalse,
      );
      // Ended at 07:00 → check-in closed at 09:00.
      expect(
        registrationIsUpcoming(
          reg(_event(day: today, start: '05:00:00', end: '07:00:00')),
          now: now,
        ),
        isFalse,
      );
    });

    test('finished (attendance rate): check-in closed and not cancelled', () {
      final past = _event(day: today.subtract(const Duration(days: 2)));
      expect(registrationIsFinished(reg(past), now: now), isTrue);
      expect(
        registrationIsFinished(
          reg(
            _event(
              day: today.subtract(const Duration(days: 2)),
              cancelled: true,
            ),
          ),
          now: now,
        ),
        isFalse,
      );
      expect(
        registrationIsFinished(
          reg(_event(day: today.add(const Duration(days: 1)))),
          now: now,
        ),
        isFalse,
      );
    });
  });

  test('bell count is recounted, not decremented', () async {
    SharedPreferences.setMockInitialValues({});
    await NotifReadStore.loadForUser('u1');
    NotifReadStore.setAll(['a', 'b', 'c', 'd', 'e']);
    expect(NotifReadStore.unreadNotifier.value, 5);
    NotifReadStore.mark('a');
    NotifReadStore.mark('a'); // already read — no change
    expect(NotifReadStore.unreadNotifier.value, 4);
    NotifReadStore.markAll(['b', 'c', 'd', 'e']);
    expect(NotifReadStore.unreadNotifier.value, 0);
    NotifReadStore.setAll(['a', 'b', 'f']);
    expect(NotifReadStore.unreadNotifier.value, 1);
  });

  test('countdown shows days', () {
    expect(
      countdownLabel(const Duration(days: 20, hours: 4, minutes: 12)),
      '20d 4h',
    );
    expect(countdownLabel(const Duration(days: 2)), '2d');
    expect(
      countdownLabel(const Duration(hours: 4, minutes: 12, seconds: 33)),
      '04:12:33',
    );
    expect(countdownLabel(const Duration(minutes: 9, seconds: 5)), '09:05');
  });

  test('student phase includes check-in open', () {
    final ev = _event(day: today, start: '07:00:00', end: '09:00:00');
    expect(eventPhaseOf(ev, now: now), EventPhase.checkInOpen);
    expect(
      eventPhaseOf(ev, now: DateTime(2026, 10, 19, 8)),
      EventPhase.ongoing,
    );
    expect(
      eventPhaseOf(ev, now: DateTime(2026, 10, 19, 12)),
      EventPhase.completed,
    );
  });

  group('organizer home', () {
    test('attendance breakdown uses the latest five non-active events', () {
      final events = [
        for (var day = 1; day <= 6; day++)
          _event(
            id: 'past-$day',
            day: DateTime(2026, 10, day),
          ),
        _event(id: 'future', day: DateTime(2026, 10, 20)),
        _event(
          id: 'ongoing',
          day: today,
          start: '09:00:00',
          end: '11:00:00',
        ),
      ];
      final recent = recentPastEventsForAttendance(events, now: now);

      expect(
        recent.map((event) => event['event_id']).toList(),
        ['past-2', 'past-3', 'past-4', 'past-5', 'past-6'],
      );

      final attendance = eventAttendanceBreakdown(recent, [
        {'event_id': 'past-1', 'status': 'checked_in'},
        {'event_id': 'past-2', 'status': 'checked_in'},
        {'event_id': 'past-2', 'status': 'pending'},
        {'event_id': 'past-3', 'status': 'rejected'},
      ]);

      expect(attendance.first, {
        'event_id': 'past-2',
        'title': 'Event past-2',
        'label': 'Oct 2',
        'checkedIn': 1,
        'total': 2,
      });
      // past-3's only registration was declined, so nobody counts as registered.
      expect(attendance.skip(1).first['total'], 0);
      expect(attendance.skip(1).first['checkedIn'], 0);
      expect(attendance.skip(2).every((event) => event['total'] == 0), isTrue);
    });

    test('weekly registrations are grouped Monday through Sunday', () {
      final registrations = [
        {'registered_at': '2026-10-18T12:00:00'}, // previous Sunday
        {'registered_at': '2026-10-19T09:00:00'},
        {'registered_at': '2026-10-19T10:00:00'},
        {'registered_at': '2026-10-21T12:00:00'},
        {'registered_at': '2026-10-25T12:00:00'},
        {'registered_at': '2026-10-26T00:00:00'}, // next Monday
        {'registered_at': 'not-a-timestamp'},
      ];

      expect(
        weeklyRegistrationsByDay(registrations, now: DateTime(2026, 10, 21)),
        [2, 0, 1, 0, 0, 0, 1],
      );
    });

    test('next event: approved only, by date and start time', () {
      final events = [
        _event(
          id: 'pending',
          day: today,
          start: '11:00:00',
          end: '12:00:00',
          approval: 'pending',
        ),
        _event(id: 'later', day: today, start: '15:00:00', end: '16:00:00'),
        _event(id: 'sooner', day: today, start: '13:00:00', end: '14:00:00'),
        _event(
          id: 'cancelled',
          day: today,
          start: '10:30:00',
          end: '11:00:00',
          cancelled: true,
        ),
      ];
      expect(nextApprovedEvent(events, now: now)?['event_id'], 'sooner');
      // An approved event already running beats the later ones.
      events.add(
        _event(id: 'running', day: today, start: '09:00:00', end: '11:00:00'),
      );
      expect(nextApprovedEvent(events, now: now)?['event_id'], 'running');
    });
  });
}

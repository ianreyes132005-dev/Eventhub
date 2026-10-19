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
    Map<String, dynamic> reg(Map<String, dynamic> ev, {String status = 'pending'}) =>
        {'status': status, 'events': ev};

    test('upcoming: not cancelled, not declined, until check-in closes', () {
      // Ended at 09:00 today → check-in open until 11:00.
      final endedRecently = _event(day: today, start: '07:00:00', end: '09:00:00');
      expect(registrationIsUpcoming(reg(endedRecently), now: now), isTrue);
      expect(registrationIsUpcoming(reg(_event(day: today.add(const Duration(days: 3)))), now: now), isTrue);
      expect(registrationIsUpcoming(reg(_event(day: today, cancelled: true)), now: now), isFalse);
      expect(registrationIsUpcoming(reg(_event(day: today), status: 'rejected'), now: now), isFalse);
      // Ended at 07:00 → check-in closed at 09:00.
      expect(registrationIsUpcoming(reg(_event(day: today, start: '05:00:00', end: '07:00:00')), now: now), isFalse);
    });

    test('finished (attendance rate): check-in closed and not cancelled', () {
      final past = _event(day: today.subtract(const Duration(days: 2)));
      expect(registrationIsFinished(reg(past), now: now), isTrue);
      expect(registrationIsFinished(reg(_event(day: today.subtract(const Duration(days: 2)), cancelled: true)), now: now), isFalse);
      expect(registrationIsFinished(reg(_event(day: today.add(const Duration(days: 1)))), now: now), isFalse);
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
    expect(countdownLabel(const Duration(days: 20, hours: 4, minutes: 12)), '20d 4h');
    expect(countdownLabel(const Duration(days: 2)), '2d');
    expect(countdownLabel(const Duration(hours: 4, minutes: 12, seconds: 33)), '04:12:33');
    expect(countdownLabel(const Duration(minutes: 9, seconds: 5)), '09:05');
  });

  test('student phase includes check-in open', () {
    final ev = _event(day: today, start: '07:00:00', end: '09:00:00');
    expect(eventPhaseOf(ev, now: now), EventPhase.checkInOpen);
    expect(eventPhaseOf(ev, now: DateTime(2026, 10, 19, 8)), EventPhase.ongoing);
    expect(eventPhaseOf(ev, now: DateTime(2026, 10, 19, 12)), EventPhase.completed);
  });

  group('organizer home', () {
    test('next event: approved only, by date and start time', () {
      final events = [
        _event(id: 'pending', day: today, start: '11:00:00', end: '12:00:00', approval: 'pending'),
        _event(id: 'later', day: today, start: '15:00:00', end: '16:00:00'),
        _event(id: 'sooner', day: today, start: '13:00:00', end: '14:00:00'),
        _event(id: 'cancelled', day: today, start: '10:30:00', end: '11:00:00', cancelled: true),
      ];
      expect(nextApprovedEvent(events, now: now)?['event_id'], 'sooner');
      // An approved event already running beats the later ones.
      events.add(_event(id: 'running', day: today, start: '09:00:00', end: '11:00:00'));
      expect(nextApprovedEvent(events, now: now)?['event_id'], 'running');
    });

    test('attendance: approved, not cancelled, had registrations, check-in closed', () {
      final yesterday = today.subtract(const Duration(days: 1));
      final events = [
        _event(id: 'ok', day: yesterday),
        _event(id: 'rejected', day: yesterday, approval: 'rejected'),
        _event(id: 'cancelled', day: yesterday, cancelled: true),
        _event(id: 'empty', day: yesterday),
        _event(id: 'checkin-open', day: today, start: '07:00:00', end: '09:00:00'),
      ];
      final counts = {'ok': 10, 'rejected': 3, 'cancelled': 4, 'checkin-open': 5};
      expect(attendanceEvents(events, counts, now: now).map((e) => e['event_id']), ['ok']);
    });

    test('sign-ups: last 7 days beside the 7 before', () {
      String at(int daysAgo) =>
          today.subtract(Duration(days: daysAgo)).add(const Duration(hours: 9)).toIso8601String();
      final s = signupsByDay([
        {'registered_at': at(0)},
        {'registered_at': at(0)},
        {'registered_at': at(6)},
        {'registered_at': at(7)},
        {'registered_at': at(13)},
        {'registered_at': at(14)}, // too old
      ], now: now);
      expect(s.last7, [1, 0, 0, 0, 0, 0, 2]);
      expect(s.prev7, [1, 0, 0, 0, 0, 0, 1]);
    });
  });
}

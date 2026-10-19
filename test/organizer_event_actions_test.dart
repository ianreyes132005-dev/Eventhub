import 'package:flutter_test/flutter_test.dart';
import 'package:eventhub/core/app_colors.dart';
import 'package:eventhub/shared/utils/realtime_utils.dart';

// The organizer action rules shared by the app (and matching the web Events
// table): edit upcoming / cancelled events, cancel any approved event that
// hasn't ended (ongoing included), restore a cancelled one before it ends.

String _two(int n) => n.toString().padLeft(2, '0');
String _date(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String _time(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}:00';

Map<String, dynamic> _event({
  required DateTime start,
  required DateTime end,
  String status = 'upcoming',
  String? approval = 'approved',
  bool archived = false,
}) => {
  'event_date': _date(start),
  'end_date': _date(end),
  'start_time': _time(start),
  'end_time': _time(end),
  'event_status': status,
  'approval_status': approval,
  if (archived) 'archived_at': '2026-10-01T00:00:00Z',
};

void main() {
  final now = DateTime.now();
  final upcoming = (start: now.add(const Duration(days: 2)), end: now.add(const Duration(days: 2, hours: 3)));
  final ongoing  = (start: now.subtract(const Duration(hours: 1)), end: now.add(const Duration(hours: 2)));
  final ended    = (start: now.subtract(const Duration(days: 2)), end: now.subtract(const Duration(days: 2) - const Duration(hours: 3)));

  ({bool edit, bool cancel, bool restore}) rules(Map<String, dynamic> e) => (
    edit: organizerCanEditEvent(e),
    cancel: organizerCanCancelEvent(e),
    restore: organizerCanRestoreEvent(e),
  );

  group('approved events', () {
    test('upcoming: edit and cancel', () {
      expect(rules(_event(start: upcoming.start, end: upcoming.end)),
          (edit: true, cancel: true, restore: false));
    });

    test('ongoing: cancel only — no edit', () {
      expect(rules(_event(start: ongoing.start, end: ongoing.end)),
          (edit: false, cancel: true, restore: false));
    });

    test('ended: nothing', () {
      expect(rules(_event(start: ended.start, end: ended.end)),
          (edit: false, cancel: false, restore: false));
    });

    test('legacy row without approval_status counts as approved', () {
      expect(rules(_event(start: ongoing.start, end: ongoing.end, approval: null)).cancel, isTrue);
    });
  });

  group('cancelled events', () {
    test('before it starts: edit and restore', () {
      expect(rules(_event(start: upcoming.start, end: upcoming.end, status: 'cancelled')),
          (edit: true, cancel: false, restore: true));
    });

    test('during its time slot: still restorable', () {
      expect(rules(_event(start: ongoing.start, end: ongoing.end, status: 'cancelled')).restore, isTrue);
    });

    test('after it would have ended: no restore', () {
      expect(rules(_event(start: ended.start, end: ended.end, status: 'cancelled')).restore, isFalse);
    });
  });

  group('not approved yet', () {
    for (final approval in ['pending', 'rejected']) {
      test('$approval + upcoming: edit, but no cancel', () {
        expect(rules(_event(start: upcoming.start, end: upcoming.end, approval: approval)),
            (edit: true, cancel: false, restore: false));
      });
    }
  });

  test('archived events allow nothing', () {
    expect(rules(_event(start: ended.start, end: ended.end, archived: true)),
        (edit: false, cancel: false, restore: false));
    expect(rules(_event(start: upcoming.start, end: upcoming.end, status: 'cancelled', archived: true)),
        (edit: false, cancel: false, restore: false));
  });

  group('realtimeRow', () {
    test('uses the new values for inserts and updates', () {
      expect(realtimeRow({'new': {'event_id': 'a'}, 'old': {'event_id': 'b'}}), {'event_id': 'a'});
    });

    test('falls back to the old values for deletes', () {
      expect(realtimeRow({'new': <String, dynamic>{}, 'old': {'id': 'r1'}}), {'id': 'r1'});
    });

    test('null when there is no row', () {
      expect(realtimeRow({'new': <String, dynamic>{}, 'old': <String, dynamic>{}}), isNull);
      expect(realtimeRow('not a map'), isNull);
    });
  });
}

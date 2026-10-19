import 'package:flutter_test/flutter_test.dart';
import 'package:eventhub/core/app_colors.dart';
import 'package:eventhub/shared/utils/event_form_validation.dart';

// Capacity = every active student: registration never closes for capacity,
// the old per-event max_participants is ignored, and the event form has no
// capacity field.

String _two(int n) => n.toString().padLeft(2, '0');
String _date(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String _time(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}:00';

void main() {
  final start = DateTime.now().add(const Duration(days: 3));
  final end   = start.add(const Duration(hours: 2));

  Map<String, dynamic> event({int? max, int current = 0}) => {
    'event_date': _date(start),
    'end_date': _date(end),
    'start_time': _time(start),
    'end_time': _time(end),
    'event_status': 'upcoming',
    'approval_status': 'approved',
    'max_participants': max,
    'current_participants': current,
  };

  group('registrationState ignores the legacy max_participants', () {
    test('an old 50-seat limit that is "reached" no longer closes registration', () {
      expect(registrationState(event(max: 50, current: 50)), RegistrationState.open);
    });

    test('no limit, many registrations: still open', () {
      expect(registrationState(event(current: 900)), RegistrationState.open);
    });

    test('other rules still apply', () {
      expect(registrationState({...event(), 'event_status': 'cancelled'}),
          RegistrationState.cancelled);
      expect(registrationState({...event(), 'approval_status': 'pending'}),
          RegistrationState.notApproved);
    });
  });

  group('capacityFill', () {
    test('share of all students registered', () {
      expect(capacityFill(50, 200), 0.25);
    });

    test('grows with the student body: same registrations, more students', () {
      expect(capacityFill(50, 250), lessThan(capacityFill(50, 200)));
    });

    test('0 until the student count is known', () {
      expect(capacityFill(50, null), 0);
      expect(capacityFill(50, 0), 0);
    });

    test('never above 100%', () {
      expect(capacityFill(210, 200), 1.0);
    });
  });

  test('the event form has no capacity field to get wrong', () {
    expect(EventFormField.values.map((f) => f.name), isNot(contains('capacity')));
    final errors = validateEventForm(
      title: 'Science Fair',
      needsOtherType: false,
      otherType: '',
      startDate: _dateOnly(start),
      endDate: _dateOnly(end),
      startTime: null,
      endTime: null,
      location: 'Gym',
    );
    // Only the missing times are reported — nothing about capacity.
    expect(errors.keys.toSet(), {EventFormField.startTime, EventFormField.endTime});
  });
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

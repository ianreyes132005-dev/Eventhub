import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:eventhub/core/app_colors.dart';
import 'package:eventhub/features/student/check_in/selfie_screen.dart';

// Registration stays open until 2 hours after the event starts; the camera
// screen closes on its own when the organizer's photo request ends.

Map<String, dynamic> _event({String start = '09:00:00', String end = '17:00:00', String? deadline}) => {
  'event_id': 'ev-1',
  'approval_status': 'approved',
  'event_status': 'upcoming',
  'event_date': '2026-10-24',
  'start_time': start,
  'end_time': end,
  'registration_deadline': deadline,
};

void main() {
  group('registration closes 2 hours after the start', () {
    test('open before and during the first 2 hours, closed after', () {
      final e = _event();
      expect(registrationState(e, now: DateTime(2026, 10, 24, 8)), RegistrationState.open);
      expect(registrationState(e, now: DateTime(2026, 10, 24, 10, 59)), RegistrationState.open);
      expect(registrationState(e, now: DateTime(2026, 10, 24, 11)), RegistrationState.started);
      expect(registrationClosesAt(e), DateTime(2026, 10, 24, 11));
    });

    test('never after the end of a short event', () {
      final e = _event(start: '09:00:00', end: '10:00:00');
      expect(registrationClosesAt(e), DateTime(2026, 10, 24, 10));
      expect(registrationState(e, now: DateTime(2026, 10, 24, 9, 30)), RegistrationState.open);
      expect(registrationState(e, now: DateTime(2026, 10, 24, 10)), RegistrationState.ended);
    });

    test('a deadline, when set, still wins', () {
      final e = _event(deadline: DateTime(2026, 10, 23, 17).toUtc().toIso8601String());
      expect(registrationClosesAt(e), DateTime(2026, 10, 23, 17));
      expect(registrationState(e, now: DateTime(2026, 10, 23, 18)), RegistrationState.deadlinePassed);
    });

    test('the database enforces the same 2 hours', () {
      final sql = File('supabase/migrations/202610210003_registration_closes_after_start.sql')
          .readAsStringSync();
      expect(sql, contains("public.event_starts_at(ev) + interval '2 hours'"));
      expect(registrationClosedReason(RegistrationState.started),
          contains('2 hours after the event starts'));
    });
  });

  group('the camera screen when the photo request ends', () {
    test('stays open while the photo is still wanted', () {
      expect(selfieRequestEndedMessage('photo_required'), isNull);
    });

    test('explains a decline, with the reason', () {
      expect(selfieRequestEndedMessage('rejected', rejectionReason: 'Not at the venue'),
          contains('Reason: Not at the venue'));
      expect(selfieRequestEndedMessage('rejected'), contains('declined'));
    });

    test('check-in, a sent photo, a withdrawn request and a removal', () {
      expect(selfieRequestEndedMessage('checked_in'), contains('already checked in'));
      expect(selfieRequestEndedMessage('photo_submitted'), contains('already sent'));
      expect(selfieRequestEndedMessage('qr_scanned'), contains('withdrew'));
      expect(selfieRequestEndedMessage(null, removed: true), contains('removed'));
    });
  });

  test('settings follow the account: only the owner can read or write them', () {
    final sql = File('supabase/migrations/202610210004_user_settings.sql').readAsStringSync();
    expect(sql, contains('ENABLE ROW LEVEL SECURITY'));
    expect('user_id = auth.uid()'.allMatches(sql).length, greaterThanOrEqualTo(3));
  });
}

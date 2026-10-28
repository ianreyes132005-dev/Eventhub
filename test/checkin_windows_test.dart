import 'package:eventhub/core/app_colors.dart';
import 'package:flutter_test/flutter_test.dart';

// Check-in has two windows: a ticket can be scanned (the student arrives)
// from 1 h before the start until 30 min after the end, and a check-in
// started in time can be finished until 2 h after the end. Then the
// attendance is final. Students can cancel until check-in opens. The
// database enforces the same (migration 202610280001).
void main() {
  // Oct 25, 2026, 08:00–09:00: check-in opens 07:00, scanning closes 09:30,
  // check-in closes 11:00.
  Map<String, dynamic> event({String status = 'upcoming', String? archivedAt}) => {
    'event_id': 'e1',
    'event_date': '2026-10-25',
    'start_time': '08:00:00',
    'end_time': '09:00:00',
    'event_status': status,
    'approval_status': 'approved',
    'archived_at': archivedAt,
  };
  DateTime at(int h, [int m = 0, int s = 0]) => DateTime(2026, 10, 25, h, m, s);
  Map<String, dynamic> reg(String status) => {'id': 'r1', 'status': status};

  group('arriving: scanning a ticket', () {
    test('from 1 hour before the start until 30 minutes after the end', () {
      expect(scanBlockedReason(event(), now: at(6, 59)), startsWith('Check-in opens'));
      expect(scanBlockedReason(event(), now: at(7)), isNull);
      expect(scanBlockedReason(event(), now: at(8, 30)), isNull);
      expect(scanBlockedReason(event(), now: at(9, 30)), isNull);
      expect(scanBlockedReason(event(), now: at(9, 31)), startsWith('Scanning closed'));
      expect(scanClosesAt(event()), at(9, 30));
    });

    test('never for a cancelled event', () {
      expect(scanBlockedReason(event(status: 'cancelled'), now: at(8)), contains('cancelled'));
    });
  });

  group('finishing: selfie and review', () {
    test('until 2 hours after the end', () {
      expect(checkInBlockedReason(event(), now: at(10, 30)), isNull);
      expect(checkInBlockedReason(event(), now: at(11)), isNull);
      expect(checkInBlockedReason(event(), now: at(11, 1)), startsWith('Check-in closed'));
    });

    test('a check-in has started once the ticket is scanned, until it is decided', () {
      for (final s in ['qr_scanned', 'photo_required', 'photo_submitted']) {
        expect(checkInStarted(s), isTrue, reason: s);
      }
      for (final s in ['pending', 'checked_in', 'rejected', null]) {
        expect(checkInStarted(s), isFalse, reason: '$s');
      }
    });
  });

  group('final attendance', () {
    test('once check-in has closed', () {
      expect(attendanceFinal(event(), now: at(11)), isFalse);
      expect(attendanceFinal(event(), now: at(11, 0, 1)), isTrue);
      expect(attendanceFinal(event(status: 'cancelled'), now: at(12)), isTrue);
    });

    test('organizers can delete a registration only before then, and never a check-in', () {
      expect(registrationDeletable(reg('pending'), event: event(), now: at(10)), isTrue);
      expect(registrationDeletable(reg('pending'), event: event(), now: at(12)), isFalse);
      expect(registrationDeletable(reg('rejected'), event: event(), now: at(12)), isFalse);
      expect(registrationDeletable(reg('checked_in'), event: event(), now: at(10)), isFalse);
      // Without its event, only the status counts.
      expect(registrationDeletable(reg('pending')), isTrue);
    });

    test('the organizer sees which part of check-in is left', () {
      expect(organizerEventStatusLabel(event(), now: at(9, 10)), 'Ended · Scanning until 9:30 AM');
      expect(organizerEventStatusLabel(event(), now: at(10)), 'Ended · Finish check-ins by 11:00 AM');
      expect(organizerEventStatusLabel(event(), now: at(12)), 'Ended');
    });
  });

  group('missed', () {
    test('an unscanned ticket once scanning closed', () {
      expect(registrationMissed(reg('pending'), event(), now: at(9, 29)), isFalse);
      expect(registrationMissed(reg('pending'), event(), now: at(9, 31)), isTrue);
    });

    test('a started check-in only once check-in closed', () {
      expect(registrationMissed(reg('photo_submitted'), event(), now: at(10)), isFalse);
      expect(registrationMissed(reg('photo_submitted'), event(), now: at(11, 1)), isTrue);
    });

    test('never a decided check-in, or a cancelled event', () {
      expect(registrationMissed(reg('checked_in'), event(), now: at(12)), isFalse);
      expect(registrationMissed(reg('rejected'), event(), now: at(12)), isFalse);
      expect(registrationMissed(reg('pending'), event(status: 'cancelled'), now: at(12)), isFalse);
    });
  });

  group('students cancelling', () {
    test('until check-in opens, while the ticket is unscanned', () {
      expect(registrationCancellable(reg('pending'), event(), now: at(6, 59)), isTrue);
      expect(registrationCancellable(reg('pending'), event(), now: at(7)), isFalse);
      expect(registrationCancellable(reg('qr_scanned'), event(), now: at(6)), isFalse);
    });

    test('not for a cancelled or archived event', () {
      expect(registrationCancellable(reg('pending'), event(status: 'cancelled'), now: at(6)), isFalse);
      expect(
        registrationCancellable(reg('pending'), event(archivedAt: '2026-10-24T00:00:00Z'), now: at(6)),
        isFalse,
      );
    });
  });
}

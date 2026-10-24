import 'package:flutter_test/flutter_test.dart';
import 'package:eventhub/core/app_colors.dart';
import 'package:eventhub/core/services/notif_read_store.dart';
import 'package:eventhub/features/organizer/web/attendance_record.dart';

// Declined registrations (status 'rejected') don't count as registered, and
// checked-in ones can't be deleted — the same rules as the database
// (migration 202610230001).

AttendanceRow _row(AttendanceMark mark) => AttendanceRow(
  last: 'Cruz',
  first: 'Ana',
  lrn: '123456261234',
  grade: 11,
  strand: null,
  section: null,
  registeredAt: null,
  checkedInAt: null,
  mark: mark,
);

void main() {
  test('every status but rejected counts as registered', () {
    for (final status in ['pending', 'qr_scanned', 'photo_required', 'photo_submitted', 'checked_in']) {
      expect(countsAsRegistered({'status': status}), isTrue, reason: status);
    }
    expect(countsAsRegistered({'status': 'rejected'}), isFalse);
  });

  test('only checked-in registrations are kept from deletion', () {
    expect(registrationDeletable({'status': 'checked_in'}), isFalse);
    for (final status in ['pending', 'qr_scanned', 'photo_required', 'photo_submitted', 'rejected']) {
      expect(registrationDeletable({'status': status}), isTrue, reason: status);
    }
  });

  test('a declined student gets no "Event updated" notice', () {
    Map<String, dynamic> reg(String status) => {
      'event_id': 'e1',
      'status': status,
      'registered_at': '2026-10-01T08:00:00Z',
      'events': {'event_status': 'upcoming', 'schedule_changed_at': '2026-10-05T08:00:00Z'},
    };
    expect(updatedNotifIdFor(reg('pending')), isNotNull);
    expect(updatedNotifIdFor(reg('rejected')), isNull);
  });

  group('attendance record', () {
    AttendanceRecord record(List<AttendanceMark> marks) => AttendanceRecord(
      event: const {'title': 'Seminar'},
      organizerName: null,
      rows: [for (final m in marks) _row(m)],
      generatedAt: DateTime(2026, 10, 23),
    );

    test('rejected rows are listed but not registered', () {
      final rec = record([
        AttendanceMark.present,
        AttendanceMark.present,
        AttendanceMark.absent,
        AttendanceMark.rejected,
      ]);
      expect(rec.rows.length, 4);
      expect(rec.registered, 3);
      expect(rec.rate, closeTo(2 / 3, 1e-9));
    });

    test('all rejected: nobody registered, rate 0', () {
      final rec = record([AttendanceMark.rejected]);
      expect(rec.registered, 0);
      expect(rec.rate, 0);
    });
  });
}

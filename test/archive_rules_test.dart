import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eventhub/core/app_colors.dart';
import 'package:eventhub/core/services/event_archive_service.dart';
import 'package:eventhub/core/services/organizer_notices.dart';
import 'package:eventhub/features/organizer/web/attendance_record.dart';

// The archive rules shared by the admin Archives tab and the database
// (202610230003_archive_records.sql): only approved events with registrations
// are archived; never-live or empty ones are deleted instead.

String _two(int n) => n.toString().padLeft(2, '0');
String _date(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String _time(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}:00';

Map<String, dynamic> _event({
  String id = 'e1',
  required DateTime start,
  required DateTime end,
  String? approval = 'approved',
  String status = 'upcoming',
  bool archived = false,
}) => {
  'event_id': id,
  'event_date': _date(start),
  'end_date': _date(end),
  'start_time': _time(start),
  'end_time': _time(end),
  'event_status': status,
  'approval_status': approval,
  if (archived) 'archived_at': '2026-10-01T00:00:00Z',
};

void main() {
  final now = DateTime(2026, 10, 23, 12);
  // Ended yesterday: check-in closed long ago.
  final past = (start: DateTime(2026, 10, 22, 9), end: DateTime(2026, 10, 22, 11));
  // Ended an hour ago: check-in still open (closes 2 h after the end).
  final justEnded = (start: DateTime(2026, 10, 23, 8), end: DateTime(2026, 10, 23, 11));
  final ahead = (start: DateTime(2026, 10, 30, 9), end: DateTime(2026, 10, 30, 11));

  ArchiveGroup? groupOf(Map<String, dynamic> e, int regs) =>
      archiveGroupOf(e, registrations: regs, now: now);

  group('archive groups', () {
    test('an approved event with registrations is ready once check-in closes', () {
      expect(groupOf(_event(start: past.start, end: past.end), 3), ArchiveGroup.ready);
      expect(eventArchivable(_event(start: past.start, end: past.end),
          registrations: 3, now: now), isTrue);
    });

    test('not while check-in is still open, nor before it happens', () {
      expect(groupOf(_event(start: justEnded.start, end: justEnded.end), 3), isNull);
      expect(groupOf(_event(start: ahead.start, end: ahead.end), 3), isNull);
    });

    test('a cancelled event with registrations is ready at once', () {
      expect(groupOf(_event(start: ahead.start, end: ahead.end, status: 'cancelled'), 2),
          ArchiveGroup.ready);
    });

    test('nothing to keep: nobody registered, or never approved', () {
      expect(groupOf(_event(start: past.start, end: past.end), 0), ArchiveGroup.empty);
      expect(groupOf(_event(start: ahead.start, end: ahead.end, status: 'cancelled'), 0),
          ArchiveGroup.empty);
      for (final approval in ['pending', 'rejected']) {
        expect(groupOf(_event(start: past.start, end: past.end, approval: approval), 0),
            ArchiveGroup.empty, reason: approval);
        expect(eventArchivable(_event(start: past.start, end: past.end, approval: approval),
            registrations: 0, now: now), isFalse);
      }
    });

    test('archived stays archived, whatever it holds', () {
      expect(groupOf(_event(start: past.start, end: past.end, archived: true), 0),
          ArchiveGroup.archived);
      expect(eventArchivable(_event(start: past.start, end: past.end, archived: true),
          registrations: 3, now: now), isFalse);
    });

    test('the sidebar counts only the ready ones', () {
      final readiness = ArchiveReadiness([
        _event(id: 'a', start: past.start, end: past.end),
        _event(id: 'b', start: past.start, end: past.end),
        _event(id: 'c', start: justEnded.start, end: justEnded.end),
      ], {'a': 4, 'c': 2});
      expect(readiness.readyCount(now: now), 1);
      // c's check-in closes at 1 PM.
      expect(readiness.readyCount(now: DateTime(2026, 10, 23, 13, 1)), 2);
    });

    test('every admin delete of an organizer’s event leaves them a bell notice', () {
      String sql(String name) => File('supabase/migrations/$name').readAsStringSync();
      for (final (file, fn) in [
        ('202610230003_archive_records.sql', 'admin_delete_unused_event'),
        ('202610230004_archive_delete_notice.sql', 'admin_delete_archived_event'),
      ]) {
        final body = sql(file);
        expect(body, contains('FUNCTION public.$fn'), reason: file);
        expect(body, contains("'event_deleted'"), reason: file);
      }
    });

    test('the database has the same rule', () {
      final sql = File('supabase/migrations/202610230003_archive_records.sql')
          .readAsStringSync();
      expect(sql, contains("COALESCE(NEW.approval_status, 'approved') <> 'approved'"));
      expect(sql, contains('NOT EXISTS (SELECT 1 FROM public.registrations WHERE event_id = NEW.event_id)'));
      expect(sql, contains("now() <= public.event_ends_at(NEW) + interval '2 hours'"));
    });
  });

  group('school years', () {
    test('start in June', () {
      expect(kSchoolYearStartMonth, DateTime.june);
      expect(schoolYearOf(DateTime(2026, 5, 31)), 2025);
      expect(schoolYearOf(DateTime(2026, 6, 1)), 2026);
      expect(schoolYearOf(DateTime(2027, 3, 15)), 2026);
      expect(schoolYearLabel(2025), 'SY 2025–2026');
      expect(eventSchoolYear({'event_date': '2026-10-05'}), 2026);
      expect(eventSchoolYear({'event_date': null}), isNull);
    });
  });

  test('history counts keep archived events; active ones don’t', () {
    final events = [
      _event(start: past.start, end: past.end),
      _event(start: past.start, end: past.end, archived: true),
      _event(start: ahead.start, end: ahead.end, approval: 'pending'),
    ];
    expect(totalApprovedEventCount(events), 2);
  });

  test('upcoming / ongoing follows the clock, not the stored status', () {
    final ongoing = (start: DateTime(2026, 10, 23, 11), end: DateTime(2026, 10, 23, 14));
    final list = upcomingApprovedEvents([
      _event(id: 'ended', start: past.start, end: past.end),           // stored 'upcoming'
      _event(id: 'later', start: ahead.start, end: ahead.end),
      _event(id: 'now', start: ongoing.start, end: ongoing.end),
      _event(id: 'archived', start: ahead.start, end: ahead.end, archived: true),
      _event(id: 'pending', start: ahead.start, end: ahead.end, approval: 'pending'),
      _event(id: 'cancelled', start: ahead.start, end: ahead.end, status: 'cancelled'),
    ], now: now);
    expect(list.map((e) => e['event_id']), ['now', 'later']);
  });

  group('school-year summary', () {
    AttendanceSummaryRow row(String title, {
      bool cancelled = false, int regs = 0, int present = 0, int rejected = 0, String date = '2026-10-05',
    }) => AttendanceSummaryRow(
      date: date, sortKey: date, title: title, type: 'Seminar', venue: 'Gym',
      organizer: 'Ms. Cruz', cancelled: cancelled, archived: true,
      registrations: regs, present: present, rejected: rejected,
    );

    test('declined registrations and cancelled events don’t count toward attendance', () {
      final rows = [
        row('Science Fair', regs: 10, present: 6, rejected: 2),   // 8 registered
        row('Sports Day', regs: 4, present: 4),
        row('Concert', cancelled: true, regs: 5),
      ];
      expect(rows.first.registered, 8);
      expect(rows.first.absent, 2);
      expect(rows.first.rate, closeTo(0.75, 1e-9));
      expect(rows.last.rate, isNull);
      final totals = attendanceSummaryTotals(rows);
      expect(totals.events, 3);
      expect(totals.registered, 12);
      expect(totals.present, 10);
      expect(totals.rejected, 2);
      expect(totals.rate, closeTo(10 / 12, 1e-9));
    });

    test('the Excel file lists every event in date order', () {
      final bytes = buildAttendanceSummaryXlsx(
        title: 'SY 2026–2027',
        rows: [
          row('Sports Day', regs: 4, present: 4, date: '2026-11-02'),
          row('Science Fair', regs: 10, present: 6, rejected: 2, date: '2026-10-05'),
        ],
        generatedAt: DateTime(2026, 10, 23, 9),
      );
      final zip = ZipDecoder().decodeBytes(bytes);
      String part(String name) =>
          utf8.decode(zip.files.firstWhere((f) => f.name == name).content as List<int>);
      final sheet = part('xl/worksheets/sheet1.xml');
      expect(sheet, contains('Attendance summary · SY 2026–2027'));
      expect(sheet.indexOf('Science Fair'), lessThan(sheet.indexOf('Sports Day')));
      expect(part('xl/workbook.xml'), contains('<sheet name="Summary"'));
    });

    test('the per-event export still names its sheet Attendance', () {
      final bytes = buildAttendanceXlsx(AttendanceRecord(
        event: const {'title': 'Seminar'},
        organizerName: null,
        rows: const [],
        generatedAt: DateTime(2026, 10, 23),
      ));
      final workbook = ZipDecoder().decodeBytes(bytes).files
          .firstWhere((f) => f.name == 'xl/workbook.xml');
      expect(utf8.decode(workbook.content as List<int>), contains('<sheet name="Attendance"'));
    });
  });

  group('organizer bell', () {
    String ago(Duration d) => DateTime.now().subtract(d).toUtc().toIso8601String();

    test('archive, restore and delete notices from the database', () {
      final n = OrganizerNotices.adminNotices([
        {'id': 5, 'notification_type': 'event_archived', 'title': '3 events archived',
         'message': '“A”, “B” and “C” were moved to Archives by the administrator.',
         'created_at': ago(const Duration(minutes: 3))},
        {'id': 6, 'notification_type': 'event_restored', 'title': 'Event restored',
         'message': '“A” was restored from Archives.', 'created_at': ago(const Duration(minutes: 2))},
        {'id': 7, 'notification_type': 'event_deleted', 'title': 'Event deleted',
         'message': '“D” was deleted by the administrator.', 'created_at': ago(const Duration(minutes: 1))},
        {'id': 8, 'notification_type': 'something_else', 'title': 'x', 'message': 'y',
         'created_at': ago(const Duration(minutes: 1))},
      ]);
      expect(n.map((x) => x.kind),
          [OrgNoticeKind.eventArchived, OrgNoticeKind.eventRestored, OrgNoticeKind.eventDeleted]);
      expect(n.map((x) => x.id), ['event_archived_5', 'event_restored_6', 'event_deleted_7']);
      expect(n.first.title, '3 events archived');
    });
  });
}

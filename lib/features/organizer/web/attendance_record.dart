import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/app_colors.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/utils/date_utils.dart';
import 'student_registration_panel.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Attendance record for an ended event — every registration with the event's
// details on top, exported as Excel (.xlsx) or PDF from the organizer web.
//
// The .xlsx is written by hand (SpreadsheetML zipped with `archive`) so no
// spreadsheet package is needed; the PDF uses `pdf`.
// ─────────────────────────────────────────────────────────────────────────────

enum AttendanceMark { present, absent, rejected }

String attendanceMarkLabel(AttendanceMark m) => switch (m) {
  AttendanceMark.present  => 'Present',
  AttendanceMark.absent   => 'Absent',
  AttendanceMark.rejected => 'Rejected',
};

class AttendanceRow {
  final String last, first, lrn;
  final int? grade;
  final String? strand, section;
  final DateTime? registeredAt, checkedInAt;
  final AttendanceMark mark;

  const AttendanceRow({
    required this.last,
    required this.first,
    required this.lrn,
    required this.grade,
    required this.strand,
    required this.section,
    required this.registeredAt,
    required this.checkedInAt,
    required this.mark,
  });

  String get name => first.isEmpty && last.isEmpty
      ? '—'
      : first.isEmpty ? last : last.isEmpty ? first : '$last, $first';
}

class AttendanceRecord {
  final Map<String, dynamic> event;
  final String? organizerName;
  final List<AttendanceRow> rows;
  final DateTime generatedAt;

  AttendanceRecord({
    required this.event,
    required this.organizerName,
    required this.rows,
    required this.generatedAt,
  });

  String get title => (event['title'] as String? ?? '').trim().isEmpty
      ? 'Untitled event'
      : (event['title'] as String).trim();

  /// Every row but a rejected one: declined registrations are listed but
  /// don't count as registered ([countsAsRegistered]).
  int get registered => rows.length - count(AttendanceMark.rejected);
  int count(AttendanceMark m) => rows.where((r) => r.mark == m).length;
  int get present => count(AttendanceMark.present);

  /// Present ÷ registered, 0–1.
  double get rate => registered == 0 ? 0 : present / registered;

  String get dateLabel {
    final start = event['event_date'] as String?;
    final end   = event['end_date'] as String?;
    if (end == null || end.isEmpty || end == start) return fmtDate(start);
    return '${fmtDate(start)} – ${fmtDate(end)}';
  }

  String get timeLabel {
    final s = fmtTime(event['start_time'] as String?);
    final e = fmtTime(event['end_time'] as String?);
    if (s.isEmpty) return '—';
    return e.isEmpty ? s : '$s – $e';
  }

  String get venue => _orDash(event['location'] as String?);
  String get type  => _orDash(event['event_type'] as String?);

  /// Check-in stays open [kCheckInClosesAfter] past the end, so a record made
  /// right after the event can still miss late check-ins. Null once closed.
  DateTime? get checkInClosesAt {
    final w = eventWindow(event);
    if (w == null) return null;
    final closes = w.end.add(kCheckInClosesAfter);
    return generatedAt.isBefore(closes) ? closes : null;
  }

  String get fileBaseName {
    final safe = title
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final date = event['event_date'] as String? ?? '';
    return 'Attendance - $safe${date.isEmpty ? '' : ' - $date'}';
  }
}

String _orDash(String? s) => (s == null || s.trim().isEmpty) ? '—' : s.trim();

/// Student profiles (grade, strand, section…) keyed by user_id.
typedef RegistrantProfileLoader =
    Future<Map<String, Map<String, dynamic>>> Function(Iterable<String?> userIds);

/// Loads every registration for [event] with each student's grade, strand and
/// section, sorted grade → section → last name → first name so a class
/// adviser can find their students together.
///
/// [profileLoader] defaults to the organizer view (their own events only);
/// the admin passes one that reads the students table.
Future<AttendanceRecord> loadAttendanceRecord(Map<String, dynamic> event,
    {RegistrantProfileLoader profileLoader = loadRegistrantProfiles}) async {
  final eventId = event['event_id'] as String?;
  if (eventId == null) throw StateError('This event has no ID.');

  final regsRaw = await SupabaseService.client
      .from('registrations')
      .select()
      .eq('event_id', eventId);
  final regs = List<Map<String, dynamic>>.from(regsRaw as List);

  String? orgName;
  final orgId = event['organizer_id'] as String?;
  if (orgId != null) {
    final org = await SupabaseService.client
        .from('organizers')
        .select('full_name')
        .eq('organizer_id', orgId)
        .maybeSingle();
    orgName = org?['full_name'] as String?;
  }

  final profiles = await profileLoader(
      regs.map((r) => r['student_user_id'] as String?));

  final rows = [
    for (final r in regs) _rowFrom(r, profiles[r['student_user_id'] as String? ?? '']),
  ]..sort((a, b) {
      int c = (a.grade ?? 99).compareTo(b.grade ?? 99);
      if (c != 0) return c;
      c = (a.section ?? '~').toLowerCase().compareTo((b.section ?? '~').toLowerCase());
      if (c != 0) return c;
      c = a.last.toLowerCase().compareTo(b.last.toLowerCase());
      if (c != 0) return c;
      return a.first.toLowerCase().compareTo(b.first.toLowerCase());
    });

  return AttendanceRecord(
    event: event,
    organizerName: orgName,
    rows: rows,
    generatedAt: DateTime.now(),
  );
}

AttendanceRow _rowFrom(Map<String, dynamic> r, Map<String, dynamic>? p) {
  var first = (p?['first_name'] as String? ?? '').trim();
  var last  = (p?['last_name']  as String? ?? '').trim();
  if (first.isEmpty || last.isEmpty) {
    // Older accounts have only a full name ("First Middle Last"): treat the
    // last word as the last name, same best guess as the admin edit dialog.
    final full = (p?['full_name'] as String? ?? r['student_name'] as String? ?? '').trim();
    final parts = full.split(RegExp(r'\s+'));
    last  = parts.length > 1 ? parts.last : full;
    first = parts.length > 1 ? parts.sublist(0, parts.length - 1).join(' ') : '';
  }
  final grade   = p?['year_level'] as int?;
  final section = (p?['section'] as String? ?? '').trim();
  final status  = r['status'] as String? ?? 'pending';
  return AttendanceRow(
    last: last,
    first: first,
    lrn: formatLrn(p?['lrn'] as String? ?? r['student_school_id'] as String? ?? ''),
    grade: grade,
    strand: (grade == 11 || grade == 12) ? (p?['strand'] as String?) : null,
    section: section.isEmpty ? null : section,
    registeredAt: DateTime.tryParse(r['registered_at'] as String? ?? '')?.toLocal(),
    checkedInAt: DateTime.tryParse(r['checked_in_at'] as String? ?? '')?.toLocal(),
    mark: switch (status) {
      'checked_in' => AttendanceMark.present,
      'rejected'   => AttendanceMark.rejected,
      _            => AttendanceMark.absent,
    },
  );
}

const _months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

String _fmtClock(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
}

String _fmtStamp(DateTime? d) =>
    d == null ? '' : '${_months[d.month - 1]} ${d.day}, ${d.year} ${_fmtClock(d)}';

// ══════════════════════════════════════════════════════════════════════════════
// Excel (.xlsx)
// ══════════════════════════════════════════════════════════════════════════════

const kXlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

// cellXfs indexes in _xlsxStyles.
const _sTitle = 1, _sSub = 2, _sLabel = 3, _sHead = 4, _sBody = 5,
    _sCenter = 6, _sPresent = 7, _sAbsent = 8, _sPct = 9, _sNote = 10;

/// Sheet rows being written, one at a time (columns A–Z).
class _XlsxRows {
  final rows = <String>[];
  var r = 0;

  /// One row of (column index, value, style) cells; null value = empty.
  void row(List<(int, Object?, int)> cells, {double? height}) {
    r++;
    final ht = height == null ? '' : ' ht="$height" customHeight="1"';
    final xml = cells.map((c) {
      final (col, v, style) = c;
      final ref = '${String.fromCharCode(65 + col)}$r';
      if (v == null) return '<c r="$ref" s="$style"/>';
      if (v is num) return '<c r="$ref" s="$style"><v>$v</v></c>';
      return '<c r="$ref" s="$style" t="inlineStr"><is><t xml:space="preserve">'
          '${_xml(v.toString())}</t></is></c>';
    }).join();
    rows.add('<row r="$r"$ht>$xml</row>');
  }

  void blank() => r++;
}

Uint8List buildAttendanceXlsx(AttendanceRecord rec) {
  final sheetRows = _XlsxRows();
  final row = sheetRows.row;
  final blank = sheetRows.blank;

  row([(0, rec.title, _sTitle)], height: 26);
  row([(0, 'Event Attendance Record · J-Jireh EventHub', _sSub)]);
  blank();

  // Event details on the left (B/C), totals on the right (I/J).
  final rejected = rec.count(AttendanceMark.rejected);
  final details = [
    ('Date', rec.dateLabel),
    ('Time', rec.timeLabel),
    ('Venue', rec.venue),
    ('Event type', rec.type),
    ('Organizer', _orDash(rec.organizerName)),
    ('Generated', _fmtStamp(rec.generatedAt)),
  ];
  final totals = <(String, num, int)>[
    ('Registered', rec.registered, _sBody),
    ('Present', rec.present, _sBody),
    ('Absent', rec.count(AttendanceMark.absent), _sBody),
    if (rejected > 0) ('Rejected', rejected, _sBody),
    ('Attendance rate', rec.rate, _sPct),
  ];
  for (var i = 0; i < details.length || i < totals.length; i++) {
    row([
      if (i < details.length) ...[
        (1, details[i].$1, _sLabel),
        (2, details[i].$2, 0),
      ],
      if (i < totals.length) ...[
        (8, totals[i].$1, _sLabel),
        (9, totals[i].$2, totals[i].$3),
      ],
    ]);
  }
  final closes = rec.checkInClosesAt;
  if (closes != null) {
    row([(1, 'Note: check-in was still open when this file was made '
        '(closes ${_fmtStamp(closes)}). Export again after that for the final record.', _sNote)]);
  }
  blank();

  const headers = ['No.', 'Last Name', 'First Name', 'LRN', 'Grade', 'Strand',
      'Section', 'Registered', 'Checked In', 'Attendance'];
  row([for (var c = 0; c < headers.length; c++) (c, headers[c], _sHead)], height: 20);
  final headerRow = sheetRows.r;

  for (var i = 0; i < rec.rows.length; i++) {
    final a = rec.rows[i];
    row([
      (0, i + 1, _sCenter),
      (1, a.last, _sBody),
      (2, a.first, _sBody),
      (3, a.lrn, _sBody),
      (4, a.grade, _sCenter),
      (5, a.strand ?? '', _sCenter),
      (6, a.section ?? '', _sBody),
      (7, _fmtStamp(a.registeredAt), _sBody),
      (8, a.mark == AttendanceMark.present ? _fmtStamp(a.checkedInAt) : '', _sBody),
      (9, attendanceMarkLabel(a.mark),
          a.mark == AttendanceMark.present ? _sPresent : _sAbsent),
    ]);
  }
  if (rec.rows.isEmpty) {
    row([(1, 'No students registered for this event.', _sNote)]);
  }
  final lastRow = rec.rows.isEmpty ? headerRow : sheetRows.r;

  const widths = [6, 18, 22, 21, 7, 8, 14, 21, 21, 15];
  final cols = [
    for (var c = 0; c < widths.length; c++)
      '<col min="${c + 1}" max="${c + 1}" width="${widths[c]}" customWidth="1"/>',
  ].join();

  // Excel header/footer codes start with "&", so a literal one is "&&".
  final footerTitle = _xml(rec.title.replaceAll('&', '&&'));
  final sheet = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>'
      '<dimension ref="A1:J${sheetRows.r}"/>'
      '<sheetViews><sheetView workbookViewId="0" showGridLines="0"/></sheetViews>'
      '<sheetFormatPr defaultRowHeight="15"/>'
      '<cols>$cols</cols>'
      '<sheetData>${sheetRows.rows.join()}</sheetData>'
      '${rec.rows.isEmpty ? '' : '<autoFilter ref="A$headerRow:J$lastRow"/>'}'
      '<pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" header="0.3" footer="0.3"/>'
      '<pageSetup paperSize="9" orientation="landscape" fitToWidth="1" fitToHeight="0"/>'
      '<headerFooter><oddFooter>&amp;L$footerTitle&amp;RPage &amp;P of &amp;N</oddFooter></headerFooter>'
      '</worksheet>';

  return _xlsxPackage('Attendance', sheet,
      filter: rec.rows.isEmpty ? null : '\$A\$$headerRow:\$J\$$lastRow',
      headerRow: headerRow);
}

/// Zips one worksheet ([sheet], named [sheetName]) into an .xlsx, with the
/// header row repeated on every printed page and the auto-filter range
/// ([filter], absolute A1 refs) registered.
Uint8List _xlsxPackage(String sheetName, String sheet,
    {String? filter, required int headerRow}) {
  final workbook = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheets><sheet name="$sheetName" sheetId="1" r:id="rId1"/></sheets>'
      '<definedNames>'
      '${filter == null ? '' : '<definedName name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">$sheetName!$filter</definedName>'}'
      '<definedName name="_xlnm.Print_Titles" localSheetId="0">$sheetName!\$$headerRow:\$$headerRow</definedName>'
      '</definedNames>'
      '</workbook>';

  final parts = <String, String>{
    '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '</Types>',
    '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>',
    'xl/workbook.xml': workbook,
    'xl/_rels/workbook.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>',
    'xl/styles.xml': _xlsxStyles,
    'xl/worksheets/sheet1.xml': sheet,
  };

  final archive = Archive();
  parts.forEach((name, xml) {
    final bytes = utf8.encode(xml);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

// ══════════════════════════════════════════════════════════════════════════════
// School-year summary (admin Archives) — one row per event
// ══════════════════════════════════════════════════════════════════════════════

/// One event in the admin's school-year attendance summary.
class AttendanceSummaryRow {
  final String date;                // as shown, e.g. "Oct 5, 2026"
  final String sortKey;             // event_date, for ordering
  final String title, type, venue, organizer;
  final bool cancelled, archived;
  /// Every registration row; [rejected] of them were declined.
  final int registrations, present, rejected;

  const AttendanceSummaryRow({
    required this.date,
    required this.sortKey,
    required this.title,
    required this.type,
    required this.venue,
    required this.organizer,
    required this.cancelled,
    required this.archived,
    required this.registrations,
    required this.present,
    required this.rejected,
  });

  /// Declined registrations don't count as registered ([countsAsRegistered]).
  int get registered => registrations - rejected;
  int get absent => cancelled ? 0 : registered - present;

  /// Present ÷ registered, or null when there's no attendance to rate
  /// (cancelled, or nobody registered).
  double? get rate => cancelled || registered <= 0 ? null : present / registered;
}

/// The summary's totals: attendance only counts events that took place.
({int events, int registered, int present, int absent, int rejected, double? rate})
    attendanceSummaryTotals(List<AttendanceSummaryRow> rows) {
  final held = rows.where((r) => !r.cancelled);
  final registered = held.fold<int>(0, (n, r) => n + r.registered);
  final present = held.fold<int>(0, (n, r) => n + r.present);
  return (
    events: rows.length,
    registered: registered,
    present: present,
    absent: registered - present,
    rejected: rows.fold<int>(0, (n, r) => n + r.rejected),
    rate: registered == 0 ? null : present / registered,
  );
}

/// [title] is e.g. "SY 2025–2026" or "All school years".
Uint8List buildAttendanceSummaryXlsx({
  required String title,
  required List<AttendanceSummaryRow> rows,
  required DateTime generatedAt,
}) {
  final sheetRows = _XlsxRows();
  final row = sheetRows.row;
  final events = [...rows]..sort((a, b) => a.sortKey.compareTo(b.sortKey));
  final totals = attendanceSummaryTotals(events);

  row([(0, 'Attendance summary · $title', _sTitle)], height: 26);
  row([(0, 'School-year attendance summary · J-Jireh EventHub', _sSub)]);
  sheetRows.blank();

  final details = [
    ('School year', title),
    ('Events', '${totals.events}'),
    ('Generated', _fmtStamp(generatedAt)),
  ];
  final figures = <(String, num?, int)>[
    ('Registered', totals.registered, _sBody),
    ('Present', totals.present, _sBody),
    ('Absent', totals.absent, _sBody),
    if (totals.rejected > 0) ('Rejected', totals.rejected, _sBody),
    ('Attendance rate', totals.rate, _sPct),
  ];
  for (var i = 0; i < details.length || i < figures.length; i++) {
    row([
      if (i < details.length) ...[
        (1, details[i].$1, _sLabel),
        (2, details[i].$2, 0),
      ],
      if (i < figures.length) ...[
        (10, figures[i].$1, _sLabel),
        (11, figures[i].$2 ?? '—', figures[i].$2 == null ? _sCenter : figures[i].$3),
      ],
    ]);
  }
  row([(1, 'Cancelled events show their registrations but no attendance; '
      'declined registrations are counted as Rejected, not as registered.', _sNote)]);
  sheetRows.blank();

  const headers = ['No.', 'Date', 'Event', 'Type', 'Venue', 'Organizer', 'Status',
      'Archived', 'Registered', 'Present', 'Absent', 'Rejected', 'Attendance'];
  row([for (var c = 0; c < headers.length; c++) (c, headers[c], _sHead)], height: 20);
  final headerRow = sheetRows.r;

  for (var i = 0; i < events.length; i++) {
    final e = events[i];
    final rate = e.rate;
    row([
      (0, i + 1, _sCenter),
      (1, e.date, _sBody),
      (2, e.title, _sBody),
      (3, e.type, _sBody),
      (4, e.venue, _sBody),
      (5, e.organizer, _sBody),
      (6, e.cancelled ? 'Cancelled' : 'Ended', e.cancelled ? _sAbsent : _sBody),
      (7, e.archived ? 'Yes' : 'No', _sCenter),
      (8, e.registered, _sCenter),
      (9, e.cancelled ? '—' : e.present, _sCenter),
      (10, e.cancelled ? '—' : e.absent, _sCenter),
      (11, e.rejected, _sCenter),
      (12, rate ?? '—', rate == null ? _sCenter : _sPct),
    ]);
  }
  if (events.isEmpty) {
    row([(1, 'No events in this school year.', _sNote)]);
  }
  final lastRow = events.isEmpty ? headerRow : sheetRows.r;

  const widths = [6, 14, 32, 12, 20, 22, 11, 10, 11, 9, 9, 9, 12];
  final cols = [
    for (var c = 0; c < widths.length; c++)
      '<col min="${c + 1}" max="${c + 1}" width="${widths[c]}" customWidth="1"/>',
  ].join();

  final footerTitle = _xml('Attendance summary $title'.replaceAll('&', '&&'));
  final sheet = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>'
      '<dimension ref="A1:M${sheetRows.r}"/>'
      '<sheetViews><sheetView workbookViewId="0" showGridLines="0"/></sheetViews>'
      '<sheetFormatPr defaultRowHeight="15"/>'
      '<cols>$cols</cols>'
      '<sheetData>${sheetRows.rows.join()}</sheetData>'
      '${events.isEmpty ? '' : '<autoFilter ref="A$headerRow:M$lastRow"/>'}'
      '<pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" header="0.3" footer="0.3"/>'
      '<pageSetup paperSize="9" orientation="landscape" fitToWidth="1" fitToHeight="0"/>'
      '<headerFooter><oddFooter>&amp;L$footerTitle&amp;RPage &amp;P of &amp;N</oddFooter></headerFooter>'
      '</worksheet>';

  return _xlsxPackage('Summary', sheet,
      filter: events.isEmpty ? null : '\$A\$$headerRow:\$M\$$lastRow',
      headerRow: headerRow);
}

const _xlsxStyles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<fonts count="7">'
    '<font><sz val="11"/><name val="Calibri"/></font>'                                  // 0 body
    '<font><b/><sz val="11"/><name val="Calibri"/></font>'                              // 1 bold
    '<font><b/><sz val="16"/><color rgb="FF111827"/><name val="Calibri"/></font>'       // 2 title
    '<font><sz val="10"/><color rgb="FF6B7280"/><name val="Calibri"/></font>'           // 3 subtitle
    '<font><b/><sz val="11"/><color rgb="FF15803D"/><name val="Calibri"/></font>'       // 4 present
    '<font><b/><sz val="11"/><color rgb="FFB91C1C"/><name val="Calibri"/></font>'       // 5 absent
    '<font><i/><sz val="10"/><color rgb="FF92400E"/><name val="Calibri"/></font>'       // 6 note
    '</fonts>'
    '<fills count="3">'
    '<fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FFF5E6C4"/><bgColor indexed="64"/></patternFill></fill>'
    '</fills>'
    '<borders count="2">'
    '<border><left/><right/><top/><bottom/><diagonal/></border>'
    '<border><left style="thin"><color rgb="FFD1D5DB"/></left><right style="thin"><color rgb="FFD1D5DB"/></right>'
    '<top style="thin"><color rgb="FFD1D5DB"/></top><bottom style="thin"><color rgb="FFD1D5DB"/></bottom><diagonal/></border>'
    '</borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="11">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'                                         // 0
    '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>'                           // 1 title
    '<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/>'                           // 2 sub
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'                           // 3 label
    '<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">'
    '<alignment vertical="center"/></xf>'                                                                     // 4 header
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"/>'                         // 5 body
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1">'
    '<alignment horizontal="center"/></xf>'                                                                   // 6 centered
    '<xf numFmtId="0" fontId="4" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1"/>'           // 7 present
    '<xf numFmtId="0" fontId="5" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1"/>'           // 8 absent
    '<xf numFmtId="9" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>'   // 9 percent
    '<xf numFmtId="0" fontId="6" fillId="0" borderId="0" xfId="0" applyFont="1"/>'                           // 10 note
    '</cellXfs>'
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
    '</styleSheet>';

/// XML-escapes [s] and drops control characters XML 1.0 doesn't allow.
String _xml(String s) => s
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

// ══════════════════════════════════════════════════════════════════════════════
// PDF
// ══════════════════════════════════════════════════════════════════════════════

const kPdfMime = 'application/pdf';

const _ink    = PdfColor.fromInt(0xFF111827);
const _sub    = PdfColor.fromInt(0xFF4B5563);
const _muted  = PdfColor.fromInt(0xFF6B7280);
const _line   = PdfColor.fromInt(0xFFE5E7EB);
const _goldDk = PdfColor.fromInt(0xFF8A6114);   // readable on white (5:1+)
const _goldBg = PdfColor.fromInt(0xFFF5E6C4);
const _green  = PdfColor.fromInt(0xFF15803D);
const _red    = PdfColor.fromInt(0xFFB91C1C);

Future<Uint8List> buildAttendancePdf(AttendanceRecord rec) async {
  pw.MemoryImage? logo;
  try {
    logo = pw.MemoryImage((await rootBundle.load('assets/logo.jpg')).buffer.asUint8List());
  } catch (_) {}

  final doc = pw.Document(title: '${_pdf(rec.title)} - Attendance record', author: 'J-Jireh EventHub');
  final rejected = rec.count(AttendanceMark.rejected);
  final closes = rec.checkInClosesAt;

  pw.Widget label(String s) => pw.Text(_pdf(s).toUpperCase(),
      style: const pw.TextStyle(fontSize: 7.5, color: _muted, letterSpacing: 0.6));

  pw.Widget info(String k, String v) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.SizedBox(width: 62, child: label(k)),
      pw.Expanded(child: pw.Text(_pdf(v), style: const pw.TextStyle(fontSize: 10, color: _ink))),
    ]),
  );

  pw.Widget stat(String k, String v, PdfColor c) => pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        label(k),
        pw.SizedBox(height: 3),
        pw.Text(v, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: c)),
      ]),
    ),
  );

  final tableData = [
    for (var i = 0; i < rec.rows.length; i++)
      [
        '${i + 1}',
        _pdf(rec.rows[i].name),
        rec.rows[i].lrn,
        [
          if (rec.rows[i].grade != null) '${rec.rows[i].grade}',
          if (rec.rows[i].strand != null) rec.rows[i].strand!,
        ].join(' '),
        _pdf(rec.rows[i].section ?? ''),
        rec.rows[i].mark == AttendanceMark.present && rec.rows[i].checkedInAt != null
            ? _fmtClock(rec.rows[i].checkedInAt!)
            : '',
        attendanceMarkLabel(rec.rows[i].mark),
      ],
  ];

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 32),
    maxPages: 500,
    header: (ctx) => ctx.pageNumber == 1
        ? pw.SizedBox()
        : pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 10),
            child: pw.Text('${_pdf(rec.title)}  ·  Attendance record (continued)',
                style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
          ),
    footer: (ctx) => pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _line))),
      child: pw.Row(children: [
        pw.Expanded(child: pw.Text(
            'J-Jireh EventHub  ·  Generated ${_fmtStamp(rec.generatedAt)}',
            style: const pw.TextStyle(fontSize: 8, color: _muted))),
        pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: _muted)),
      ]),
    ),
    build: (ctx) => [
      // Letterhead
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        if (logo != null) ...[
          pw.ClipRRect(horizontalRadius: 6, verticalRadius: 6,
              child: pw.Image(logo, width: 40, height: 40, fit: pw.BoxFit.cover)),
          pw.SizedBox(width: 10),
        ],
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('J-JIREH SCHOOL, INC.', style: pw.TextStyle(fontSize: 10,
              fontWeight: pw.FontWeight.bold, color: _goldDk, letterSpacing: 1)),
          pw.SizedBox(height: 2),
          pw.Text('Event Attendance Record', style: const pw.TextStyle(fontSize: 9, color: _sub)),
        ]),
      ]),
      pw.SizedBox(height: 10),
      pw.Container(height: 2, color: _goldBg),
      pw.SizedBox(height: 14),

      pw.Text(_pdf(rec.title), style: pw.TextStyle(fontSize: 18,
          fontWeight: pw.FontWeight.bold, color: _ink)),
      pw.SizedBox(height: 12),

      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(child: pw.Column(children: [
          info('Date', rec.dateLabel),
          info('Time', rec.timeLabel),
          info('Venue', rec.venue),
        ])),
        pw.SizedBox(width: 16),
        pw.Expanded(child: pw.Column(children: [
          info('Type', rec.type),
          info('Organizer', _orDash(rec.organizerName)),
        ])),
      ]),
      pw.SizedBox(height: 8),

      pw.Row(children: [
        stat('Registered', '${rec.registered}', _ink),
        pw.SizedBox(width: 8),
        stat('Present', '${rec.present}', _green),
        pw.SizedBox(width: 8),
        stat('Absent', '${rec.count(AttendanceMark.absent)}', _red),
        if (rejected > 0) ...[
          pw.SizedBox(width: 8),
          stat('Rejected', '$rejected', _red),
        ],
        pw.SizedBox(width: 8),
        stat('Attendance', '${(rec.rate * 100).round()}%', _goldDk),
      ]),

      if (closes != null) ...[
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFFEF3C7),
              borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Text(
              'Check-in was still open when this record was generated (closes '
              '${_fmtStamp(closes)}). Late check-ins are not included.',
              style: const pw.TextStyle(fontSize: 8.5, color: PdfColor.fromInt(0xFF92400E))),
        ),
      ],
      pw.SizedBox(height: 16),

      if (rec.rows.isEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 24),
          child: pw.Center(child: pw.Text('No students registered for this event.',
              style: const pw.TextStyle(fontSize: 10, color: _muted))),
        )
      else
        pw.TableHelper.fromTextArray(
          headers: ['No.', 'Name', 'LRN', 'Grade', 'Section', 'Checked in', 'Attendance'],
          data: tableData,
          border: const pw.TableBorder(
            horizontalInside: pw.BorderSide(color: _line, width: 0.6),
            bottom: pw.BorderSide(color: _line, width: 0.6),
          ),
          headerDecoration: const pw.BoxDecoration(color: _goldBg),
          headerStyle: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _ink),
          headerAlignment: pw.Alignment.centerLeft,
          cellStyle: const pw.TextStyle(fontSize: 8.5, color: _ink),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4.5),
          headerPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
          cellAlignments: {0: pw.Alignment.centerRight},
          columnWidths: const {
            0: pw.FixedColumnWidth(26),
            1: pw.FlexColumnWidth(3),
            2: pw.FixedColumnWidth(98),
            3: pw.FixedColumnWidth(54),
            4: pw.FlexColumnWidth(1.4),
            5: pw.FixedColumnWidth(56),
            6: pw.FixedColumnWidth(58),
          },
          textStyleBuilder: (col, data, row) => col != 6 || row == 0
              ? null
              : pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold,
                  color: data == 'Present' ? _green : _red),
        ),

      // Sign-off block for submitting the record to the school.
      pw.SizedBox(height: 36),
      pw.Row(children: [
        pw.SizedBox(
          width: 200,
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Container(height: 0.8, color: _sub),
            pw.SizedBox(height: 4),
            pw.Text(_pdf(_orDash(rec.organizerName)),
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _ink)),
            pw.Text('Prepared by (event organizer)',
                style: const pw.TextStyle(fontSize: 8, color: _muted)),
          ]),
        ),
      ]),
    ],
  ));

  return doc.save();
}

/// The PDF's built-in Helvetica only covers Latin-1 (ñ, é… are fine): swap
/// common typographic characters for plain ones and replace anything else.
String _pdf(String s) => s
    .replaceAll(RegExp('[–—−]'), '-')
    .replaceAll(RegExp('[‘’‚′]'), "'")
    .replaceAll(RegExp('[“”„″]'), '"')
    .replaceAll('…', '...')
    .replaceAll(RegExp(r'[^\x00-\xFF]'), '?');

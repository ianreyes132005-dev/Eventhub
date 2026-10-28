// ─────────────────────────────────────────────────────────────────────────────
// Admin — Students tab: import the registrar's student list.
//
// The registrar's export (DepEd LIS SF1 in Excel, or any CSV) is the source of
// truth. Each import is matched to EventHub by LRN:
//   in file, not in EventHub      → New      (account created, password generated)
//   in both, grade/strand/… differ → Update  (this is how a new school year rolls in)
//   in both, identical             → Unchanged
//   in EventHub, not in file       → Not in list (optional deactivate — never deleted)
//
// Privacy: the file is read here in the browser. Only LRN, last/first name,
// grade, strand and section are sent to the server; the original file (with
// birthdates, addresses, guardians…) is never uploaded or stored.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/friendly_error.dart';
import '../../core/services/supabase_service.dart';
import '../../shared/utils/csv_download.dart';
import '../organizer/web/attendance_record.dart'
    show StudentLogin, buildStudentLoginsXlsx, kXlsxMime;
import '../organizer/web/web_shared.dart';
import 'admin_shared.dart';

const _kImportStrands = ['STEM', 'HUMSS', 'GAS'];
const _kBatchSize = 50; // must stay ≤ MAX_ROWS in bulk-upsert-students

// ═════════════════════════════════════════════════════════════════════════════
// Reading files
// ═════════════════════════════════════════════════════════════════════════════

/// RFC-4180 CSV → rows of cells. Handles quoted cells, escaped quotes, CRLF,
/// a UTF-8 BOM, and comma / semicolon / tab delimiters.
List<List<String>> parseCsvText(String text) {
  if (text.startsWith('﻿')) text = text.substring(1);
  final firstLine = text.split('\n').first;
  final delim = [',', ';', '\t'].reduce(
    (a, b) => firstLine.split(a).length >= firstLine.split(b).length ? a : b,
  );

  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == delim) {
      row.add(cell.toString().trim());
      cell.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString().trim());
      cell.clear();
      rows.add(row);
      row = <String>[];
    } else {
      cell.write(ch);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString().trim());
    rows.add(row);
  }
  return rows;
}

/// Reads an .xlsx workbook into rows of display strings and returns the
/// first worksheet with a recognizable header row (else the largest sheet).
///
/// A small purpose-built reader instead of a general Excel library: .xlsx is
/// a zip of XML parts, and registrar / Google Sheets / Python-generated files
/// vary in ways general libraries choke on (absolute part paths like
/// "/xl/worksheets/sheet1.xml", inline strings, namespace prefixes, unusual
/// styles). Only cell *values* are read — styles are never parsed.
({String sheet, List<List<String>> rows}) readXlsxRows(Uint8List bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FriendlyException(
      'This doesn’t look like an Excel (.xlsx) file. If it’s an older .xls file, '
      'open it in Excel and “Save As” .xlsx or CSV, then try again.',
    );
  }

  String? part(String path) {
    final f = zip.findFile(path);
    if (f == null) return null;
    return utf8.decode(f.content as List<int>, allowMalformed: true);
  }

  final workbookXml = part('xl/workbook.xml');
  if (workbookXml == null) {
    throw const FriendlyException('This Excel file has no workbook inside it.');
  }
  final workbook = XmlDocument.parse(workbookXml);

  // rId → part path. Targets may be relative to xl/ ("worksheets/sheet1.xml")
  // or absolute ("/xl/worksheets/sheet1.xml").
  final targets = <String, String>{};
  String? sharedStringsPath;
  final relsXml = part('xl/_rels/workbook.xml.rels');
  if (relsXml != null) {
    for (final rel in _xmlEls(XmlDocument.parse(relsXml), 'Relationship')) {
      final id = rel.getAttribute('Id');
      final target = rel.getAttribute('Target');
      if (id == null || target == null) continue;
      final path = _resolvePart(target);
      targets[id] = path;
      if ((rel.getAttribute('Type') ?? '').endsWith('/sharedStrings')) {
        sharedStringsPath = path;
      }
    }
  }

  // Shared string table (absent when every cell uses inline strings).
  final shared = <String>[];
  final ssXml = part(sharedStringsPath ?? 'xl/sharedStrings.xml');
  if (ssXml != null) {
    for (final si in _xmlEls(XmlDocument.parse(ssXml), 'si')) {
      shared.add(_xmlEls(si, 't').map((t) => t.innerText).join());
    }
  }

  var bestName = '';
  var bestRows = <List<String>>[];
  var index = 0;
  for (final sheet in _xmlEls(workbook, 'sheet')) {
    index++;
    final name = sheet.getAttribute('name') ?? 'Sheet$index';
    final rid = sheet.attributes
        .where((a) => a.name.local == 'id')
        .map((a) => a.value)
        .firstOrNull;
    final sheetXml = part(targets[rid] ?? 'xl/worksheets/sheet$index.xml');
    if (sheetXml == null) continue;

    final rows = _readSheetRows(XmlDocument.parse(sheetXml), shared);
    if (findHeaderRow(rows) != null) return (sheet: name, rows: rows);
    if (rows.length > bestRows.length) {
      bestName = name;
      bestRows = rows;
    }
  }
  return (sheet: bestName, rows: bestRows);
}

/// Descendant elements by local name (ignores namespace prefixes like "x:").
Iterable<XmlElement> _xmlEls(XmlNode node, String local) => node.descendants
    .whereType<XmlElement>()
    .where((e) => e.name.local == local);

/// Relationship target → zip path: "/xl/a.xml" → "xl/a.xml",
/// "worksheets/s.xml" → "xl/worksheets/s.xml", "../x.xml" handled.
String _resolvePart(String target) {
  final t = target.replaceAll('\\', '/');
  if (t.startsWith('/')) return t.substring(1);
  final out = <String>['xl'];
  for (final seg in t.split('/')) {
    if (seg.isEmpty || seg == '.') continue;
    if (seg == '..') {
      if (out.isNotEmpty) out.removeLast();
    } else {
      out.add(seg);
    }
  }
  return out.join('/');
}

/// "AB12" → 27 (zero-based column index); null when there's no reference.
int? _colIndex(String? ref) {
  if (ref == null) return null;
  var n = 0;
  var any = false;
  for (final ch in ref.toUpperCase().codeUnits) {
    if (ch < 65 || ch > 90) break;
    n = n * 26 + (ch - 64);
    any = true;
  }
  return any ? n - 1 : null;
}

List<List<String>> _readSheetRows(XmlDocument doc, List<String> shared) {
  final rows = <List<String>>[];
  for (final row in _xmlEls(doc, 'row')) {
    // Rows can skip numbers (blank rows aren't written) — keep positions so
    // reported row numbers match what the admin sees in Excel.
    final rowNo = int.tryParse(row.getAttribute('r') ?? '') ?? rows.length + 1;
    while (rows.length < rowNo - 1) {
      rows.add(<String>[]);
    }

    final cells = <String>[];
    for (final c in row.childElements.where((e) => e.name.local == 'c')) {
      final col = _colIndex(c.getAttribute('r')) ?? cells.length;
      while (cells.length < col) {
        cells.add('');
      }
      final value = _xlsxCellValue(c, shared);
      if (cells.length == col) {
        cells.add(value);
      } else {
        cells[col] = value;
      }
    }
    rows.add(cells);
  }
  return rows;
}

String _xlsxCellValue(XmlElement c, List<String> shared) {
  final type = c.getAttribute('t');
  final v =
      c.childElements
          .where((e) => e.name.local == 'v')
          .map((e) => e.innerText)
          .firstOrNull ??
      '';
  switch (type) {
    case 'inlineStr':
      return _xmlEls(c, 't').map((t) => t.innerText).join().trim();
    case 's':
      final i = int.tryParse(v);
      return i != null && i >= 0 && i < shared.length ? shared[i].trim() : '';
    case 'str':
      return v.trim();
    case 'b':
      return v == '1' ? 'TRUE' : 'FALSE';
    case 'e':
      return '';
    default:
      // Numbers. LRNs typed as numbers come back as "123456260100" or
      // "1.234562601E+11" — always show whole numbers without ".0" / exponent.
      final d = double.tryParse(v);
      if (d != null && d == d.roundToDouble() && d.abs() < 1e15) {
        return d.toStringAsFixed(0);
      }
      return v.trim();
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Recognizing the layout
// ═════════════════════════════════════════════════════════════════════════════

enum ImportField {
  lrn,
  lastName,
  firstName,
  middleName,
  fullName,
  grade,
  strand,
  section,
}

const importFieldLabels = {
  ImportField.lrn: 'LRN',
  ImportField.lastName: 'Last name',
  ImportField.firstName: 'First name',
  ImportField.middleName: 'Middle name',
  ImportField.fullName: 'Full name',
  ImportField.grade: 'Grade',
  ImportField.strand: 'Strand',
  ImportField.section: 'Section',
};

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Which field a header cell names — registrar wording varies a lot
/// ("LRN", "Learner Reference Number", "NAME (Last Name, First Name, …)").
ImportField? fieldForHeader(String header) {
  final h = _norm(header);
  if (h.isEmpty) return null;
  if (h.startsWith('lrn') ||
      h.contains('learnerreferencenumber') ||
      h == 'learnerid') {
    return ImportField.lrn;
  }
  if (h.contains('extension') || h.contains('suffix')) return null;
  if (h.contains('lastname') && h.contains('firstname'))
    return ImportField.fullName;
  if (h.contains('lastname') ||
      h.contains('surname') ||
      h.contains('familyname')) {
    return ImportField.lastName;
  }
  if (h.contains('firstname') || h.contains('givenname'))
    return ImportField.firstName;
  if (h.contains('middlename') || h.contains('middleinitial') || h == 'mi') {
    return ImportField.middleName;
  }
  if (h.contains('section')) return ImportField.section;
  if (h.contains('strand') || h.contains('track')) return ImportField.strand;
  if (h.contains('gradelevel') ||
      h.contains('yearlevel') ||
      h == 'grade' ||
      h == 'level' ||
      h == 'gradeyear') {
    return ImportField.grade;
  }
  if (h.contains('name')) return ImportField.fullName;
  return null;
}

/// Index of the header row: the first row (in the top 40) naming both an LRN
/// column and some name column. SF1 has several title rows above it.
int? findHeaderRow(List<List<String>> rows) {
  for (var i = 0; i < rows.length && i < 40; i++) {
    final fields = rows[i].map(fieldForHeader).toSet();
    if (fields.contains(ImportField.lrn) &&
        (fields.contains(ImportField.fullName) ||
            fields.contains(ImportField.lastName))) {
      return i;
    }
  }
  return null;
}

Map<ImportField, int> detectColumns(List<String> header) {
  final map = <ImportField, int>{};
  for (var c = 0; c < header.length; c++) {
    final f = fieldForHeader(header[c]);
    if (f != null) map.putIfAbsent(f, () => c);
  }
  return map;
}

/// Grade / section / strand written once for the whole sheet — SF1 prints
/// "Grade Level: 7  Section: Sampaguita" above the table — or in the filename.
({int? grade, String? section, String? strand}) detectSheetContext(
  List<List<String>> rows,
  int headerRow,
  String fileName,
) {
  int? grade;
  String? section, strand;
  for (var r = 0; r < headerRow && r < rows.length; r++) {
    final line = rows[r].where((c) => c.isNotEmpty).join(' | ');
    final g = RegExp(
      r'grade\s*(?:level)?\s*[:\-]?\s*\|?\s*(\d{1,2})\b',
      caseSensitive: false,
    ).firstMatch(line);
    if (g != null) grade ??= int.tryParse(g.group(1)!);
    final s = RegExp(
      r'section\s*[:\-]?\s*\|?\s*([A-Za-z0-9][A-Za-z0-9 .\-]*)',
      caseSensitive: false,
    ).firstMatch(line);
    if (s != null) section ??= s.group(1)!.trim();
    if (RegExp(r'strand|track', caseSensitive: false).hasMatch(line)) {
      final st = RegExp(
        r'\b(STEM|HUMSS|GAS)\b',
        caseSensitive: false,
      ).firstMatch(line);
      if (st != null) strand ??= st.group(1)!.toUpperCase();
    }
  }
  if (grade == null) {
    final g = RegExp(
      r'(?:grade|\bg)[\s_\-]*(\d{1,2})\b',
      caseSensitive: false,
    ).firstMatch(fileName);
    if (g != null) grade = int.tryParse(g.group(1)!);
  }
  if (grade != null && (grade < 7 || grade > 12)) grade = null;
  return (grade: grade, section: section, strand: strand);
}

// ═════════════════════════════════════════════════════════════════════════════
// Building the import plan
// ═════════════════════════════════════════════════════════════════════════════

enum ImportAction { create, update, unchanged, error }

class ImportRow {
  final int line; // spreadsheet row number, 1-based
  String lrn = ''; // 12 digits
  String first = '';
  String last = '';
  String? middle; // null = none
  // The file says what the middle name is (its own column, or one found in a
  // combined name). Only then is it saved, so a list without middle names
  // never erases ones already in EventHub.
  bool middleKnown = false;
  int? grade;
  String? strand;
  String? section;
  final errors = <String>[];
  final notes = <String>[];
  ImportAction action = ImportAction.error;
  String? changes; // "Grade 7 → 8 · Section A → B"
  ImportRow(this.line);

  bool get isShs => grade == 11 || grade == 12;
}

/// How a single "Name" cell *without a comma* is ordered.
/// Registrar masterlists usually put the surname first ("Santos Juan").
enum NameOrder { lastFirst, firstLast }

class ImportOverrides {
  final int? grade;
  final String? strand;
  final String? section;
  final NameOrder nameOrder;
  const ImportOverrides({
    this.grade,
    this.strand,
    this.section,
    this.nameOrder = NameOrder.lastFirst,
  });
}

class StudentImportPlan {
  final List<ImportRow> rows;
  final List<Map<String, dynamic>> notInList;
  final int missingGrade; // rows with no grade before overrides
  final int missingStrand; // SHS rows with no strand before overrides
  final int namesWithoutComma; // combined-name rows that depend on NameOrder
  const StudentImportPlan(
    this.rows,
    this.notInList, {
    required this.missingGrade,
    required this.missingStrand,
    this.namesWithoutComma = 0,
  });

  Iterable<ImportRow> of(ImportAction a) => rows.where((r) => r.action == a);
  int count(ImportAction a) => of(a).length;
}

String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

String? _cleanOpt(String? s) {
  if (s == null) return null;
  final c = adminCleanName(s);
  return c.isEmpty ? null : c;
}

// Surname particles that belong to the word after them ("De Leon",
// "Del Rosario", "Dela Cruz", "De los Santos", "San Jose", "Sta. Maria").
const _kSurnameParticles = {
  'de',
  'del',
  'dela',
  'della',
  'la',
  'las',
  'los',
  'delos',
  'de los',
  'san',
  'santa',
  'sta',
  'sto',
  'santo',
  'van',
  'von',
  'da',
  'di',
  'dos',
  'du',
};

bool _isParticle(String w) =>
    _kSurnameParticles.contains(w.toLowerCase().replaceAll('.', ''));

/// Splits a comma-less name using [order], keeping surname particles with
/// the surname. "Santos Juan Miguel" (lastFirst) → (Santos, Juan Miguel);
/// "De Leon Chloe" → (De Leon, Chloe); "Juan Dela Cruz" (firstLast) →
/// (Dela Cruz, Juan).
(String last, String first, String? note) _splitNoComma(
  String raw,
  NameOrder order,
) {
  final w = raw
      .trim()
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .toList();
  if (w.isEmpty) return ('', '', null);
  if (w.length == 1) return ('', w.first, null);

  if (order == NameOrder.lastFirst) {
    // Surname = leading particles + one word.
    var n = 0;
    while (n < w.length - 1 && _isParticle(w[n])) {
      n++;
    }
    n = (n + 1).clamp(1, w.length - 1);
    final last = w.sublist(0, n).join(' ');
    final first = w.sublist(n).join(' ');
    // 3+ words with no particle: could be a two-word surname — worth a look.
    final note = w.length >= 3 && n == 1 ? 'Check the name split' : null;
    return (last, first, note);
  }

  // firstLast: surname = one word + the particles right before it.
  var s = w.length - 1;
  while (s > 1 && _isParticle(w[s - 1])) {
    s--;
  }
  final last = w.sublist(s).join(' ');
  final first = w.sublist(0, s).join(' ');
  final note = w.length >= 3 && s == w.length - 1
      ? 'Check the name split'
      : null;
  return (last, first, note);
}

/// "DELA CRUZ, JUAN PEREZ" → (Dela Cruz, Juan, Perez) — SF1 lists one
/// combined "Last, First Middle" name. Without a separate middle-name column
/// the last word after the comma, with any surname particle before it
/// ("Juan De Leon" → De Leon), is read as the middle name — noted, since a
/// two-word first name ("Maria Clara") reads the same way.
/// "Last, First, Middle" splits exactly; with a middle-name column the cell
/// holds "Last, First" and the middle name comes from that column.
/// Names without a comma are split by [order] (see [_splitNoComma]); their
/// middle name can't be told apart, so it stays unknown (null).
(String last, String first, String? middle, String? note) _splitFullName(
  String raw, {
  required bool hasMiddleCol,
  required NameOrder order,
}) {
  final parts = raw
      .split(',')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return ('', '', null, null);
  if (parts.length == 1) {
    final (last, first, note) = _splitNoComma(parts.first, order);
    return (last, first, null, note);
  }
  final last = parts[0];
  if (hasMiddleCol) return (last, parts[1], null, null);
  if (parts.length >= 3) {
    return (last, parts[1], parts.sublist(2).join(' '), null); // "Last, First, Middle"
  }
  final words = parts[1].split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.length >= 2) {
    var m = words.length - 1;
    while (m > 1 && _isParticle(words[m - 1])) {
      m--;
    }
    final middle = adminCleanName(words.sublist(m).join(' '));
    return (
      last,
      words.sublist(0, m).join(' '),
      middle,
      'Middle name read as “$middle” — check it',
    );
  }
  return (last, parts[1], null, null);
}

StudentImportPlan buildImportPlan({
  required List<List<String>> rows,
  required int headerRow,
  required Map<ImportField, int> columns,
  required ({int? grade, String? section, String? strand}) context,
  required ImportOverrides overrides,
  required List<Map<String, dynamic>> existing,
}) {
  String cell(List<String> r, ImportField f) {
    final c = columns[f];
    return c == null || c >= r.length ? '' : r[c].trim();
  }

  final byLrn = <String, Map<String, dynamic>>{
    for (final s in existing) _digits(s['lrn'] as String? ?? ''): s,
  };
  final seen = <String, int>{};
  final out = <ImportRow>[];
  var missingGrade = 0, missingStrand = 0, namesWithoutComma = 0;

  for (var i = headerRow + 1; i < rows.length; i++) {
    final r = rows[i];
    if (r.every((c) => c.trim().isEmpty)) continue;

    final rawLrn = cell(r, ImportField.lrn);
    final rawName = [
      cell(r, ImportField.fullName),
      cell(r, ImportField.lastName),
      cell(r, ImportField.firstName),
    ].join(' ').trim();
    // Blank lines and SF1 summary rows ("<=== TOTAL MALE ===>") have no LRN.
    if (rawLrn.isEmpty &&
        (rawName.isEmpty || rawName.toLowerCase().contains('total'))) {
      continue;
    }

    final row = ImportRow(i + 1);
    out.add(row);

    // LRN
    row.lrn = _digits(rawLrn);
    if (row.lrn.isEmpty) {
      row.errors.add('Missing LRN');
    } else if (row.lrn.length != 12) {
      row.errors.add('LRN must be 12 digits (found ${row.lrn.length})');
    } else if (seen.containsKey(row.lrn)) {
      row.errors.add('Same LRN as row ${seen[row.lrn]}');
    } else {
      seen[row.lrn] = row.line;
    }

    // Name
    if (columns.containsKey(ImportField.lastName) ||
        columns.containsKey(ImportField.firstName)) {
      row.last = adminCleanName(cell(r, ImportField.lastName));
      row.first = adminCleanName(cell(r, ImportField.firstName));
    } else {
      final full = cell(r, ImportField.fullName);
      if (full.isNotEmpty && !full.contains(',')) namesWithoutComma++;
      final (l, f, m, note) = _splitFullName(
        full,
        hasMiddleCol: columns.containsKey(ImportField.middleName),
        order: overrides.nameOrder,
      );
      row.last = adminCleanName(l);
      row.first = adminCleanName(f);
      if (m != null) {
        row.middle = _cleanOpt(m);
        row.middleKnown = true;
      }
      if (note != null) row.notes.add(note);
    }
    // Middle name column (blank cell = no middle name).
    if (columns.containsKey(ImportField.middleName)) {
      row.middle = _cleanOpt(cell(r, ImportField.middleName));
      row.middleKnown = true;
      // A "First Middle" first-name cell next to it: keep the middle name once.
      final m = row.middle;
      if (m != null && row.first.toLowerCase().endsWith(' ${m.toLowerCase()}')) {
        row.first = row.first.substring(0, row.first.length - m.length).trim();
      }
    }
    if (row.last.isEmpty) row.errors.add('Missing last name');
    if (row.first.isEmpty) row.errors.add('Missing first name');

    // Grade
    final g = int.tryParse(_digits(cell(r, ImportField.grade)));
    row.grade = g ?? context.grade;
    if (row.grade == null) {
      missingGrade++;
      row.grade = overrides.grade;
    }
    if (row.grade == null) {
      row.errors.add('Missing grade level');
    } else if (row.grade! < 7 || row.grade! > 12) {
      row.errors.add('Grade ${row.grade} is outside 7–12');
    }

    // Strand (Senior High only)
    if (row.isShs) {
      final raw = cell(r, ImportField.strand);
      String? st;
      for (final s in _kImportStrands) {
        if (RegExp('\\b$s\\b', caseSensitive: false).hasMatch(raw)) st = s;
      }
      if (st == null && raw.isNotEmpty) {
        row.errors.add('Strand “$raw” isn’t offered (STEM, HUMSS, GAS)');
      } else {
        st ??= context.strand;
        if (st == null) {
          missingStrand++;
          st = overrides.strand;
        }
        if (st == null) row.errors.add('Missing strand');
        row.strand = st;
      }
    }

    // Section (optional)
    row.section =
        _cleanOpt(cell(r, ImportField.section)) ??
        _cleanOpt(context.section) ??
        _cleanOpt(overrides.section);

    if (row.errors.isNotEmpty) {
      row.action = ImportAction.error;
      continue;
    }

    // Compare with EventHub
    final ex = byLrn[row.lrn];
    if (ex == null) {
      row.action = ImportAction.create;
      continue;
    }
    final diffs = <String>[];
    final exGrade = ex['year_level'] as int?;
    if (exGrade != row.grade)
      diffs.add('Grade ${exGrade ?? '—'} → ${row.grade}');
    final exStrand = (exGrade == 11 || exGrade == 12)
        ? ex['strand'] as String?
        : null;
    if (exStrand != row.strand)
      diffs.add('Strand ${exStrand ?? '—'} → ${row.strand ?? '—'}');
    final exSection = ex['section'] as String?;
    if ((exSection ?? '').toLowerCase() != (row.section ?? '').toLowerCase()) {
      diffs.add('Section ${exSection ?? '—'} → ${row.section ?? '—'}');
    }
    final exFull = (ex['full_name'] as String? ?? '').trim().toLowerCase();
    final exFirst = (ex['first_name'] as String? ?? '').trim().toLowerCase();
    final exLast = (ex['last_name'] as String? ?? '').trim().toLowerCase();
    final nameSame = exFirst.isNotEmpty && exLast.isNotEmpty
        ? exFirst == row.first.toLowerCase() && exLast == row.last.toLowerCase()
        : exFull == '${row.first} ${row.last}'.toLowerCase();
    final exMiddle = (ex['middle_name'] as String? ?? '').trim();
    if (!nameSame) {
      diffs.add('Name');
    } else if (row.middleKnown &&
        exMiddle.toLowerCase() != (row.middle ?? '').toLowerCase()) {
      diffs.add('Middle name ${exMiddle.isEmpty ? '—' : exMiddle} → ${row.middle ?? '—'}');
    }
    if (ex['is_active'] != true) row.notes.add('Account is deactivated');

    row.action = diffs.isEmpty ? ImportAction.unchanged : ImportAction.update;
    row.changes = diffs.isEmpty ? null : diffs.join(' · ');
  }

  // Active students in the same grade(s) — and section(s), when the file
  // names them — who aren't on the list: likely graduated or transferred.
  final fileLrns = seen.keys.toSet();
  final fileGrades = out.map((r) => r.grade).whereType<int>().toSet();
  final fileSections = out
      .map((r) => r.section?.toLowerCase())
      .whereType<String>()
      .toSet();
  final notInList = existing.where((s) {
    if (s['is_active'] != true) return false;
    if (fileLrns.contains(_digits(s['lrn'] as String? ?? ''))) return false;
    if (!fileGrades.contains(s['year_level'])) return false;
    if (fileSections.isEmpty) return true;
    final sec = (s['section'] as String?)?.toLowerCase();
    return sec != null && fileSections.contains(sec);
  }).toList();

  return StudentImportPlan(
    out,
    notInList,
    missingGrade: missingGrade,
    missingStrand: missingStrand,
    namesWithoutComma: namesWithoutComma,
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// CSV output (template / logins / failures)
// ═════════════════════════════════════════════════════════════════════════════

// Quotes every cell; neutralizes spreadsheet formula injection (=, +, -, @).
String _csv(List<List<String>> rows) => rows
    .map(
      (r) => r
          .map((c) {
            var v = c;
            if (v.isNotEmpty && '=+-@'.contains(v[0])) v = "'$v";
            return '"${v.replaceAll('"', '""')}"';
          })
          .join(','),
    )
    .join('\r\n');

String _fmtLrn(String d) => d.length == 12
    ? '${d.substring(0, 6)} - ${d.substring(6, 8)} - ${d.substring(8)}'
    : d;

void downloadStudentImportTemplate() => downloadCsv(
  _csv([
    ['LRN', 'Last Name', 'First Name', 'Middle Name', 'Grade Level', 'Strand', 'Section'],
    ['123456260001', 'Dela Cruz', 'Juan', 'Reyes', '7', '', 'Sampaguita'],
    ['123456240015', 'Santos', 'Maria', '', '11', 'STEM', 'Einstein'],
  ]),
  'eventhub_student_import_template',
);

// ═════════════════════════════════════════════════════════════════════════════
// Dialog
// ═════════════════════════════════════════════════════════════════════════════

enum _Step { upload, review, applying, done }

class _RowResult {
  final ImportRow row;
  final bool ok;
  final String? error;
  final String? password;
  const _RowResult(this.row, {required this.ok, this.error, this.password});
}

/// Returns `true` when anything was written (the Students tab reloads).
class AdminStudentImportDialog extends StatefulWidget {
  final List<Map<String, dynamic>> existing;

  /// Starts on the Review step with already-read rows (widget tests only —
  /// the real flow goes through the file picker).
  @visibleForTesting
  final ({String name, List<List<String>> rows})? debugFile;
  const AdminStudentImportDialog({
    super.key,
    required this.existing,
    this.debugFile,
  });

  static Future<bool?> show(
    BuildContext context,
    List<Map<String, dynamic>> existing,
  ) => showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AdminStudentImportDialog(existing: existing),
  );

  @override
  State<AdminStudentImportDialog> createState() =>
      _AdminStudentImportDialogState();
}

class _AdminStudentImportDialogState extends State<AdminStudentImportDialog> {
  _Step _step = _Step.upload;
  bool _reading = false;

  // Parsed file
  String _fileName = '';
  String _sheet = '';
  List<List<String>> _rows = const [];
  int _headerRow = 0;
  Map<ImportField, int> _columns = {};
  ({int? grade, String? section, String? strand}) _context = (
    grade: null,
    section: null,
    strand: null,
  );

  // Admin choices on the review step
  int? _ovGrade;
  String? _ovStrand;
  final _ovSectionCtrl = TextEditingController();
  bool _showMapping = false;
  ImportAction? _tab = ImportAction.create; // null = "Not in list"
  bool _deactivateMissing = false;
  NameOrder _nameOrder = NameOrder.lastFirst;

  StudentImportPlan? _plan;

  // Applying / done
  int _done = 0, _total = 0;
  final _results = <_RowResult>[];
  int _deactivated = 0;
  String? _deactivateError;

  @override
  void initState() {
    super.initState();
    final f = widget.debugFile;
    if (f != null) _loadRows(f.name, '', f.rows);
  }

  @override
  void dispose() {
    _ovSectionCtrl.dispose();
    super.dispose();
  }

  /// Recognizes the layout of already-read rows and moves to Review.
  void _loadRows(String name, String sheet, List<List<String>> rows) {
    final header = findHeaderRow(rows);
    if (header == null) {
      throw const FriendlyException(
        'Couldn’t find the column headers. The file needs an “LRN” column '
        'and a name column (e.g. “Name” or “Last Name” / “First Name”).',
      );
    }
    _fileName = name;
    _sheet = sheet;
    _rows = rows;
    _headerRow = header;
    _columns = detectColumns(rows[header]);
    _context = detectSheetContext(rows, header, name);
    _step = _Step.review;
    _rebuildPlan();
  }

  // ── Step 1: read the file ──────────────────────────────────────────────────

  Future<void> _pickFile() async {
    setState(() {
      _reading = true;
    });
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'csv'],
        withData: true,
      );
      final f = picked?.files.single;
      if (f == null) {
        setState(() => _reading = false);
        return;
      }
      if (f.bytes == null) {
        throw const FriendlyException(
          'The selected file couldn’t be opened. Try saving it again as .xlsx or CSV.',
        );
      }

      final ext = (f.extension ?? '').toLowerCase();
      List<List<String>> rows;
      var sheet = '';
      if (ext == 'xlsx') {
        final r = readXlsxRows(f.bytes!);
        rows = r.rows;
        sheet = r.sheet;
      } else if (ext == 'csv') {
        rows = parseCsvText(utf8.decode(f.bytes!, allowMalformed: true));
      } else {
        throw const FriendlyException('Choose an Excel (.xlsx) or CSV file.');
      }

      setState(() {
        _loadRows(f.name, sheet, rows);
        _reading = false;
      });
    } catch (e) {
      // The technical reason goes to the debug log, so a reader bug can
      // still be told apart from a bad file.
      debugPrint('Student import: the file couldn’t be read: $e');
      if (mounted) setState(() => _reading = false);
      final message = e is FriendlyException
          ? e.message
          : 'Couldn’t read this file. Try opening it in Excel and saving it again '
                'as .xlsx or CSV.';
      if (mounted) {
        await Swal.fire(
          context,
          icon: SwalIcon.error,
          title: 'Couldn’t open file',
          text: message,
          confirmButtonColor: kAdminSwalConfirm,
        );
      }
    }
  }

  void _rebuildPlan() {
    _plan = buildImportPlan(
      rows: _rows,
      headerRow: _headerRow,
      columns: _columns,
      context: _context,
      overrides: ImportOverrides(
        grade: _ovGrade,
        strand: _ovStrand,
        nameOrder: _nameOrder,
        section: _ovSectionCtrl.text.trim().isEmpty
            ? null
            : _ovSectionCtrl.text,
      ),
      existing: widget.existing,
    );
  }

  void _update(VoidCallback fn) => setState(() {
    fn();
    _rebuildPlan();
  });

  // ── Step 3: apply ──────────────────────────────────────────────────────────

  Future<void> _apply() async {
    final plan = _plan!;
    final work = [
      ...plan.of(ImportAction.create),
      ...plan.of(ImportAction.update),
    ];
    final passwords = {
      for (final r in plan.of(ImportAction.create))
        r.lrn: adminGeneratePassword(),
    };
    setState(() {
      _step = _Step.applying;
      _done = 0;
      _total = work.length;
    });

    for (var i = 0; i < work.length; i += _kBatchSize) {
      final batch = work.sublist(i, (i + _kBatchSize).clamp(0, work.length));
      try {
        final res = await SupabaseService.client.functions.invoke(
          'bulk-upsert-students',
          body: {
            'rows': [
              for (final r in batch)
                {
                  'action': r.action == ImportAction.create
                      ? 'create'
                      : 'update',
                  'lrn': r.lrn,
                  'first_name': r.first,
                  'last_name': r.last,
                  // Only when the file says — never erase a saved one.
                  if (r.middleKnown) 'middle_name': r.middle,
                  'year_level': r.grade,
                  'strand': r.strand,
                  'section': r.section,
                  if (r.action == ImportAction.create)
                    'password': passwords[r.lrn],
                },
            ],
          },
        );
        final data = res.data is Map
            ? Map<String, dynamic>.from(res.data as Map)
            : null;
        final list = data?['results'] as List?;
        if (res.status != 200 || list == null) {
          final raw = data?['message'] as String?;
          // Supabase answers 404 "Requested function was not found" when
          // the Edge Function was never deployed.
          final msg =
              res.status == 404 && (raw == null || raw.contains('function'))
              ? 'The import service isn’t set up yet. Please contact the system administrator.'
              : friendlyError(
                  raw,
                  fallback:
                      'The import service couldn’t process these rows. Please try again.',
                );
          for (final r in batch) {
            _results.add(_RowResult(r, ok: false, error: msg));
          }
        } else {
          for (var j = 0; j < batch.length; j++) {
            final m = j < list.length
                ? Map<String, dynamic>.from(list[j] as Map)
                : null;
            final ok = m?['ok'] == true;
            _results.add(
              _RowResult(
                batch[j],
                ok: ok,
                error: ok
                    ? null
                    : friendlyError(
                        m?['error'],
                        fallback:
                            'This row couldn’t be imported. Please try again.',
                      ),
                password: ok && batch[j].action == ImportAction.create
                    ? passwords[batch[j].lrn]
                    : null,
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('bulk-upsert-students failed: $e');
        final msg = friendlyError(
          e,
          fallback: 'Couldn’t reach the import service. Please try again.',
        );
        for (final r in batch) {
          _results.add(_RowResult(r, ok: false, error: msg));
        }
      }
      if (!mounted) return;
      setState(() => _done = (i + batch.length).clamp(0, work.length));
    }

    if (_deactivateMissing && plan.notInList.isNotEmpty) {
      try {
        final lrns = plan.notInList.map((s) => s['lrn'] as String).toList();
        final updated = await SupabaseService.client
            .from('students')
            .update({'is_active': false})
            .in_('lrn', lrns)
            .select('lrn');
        _deactivated = (updated as List).length;
      } catch (e) {
        debugPrint('Student import: deactivation failed: $e');
        _deactivateError =
            'The students missing from the list couldn’t be '
            'deactivated. ${friendlyError(e)}';
      }
    }
    if (mounted) setState(() => _step = _Step.done);
  }

  // An Excel file of the new accounts' initial passwords, sorted grade →
  // section → name (buildStudentLoginsXlsx).
  void _downloadLogins() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    downloadFile(
      buildStudentLoginsXlsx(
        [
          for (final r in _results)
            if (r.ok && r.password != null)
              StudentLogin(
                lrn: _fmtLrn(r.row.lrn),
                last: r.row.last,
                first: r.row.first,
                middle: r.row.middle,
                grade: r.row.grade,
                strand: r.row.strand,
                section: r.row.section,
                password: r.password!,
              ),
        ],
        generatedAt: now,
      ),
      'Student logins - ${now.year}-${two(now.month)}-${two(now.day)}.xlsx',
      kXlsxMime,
    );
  }

  void _downloadFailures() {
    downloadCsv(
      _csv([
        [
          'Row',
          'LRN',
          'Last Name',
          'First Name',
          'Middle Name',
          'Grade',
          'Strand',
          'Section',
          'Problem',
        ],
        for (final r in _plan!.of(ImportAction.error))
          [
            '${r.line}',
            r.lrn,
            r.last,
            r.first,
            r.middle ?? '',
            '${r.grade ?? ''}',
            r.strand ?? '',
            r.section ?? '',
            r.errors.join('; '),
          ],
        for (final r in _results.where((r) => !r.ok))
          [
            '${r.row.line}',
            r.row.lrn,
            r.row.last,
            r.row.first,
            r.row.middle ?? '',
            '${r.row.grade ?? ''}',
            r.row.strand ?? '',
            r.row.section ?? '',
            r.error ?? '',
          ],
      ]),
      'eventhub_import_problems',
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final wide = _step == _Step.review;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: wide ? 980 : 560, maxHeight: 760),
        child: Container(
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 40,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: t.border)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AdminDialogHeader(
                      icon: Icons.upload_file_rounded,
                      iconColor: kAdminAccent,
                      title: 'Import from registrar',
                      subtitle:
                          'Create and update student accounts from the registrar’s list.',
                      closeEnabled: _step != _Step.applying,
                    ),
                    const SizedBox(height: 14),
                    _Stepper(step: _step),
                  ],
                ),
              ),
              Flexible(
                child: switch (_step) {
                  _Step.upload => _buildUpload(t),
                  _Step.review => _buildReview(t),
                  _Step.applying => _buildApplying(t),
                  _Step.done => _buildDone(t),
                },
              ),
              _buildFooter(t),
            ],
          ),
        ),
      ),
    );
  }

  // ── Upload ─────────────────────────────────────────────────────────────────

  Widget _buildUpload(WebTk t) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: kAdminAccent.withValues(alpha: t.dark ? 0.06 : 0.035),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: kAdminAccent.withValues(alpha: 0.35),
              width: 1.2,
            ),
          ),
          child: InkWell(
            onTap: _reading ? null : _pickFile,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
              child: Column(
                children: [
                  _reading
                      ? const SizedBox(
                          width: 30,
                          height: 30,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: kAdminAccent,
                          ),
                        )
                      : Icon(
                          Icons.cloud_upload_outlined,
                          size: 34,
                          color: kAdminAccent.withValues(alpha: 0.85),
                        ),
                  const SizedBox(height: 12),
                  Text(
                    _reading
                        ? 'Reading file…'
                        : 'Choose the registrar’s student list',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Excel (.xlsx) or CSV · e.g. the SF1 export from LIS',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: t.sub,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        _infoLine(
          t,
          Icons.auto_fix_high_rounded,
          'Columns are recognized automatically — LRN, name, grade, strand and section. '
          'Grade and section printed above the table (SF1) are picked up too.',
        ),
        _infoLine(
          t,
          Icons.sync_rounded,
          'Students are matched by LRN: new ones get accounts, existing ones are updated '
          '(e.g. promoted to the next grade). Nothing is saved until you confirm.',
        ),
        _infoLine(
          t,
          Icons.lock_outline_rounded,
          'The file is read on this computer. Only LRN, name, grade, strand and section are '
          'sent to EventHub — birthdates, addresses and other details are not uploaded.',
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: downloadStudentImportTemplate,
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text(
              'Download a CSV template',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: TextButton.styleFrom(foregroundColor: kAdminAccent),
          ),
        ),
      ],
    ),
  );

  Widget _infoLine(WebTk t, IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: t.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: t.sub,
              height: 1.5,
            ),
          ),
        ),
      ],
    ),
  );

  // ── Review ─────────────────────────────────────────────────────────────────

  Widget _buildReview(WebTk t) {
    final plan = _plan!;
    final dataRows = _rows.length - _headerRow - 1;
    final headers = _rows[_headerRow];

    String colDesc(ImportField f) {
      final c = _columns[f];
      if (c != null) return '“${headers[c]}”';
      if (f == ImportField.grade && _context.grade != null)
        return 'Sheet header (Grade ${_context.grade})';
      if (f == ImportField.section && _context.section != null)
        return 'Sheet header (${_context.section})';
      if (f == ImportField.strand && _context.strand != null)
        return 'Sheet header (${_context.strand})';
      return 'Not found';
    }

    final hasNameCols =
        _columns.containsKey(ImportField.lastName) ||
        _columns.containsKey(ImportField.firstName);
    final shownFields = [
      ImportField.lrn,
      if (hasNameCols) ...[
        ImportField.lastName,
        ImportField.firstName,
      ] else
        ImportField.fullName,
      if (hasNameCols || _columns.containsKey(ImportField.middleName))
        ImportField.middleName,
      ImportField.grade,
      ImportField.strand,
      ImportField.section,
    ];

    final needsGrade = plan.missingGrade > 0;
    final needsStrand = plan.missingStrand > 0;
    final needsSection =
        !_columns.containsKey(ImportField.section) && _context.section == null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // File + detected layout
          Row(
            children: [
              Icon(Icons.description_outlined, size: 18, color: t.sub),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: _fileName,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: t.text,
                        ),
                      ),
                      TextSpan(
                        text:
                            '   ${_sheet.isNotEmpty ? 'Sheet “$_sheet” · ' : ''}'
                            '$dataRows rows · headers on row ${_headerRow + 1}',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: t.muted,
                        ),
                      ),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _step = _Step.upload;
                  _plan = null;
                }),
                child: const Text(
                  'Choose another file',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: kAdminAccent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in shownFields)
                _MappingChip(
                  label: importFieldLabels[f]!,
                  value: colDesc(f),
                  found: colDesc(f) != 'Not found',
                ),
              TextButton.icon(
                onPressed: () => setState(() => _showMapping = !_showMapping),
                icon: Icon(
                  _showMapping ? Icons.expand_less_rounded : Icons.tune_rounded,
                  size: 15,
                ),
                label: Text(
                  _showMapping ? 'Hide columns' : 'Adjust columns',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: t.sub,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
          if (_showMapping) ...[
            const SizedBox(height: 10),
            _buildMappingEditor(t, headers),
          ],

          // Names written without a comma — order has to be confirmed
          if (plan.namesWithoutComma > 0) ...[
            const SizedBox(height: 12),
            _buildNameOrder(t),
          ],

          // Values the file doesn't provide
          if (needsGrade || needsStrand || needsSection) ...[
            const SizedBox(height: 12),
            _buildOverrides(
              t,
              needsGrade: needsGrade,
              needsStrand: needsStrand,
              needsSection: needsSection,
            ),
          ],

          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _tabChip(
                'New',
                ImportAction.create,
                plan.count(ImportAction.create),
                const Color(0xFF10B981),
              ),
              _tabChip(
                'Updates',
                ImportAction.update,
                plan.count(ImportAction.update),
                const Color(0xFF3B82F6),
              ),
              _tabChip(
                'Unchanged',
                ImportAction.unchanged,
                plan.count(ImportAction.unchanged),
                kMuted,
              ),
              _tabChip(
                'Needs attention',
                ImportAction.error,
                plan.count(ImportAction.error),
                kAdminErrorRed,
              ),
              _tabChip(
                'Not in list',
                null,
                plan.notInList.length,
                const Color(0xFFF59E0B),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _tab == null
                ? _buildNotInList(t, plan)
                : _buildRowTable(t, plan),
          ),
        ],
      ),
    );
  }

  Widget _tabChip(String label, ImportAction? tab, int count, Color color) =>
      WebFilterChip(
        label: label,
        count: count,
        selected: _tab == tab,
        selectedColor: color,
        onTap: () => setState(() => _tab = tab),
      );

  Widget _buildMappingEditor(WebTk t, List<String> headers) {
    Widget picker(ImportField f) => SizedBox(
      width: 220,
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(
              importFieldLabels[f]!,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: t.text,
              ),
            ),
          ),
          Expanded(
            child: DropdownButton<int>(
              value: _columns[f] ?? -1,
              isExpanded: true,
              isDense: true,
              underline: Container(height: 1, color: t.border),
              dropdownColor: t.card,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                color: t.text,
              ),
              items: [
                DropdownMenuItem(
                  value: -1,
                  child: Text(
                    '—  not in file',
                    style: TextStyle(color: t.muted),
                  ),
                ),
                for (var c = 0; c < headers.length; c++)
                  if (headers[c].trim().isNotEmpty)
                    DropdownMenuItem(
                      value: c,
                      child: Text(headers[c], overflow: TextOverflow.ellipsis),
                    ),
              ],
              onChanged: (v) => _update(() {
                if (v == null || v < 0) {
                  _columns.remove(f);
                } else {
                  _columns[f] = v;
                }
              }),
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.inputBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.border),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 10,
        children: [for (final f in ImportField.values) picker(f)],
      ),
    );
  }

  // "Name format" — shown when the file's single Name column has no commas,
  // with a live example taken from the file itself.
  Widget _buildNameOrder(WebTk t) {
    final col = _columns[ImportField.fullName];
    String? sample;
    if (col != null) {
      for (var i = _headerRow + 1; i < _rows.length; i++) {
        final r = _rows[i];
        final v = col < r.length ? r[col].trim() : '';
        if (v.isNotEmpty &&
            !v.contains(',') &&
            v.contains(' ') &&
            !v.toLowerCase().contains('total')) {
          sample = v;
          break;
        }
      }
    }
    final split = sample == null ? null : _splitNoComma(sample, _nameOrder);

    Widget option(NameOrder o, String title, String example) {
      final sel = _nameOrder == o;
      return Material(
        color: sel ? kAdminAccent.withValues(alpha: 0.10) : t.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: sel ? kAdminAccent : t.border,
            width: sel ? 1.4 : 1,
          ),
        ),
        child: InkWell(
          onTap: () => _update(() => _nameOrder = o),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  sel
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 15,
                  color: sel ? kAdminAccent : t.muted,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    color: sel ? kAdminAccent : t.text,
                  ),
                ),
                Text(
                  '  $example',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11.5,
                    color: t.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: t.inputBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.badge_outlined, size: 15, color: t.sub),
              const SizedBox(width: 8),
              Text(
                'Name format',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: t.text,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Names in this file have no comma — how are they written?',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11.5,
                    color: t.sub,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              option(NameOrder.lastFirst, 'Last name first', 'Santos Juan'),
              option(NameOrder.firstLast, 'First name first', 'Juan Santos'),
            ],
          ),
          if (sample != null && split != null) ...[
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11.5,
                  color: t.sub,
                ),
                children: [
                  const TextSpan(text: 'From your file:  '),
                  TextSpan(
                    text: '“$sample”',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: t.text,
                    ),
                  ),
                  const TextSpan(text: '  →  Last name '),
                  TextSpan(
                    text: adminCleanName(split.$1),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: kAdminAccent,
                    ),
                  ),
                  const TextSpan(text: '  ·  First name '),
                  TextSpan(
                    text: adminCleanName(split.$2),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: kAdminAccent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOverrides(
    WebTk t, {
    required bool needsGrade,
    required bool needsStrand,
    required bool needsSection,
  }) {
    Widget choice(String label, bool sel, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: sel ? kAdminAccent.withValues(alpha: 0.10) : t.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
          side: BorderSide(
            color: sel ? kAdminAccent : t.border,
            width: sel ? 1.4 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                color: sel ? kAdminAccent : t.text,
              ),
            ),
          ),
        ),
      ),
    );
    Widget line(String label, Widget child) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: t.text,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: t.dark ? 0.08 : 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'The file doesn’t say — apply to rows without a value:',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.sub),
          ),
          if (needsGrade)
            line(
              'Grade (${_plan!.missingGrade} rows)',
              Wrap(
                children: [
                  for (final g in [7, 8, 9, 10, 11, 12])
                    choice(
                      '$g',
                      _ovGrade == g,
                      () => _update(() => _ovGrade = g),
                    ),
                ],
              ),
            ),
          if (needsStrand)
            line(
              'Strand (${_plan!.missingStrand} rows)',
              Wrap(
                children: [
                  for (final s in _kImportStrands)
                    choice(
                      s,
                      _ovStrand == s,
                      () => _update(() => _ovStrand = s),
                    ),
                ],
              ),
            ),
          if (needsSection)
            line(
              'Section (optional)',
              SizedBox(
                width: 220,
                height: 34,
                child: TextField(
                  controller: _ovSectionCtrl,
                  onChanged: (_) => _update(() {}),
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12.5,
                    color: t.text,
                  ),
                  decoration: webInputDeco('e.g. Sampaguita', dark: t.dark)
                      .copyWith(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRowTable(WebTk t, StudentImportPlan plan) {
    final rows = plan.of(_tab!).toList();
    if (rows.isEmpty) {
      return Center(
        child: Text(
          switch (_tab!) {
            ImportAction.create => 'No new students in this file.',
            ImportAction.update => 'No changes to existing students.',
            ImportAction.unchanged => 'No unchanged students.',
            ImportAction.error => 'Every row is ready to import. 🎉',
          },
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12.5,
            color: t.muted,
          ),
        ),
      );
    }
    final isError = _tab == ImportAction.error;
    TextStyle h = TextStyle(
      fontFamily: 'Poppins',
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.7,
      color: t.sub,
    );
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: t.bg,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              children: [
                SizedBox(width: 46, child: Text('ROW', style: h)),
                Expanded(flex: 3, child: Text('LRN', style: h)),
                Expanded(flex: 4, child: Text('NAME', style: h)),
                Expanded(flex: 2, child: Text('GRADE', style: h)),
                Expanded(flex: 3, child: Text('SECTION', style: h)),
                Expanded(
                  flex: 5,
                  child: Text(
                    isError
                        ? 'PROBLEM'
                        : _tab == ImportAction.update
                        ? 'CHANGES'
                        : 'NOTES',
                    style: h,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: t.border),
              itemBuilder: (_, i) {
                final r = rows[i];
                final body = TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: t.text,
                );
                final muted = TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11.5,
                  color: t.muted,
                );
                final note = isError
                    ? r.errors.join(' · ')
                    : _tab == ImportAction.update
                    ? (r.changes ?? '')
                    : r.notes.join(' · ');
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 46,
                        child: Text('${r.line}', style: muted),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          r.lrn.isEmpty ? '—' : _fmtLrn(r.lrn),
                          style: body.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: Text(
                          // Roster order: "Last, First Middle".
                          [
                            r.last,
                            [r.first, r.middle ?? '']
                                .where((s) => s.isNotEmpty)
                                .join(' '),
                          ].where((s) => s.isNotEmpty).join(', ').ifEmpty('—'),
                          style: body.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          r.grade == null
                              ? '—'
                              : 'G${r.grade}${r.strand != null ? ' · ${r.strand}' : ''}',
                          style: body,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          r.section ?? '—',
                          style: body,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 5,
                        child: Text(
                          note.ifEmpty('—'),
                          style: isError
                              ? const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11.5,
                                  color: kAdminErrorRed,
                                )
                              : muted,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotInList(WebTk t, StudentImportPlan plan) {
    if (plan.notInList.isEmpty) {
      return Center(
        child: Text(
          'Every active student in these grades is on the list.',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12.5,
            color: t.muted,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Active students in the same grade${plan.notInList.length == 1 ? '' : 's'}'
          ' (and section, when the file lists one) who aren’t in this file — '
          'possibly graduated or transferred. Nothing happens to them unless you choose:',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            color: t.sub,
            height: 1.5,
          ),
        ),
        CheckboxListTile(
          value: _deactivateMissing,
          onChanged: (v) => setState(() => _deactivateMissing = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          activeColor: kAdminAccent,
          title: Text(
            'Deactivate these ${plan.notInList.length} students',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: t.text,
            ),
          ),
          subtitle: Text(
            'They can’t log in until reactivated. Their records are kept.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              color: t.muted,
            ),
          ),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: t.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ListView.separated(
              itemCount: plan.notInList.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: t.border),
              itemBuilder: (_, i) {
                final s = plan.notInList[i];
                final yr = s['year_level'];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          formatLrn(s['lrn'] as String? ?? ''),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: t.sub,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: Text(
                          s['full_name'] as String? ?? '—',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: t.text,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          'G$yr',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: t.text,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          s['section'] as String? ?? '—',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: t.sub,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // ── Applying / done ────────────────────────────────────────────────────────

  Widget _buildApplying(WebTk t) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Saving students…',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: t.text,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$_done of $_total · keep this window open',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: t.sub),
        ),
        const SizedBox(height: 18),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _total == 0 ? null : _done / _total,
            minHeight: 6,
            color: kAdminAccent,
            backgroundColor: t.border,
          ),
        ),
      ],
    ),
  );

  Widget _buildDone(WebTk t) {
    final created = _results
        .where((r) => r.ok && r.row.action == ImportAction.create)
        .length;
    final updated = _results
        .where((r) => r.ok && r.row.action == ImportAction.update)
        .length;
    final failed =
        _results.where((r) => !r.ok).length + _plan!.count(ImportAction.error);
    Widget stat(IconData icon, Color c, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 10),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: t.text,
            ),
          ),
        ],
      ),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          stat(
            Icons.person_add_alt_1_rounded,
            const Color(0xFF10B981),
            '$created account${created == 1 ? '' : 's'} created',
          ),
          stat(
            Icons.sync_rounded,
            const Color(0xFF3B82F6),
            '$updated student${updated == 1 ? '' : 's'} updated',
          ),
          if (_deactivated > 0)
            stat(
              Icons.person_off_outlined,
              const Color(0xFFF59E0B),
              '$_deactivated student${_deactivated == 1 ? '' : 's'} deactivated',
            ),
          if (failed > 0)
            stat(
              Icons.error_outline_rounded,
              kAdminErrorRed,
              '$failed row${failed == 1 ? '' : 's'} not imported',
            ),
          if (_deactivateError != null) ...[
            const SizedBox(height: 4),
            AdminFormErrorBanner(_deactivateError!),
          ],
          if (created > 0) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kAdminAccent.withValues(alpha: t.dark ? 0.08 : 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kAdminAccent.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Download the logins now',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'The Excel file lists each new student’s LRN and initial password, '
                    'sorted by grade and section for advisers. Passwords are shown only '
                    'here — store the file securely.',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11.5,
                      color: t.sub,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: WebBtn(
                      label: 'Download logins (Excel)',
                      icon: Icons.download_rounded,
                      onTap: _downloadLogins,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (failed > 0) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _downloadFailures,
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text(
                  'Download rows that weren’t imported',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5),
                ),
                style: TextButton.styleFrom(foregroundColor: kAdminErrorRed),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Footer ─────────────────────────────────────────────────────────────────

  Widget _buildFooter(WebTk t) {
    final plan = _plan;
    final nCreate = plan?.count(ImportAction.create) ?? 0;
    final nUpdate = plan?.count(ImportAction.update) ?? 0;
    final nDeact = _deactivateMissing ? (plan?.notInList.length ?? 0) : 0;

    String primaryLabel() {
      final parts = [
        if (nCreate > 0) 'create $nCreate',
        if (nUpdate > 0) 'update $nUpdate',
        if (nDeact > 0) 'deactivate $nDeact',
      ];
      if (parts.isEmpty) return 'Nothing to import';
      final s = parts.join(' · ');
      return '${s[0].toUpperCase()}${s.substring(1)}';
    }

    final showCancel = _step == _Step.upload || _step == _Step.review;
    final showPrimary = _step == _Step.review || _step == _Step.done;
    if (_step == _Step.applying) return const SizedBox(height: 8);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          if (_step == _Step.review &&
              (plan?.count(ImportAction.error) ?? 0) > 0)
            Expanded(
              child: Text(
                '${plan!.count(ImportAction.error)} row(s) with problems will be skipped.',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11.5,
                  color: kAdminErrorRed,
                ),
              ),
            )
          else
            const Spacer(),
          if (showCancel)
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: t.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 13,
                  horizontal: 20,
                ),
              ),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  color: t.sub,
                ),
              ),
            ),
          if (showPrimary) ...[
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: _step == _Step.done
                  ? () => Navigator.of(context).pop(true)
                  : (nCreate + nUpdate + nDeact == 0 ? null : _apply),
              style: ElevatedButton.styleFrom(
                backgroundColor: kAdminAccent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: kAdminAccent.withValues(alpha: 0.35),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 13,
                  horizontal: 22,
                ),
              ),
              child: Text(
                _step == _Step.done ? 'Done' : primaryLabel(),
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

// ─── Small pieces ─────────────────────────────────────────────────────────────

class _Stepper extends StatelessWidget {
  final _Step step;
  const _Stepper({required this.step});

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    const labels = ['Upload', 'Review', 'Save', 'Done'];
    final current = step.index;
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < current
                  ? kAdminAccent
                  : i == current
                  ? kAdminAccent.withValues(alpha: 0.14)
                  : t.inputBg,
              border: Border.all(color: i <= current ? kAdminAccent : t.border),
            ),
            alignment: Alignment.center,
            child: i < current
                ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                : Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: i == current ? kAdminAccent : t.muted,
                    ),
                  ),
          ),
          const SizedBox(width: 6),
          Text(
            labels[i],
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11.5,
              fontWeight: i == current ? FontWeight.w700 : FontWeight.w500,
              color: i == current ? t.text : t.muted,
            ),
          ),
          if (i < labels.length - 1)
            Expanded(
              child: Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: i < current
                    ? kAdminAccent.withValues(alpha: 0.6)
                    : t.border,
              ),
            ),
        ],
      ],
    );
  }
}

class _MappingChip extends StatelessWidget {
  final String label, value;
  final bool found;
  const _MappingChip({
    required this.label,
    required this.value,
    required this.found,
  });

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final c = found ? const Color(0xFF10B981) : t.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: t.inputBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            found
                ? Icons.check_circle_rounded
                : Icons.remove_circle_outline_rounded,
            size: 13,
            color: c,
          ),
          const SizedBox(width: 6),
          Text(
            '$label  ',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: t.text,
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11.5,
                color: t.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:eventhub/features/admin/admin_web_student_import.dart';

// Middle names in the registrar import: read from their own column or from a
// combined "Last, First Middle" name, and never erased by a list without them.

const _noContext = (grade: null, section: null, strand: null);

StudentImportPlan _plan(
  List<List<String>> rows, {
  List<Map<String, dynamic>> existing = const [],
}) =>
    buildImportPlan(
      rows: rows,
      headerRow: 0,
      columns: detectColumns(rows.first),
      context: _noContext,
      overrides: const ImportOverrides(),
      existing: existing,
    );

void main() {
  const separate = ['LRN', 'Last Name', 'First Name', 'Middle Name', 'Grade Level', 'Section'];
  const combined = ['LRN', 'NAME (Last Name, First Name, Middle Name)', 'Grade Level'];

  test('a Middle Name / MI header is recognized', () {
    expect(detectColumns(separate)[ImportField.middleName], 3);
    expect(fieldForHeader('MI'), ImportField.middleName);
    expect(fieldForHeader('Middle Initial'), ImportField.middleName);
    // The combined SF1 header is still the full-name column.
    expect(fieldForHeader(combined[1]), ImportField.fullName);
  });

  test('separate columns: the middle name is read and cleaned', () {
    final r = _plan([
      separate,
      ['123456260001', 'DELA CRUZ', 'JUAN', 'REYES', '7', 'Sampaguita'],
    ]).rows.single;
    expect((r.last, r.first, r.middle, r.middleKnown), ('Dela Cruz', 'Juan', 'Reyes', true));
    expect(r.action, ImportAction.create);
  });

  test('separate columns: a blank middle-name cell means none', () {
    final r = _plan([
      separate,
      ['123456260001', 'Santos', 'Maria', '', '8', ''],
    ]).rows.single;
    expect((r.middle, r.middleKnown), (null, true));
  });

  test('a first-name cell that already ends with the middle name keeps it once', () {
    final r = _plan([
      separate,
      ['123456260001', 'Dela Cruz', 'Juan Reyes', 'Reyes', '7', ''],
    ]).rows.single;
    expect((r.first, r.middle), ('Juan', 'Reyes'));
  });

  test('SF1 "Last, First Middle": the last word is the middle name (flagged)', () {
    final r = _plan([
      combined,
      ['123456260002', 'DELA CRUZ, JUAN PEREZ', '8'],
    ]).rows.single;
    expect((r.last, r.first, r.middle, r.middleKnown), ('Dela Cruz', 'Juan', 'Perez', true));
    expect(r.notes.join(), contains('Middle name read as “Perez”'));
  });

  test('a two-word middle name with a particle stays together', () {
    final r = _plan([
      combined,
      ['123456260003', 'SANTOS, MARIA DE LEON', '9'],
    ]).rows.single;
    expect((r.first, r.middle), ('Maria', 'De Leon'));
  });

  test('"Last, First, Middle" splits exactly, with no note', () {
    final r = _plan([
      combined,
      ['123456260004', 'REYES, ANA, CRUZ', '10'],
    ]).rows.single;
    expect((r.last, r.first, r.middle), ('Reyes', 'Ana', 'Cruz'));
    expect(r.notes, isEmpty);
  });

  final juan = {
    'lrn': '123456 - 26 - 0001',
    'first_name': 'Juan',
    'last_name': 'Dela Cruz',
    'middle_name': 'Perez',
    'full_name': 'Juan Dela Cruz',
    'year_level': 7,
    'section': 'Sampaguita',
    'is_active': true,
  };

  test('a list without middle names leaves a saved one alone', () {
    final r = _plan([
      ['LRN', 'Last Name', 'First Name', 'Grade Level', 'Section'],
      ['123456260001', 'Dela Cruz', 'Juan', '7', 'Sampaguita'],
    ], existing: [juan]).rows.single;
    expect(r.middleKnown, isFalse);
    expect(r.action, ImportAction.unchanged);
  });

  test('a different middle name is an update', () {
    final r = _plan([
      separate,
      ['123456260001', 'Dela Cruz', 'Juan', 'Reyes', '7', 'Sampaguita'],
    ], existing: [juan]).rows.single;
    expect(r.action, ImportAction.update);
    expect(r.changes, 'Middle name Perez → Reyes');
  });

  test('the same middle name in different case is unchanged', () {
    final r = _plan([
      separate,
      ['123456260001', 'DELA CRUZ', 'JUAN', 'PEREZ', '7', 'Sampaguita'],
    ], existing: [juan]).rows.single;
    expect(r.action, ImportAction.unchanged);
  });
}

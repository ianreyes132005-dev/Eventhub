import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:eventhub/features/organizer/web/attendance_record.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

// The registrar import's logins download is an Excel file (it was a CSV).
void main() {
  StudentLogin login(String last, {int? grade, String? section, String password = 'Pw1'}) =>
      StudentLogin(
        lrn: '123456 - 26 - 0001',
        last: last,
        first: 'Ana',
        password: password,
        grade: grade,
        section: section,
      );

  String part(List<StudentLogin> logins, String name) {
    final zip = ZipDecoder().decodeBytes(
        buildStudentLoginsXlsx(logins, generatedAt: DateTime(2026, 10, 28, 9)));
    return utf8.decode(zip.files.firstWhere((f) => f.name == name).content as List<int>);
  }

  test('lists each new student with their initial password', () {
    final sheet = part(
        [login('Santos', grade: 7, section: 'Rizal', password: 'Kp4mNx72qa')],
        'xl/worksheets/sheet1.xml');
    expect(sheet, contains('Initial Password'));
    expect(sheet, contains('123456 - 26 - 0001'));
    expect(sheet, contains('Santos'));
    expect(sheet, contains('Kp4mNx72qa'));
    // Well-formed, so Excel opens it.
    expect(() => XmlDocument.parse(sheet), returnsNormally);
  });

  test('sorted by grade as a number, then section and last name', () {
    final sheet = part([
      login('Grade10', grade: 10, section: 'A'),
      login('SevenB', grade: 7, section: 'B'),
      login('SevenA', grade: 7, section: 'A'),
    ], 'xl/worksheets/sheet1.xml');
    // Grade 7 comes before Grade 10 (the CSV sorted "10" before "7").
    expect(sheet.indexOf('SevenA'), lessThan(sheet.indexOf('SevenB')));
    expect(sheet.indexOf('SevenB'), lessThan(sheet.indexOf('Grade10')));
  });

  test('the workbook has one sheet named Logins', () {
    expect(part(const [], 'xl/workbook.xml'), contains('<sheet name="Logins"'));
  });
}

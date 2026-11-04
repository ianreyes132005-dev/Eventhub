import 'package:eventhub/features/admin/admin_shared.dart';
import 'package:flutter_test/flutter_test.dart';

// The admin Students and Organizers tables show the whole name, middle name
// included, as soon as an account is created. full_name itself stays
// "First Last" (greetings, avatars and tickets read it); the middle name is
// stored on its own and put back for the tables.

void main() {
  test('a new account: first, middle and last name', () {
    expect(
      adminFullName({
        'first_name': 'Juan',
        'middle_name': 'Santos',
        'last_name': 'Dela Cruz',
        'full_name': 'Juan Dela Cruz',
      }),
      'Juan Santos Dela Cruz',
    );
  });

  test('no middle name: First Last', () {
    for (final middle in [null, '', '   ']) {
      expect(
        adminFullName({
          'first_name': 'Ana',
          'middle_name': middle,
          'last_name': 'Reyes',
          'full_name': 'Ana Reyes',
        }),
        'Ana Reyes',
      );
    }
  });

  test('extra spaces are tidied', () {
    expect(
      adminFullName({
        'first_name': ' Maria  Angelica ',
        'middle_name': ' Lopez',
        'last_name': 'De  Leon ',
      }),
      'Maria Angelica Lopez De Leon',
    );
  });

  test('older rows without first/last names show full_name', () {
    expect(adminFullName({'full_name': ' Pedro Penduko '}), 'Pedro Penduko');
    expect(
      adminFullName({'first_name': 'Pedro', 'full_name': 'Pedro Penduko'}),
      'Pedro Penduko',
    );
    expect(adminFullName(const {}), '');
  });
}

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:eventhub/core/services/registration_service.dart';
import 'package:eventhub/core/services/selfie_links.dart';

// The organizer's screens stay current: live registration changes are kept
// to the organizer's own events (a new event's first sign-ups included), and
// selfie links are renewed before they expire.

void main() {
  group('which live registration changes reach an organizer', () {
    final mine = {'ev-a', 'ev-b'};
    bool allowed(String type, Map<String, dynamic> row, [Set<String>? ids]) =>
        RegistrationService.registrationChangeAllowed(type, row, ids ?? mine);

    test('their own events’ sign-ups and updates, nobody else’s', () {
      expect(allowed('INSERT', {'id': 'r1', 'event_id': 'ev-a'}), isTrue);
      expect(allowed('UPDATE', {'id': 'r1', 'event_id': 'ev-b'}), isTrue);
      expect(allowed('INSERT', {'id': 'r2', 'event_id': 'ev-other'}), isFalse);
      expect(allowed('UPDATE', {'id': 'r3'}), isFalse);
    });

    test('a delete carries only the row id, so it always comes through', () {
      expect(allowed('DELETE', {'id': 'r1'}), isTrue);
    });

    test('an event added after subscribing counts from then on', () {
      final live = <String>{};            // filled after the subscription
      final row = {'id': 'r9', 'event_id': 'ev-new'};
      expect(allowed('INSERT', row, live), isFalse);
      live.add('ev-new');                 // the organizer's new event arrives
      expect(allowed('INSERT', row, live), isTrue);
    });

    test('no filter lets everything through', () {
      expect(RegistrationService.registrationChangeAllowed(
          'INSERT', {'event_id': 'x'}, null), isTrue);
    });
  });

  group('selfie links', () {
    late DateTime now;
    late List<String> signed;
    late SelfieLinks links;

    setUp(() {
      now = DateTime(2026, 10, 22, 9);
      signed = [];
      var n = 0;
      links = SelfieLinks(
        now: () => now,
        sign: (path) async {
          signed.add(path);
          return 'https://x/$path?token=${++n}';
        },
      );
    });

    test('renewed well before the 1-hour link expires', () {
      expect(SelfieLinks.renewAfter < RegistrationService.selfieLinkLifetime, isTrue);
    });

    test('made once, kept while fresh, renewed when old', () async {
      expect(await links.fetch({'r1': 'u1/r1.jpg'}), isTrue);
      final first = links['r1'];
      now = now.add(const Duration(minutes: 30));
      expect(await links.fetch({'r1': 'u1/r1.jpg'}), isFalse);
      expect(links['r1'], first);
      now = now.add(const Duration(minutes: 15));   // 45 minutes old
      expect(await links.fetch({'r1': 'u1/r1.jpg'}), isTrue);
      expect(links['r1'], isNot(first));
      expect(signed.length, 2);
    });

    test('a just-submitted selfie always gets a new link', () async {
      await links.fetch({'r1': 'u1/r1.jpg'});
      final first = links['r1'];
      expect(await links.fetch({'r1': 'u1/r1.jpg'}, fresh: true), isTrue);
      expect(links['r1'], isNot(first));
    });

    test('opening an old photo renews its link first', () async {
      await links.fetch({'r1': 'u1/r1.jpg'});
      now = now.add(const Duration(hours: 2));      // the old link is dead
      final url = await links.linkFor('r1', 'u1/r1.jpg');
      expect(url, endsWith('token=2'));
    });

    test('a failed link keeps the old one; a removed row forgets it', () async {
      final failing = SelfieLinks(now: () => now, sign: (_) async => throw Exception('offline'));
      expect(await failing.fetch({'r1': 'p'}), isFalse);
      expect(failing['r1'], isNull);

      await links.fetch({'r1': 'u1/r1.jpg'});
      links.remove('r1');
      expect(links['r1'], isNull);
      expect(links.needsLink('r1', 'u1/r1.jpg'), isTrue);
    });
  });

  test('change requests and notices are in the realtime publication', () {
    final sql = File('supabase/migrations/202610220001_organizer_realtime.sql')
        .readAsStringSync();
    for (final table in ['events', 'event_revisions', 'notifications']) {
      expect(sql, contains("'$table'"));
    }
    expect(sql, contains('IF NOT EXISTS'));
    expect(sql, contains('ALTER PUBLICATION supabase_realtime ADD TABLE'));
    // A table whose migration hasn't run yet is skipped, not fatal.
    expect(sql, contains("to_regclass('public.' || t) IS NULL"));
  });

  test('the migration check covers every migration', () {
    final check = File('supabase/checks/migration_status.sql').readAsStringSync();
    // The attendance hardening and its rollback are a choice, not a step.
    const choices = {
      '202610150001_attendance_security_hardening',
      '202610150003_rollback_attendance_security_hardening',
    };
    final names = Directory('supabase/migrations')
        .listSync()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.sql'))
        .map((n) => n.replaceAll('.sql', ''))
        .where((n) => !choices.contains(n));
    for (final name in names) {
      expect(check, contains("'$name'"), reason: '$name is missing from the check');
    }
  });
}

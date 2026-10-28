import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:eventhub/features/auth/privacy_content.dart';
import 'package:eventhub/features/auth/terms_content.dart';

// Guards for the student-app cleanup: the legal text matches how EventHub
// works, the event details page uses theme colours (dark mode), and nothing
// unused is bundled into the app.

String _all(List<({dynamic icon, String title, String body})> sections) =>
    sections.map((s) => '${s.title}\n${s.body}').join('\n');

void main() {
  group('Privacy Policy and Terms', () {
    final privacy = _all(eventHubPrivacy);
    final terms = _all(eventHubTerms);

    test('point to the school administrator — there is no support team', () {
      expect(privacy, isNot(contains('support team')));
      expect(terms, isNot(contains('support team')));
      expect(privacy, contains('school administrator'));
    });

    test('say what is really kept and who sees it', () {
      expect(privacy, contains('does not ask for your email address'));
      expect(privacy, contains('LRN'));
      expect(privacy, contains('Event organizers'));
      // Organizers only see their own events' registrations (202610230002).
      expect(privacy, contains('only the organizer of an event you register for'));
      expect(terms, contains('that event’s organizer'));
      expect(privacy, contains('school administrator'));
      // The profile photo is stored behind a link anyone who has it can open.
      expect(privacy, contains('anyone who has the photo’s link can open it'));
    });

    test('name the outside services, including the AI assistant’s', () {
      expect(privacy, contains('Supabase'));
      expect(privacy, contains('Groq'));
      expect(terms, contains('Groq'));
      // The assistant is in the app too, and on the organizer web portal
      // (the admin portal has none).
      expect(terms, contains('in the mobile app and the organizer web portal'));
      expect(privacy, isNot(contains('personalized')));
    });

    test('match the app’s rules: Ticket IDs, the camera prompt, the 2-hour close', () {
      expect(terms, contains('Ticket ID'));
      expect(terms, contains('asks before it opens the camera'));
      expect(terms, contains('closes 2 hours after an event starts'));
    });

    test('match the check-in rules of migration 202610280001', () {
      // Students can cancel until check-in opens.
      expect(terms, contains('cancel a registration until check-in opens'));
      expect(privacy, contains('Cancel a registration until check-in opens'));
      // Scanning until 30 min after the end, finishing until 2 h after.
      expect(terms, contains('until 30 minutes after the event ends'));
      expect(terms, contains('until 2 hours after the end'));
      // Then it's final, and only the admin corrects it, with a reason.
      expect(terms, contains('attendance is final'));
      expect(terms, contains('Only the school administrator can correct attendance'));
      expect(privacy, contains('corrected by the school administrator'));
    });

    test('say that notifications are in the app only, and when the text changed', () {
      expect(terms, contains('does not send push notifications'));
      expect(eventHubLegalUpdated, isNotEmpty);
    });
  });

  test('the event details page uses theme colours, so dark mode is readable', () {
    final page = File('lib/features/student/events/event_details_page.dart').readAsStringSync();
    expect(page, isNot(contains('color: kText')));
    expect(page, isNot(contains('color: kSubText')));
    expect(page, isNot(contains('Colors.grey[')));
  });

  test('everything in assets/ is used by the app', () {
    final code = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.readAsStringSync())
        .join('\n');
    final assets = Directory('assets')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last);
    for (final name in assets) {
      expect(code, contains(name), reason: 'assets/$name is bundled but never used');
    }
  });
}

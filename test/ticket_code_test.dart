import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eventhub/core/ticket_code.dart';
import 'package:eventhub/features/organizer/mobile/registrations/ticket_entry_dialog.dart';
import 'package:eventhub/models/event_registration.dart';
import 'package:eventhub/shared/widgets/qr_code_dialog.dart';

// Every ticket has a short Ticket ID under its QR code. When the QR won't
// scan, the organizer types the code instead.

const _uuid = '3f2a9c1e-7b4d-4e8a-9c2f-1a2b3c4d5e6f';

String _two(int n) => n.toString().padLeft(2, '0');
String _date(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String _time(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}:00';

/// An event whose check-in is open now (it starts in 10 minutes).
Map<String, dynamic> _openEvent(String title) {
  final start = DateTime.now().add(const Duration(minutes: 10));
  final end = start.add(const Duration(hours: 2));
  return {
    'event_id': 'ev-$title',
    'title': title,
    'event_date': _date(start),
    'start_time': _time(start),
    'end_date': _date(end),
    'end_time': _time(end),
    'event_status': 'upcoming',
  };
}

/// An event whose check-in isn't open (it's years away).
Map<String, dynamic> _laterEvent(String title) => {
  'event_id': 'ev-$title',
  'title': title,
  'event_date': '2099-01-10',
  'start_time': '09:00:00',
  'end_time': '12:00:00',
  'event_status': 'upcoming',
};

TicketMatch _match(Map<String, dynamic> event, String qr, {String student = 'Ana Cruz'}) => (
  registration: {
    'id': qr,
    'qr_code': qr,
    'ticket_code': '4821',
    'event_id': event['event_id'],
    'student_name': student,
  },
  event: event,
);

void main() {
  group('what the organizer types', () {
    test('4 or 5 digits are a Ticket ID; spaces and # are ignored', () {
      expect(parseTicketInput('4821'), (kind: TicketInputKind.ticketCode, value: '4821'));
      expect(parseTicketInput(' 48 21 ').value, '4821');
      expect(parseTicketInput('#4821').value, '4821');
      expect(parseTicketInput('48213').kind, TicketInputKind.ticketCode);
    });

    test('a pasted QR value still works', () {
      expect(parseTicketInput(_uuid.toUpperCase()),
          (kind: TicketInputKind.qrValue, value: _uuid));
    });

    test('anything else is not a Ticket ID', () {
      for (final typed in ['', '482', '482133', 'abcd', '48a1']) {
        expect(parseTicketInput(typed).kind, TicketInputKind.invalid, reason: typed);
      }
    });
  });

  group('the same code in several events', () {
    bool open(String e) => e.startsWith('open');

    test('events with check-in open come first — one opens straight away', () {
      expect(ticketChoices(['open-a', 'later-b'], open), ['open-a']);
      expect(ticketChoices(['open-a', 'open-b', 'later-c'], open), ['open-a', 'open-b']);
    });

    test('with none open, every match is offered', () {
      expect(ticketChoices(['later-a', 'later-b'], open), ['later-a', 'later-b']);
      expect(ticketChoices(<String>[], open), isEmpty);
    });
  });

  test('the database picks a random 4-digit code, unique within the event', () {
    final sql = File('supabase/migrations/202610210002_ticket_codes.sql').readAsStringSync();
    expect(sql, contains('ADD COLUMN IF NOT EXISTS ticket_code text'));
    expect(sql, contains('(1000  + floor(random() * 9000))'));
    expect(sql, contains('BEFORE INSERT OR UPDATE OF ticket_code, event_id ON public.registrations'));
    expect(sql, contains('pg_advisory_xact_lock'));
    expect(sql, contains('ALTER COLUMN ticket_code SET NOT NULL'));
    expect(sql, contains('ON public.registrations (ticket_code, event_id)'));
    // The registration guard is back on after the backfill.
    expect(sql.indexOf('ENABLE TRIGGER trg_enforce_registration_update_rules'),
        greaterThan(sql.indexOf('DISABLE TRIGGER trg_enforce_registration_update_rules')));
  });

  group('the student’s ticket', () {
    Future<void> showTicket(WidgetTester tester, {required String code}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: QRCodeDialog(
            registration: EventRegistration(
              registrationId: _uuid,
              eventTitle: 'Science Fair',
              studentId: '123456260001',
              studentName: 'Ana Cruz',
              registrationDate: DateTime(2026, 10, 21),
              qrCodeData: _uuid,
              ticketCode: code,
            ),
          ),
        ),
      ));
    }

    testWidgets('shows the Ticket ID big, once', (tester) async {
      await showTicket(tester, code: '4821');
      expect(find.text('TICKET ID'), findsOneWidget);
      expect(find.text('4821'), findsOneWidget);
      expect(find.text('QR won’t scan? The organizer can type this instead.'), findsOneWidget);
      expect(find.text('Ticket ID'), findsNothing);
    });
  });

  group('typing a Ticket ID in the scanner', () {
    String? opened;
    var dialogOpen = false;
    final looked = <String>[];

    Future<void> openBox(WidgetTester tester, List<TicketMatch> found) async {
      opened = null;
      dialogOpen = true;
      looked.clear();
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  opened = await showTicketEntryDialog(context, lookup: (code) async {
                    looked.add(code);
                    return found;
                  });
                  dialogOpen = false;
                },
                child: const Text('type'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('type'));
      await tester.pumpAndSettle();
    }

    Future<void> lookUp(WidgetTester tester, String typed) async {
      await tester.enterText(find.byType(TextField), typed);
      await tester.tap(find.text('Look Up'));
      await tester.pumpAndSettle();
    }

    testWidgets('one match opens that ticket', (tester) async {
      await openBox(tester, [_match(_laterEvent('Science Fair'), 'qr-1')]);
      expect(find.text('Type Ticket ID'), findsOneWidget);
      await lookUp(tester, '48 21');
      expect(looked, ['4821']);
      expect(opened, 'qr-1');
      expect(dialogOpen, isFalse);
    });

    testWidgets('a wrong entry or unknown code says so and stays open', (tester) async {
      await openBox(tester, []);
      await lookUp(tester, '48');
      expect(find.text('A Ticket ID is 4 digits, like 4821.'), findsOneWidget);
      expect(looked, isEmpty);

      await lookUp(tester, '4821');
      expect(find.text('No ticket with ID 4821 in your events.'), findsOneWidget);
      expect(dialogOpen, isTrue);
    });

    testWidgets('the event with check-in open wins over a later one', (tester) async {
      await openBox(tester, [
        _match(_openEvent('Intramurals'), 'qr-open'),
        _match(_laterEvent('Science Fair'), 'qr-later'),
      ]);
      await lookUp(tester, '4821');
      expect(opened, 'qr-open');
    });

    testWidgets('otherwise the organizer picks the event', (tester) async {
      await openBox(tester, [
        _match(_laterEvent('Science Fair'), 'qr-a', student: 'Ana Cruz'),
        _match(_laterEvent('Book Week'), 'qr-b', student: 'Ben Reyes'),
      ]);
      await lookUp(tester, '4821');
      expect(find.text('Ticket ID 4821'), findsOneWidget);
      expect(find.text('Science Fair'), findsOneWidget);
      expect(find.textContaining('Ben Reyes'), findsOneWidget);

      await tester.tap(find.text('Book Week'));
      await tester.pumpAndSettle();
      expect(opened, 'qr-b');
    });

    testWidgets('a pasted QR value opens without a lookup', (tester) async {
      await openBox(tester, []);
      await lookUp(tester, _uuid);
      expect(looked, isEmpty);
      expect(opened, _uuid);
    });
  });
}

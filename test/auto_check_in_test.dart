import 'package:eventhub/features/organizer/mobile/registrations/auto_check_in.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Scan QR in the organizer app confirms each ticket on its own (no Confirm
// tap, no sheet): a new ticket is marked scanned and the student's phone is
// asked for the check-in photo, so the next student can be scanned at once.

class _FakeDb {
  _FakeDb(this.ticket, {this.problem, this.fail = false});

  final Map<String, dynamic>? ticket;
  final String? problem;
  final bool fail;
  final writes = <String>[];
  bool? scanningAsked;

  ScanServices get services => ScanServices(
        findTicket: (code) async {
          if (fail) throw Exception('SocketException: Failed host lookup');
          return ticket;
        },
        checkInWindow: (eventId, {bool scanning = false}) async {
          scanningAsked = scanning;
          return (problem: problem, opensAt: null);
        },
        setStatus: (id, status) async => writes.add(status),
      );
}

Map<String, dynamic> _ticket(String status) => {
      'id': 'r1',
      'event_id': 'e1',
      'status': status,
      'student_name': 'Juan Dela Cruz',
      'event_title': 'Science Fair',
    };

void main() {
  group('one scan confirms itself', () {
    test('a new ticket: scanned, then the photo requested — no Confirm tap', () async {
      final db = _FakeDb(_ticket('pending'));
      final r = await autoCheckIn('QR', services: db.services);
      expect(db.writes, ['qr_scanned', 'photo_required']);
      expect(db.scanningAsked, isTrue, reason: 'a new ticket needs scanning to be open');
      expect(r.outcome, ScanOutcome.requested);
      expect(r.ok, isTrue);
      expect(r.title, 'Juan Dela Cruz');
      expect(r.message, 'Scanned — photo requested · Science Fair');
    });

    test('scanned before but never confirmed: the photo is requested', () async {
      final db = _FakeDb(_ticket('qr_scanned'));
      final r = await autoCheckIn('QR', services: db.services);
      expect(db.writes, ['photo_required']);
      expect(db.scanningAsked, isFalse);
      expect(r.outcome, ScanOutcome.requested);
    });

    test('photo asked for and none came: asked again', () async {
      final db = _FakeDb(_ticket('photo_required'));
      final r = await autoCheckIn('QR', services: db.services);
      expect(db.writes, ['photo_required']);
      expect(r.outcome, ScanOutcome.requestedAgain);
      expect(r.message, 'Photo requested again · Science Fair');
    });
  });

  group('finished registrations are only reported', () {
    for (final (status, outcome, ok) in [
      ('photo_submitted', ScanOutcome.awaitingReview, true),
      ('checked_in', ScanOutcome.alreadyCheckedIn, false),
      ('rejected', ScanOutcome.declined, false),
    ]) {
      test(status, () async {
        final db = _FakeDb(_ticket(status));
        final r = await autoCheckIn('QR', services: db.services);
        expect(db.writes, isEmpty);
        expect(r.outcome, outcome);
        expect(r.ok, ok);
      });
    }
  });

  test('outside the check-in window nothing changes, and the reason shows', () async {
    const why = 'Check-in opens 1 hour before the event starts (Nov 7, 12:00 PM).';
    final db = _FakeDb(_ticket('pending'), problem: why);
    final r = await autoCheckIn('QR', services: db.services);
    expect(db.writes, isEmpty);
    expect(r.outcome, ScanOutcome.notOpen);
    expect(r.message, why);
    expect(r.ok, isFalse);
  });

  test('not one of the organizer’s tickets', () async {
    final db = _FakeDb(null);
    final r = await autoCheckIn('QR', services: db.services);
    expect(r.outcome, ScanOutcome.notYours);
    expect(db.writes, isEmpty);
  });

  test('no connection: a plain message, not the raw error', () async {
    final r = await autoCheckIn('QR', services: _FakeDb(null, fail: true).services);
    expect(r.outcome, ScanOutcome.failed);
    expect(r.message, isNot(contains('SocketException')));
  });

  group('a ticket held in view counts once', () {
    final t0 = DateTime(2026, 11, 5, 9);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

    test('read again and again while in view: only the first counts', () {
      final gate = ScanGate();
      expect(gate.admit('A', at(0)), isTrue);
      for (var ms = 250; ms <= 5000; ms += 250) {
        expect(gate.admit('A', at(ms)), isFalse, reason: 'still in view at $ms ms');
      }
    });

    test('out of view for a while, then shown again: counts again', () {
      final gate = ScanGate();
      expect(gate.admit('A', at(0)), isTrue);
      expect(gate.admit('A', at(4000)), isTrue);
    });

    test('the next student’s ticket counts at once', () {
      final gate = ScanGate();
      expect(gate.admit('A', at(0)), isTrue);
      expect(gate.admit('B', at(300)), isTrue);
    });

    test('while one is being checked, the next waits — then goes through at once', () {
      final gate = ScanGate();
      expect(gate.admit('A', at(0)), isTrue);
      expect(gate.admit('B', at(100), busy: true), isFalse);
      expect(gate.admit('B', at(350), busy: true), isFalse);
      // A is done: B, still held up, counts without being shown again…
      expect(gate.admit('B', at(600)), isTrue);
      // …once.
      expect(gate.admit('B', at(850)), isFalse);
    });
  });

  testWidgets('the result under the frame: checking, then who and what happened',
      (tester) async {
    Future<void> show(ScanResult? r) => tester.pumpWidget(MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: SizedBox(width: 320, child: ScanResultCard(result: r))),
          ),
        ));
    await show(null);
    expect(find.text('Checking ticket…'), findsOneWidget);
    await show(const ScanResult(ScanOutcome.requested, 'Juan Dela Cruz',
        'Scanned — photo requested · Science Fair'));
    expect(find.text('Juan Dela Cruz'), findsOneWidget);
    expect(find.text('Scanned — photo requested · Science Fair'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

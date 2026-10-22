import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eventhub/core/services/scan_feedback.dart';
import 'package:eventhub/models/event_registration.dart';
import 'package:eventhub/shared/widgets/qr_code_dialog.dart';

// QR check-in feedback: which scans count as accepted vs blocked (the
// organizer's phone vibrates, with no sound), the student's chime, and their
// "Ticket scanned" banner.

({int channels, int rate, int ms}) _wavInfo(String path) {
  final b = ByteData.sublistView(File(path).readAsBytesSync());
  final channels = b.getUint16(22, Endian.little);
  final rate = b.getUint32(24, Endian.little);
  final bytesPerSec = b.getUint32(28, Endian.little);
  final dataBytes = b.getUint32(40, Endian.little);
  return (channels: channels, rate: rate, ms: dataBytes * 1000 ~/ bytesPerSec);
}

void main() {
  test('a valid ticket is accepted; one that can’t move forward is blocked', () {
    for (final s in ['qr_scanned', 'photo_required', 'photo_submitted']) {
      expect(ScanFeedback.isAccepted(s), isTrue, reason: s);
    }
    for (final s in ['checked_in', 'rejected']) {
      expect(ScanFeedback.isAccepted(s), isFalse, reason: s);
    }
  });

  test('the student’s chime is a short mono WAV bundled with the app', () {
    final info = _wavInfo('assets/sounds/ticket_scanned.wav');
    expect(info.channels, 1);
    expect(info.rate, 44100);
    expect(info.ms, lessThan(350), reason: 'it should be a quick sound');
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/sounds/'));
  });

  testWidgets('an open ticket shows "Ticket scanned" when it is scanned', (tester) async {
    final reg = EventRegistration(
      registrationId: 'reg-123',
      eventTitle: 'Intramurals',
      studentId: '123456260001',
      studentName: 'Juan Dela Cruz',
      registrationDate: DateTime(2026, 10, 20),
      qrCodeData: 'reg-123',
      ticketCode: '4821',
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: QRCodeDialog(registration: reg)),
    ));
    expect(find.text('Ticket scanned'), findsNothing);

    QRCodeDialog.markScanned('someone-else');
    await tester.pumpAndSettle();
    expect(find.text('Ticket scanned'), findsNothing);

    QRCodeDialog.markScanned('reg-123');
    await tester.pumpAndSettle();
    expect(find.text('Ticket scanned'), findsOneWidget);
  });
}

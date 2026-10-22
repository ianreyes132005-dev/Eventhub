import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eventhub/features/student/check_in/photo_consent.dart';

// After the organizer requests a check-in photo, the student is asked first
// (SweetAlert2) — the camera opens only when they allow it.

void main() {
  bool? answer;

  Future<void> open(WidgetTester tester, {String? event}) async {
    answer = null;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async =>
                  answer = await askCheckInPhotoConsent(context, eventTitle: event),
              child: const Text('request'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('request'));
    await tester.pumpAndSettle();
  }

  testWidgets('explains the photo and names the event', (tester) async {
    await open(tester, event: 'Intramurals 2026');
    expect(find.text('Take a check-in photo?'), findsOneWidget);
    expect(find.textContaining('“Intramurals 2026”'), findsOneWidget);
    expect(find.textContaining('proof that you’re at the venue'), findsOneWidget);
    expect(find.text('Allow & Take Photo'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('Allow opens the camera; Not now doesn’t', (tester) async {
    await open(tester);
    await tester.tap(find.text('Allow & Take Photo'));
    await tester.pumpAndSettle();
    expect(answer, isTrue);

    await open(tester);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(answer, isFalse);
  });

  testWidgets('a tap outside doesn’t answer for the student', (tester) async {
    await open(tester);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text('Take a check-in photo?'), findsOneWidget);
    expect(answer, isNull);
  });
}

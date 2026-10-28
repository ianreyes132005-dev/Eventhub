import 'package:eventhub/shared/widgets/about_eventhub.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// About EventHub: one shared content for the student app, the organizer app
// and the organizer web portal.
void main() {
  test('the version says which build it is', () {
    expect(aboutVersionLabel('1.0.7', '8'), 'Version 1.0.7 (build 8)');
    expect(aboutVersionLabel('1.0.7', ''), 'Version 1.0.7');
    expect(aboutVersionLabel('—', ''), 'Version —');
  });

  Future<void> pump(WidgetTester tester, AboutAudience who, {
    VoidCallback? onTerms,
    VoidCallback? onPrivacy,
  }) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AboutEventHubBody(
            audience: who,
            onOpenTerms: onTerms ?? () {},
            onOpenPrivacy: onPrivacy ?? () {},
            textColor: Colors.black,
            mutedColor: Colors.grey,
            dividerColor: Colors.black12,
            centered: true,
          ),
        ),
      ),
    ));
  }

  testWidgets('names the school, the contact and the developers', (tester) async {
    await pump(tester, AboutAudience.student);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('J-Jireh School, Inc.'), findsWidgets);
    expect(find.textContaining('Inc..'), findsNothing);
    expect(find.textContaining('show your QR ticket at check-in'), findsOneWidget);
    expect(find.textContaining('Learning Center'), findsNothing);
    for (final name in ['Reyes, Ian', 'Jamallul, Trisha', 'Ammad, Ainie']) {
      expect(find.text(name), findsOneWidget);
    }
    // The contact is the school administrator only — no email — and there's
    // no open-source licenses link or Updates box (the user asked to remove
    // them).
    expect(find.textContaining('Flutter · Dart · Supabase'), findsOneWidget);
    expect(find.textContaining('School administrator'), findsOneWidget);
    expect(find.textContaining('@'), findsNothing);
    expect(find.text('Open-source licenses'), findsNothing);
    expect(find.text('Updates'), findsNothing);
  });

  testWidgets('opens the Terms and the Privacy Policy', (tester) async {
    var terms = 0, privacy = 0;
    await pump(tester, AboutAudience.organizer,
        onTerms: () => terms++, onPrivacy: () => privacy++);
    await tester.tap(find.text('Terms and Conditions'));
    await tester.tap(find.text('Privacy Policy'));
    expect((terms, privacy), (1, 1));
    expect(find.textContaining('Android app · web portal'), findsOneWidget);
  });
}

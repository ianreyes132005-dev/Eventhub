import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eventhub/core/event_audience.dart';
import 'package:eventhub/shared/widgets/audience_picker.dart';

// The "Who can register" picker shared by the web event dialog and the app's
// event screen: what it shows for each choice, and what a tap reports.

const _colors = AudiencePickerColors(
  dark: false,
  surface: Colors.white,
  border: Color(0xFFE8EBF0),
  text: Color(0xFF111827),
  muted: Color(0xFF6B7280),
);

Future<AudienceChoice?> _pump(WidgetTester tester, AudienceChoice value,
    {bool touch = false, double width = 560, Finder? tap}) async {
  AudienceChoice? reported;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: AudiencePicker(
            value: value,
            onChanged: (c) => reported = c,
            colors: _colors,
            touch: touch,
          ),
        ),
      ),
    ),
  ));
  if (tap != null) {
    await tester.tap(tap);
    await tester.pump();
  }
  return reported;
}

Finder _text(String s) => find.textContaining(s, findRichText: true);

void main() {
  testWidgets('the four groups; no grades or strands for every student', (tester) async {
    await _pump(tester, const AudienceChoice());
    expect(_text('All students'), findsOneWidget);
    expect(_text('Junior High'), findsOneWidget);
    expect(_text('Senior High'), findsOneWidget);
    expect(_text('Specific grades'), findsOneWidget);
    expect(find.bySemanticsLabel('Grade 7'), findsNothing);
    expect(_text('HUMSS'), findsNothing);
  });

  testWidgets('tapping Senior High reports it', (tester) async {
    final c = await _pump(tester, const AudienceChoice(), tap: _text('Grades 11–12'));
    expect(c?.audience, EventAudience.seniorHigh);
  });

  testWidgets('Senior High shows the strands; tapping one narrows to it', (tester) async {
    final value = const AudienceChoice().choose(AudiencePreset.seniorHigh);
    final c = await _pump(tester, value, tap: _text('STEM'));
    expect(c?.audience.label, 'Senior High · STEM');
  });

  testWidgets('Specific grades shows the grades; strands once 11 or 12 is in', (tester) async {
    final custom = const AudienceChoice().choose(AudiencePreset.custom);
    final c = await _pump(tester, custom, tap: find.bySemanticsLabel('Grade 12'));
    expect(c?.grades, {12});
    expect(_text('STEM'), findsNothing);

    await _pump(tester, custom.toggleGrade(10).toggleGrade(12));
    expect(_text('STEM'), findsOneWidget);
    expect(_text('Strands only narrow the Senior High grades'), findsOneWidget);
  });

  testWidgets('fits a phone: grades on a second line, comfortable taps', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pump(tester, const AudienceChoice().choose(AudiencePreset.custom).toggleGrade(11),
        touch: true, width: 328);
    expect(tester.takeException(), isNull);
    // Stacked: the label and its grades are separate lines.
    expect(find.text('Grades 11–12'), findsOneWidget);
    final grade = tester.getSize(find.bySemanticsLabel('Grade 7'));
    expect(grade.height, greaterThanOrEqualTo(40));
  });
}

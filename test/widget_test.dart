import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eventhub/app_theme.dart';
import 'package:eventhub/widgets/gradient_button.dart';

void main() {
  // ── GradientButton ──────────────────────────────────────────────────────────

  testWidgets('GradientButton renders label', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: GradientButton('Log In', onPressed: () {}),
          ),
        ),
      ),
    );

    expect(find.text('Log In'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsOneWidget);
  });

  testWidgets('GradientButton shows spinner when isLoading',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GradientButton('Log In', isLoading: true, onPressed: () {}),
          ),
        ),
      ),
    );

    // Label hidden, spinner visible
    expect(find.text('Log In'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('GradientButton onPressed fires', (WidgetTester tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GradientButton('Log In', onPressed: () => tapped = true),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Log In'));
    expect(tapped, isTrue);
  });

  testWidgets('GradientButton disabled when onPressed is null',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: GradientButton('Log In')),
        ),
      ),
    );

    final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(btn.onPressed, isNull);
  });
}

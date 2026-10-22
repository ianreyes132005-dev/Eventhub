import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eventhub/core/app_colors.dart';
import 'package:eventhub/features/organizer/mobile/registrations/check_in_countdown.dart';

// "Check-in isn't open yet" on the organizer's scanner: when check-in opens,
// and the countdown to it.

Map<String, dynamic> _event({String status = 'upcoming'}) => {
  'event_date': '2026-10-25',
  'end_date': '2026-10-25',
  'start_time': '09:00:00',
  'end_time': '12:00:00',
  'event_status': status,
};

void main() {
  final opens = DateTime(2026, 10, 25, 8); // 1 h before the 9:00 start

  test('check-in opens 1 hour before the start — counted down only until then', () {
    expect(checkInOpensAt(_event(), now: DateTime(2026, 10, 24, 20)), opens);
    expect(checkInOpensAt(_event(), now: DateTime(2026, 10, 25, 7, 59, 59)), opens);
    // Open, ongoing, or already closed: nothing to count down to.
    expect(checkInOpensAt(_event(), now: opens), isNull);
    expect(checkInOpensAt(_event(), now: DateTime(2026, 10, 25, 10)), isNull);
    expect(checkInOpensAt(_event(), now: DateTime(2026, 10, 25, 15)), isNull);
  });

  test('a cancelled event never counts down', () {
    expect(checkInOpensAt(_event(status: 'cancelled'), now: DateTime(2026, 10, 24)), isNull);
  });

  test('the countdown goes with "check-in opens…", never with "check-in closed…"', () {
    for (final now in [DateTime(2026, 10, 24, 20), DateTime(2026, 10, 25, 7, 30)]) {
      expect(checkInBlockedReason(_event(), now: now), startsWith('Check-in opens'));
      expect(checkInOpensAt(_event(), now: now), isNotNull);
    }
    final late = DateTime(2026, 10, 25, 15);
    expect(checkInBlockedReason(_event(), now: late), startsWith('Check-in closed'));
    expect(checkInOpensAt(_event(), now: late), isNull);
  });

  /// A clock that starts [left] before check-in opens and moves with the
  /// test's fake time, so the widget's timers and its clock agree.
  DateTime Function() clockFrom(WidgetTester tester, Duration left) {
    final t0 = tester.binding.clock.now();
    final start = opens.subtract(left);
    return () => start.add(tester.binding.clock.now().difference(t0));
  }

  Future<void> show(WidgetTester tester, DateTime Function() now, VoidCallback onOpened) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CheckInCountdown(
            opensAt: opens,
            onOpened: onOpened,
            textColor: Colors.black,
            accentColor: Colors.brown,
            now: now,
          ),
        ),
      ));

  testWidgets('ticks every second and reports once when check-in opens', (tester) async {
    var opened = 0;
    await show(tester, clockFrom(tester, const Duration(minutes: 1, seconds: 2)), () => opened++);
    expect(find.text('CHECK-IN OPENS IN'), findsOneWidget);
    expect(find.text('01:02'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('01:01'), findsOneWidget);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('00:01'), findsOneWidget);
    expect(opened, 0);

    await tester.pump(const Duration(seconds: 1));
    expect(opened, 1);
    await tester.pump(const Duration(seconds: 5));
    expect(opened, 1);
  });

  testWidgets('rounds up — never shows 00:00 while check-in is still closed', (tester) async {
    var opened = 0;
    await show(tester, clockFrom(tester, const Duration(milliseconds: 2400)), () => opened++);
    expect(find.text('00:03'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('00:02'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1999));
    expect(find.text('00:01'), findsOneWidget);
    expect(opened, 0);

    await tester.pump(const Duration(milliseconds: 1));
    expect(opened, 1);
  });

  testWidgets('a long wait shows days and hours', (tester) async {
    await show(tester, clockFrom(tester, const Duration(days: 2, hours: 3, minutes: 5)), () {});
    expect(find.text('2d 3h'), findsOneWidget);
  });

  testWidgets('already open when shown: reports open straight away', (tester) async {
    var opened = 0;
    await show(tester, () => opens.add(const Duration(seconds: 1)), () => opened++);
    expect(opened, 1);
  });
}

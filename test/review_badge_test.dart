import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eventhub/core/app_colors.dart';
import 'package:eventhub/shared/widgets/web/web_nav_badge.dart';

// The organizer web's Registrations badge counts selfies that can still be
// approved — on events whose check-in is open — and looks like the admin's.

Map<String, dynamic> _event({String status = 'upcoming', String? archivedAt}) => {
  'event_date': '2026-10-25',
  'end_date': '2026-10-25',
  'start_time': '09:00:00',
  'end_time': '12:00:00',
  'event_status': status,
  'archived_at': ?archivedAt,
};

void main() {
  test('check-in is open from 1 hour before the start to 2 hours after the end', () {
    expect(checkInIsOpen(_event(), now: DateTime(2026, 10, 25, 7, 59)), isFalse);
    expect(checkInIsOpen(_event(), now: DateTime(2026, 10, 25, 8)), isTrue);
    expect(checkInIsOpen(_event(), now: DateTime(2026, 10, 25, 10, 30)), isTrue);
    expect(checkInIsOpen(_event(), now: DateTime(2026, 10, 25, 14)), isTrue);
    expect(checkInIsOpen(_event(), now: DateTime(2026, 10, 25, 14, 1)), isFalse);
  });

  test('cancelled and archived events never count', () {
    final during = DateTime(2026, 10, 25, 10);
    expect(checkInIsOpen(_event(status: 'cancelled'), now: during), isFalse);
    expect(checkInIsOpen(_event(archivedAt: '2026-10-25T03:00:00Z'), now: during), isFalse);
  });

  testWidgets('the badge shows the count, 9+ above nine, and says what it counts', (tester) async {
    Future<void> show(int count, {String? tip}) => tester.pumpWidget(MaterialApp(
          home: Scaffold(body: Center(child: WebNavBadge(count: count, tooltip: tip))),
        ));

    await show(3, tip: '3 selfies waiting for your review');
    expect(find.text('3'), findsOneWidget);
    expect(find.byTooltip('3 selfies waiting for your review'), findsOneWidget);

    await show(12);
    expect(find.text('9+'), findsOneWidget);
    expect(find.byType(Tooltip), findsNothing);
  });
}

import 'package:eventhub/shared/widgets/mark_all_read_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Student Notifications screen and the organizer app's notification sheet:
// "Mark all as read" turns into "All read" once it's tapped.
void main() {
  testWidgets('tapping Mark all as read turns it into All read', (tester) async {
    var unread = 3;
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => MarkAllReadButton(
            unread: unread,
            onTap: () => setState(() {
              taps++;
              unread = 0;
            }),
          ),
        ),
      ),
    ));
    expect(find.text('Mark all as read'), findsOneWidget);
    expect(find.text('All read'), findsNothing);

    await tester.tap(find.text('Mark all as read'));
    await tester.pumpAndSettle();

    expect(taps, 1);
    expect(find.text('All read'), findsOneWidget);
    expect(find.text('Mark all as read'), findsNothing);
  });

  testWidgets('says All read when nothing is unread, and tapping it does nothing',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MarkAllReadButton(unread: 0, onTap: () => taps++)),
    ));
    expect(find.text('All read'), findsOneWidget);
    expect(find.text('Mark all as read'), findsNothing);

    await tester.tap(find.text('All read'));
    await tester.pump();
    expect(taps, 0);
  });

  testWidgets('goes back to Mark all as read when something new arrives',
      (tester) async {
    Widget at(int unread) => MaterialApp(
          home: Scaffold(body: MarkAllReadButton(unread: unread, onTap: () {})),
        );
    await tester.pumpWidget(at(0));
    await tester.pumpWidget(at(1));
    await tester.pumpAndSettle();
    expect(find.text('Mark all as read'), findsOneWidget);
    expect(find.text('All read'), findsNothing);
  });
}

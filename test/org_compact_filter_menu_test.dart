import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eventhub/core/app_colors.dart';
import 'package:eventhub/shared/widgets/compact_filter_menu.dart';

void main() {
  testWidgets(
    'selecting a filter updates its trigger and exposes a clear action',
    (tester) async {
      var selected = 'All';
      const options = [
        CompactFilterOption(value: 'All', label: 'All', count: 3),
        CompactFilterOption(
          value: 'Rejected',
          label: 'Rejected',
          count: 1,
          color: Colors.red,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Center(
                child: CompactFilterMenu<String>(
                  label: 'Status',
                  icon: Icons.filter_list_rounded,
                  options: options,
                  selected: selected,
                  onSelect: (value) => setState(() => selected = value),
                  t: const AppTk(false),
                  accent: kGold,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Status · All 3'), findsOneWidget);
      await tester.tap(find.text('Status · All 3'));
      await tester.pumpAndSettle();
      expect(find.text('Rejected'), findsOneWidget);

      await tester.tap(find.text('Rejected'));
      await tester.pumpAndSettle();

      expect(find.text('Status · Rejected 1'), findsOneWidget);
      expect(find.byTooltip('Clear Status filter'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear Status filter'));
      await tester.pumpAndSettle();
      expect(find.text('Status · All 3'), findsOneWidget);
    },
  );

  testWidgets('searchable filter sheets narrow options by label', (
    tester,
  ) async {
    final options = [
      const CompactFilterOption(value: 'All', label: 'All events', count: 9),
      for (var i = 1; i <= 9; i++)
        CompactFilterOption(
          value: 'event-$i',
          label: 'Event $i',
          count: i,
          color: Colors.purple,
        ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: CompactFilterMenu<String>(
              label: 'Event',
              icon: Icons.event_rounded,
              options: options,
              selected: 'All',
              onSelect: (_) {},
              t: const AppTk(false),
              accent: const Color(0xFF8B5CF6),
              searchable: true,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Event · All events 9'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Event 9');
    await tester.pumpAndSettle();

    expect(find.text('Event 9'), findsNWidgets(2));
    expect(find.text('Event 1'), findsNothing);
  });

  testWidgets('selecting a searched event closes the sheet cleanly', (
    tester,
  ) async {
    final options = [
      CompactFilterOption(value: 'All', label: 'All events', count: 9),
      for (var i = 1; i <= 9; i++)
        CompactFilterOption(
          value: 'event-$i',
          label: 'Event $i',
          count: i,
          color: Colors.purple,
        ),
    ];
    var selected = 'All';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Center(
              child: CompactFilterMenu<String>(
                label: 'Event',
                icon: Icons.event_rounded,
                options: options,
                selected: selected,
                onSelect: (value) => setState(() => selected = value),
                t: const AppTk(false),
                accent: const Color(0xFF8B5CF6),
                searchable: true,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Event · All events 9'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Event 9');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Event 9').last);
    await tester.pumpAndSettle();

    expect(selected, 'event-9');
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

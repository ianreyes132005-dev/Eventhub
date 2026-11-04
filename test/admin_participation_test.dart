import 'package:eventhub/features/admin/admin_participation.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The admin dashboard's Student Participation card (admin_participation.dart,
// counted by admin_registration_trend in migration 202611040003): how many
// active students joined at least one event in a school year, overall and by
// grade.

final _today = DateTime(2026, 11, 4); // in SY 2026–2027

void main() {
  test('school time is Asia/Manila, whatever the computer’s clock', () {
    // 5:00 PM UTC on Nov 3 is already Nov 4 in the Philippines.
    expect(schoolToday(DateTime.utc(2026, 11, 3, 17)), DateTime(2026, 11, 4));
    expect(schoolToday(DateTime.utc(2026, 11, 3, 15)), DateTime(2026, 11, 3));
  });

  test('a school year runs June to May; this one up to today', () {
    final now = schoolYearDays(2026, today: _today);
    expect(now.from, DateTime(2026, 6, 1));
    expect(now.to, _today);
    expect(now.prevFrom, DateTime(2025, 6, 1));
    expect(now.prevTo, DateTime(2026, 5, 31));
    final earlier = schoolYearDays(2025, today: _today);
    expect(earlier.from, DateTime(2025, 6, 1));
    expect(earlier.to, DateTime(2026, 5, 31));
  });

  group('by grade', () {
    const counts = <ReachCount>[
      (grade: 8, strand: null, students: 50, reached: 15),
      (grade: 7, strand: null, students: 80, reached: 52),
      (grade: 11, strand: 'STEM', students: 70, reached: 60),
      (grade: 11, strand: 'HUMSS', students: 65, reached: 40),
      (grade: 12, strand: null, students: 0, reached: 0),
      (grade: null, strand: null, students: 6, reached: 0),
    ];

    test('one row per grade, strands together, no grade on file last', () {
      final rows = gradeReach(counts);
      expect(rows.map((r) => gradeLabel(r.grade)),
          ['Grade 7', 'Grade 8', 'Grade 11', 'Grade not on file']);
      final g11 = rows.singleWhere((r) => r.grade == 11);
      expect((g11.students, g11.reached), (135, 100));
    });
  });

  test('read the way the database sends it', () {
    final data = ParticipationData.fromJson({
      'reach': [{'grade': 7, 'strand': null, 'students': 80, 'reached': 52}],
      'attendance': [
        {'week': '2026-10-19', 'registered': 100, 'attended': 80, 'events': 2},
        {'week': '2026-10-26', 'registered': 140, 'attended': 116, 'events': 3},
      ],
      'first_day': '2025-08-12',
      // The database function also sends these; the card doesn't need them.
      'days': [],
      'previous': 0,
    });
    expect(data.reach.single.reached, 52);
    expect(data.firstDay, DateTime(2025, 8, 12));
    expect(formatCount(1240), '1,240');
    expect(formatCount(7), '7');
  });

  group('the card', () {
    Map<String, dynamic> answer(int year) => {
          'reach': [
            {'grade': 7, 'strand': null, 'students': 80, 'reached': 61},
            {'grade': 8, 'strand': null, 'students': 80, 'reached': 24},
            {'grade': 11, 'strand': 'STEM', 'students': 160, 'reached': 120},
            {'grade': 11, 'strand': 'GAS', 'students': 160, 'reached': 107},
          ],
          'attendance': [
            {'week': '2026-10-26', 'registered': 240, 'attended': 196, 'events': 3},
          ],
          'first_day': '2025-08-12',
        };

    Future<List<int>> pump(WidgetTester tester, {double width = 680,
        Future<Map<String, dynamic>> Function(int)? load}) async {
      tester.view.physicalSize = Size(width + 40, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final asked = <int>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: width,
                child: AdminParticipationCard(
                  now: DateTime.utc(2026, 11, 4, 2),
                  load: (year) {
                    asked.add(year);
                    return (load ?? (y) async => answer(y))(year);
                  },
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return asked;
    }

    Finder text(String s) => find.textContaining(s, findRichText: true);

    testWidgets('one number and one bar per grade, nothing else', (tester) async {
      final asked = await pump(tester);
      expect(asked, [2026]);
      expect(find.text('Student Participation'), findsOneWidget);
      expect(find.text('SY 2026–2027'), findsOneWidget);
      // 312 of 480 joined.
      expect(find.text('65%'), findsOneWidget);
      expect(find.text('312 of 480 active students'), findsOneWidget);
      expect(find.text('Grade 7'), findsOneWidget);
      expect(find.text('Grade 11'), findsOneWidget); // strands together
      expect(find.text('24/80'), findsOneWidget);
      // No lowest-grade note and no show-up line; every bar the same colour.
      expect(text('lowest'), findsNothing);
      expect(text('showed up'), findsNothing);
      final colours = tester
          .widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .map((b) => (b.valueColor as AlwaysStoppedAnimation<Color?>).value)
          .toSet();
      expect(colours.length, 1);
      // Simple: no charts, no period switch.
      expect(find.byType(BarChart), findsNothing);
      expect(find.byType(LineChart), findsNothing);
      expect(find.text('Last 30 days'), findsNothing);
    });

    testWidgets('picking an earlier school year loads that one', (tester) async {
      final asked = await pump(tester);
      await tester.tap(find.text('SY 2026–2027'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SY 2025–2026').last);
      await tester.pumpAndSettle();
      expect(asked, [2026, 2025]);
      expect(find.text('SY 2025–2026'), findsOneWidget);
    });

    testWidgets('a failure says so and can be tried again', (tester) async {
      var fail = true;
      final asked = await pump(tester, load: (y) async {
        if (fail) throw Exception('function not found');
        return answer(y);
      });
      expect(text('Couldn’t load student participation'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(asked.length, 2);
      expect(find.text('65%'), findsOneWidget);
    });

    testWidgets('fits a narrow card', (tester) async {
      await pump(tester, width: 360);
      expect(tester.takeException(), isNull);
    });
  });
}

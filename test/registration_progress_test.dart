import 'package:eventhub/core/event_audience.dart';
import 'package:eventhub/shared/utils/registration_progress.dart';
import 'package:eventhub/shared/widgets/registration_progress_card.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The organizer's Registration progress card (web Dashboard and the app's
// Home): one counting rule for both, a rolling two weeks instead of a
// calendar week, and how far each grade is toward the event's group.

final _now = DateTime(2026, 11, 4, 10); // a Wednesday

Map<String, dynamic> _reg(
  String day, {
  String event = 'e1',
  String status = 'registered',
  int hour = 9,
}) => {
  'id': '$event-$day-$hour-$status',
  'event_id': event,
  'status': status,
  'registered_at': DateTime.parse(
    '${day}T${hour.toString().padLeft(2, '0')}:00:00',
  ).toUtc().toIso8601String(),
};

Map<String, dynamic> _event(
  String id,
  String day, {
  String approval = 'approved',
  String status = 'upcoming',
  String? archivedAt,
  List<int>? grades,
  List<String>? strands,
}) => {
  'event_id': id,
  'title': 'Event $id',
  'event_date': day,
  'start_time': '13:00:00',
  'end_time': '16:00:00',
  'approval_status': approval,
  'event_status': status,
  'archived_at': archivedAt,
  'audience_grades': grades,
  'audience_strands': strands,
};

const _counts = <GradeCount>[
  (grade: 7, strand: null, students: 50),
  (grade: 10, strand: null, students: 60),
  (grade: 11, strand: 'STEM', students: 70),
  (grade: 11, strand: 'HUMSS', students: 65),
  (grade: 12, strand: 'GAS', students: 40),
  (grade: null, strand: null, students: 5),
];

void main() {
  group('sign-ups per day', () {
    final regs = [
      _reg('2026-11-04'), _reg('2026-11-04', hour: 8),
      _reg('2026-11-03'),
      _reg('2026-11-03', status: 'rejected'), // declined: not a registration
      _reg('2026-10-28', event: 'e2'),
      _reg('2026-10-22'), // first day of the window
      _reg('2026-10-21'), // the day before: left out
    ];

    test('always 14 days, ending today — quiet days are real zeros', () {
      final d = dailySignups(regs, now: _now);
      expect(d.length, kSignupChartDays);
      expect(d.first.day, DateTime(2026, 10, 22));
      expect(d.last.day, DateTime(2026, 11, 4));
      expect(d.last.count, 2);
      expect(d[d.length - 2].count, 1); // Nov 3, the declined one not counted
      expect(d.first.count, 1);
      expect(d.fold<int>(0, (s, x) => s + x.count), 5);
    });

    test('one event', () {
      final d = dailySignups(regs, eventId: 'e2', now: _now);
      expect(d.fold<int>(0, (s, x) => s + x.count), 1);
    });

    test('the last 7 days against the 7 before', () {
      final w = lastTwoWeeks(dailySignups(regs, now: _now));
      expect(w, (last7: 3, previous7: 2)); // Oct 29–Nov 4 vs Oct 22–28
      expect(weekChangeLabel(w), '+1 vs previous 7 days');
      expect(
        weekChangeLabel((last7: 2, previous7: 5)),
        '−3 vs previous 7 days',
      );
      expect(
        weekChangeLabel((last7: 4, previous7: 4)),
        'Same as the previous 7 days',
      );
    });

    test('registered for an event leaves declined out', () {
      expect(registeredFor(regs, 'e1'), 5);
    });
  });

  group('which events the card follows', () {
    test('approved and still running, soonest first', () {
      final events = [
        _event('later', '2026-11-20'),
        _event('next', '2026-11-07'),
        _event('pending', '2026-11-06', approval: 'pending'),
        _event('cancelled', '2026-11-06', status: 'cancelled'),
        _event('archived', '2026-11-06', archivedAt: '2026-11-01T00:00:00Z'),
        _event('over', '2026-11-01'),
      ];
      expect(
        registrationProgressEvents(events, now: _now).map((e) => e['event_id']),
        ['next', 'later'],
      );
    });

    test('when registration closes', () {
      // Closes 2 hours after a 1:00 PM start.
      expect(
        registrationCloseLabel(_event('a', '2026-11-04'), now: _now),
        'Closes today at 3:00 PM',
      );
      expect(
        registrationCloseLabel(_event('a', '2026-11-05'), now: _now),
        'Closes tomorrow at 3:00 PM',
      );
      expect(
        registrationCloseLabel(_event('a', '2026-11-07'), now: _now),
        'Closes in 3 days (Nov 7)',
      );
      expect(
        registrationCloseLabel(
          _event('a', '2026-11-04'),
          now: DateTime(2026, 11, 4, 15, 30),
        ),
        'Registration closed',
      );
    });
  });

  group('by grade', () {
    const seniorHigh = <StudentGroup>[
      (grade: 11, strand: 'STEM'), (grade: 11, strand: 'STEM'),
      (grade: 11, strand: 'HUMSS'),
      (grade: 12, strand: 'GAS'), (grade: 12, strand: 'GAS'),
      (grade: 10, strand: null), // registered before the group was narrowed
    ];

    test('Senior High: one row per grade and strand, and who is outside', () {
      final rows = gradeProgress(
        audience: EventAudience.seniorHigh,
        counts: _counts,
        registrants: seniorHigh,
      );
      expect(rows, [
        (label: 'Grade 11 · HUMSS', registered: 1, eligible: 65),
        (label: 'Grade 11 · STEM', registered: 2, eligible: 70),
        (label: 'Grade 12 · GAS', registered: 2, eligible: 40),
        (label: 'Not in the group', registered: 1, eligible: null),
      ]);
    });

    test(
      'every student: Junior High by grade, and students with no grade on file',
      () {
        final rows = gradeProgress(
          audience: EventAudience.everyone,
          counts: _counts,
          registrants: const [],
        );
        expect(rows.map((r) => r.label), [
          'Grade 7',
          'Grade 10',
          'Grade 11 · HUMSS',
          'Grade 11 · STEM',
          'Grade 12 · GAS',
          'Grade not on file',
        ]);
        expect(rows.every((r) => r.registered == 0), isTrue);
      },
    );

    test('a strand group shows only its strand', () {
      final rows = gradeProgress(
        audience: EventAudience.pick(
          grades: kSeniorHighGrades,
          strands: ['STEM'],
        ),
        counts: _counts,
        registrants: const [(grade: 11, strand: 'STEM')],
      );
      expect(rows, [(label: 'Grade 11 · STEM', registered: 1, eligible: 70)]);
    });

    test(
      'without the student counts, registered students are still listed',
      () {
        final rows = gradeProgress(
          audience: EventAudience.seniorHigh,
          counts: null,
          registrants: const [(grade: 12, strand: 'GAS')],
        );
        expect(rows, [
          (label: 'Grade 12 · GAS', registered: 1, eligible: null),
        ]);
      },
    );

    test('the group furthest behind, when it is under half', () {
      expect(
        gradeFurthestBehind(const [
          (label: 'A', registered: 58, eligible: 70),
          (label: 'B', registered: 31, eligible: 65),
          (label: 'C', registered: 20, eligible: 40),
        ])?.label,
        'B',
      );
      // Everyone at half or more: nothing to point out.
      expect(
        gradeFurthestBehind(const [
          (label: 'A', registered: 40, eligible: 70),
          (label: 'B', registered: 33, eligible: 65),
        ]),
        isNull,
      );
      // One group: nothing to compare.
      expect(
        gradeFurthestBehind(const [(label: 'A', registered: 1, eligible: 70)]),
        isNull,
      );
    });
  });

  group('the card', () {
    final events = [
      _event('e1', '2026-11-07', grades: kSeniorHighGrades),
      _event('e2', '2026-11-20'),
    ];
    final regs = [
      for (var i = 0; i < 3; i++) _reg('2026-11-04', hour: 8 + i),
      _reg('2026-11-02'),
      _reg('2026-11-02', status: 'rejected'),
      _reg('2026-10-25', event: 'e2'),
    ];
    const groups = <StudentGroup>[
      (grade: 11, strand: 'STEM'),
      (grade: 11, strand: 'STEM'),
      (grade: 11, strand: 'HUMSS'),
      (grade: 12, strand: 'GAS'),
    ];

    Future<void> pump(WidgetTester tester, {double width = 560}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Center(
                child: SizedBox(
                  width: width,
                  child: RegistrationProgressCard(
                    events: events,
                    registrations: regs,
                    gradeCounts: _counts,
                    allStudents: 290,
                    loadGroups: (_) async => groups,
                    now: _now,
                    colors: const RegistrationProgressColors(
                      dark: false,
                      text: Color(0xFF111827),
                      sub: Color(0xFF4B5563),
                      muted: Color(0xFF6B7280),
                      border: Color(0xFFE5E7EB),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder text(String s) => find.textContaining(s, findRichText: true);

    testWidgets('opens on the next event: goal, closing time, grades', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Registration progress'), findsOneWidget);
      expect(find.text('Event e1'), findsOneWidget); // the picker
      // 4 registered (the declined one left out) of 175 Senior High students.
      expect(text('of 175 Senior High students'), findsOneWidget);
      expect(find.text('2%'), findsOneWidget);
      expect(find.text('Closes in 3 days (Nov 7)'), findsOneWidget);
      expect(find.text('Grade 11 · HUMSS'), findsOneWidget);
      expect(find.text('2/70'), findsOneWidget);
      expect(text('is furthest behind'), findsNothing);
      // Removed: the weekday "Peak" number and the "Today vs. this week" bar.
      expect(text('Peak'), findsNothing);
      expect(text('Today vs. this week'), findsNothing);
    });

    testWidgets('no always-on tooltips; quiet days have no stub bar', (
      tester,
    ) async {
      await pump(tester);
      final chart = tester.widget<BarChart>(find.byType(BarChart));
      final groups = chart.data.barGroups;
      expect(groups.length, kSignupChartDays);
      // A number shows only when a bar is hovered or touched.
      expect(groups.every((g) => g.showingTooltipIndicators.isEmpty), isTrue);
      expect(chart.data.barTouchData.enabled, isTrue);
      // Today has 3; a day with none draws nothing (no grey placeholder).
      expect(groups.last.barRods.single.toY, 3);
      expect(groups.first.barRods.single.toY, 0);
    });

    testWidgets('All events: sign-ups across events, and a hint to pick one', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('Event e1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All events').last);
      await tester.pumpAndSettle();
      expect(text('Senior High students'), findsNothing);
      expect(text('Pick an event to see'), findsOneWidget);
    });

    testWidgets('fits a phone', (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(tester, width: 328);
      expect(tester.takeException(), isNull);
      expect(find.text('Closes in 3 days (Nov 7)'), findsOneWidget);
    });
  });
}

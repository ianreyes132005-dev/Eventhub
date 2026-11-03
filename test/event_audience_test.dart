import 'package:flutter_test/flutter_test.dart';
import 'package:eventhub/core/event_audience.dart';
import 'package:eventhub/core/services/event_change_request_service.dart';
import 'package:eventhub/shared/utils/event_form_validation.dart';

// Who can register for an event (lib/core/event_audience.dart). The database
// refuses everyone else with the same rule (event_audience_allows, migration
// 202611030001), so these cases are the ones the two must agree on.

void main() {
  group('allows', () {
    test('an event for every student takes every student, even with no grade on file', () {
      expect(EventAudience.everyone.allows(grade: 8), isTrue);
      expect(EventAudience.everyone.allows(grade: 12, strand: 'STEM'), isTrue);
      expect(EventAudience.everyone.allows(), isTrue);
    });

    test('Senior High: Grades 11–12 only', () {
      expect(EventAudience.seniorHigh.allows(grade: 11, strand: 'GAS'), isTrue);
      expect(EventAudience.seniorHigh.allows(grade: 12), isTrue);
      expect(EventAudience.seniorHigh.allows(grade: 10), isFalse);
    });

    test('Junior High: Grades 7–10 only', () {
      expect(EventAudience.juniorHigh.allows(grade: 7), isTrue);
      expect(EventAudience.juniorHigh.allows(grade: 11, strand: 'STEM'), isFalse);
    });

    test('a student with no grade on file can only join events for every student', () {
      expect(EventAudience.seniorHigh.allows(), isFalse);
      expect(EventAudience.juniorHigh.allows(strand: 'STEM'), isFalse);
    });

    test('strands narrow the Senior High grades', () {
      final stem = EventAudience.pick(grades: kSeniorHighGrades, strands: ['STEM']);
      expect(stem.allows(grade: 12, strand: 'STEM'), isTrue);
      expect(stem.allows(grade: 12, strand: 'GAS'), isFalse);
      // A Senior High student with no strand on file isn't in a strand group.
      expect(stem.allows(grade: 11), isFalse);
    });

    test('a Junior High grade in a strand group stays open to all of that grade', () {
      final mixed = EventAudience.pick(grades: [10, 11, 12], strands: ['STEM']);
      expect(mixed.allows(grade: 10), isTrue);
      expect(mixed.allows(grade: 11, strand: 'STEM'), isTrue);
      expect(mixed.allows(grade: 11, strand: 'HUMSS'), isFalse);
      expect(mixed.allows(grade: 9), isFalse);
    });
  });

  group('label', () {
    String label(List<int>? g, [List<String>? s]) =>
        EventAudience.pick(grades: g, strands: s).label;

    test('shortcuts', () {
      expect(EventAudience.everyone.label, 'All students');
      expect(EventAudience.juniorHigh.label, 'Junior High');
      expect(EventAudience.seniorHigh.label, 'Senior High');
    });

    test('specific grades', () {
      expect(label([12]), 'Grade 12');
      expect(label([7, 8, 9]), 'Grades 7–9');
      expect(label([9, 7, 12]), 'Grades 7, 9 & 12');
      expect(label([10, 11, 12]), 'Grades 10–12');
    });

    test('with strands', () {
      expect(label(kSeniorHighGrades, ['STEM']), 'Senior High · STEM');
      expect(label([12], ['STEM', 'HUMSS']), 'Grade 12 · HUMSS & STEM');
      expect(label([10, 11, 12], ['STEM']), 'Grade 10 + Senior High · STEM');
      expect(label(kAllGrades, ['GAS']), 'Junior High + Senior High · GAS');
    });

    test('for a student outside the group', () {
      expect(EventAudience.seniorHigh.onlyLabel, 'Senior High only');
    });

    test('a change request shows strands in words', () {
      expect(EventAudience.strandsLabel(null), 'All strands');
      expect(EventAudience.strandsLabel(['STEM', 'GAS']), 'GAS & STEM');
    });
  });

  group('pick tidies the group the way it is saved', () {
    test('grades sorted, repeats and grades outside 7–12 dropped', () {
      expect(EventAudience.pick(grades: [12, 11, 12, 5]).grades, [11, 12]);
    });

    test('every grade with any strand is every student', () {
      expect(EventAudience.pick(grades: kAllGrades), EventAudience.everyone);
    });

    test('all three strands = any strand', () {
      expect(EventAudience.pick(grades: kSeniorHighGrades, strands: kShsStrands).strands, isNull);
    });

    test('strands need a Senior High grade', () {
      expect(EventAudience.pick(grades: [9, 10], strands: ['STEM']).strands, isNull);
    });

    test('strands keep a fixed order, so an unchanged group compares equal', () {
      expect(EventAudience.pick(grades: [11], strands: ['STEM', 'HUMSS']).strands,
          ['HUMSS', 'STEM']);
    });

    test('"Specific grades" with none picked is not valid', () {
      expect(EventAudience.pick(grades: const <int>[]).isValid, isFalse);
      expect(EventAudience.everyone.isValid, isTrue);
    });
  });

  group('of reads the saved columns', () {
    test('an event from before the migration is for every student', () {
      expect(EventAudience.of({'title': 'Fair'}), EventAudience.everyone);
    });

    test('lists as the database returns them', () {
      final a = EventAudience.of({
        'audience_grades': <dynamic>[12, 11],
        'audience_strands': <dynamic>['STEM'],
      });
      expect(a.grades, [11, 12]);
      expect(a.strands, ['STEM']);
      expect(a.preset, AudiencePreset.seniorHigh);
    });

    test('which shortcut the form shows', () {
      expect(EventAudience.everyone.preset, AudiencePreset.everyone);
      expect(EventAudience.juniorHigh.preset, AudiencePreset.juniorHigh);
      expect(EventAudience.pick(grades: [12]).preset, AudiencePreset.custom);
    });
  });

  group('capacity = the active students in the group', () {
    const counts = <GradeCount>[
      (grade: 7, strand: null, students: 40),
      (grade: 10, strand: null, students: 35),
      (grade: 11, strand: 'STEM', students: 20),
      (grade: 11, strand: 'HUMSS', students: 15),
      (grade: 12, strand: 'STEM', students: 18),
      (grade: 12, strand: null, students: 2),
      (grade: null, strand: null, students: 5),
    ];

    test('every student: the active student count', () {
      expect(EventAudience.everyone.capacity(allStudents: 135, counts: counts), 135);
      expect(EventAudience.everyone.capacity(counts: counts), 135);
    });

    test('Senior High', () {
      expect(EventAudience.seniorHigh.capacity(counts: counts), 55);
    });

    test('Senior High STEM', () {
      final stem = EventAudience.pick(grades: kSeniorHighGrades, strands: ['STEM']);
      expect(stem.capacity(counts: counts), 38);
    });

    test('unknown until the breakdown can be read', () {
      expect(EventAudience.seniorHigh.capacity(allStudents: 135), isNull);
    });
  });

  test('outside: registered students a narrower group leaves out (they stay registered)', () {
    const students = <StudentGroup>[
      (grade: 10, strand: null),
      (grade: 11, strand: 'STEM'),
      (grade: 12, strand: 'GAS'),
      (grade: null, strand: null),
    ];
    expect(EventAudience.everyone.outside(students), 0);
    expect(EventAudience.seniorHigh.outside(students), 2);
    expect(EventAudience.pick(grades: kSeniorHighGrades, strands: ['STEM']).outside(students), 3);
  });

  group('AudienceChoice: what the form picker holds', () {
    test('starts as every student', () {
      expect(const AudienceChoice().audience, EventAudience.everyone);
    });

    test('a shortcut is the group', () {
      final c = const AudienceChoice().choose(AudiencePreset.seniorHigh);
      expect(c.audience, EventAudience.seniorHigh);
      expect(c.showsStrands, isTrue);
    });

    test('"Specific grades" starts from the shortcut that was picked', () {
      final c = const AudienceChoice()
          .choose(AudiencePreset.juniorHigh)
          .choose(AudiencePreset.custom);
      expect(c.grades, {7, 8, 9, 10});
      expect(c.audience, EventAudience.juniorHigh);
    });

    test('"Specific grades" from every student starts empty — the form asks for one', () {
      final c = const AudienceChoice().choose(AudiencePreset.custom);
      expect(c.grades, isEmpty);
      expect(c.audience.isValid, isFalse);
    });

    test('grades toggle; strands show once Grade 11 or 12 is picked', () {
      var c = const AudienceChoice().choose(AudiencePreset.custom).toggleGrade(10);
      expect(c.showsStrands, isFalse);
      c = c.toggleGrade(12);
      expect(c.showsStrands, isTrue);
      expect(c.mixesLevels, isTrue);
      c = c.toggleGrade(10);
      expect(c.mixesLevels, isFalse);
      expect(c.audience.grades, [12]);
    });

    test('strands toggle; all three = all strands', () {
      var c = const AudienceChoice().choose(AudiencePreset.seniorHigh).toggleStrand('STEM');
      expect(c.audience.label, 'Senior High · STEM');
      c = c.toggleStrand('GAS').toggleStrand('HUMSS');
      expect(c.strands, isEmpty);
      expect(c.audience, EventAudience.seniorHigh);
      expect(c.toggleStrand('GAS').allStrands().strands, isEmpty);
    });

    test('All students and Junior High drop the strands', () {
      final c = const AudienceChoice()
          .choose(AudiencePreset.seniorHigh)
          .toggleStrand('STEM')
          .choose(AudiencePreset.juniorHigh);
      expect(c.strands, isEmpty);
      expect(c.choose(AudiencePreset.seniorHigh).audience, EventAudience.seniorHigh);
    });

    test('opens on an event\'s saved group', () {
      final saved = EventAudience.pick(grades: [10, 11, 12], strands: ['STEM']);
      final c = AudienceChoice.of(saved);
      expect(c.preset, AudiencePreset.custom);
      expect(c.audience, saved);
      expect(AudienceChoice.of(EventAudience.seniorHigh).preset, AudiencePreset.seniorHigh);
    });
  });

  test('the event form reports "Specific grades" with no grade picked', () {
    Map<EventFormField, String> errors(EventAudience a) => validateEventForm(
          title: 'Fair', needsOtherType: false, otherType: '',
          startDate: null, endDate: null, startTime: null, endTime: null,
          location: 'Gym', audience: a,
        );
    expect(errors(EventAudience.pick(grades: const <int>[])),
        containsPair(EventFormField.audience, 'Pick at least one grade.'));
    expect(errors(EventAudience.seniorHigh).containsKey(EventFormField.audience), isFalse);
  });

  group('change requests', () {
    final live = <String, dynamic>{
      'title': 'Fair',
      'audience_grades': <dynamic>[11, 12],
      'audience_strands': null,
    };

    test('an unchanged group is not a change', () {
      expect(EventChangeRequestService.diff(live, {
        'title': 'Fair',
        ...EventAudience.seniorHigh.columns,
      }), isEmpty);
    });

    test('narrowing to a strand changes only the strands', () {
      final stem = EventAudience.pick(grades: kSeniorHighGrades, strands: ['STEM']);
      expect(EventChangeRequestService.diff(live, stem.columns),
          {'audience_strands': ['STEM']});
    });

    test('opening it to every student clears the grades', () {
      expect(EventChangeRequestService.diff(live, EventAudience.everyone.columns),
          {'audience_grades': null});
    });

    test('an event that never had a group, opened to every student: no change', () {
      expect(EventChangeRequestService.diff({'title': 'Fair'}, EventAudience.everyone.columns),
          isEmpty);
    });
  });
}

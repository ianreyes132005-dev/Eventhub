import 'package:flutter/foundation.dart' show listEquals;

// ─────────────────────────────────────────────────────────────────────────────
// Who can register for an event — events.audience_grades / audience_strands
// (migration 202611030001).
//
//   • No grades: every student (the default, and every older event).
//   • Grades 7–12: only students in those grades. Junior High = Grades 7–10,
//     Senior High = Grades 11–12.
//   • Strands (HUMSS, GAS, STEM): narrow the group's Senior High grades to
//     those strands. A Junior High grade in the group stays open to all of
//     that grade.
//
// Students outside the group still see the event, labelled ("Senior High
// only"), but can't register: the database refuses it with the same rule
// (event_audience_allows) — keep the two the same.
// ─────────────────────────────────────────────────────────────────────────────

const kJuniorHighGrades = [7, 8, 9, 10];
const kSeniorHighGrades = [11, 12];
const kAllGrades        = [7, 8, 9, 10, 11, 12];
const kShsStrands       = ['HUMSS', 'GAS', 'STEM'];

bool isSeniorHighGrade(int grade) => grade >= 11;

/// Active students in one grade and strand — a row of
/// active_student_counts(). Grade and strand are null when not on file.
typedef GradeCount = ({int? grade, String? strand, int students});

/// One student's grade and strand (null when not on file).
typedef StudentGroup = ({int? grade, String? strand});

/// The event form's shortcuts. [custom] is any other group of grades.
enum AudiencePreset { everyone, juniorHigh, seniorHigh, custom }

class EventAudience {
  /// Use [EventAudience.pick] to build one from the form's choices.
  const EventAudience({this.grades, this.strands});

  /// Grades that can register, sorted; null = every student.
  final List<int>? grades;

  /// Senior High strands that can register, in [kShsStrands] order; null =
  /// any strand.
  final List<String>? strands;

  static const everyone   = EventAudience();
  static const juniorHigh = EventAudience(grades: kJuniorHighGrades);
  static const seniorHigh = EventAudience(grades: kSeniorHighGrades);

  /// The group as the form picked it, tidied the way it's saved: grades
  /// sorted; strands only with a Senior High grade, and none (any strand)
  /// when all three are picked; every grade with any strand = every student.
  /// An empty [grades] stays empty — the form reports it ([isValid]).
  factory EventAudience.pick({Iterable<int>? grades, Iterable<String>? strands}) {
    if (grades == null) return everyone;
    final g = kAllGrades.where(grades.toSet().contains).toList();
    final picked = strands?.toSet() ?? const <String>{};
    final s = kShsStrands.where(picked.contains).toList();
    final keepStrands = g.any(isSeniorHighGrade) && s.isNotEmpty && s.length < kShsStrands.length;
    if (!keepStrands && listEquals(g, kAllGrades)) return everyone;
    return EventAudience(grades: g, strands: keepStrands ? s : null);
  }

  /// The event's group as saved. An event from before the migration (no
  /// columns) is open to every student.
  factory EventAudience.of(Map<String, dynamic> event) => EventAudience(
        grades: _ints(event['audience_grades']),
        strands: _strings(event['audience_strands']),
      );

  bool get isEveryone => grades == null;

  /// False when the form picked "Specific grades" but no grade.
  bool get isValid => grades == null || grades!.isNotEmpty;

  /// The group includes Senior High students, so strands can narrow it.
  bool get includesSeniorHigh => grades == null || grades!.any(isSeniorHighGrade);

  /// Which of the form's shortcuts this group is.
  AudiencePreset get preset {
    final g = grades;
    if (g == null) return AudiencePreset.everyone;
    if (strands == null && listEquals(g, kJuniorHighGrades)) return AudiencePreset.juniorHigh;
    if (listEquals(g, kSeniorHighGrades)) return AudiencePreset.seniorHigh;
    return AudiencePreset.custom;
  }

  /// The columns to save. Lists keep a fixed order, so an unchanged group
  /// compares equal in a change request.
  Map<String, dynamic> get columns =>
      {'audience_grades': grades, 'audience_strands': strands};

  /// Can a student in [grade] / [strand] register? A student with no grade
  /// on file only can when the event is open to every student.
  bool allows({int? grade, String? strand}) {
    final g = grades;
    if (g == null) return true;
    if (grade == null || !g.contains(grade)) return false;
    final s = strands;
    if (!isSeniorHighGrade(grade) || s == null) return true;
    return strand != null && s.contains(strand);
  }

  /// "All students", "Junior High", "Senior High", "Grade 12", "Grades 7–9",
  /// "Senior High · STEM", "Grade 10 + Senior High · HUMSS & STEM".
  String get label {
    final g = grades;
    if (g == null) return 'All students';
    if (g.isEmpty) return 'No grades picked';
    final shs = g.where(isSeniorHighGrade).toList();
    final s = strands;
    if (s == null || shs.isEmpty) {
      if (listEquals(g, kJuniorHighGrades)) return 'Junior High';
      if (listEquals(g, kSeniorHighGrades)) return 'Senior High';
      return _gradesText(g);
    }
    final shsPart =
        '${listEquals(shs, kSeniorHighGrades) ? 'Senior High' : _gradesText(shs)} · ${_and(s)}';
    final jhs = g.where((x) => !isSeniorHighGrade(x)).toList();
    if (jhs.isEmpty) return shsPart;
    final jhsPart = listEquals(jhs, kJuniorHighGrades) ? 'Junior High' : _gradesText(jhs);
    return '$jhsPart + $shsPart';
  }

  /// For a student outside the group: "Senior High only".
  String get onlyLabel => '$label only';

  /// How many of [students] (e.g. the ones already registered) aren't in the
  /// group — they keep their registration when an organizer narrows it.
  int outside(Iterable<StudentGroup> students) =>
      students.where((s) => !allows(grade: s.grade, strand: s.strand)).length;

  /// How many active students can register: every active student
  /// ([allStudents]) when the event is open to all, otherwise the ones in the
  /// group, added up from [counts]. Null while unknown.
  int? capacity({int? allStudents, List<GradeCount>? counts}) {
    if (isEveryone) {
      return allStudents ?? counts?.fold<int>(0, (n, c) => n + c.students);
    }
    if (counts == null) return null;
    return counts
        .where((c) => allows(grade: c.grade, strand: c.strand))
        .fold<int>(0, (n, c) => n + c.students);
  }

  /// A change request's strands value: "All strands" or "HUMSS & STEM".
  static String strandsLabel(Object? value) {
    final s = _strings(value);
    return s == null ? 'All strands' : _and(s);
  }

  @override
  bool operator ==(Object other) =>
      other is EventAudience &&
      listEquals(other.grades, grades) &&
      listEquals(other.strands, strands);

  @override
  int get hashCode => Object.hash(
      grades == null ? null : Object.hashAll(grades!),
      strands == null ? null : Object.hashAll(strands!));

  @override
  String toString() => 'EventAudience($label)';
}

/// What the event form's "Who can register" picker holds (web and app): a
/// shortcut, the grades picked under "Specific grades", and the Senior High
/// strands picked (none = all strands). Each tap returns a new one.
class AudienceChoice {
  const AudienceChoice({
    this.preset = AudiencePreset.everyone,
    this.grades = const {},
    this.strands = const {},
  });

  final AudiencePreset preset;

  /// The grades picked under [AudiencePreset.custom].
  final Set<int> grades;

  /// Senior High strands picked; empty = all strands.
  final Set<String> strands;

  /// The picker set to an event's saved group.
  factory AudienceChoice.of(EventAudience audience) => AudienceChoice(
        preset: audience.preset,
        grades: audience.preset == AudiencePreset.custom
            ? {...?audience.grades}
            : const {},
        strands: {...?audience.strands},
      );

  /// The group to save.
  EventAudience get audience => switch (preset) {
        AudiencePreset.everyone   => EventAudience.everyone,
        AudiencePreset.juniorHigh => EventAudience.juniorHigh,
        AudiencePreset.seniorHigh =>
          EventAudience.pick(grades: kSeniorHighGrades, strands: strands),
        AudiencePreset.custom => EventAudience.pick(grades: grades, strands: strands),
      };

  /// Strands can narrow the group: Senior High, or specific grades with 11
  /// or 12 among them.
  bool get showsStrands =>
      preset == AudiencePreset.seniorHigh ||
      (preset == AudiencePreset.custom && grades.any(isSeniorHighGrade));

  /// Specific grades from both levels, with strands showing — the strands
  /// only narrow the Senior High ones.
  bool get mixesLevels =>
      showsStrands &&
      preset == AudiencePreset.custom &&
      grades.any((g) => !isSeniorHighGrade(g));

  /// A shortcut was tapped. "Specific grades" starts from the shortcut that
  /// was picked, so it can be adjusted; All students and Junior High have no
  /// strands.
  AudienceChoice choose(AudiencePreset next) => AudienceChoice(
        preset: next,
        grades: next == AudiencePreset.custom && preset != AudiencePreset.custom
            ? {...?audience.grades}
            : grades,
        strands: next == AudiencePreset.everyone || next == AudiencePreset.juniorHigh
            ? const {}
            : strands,
      );

  AudienceChoice toggleGrade(int grade) => AudienceChoice(
        preset: preset,
        grades: grades.contains(grade)
            ? ({...grades}..remove(grade))
            : {...grades, grade},
        strands: strands,
      );

  /// All three strands = any strand.
  AudienceChoice toggleStrand(String strand) {
    final next = strands.contains(strand)
        ? ({...strands}..remove(strand))
        : {...strands, strand};
    return AudienceChoice(
      preset: preset,
      grades: grades,
      strands: next.length == kShsStrands.length ? const {} : next,
    );
  }

  AudienceChoice allStrands() =>
      AudienceChoice(preset: preset, grades: grades, strands: const {});
}

List<int>? _ints(Object? v) {
  if (v is! List) return null;
  final out = [
    for (final x in v)
      if (x is num) x.toInt() else ?int.tryParse('$x'),
  ]..sort();
  return out;
}

List<String>? _strings(Object? v) {
  if (v is! List) return null;
  final set = {for (final x in v) '$x'.trim().toUpperCase()};
  return [
    ...kShsStrands.where(set.contains),
    ...set.where((x) => !kShsStrands.contains(x)),
  ];
}

/// "Grade 7", "Grades 7–9" (a run), "Grades 7, 9 & 12".
String _gradesText(List<int> g) {
  if (g.length == 1) return 'Grade ${g.first}';
  final run = g.last - g.first == g.length - 1;
  return run ? 'Grades ${g.first}–${g.last}' : 'Grades ${_and(g.map((x) => '$x').toList())}';
}

/// "A", "A & B", "A, B & C".
String _and(List<String> items) => items.length <= 1
    ? items.join()
    : '${items.sublist(0, items.length - 1).join(', ')} & ${items.last}';

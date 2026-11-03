import '../../core/app_colors.dart'
    show countsAsRegistered, eventIsApproved, eventIsArchived, eventIsCancelled,
        eventWindow, registrationClosesAt;
import '../../core/event_audience.dart';
import 'event_labels.dart' show monthDayLabel;

// ─────────────────────────────────────────────────────────────────────────────
// The organizer's "Registration progress" card (web Dashboard and the app's
// Home, RegistrationProgressCard): how an event is filling up toward the
// students it's for, which grades are behind, and new sign-ups per day. Kept
// apart from the widget so the web and the app count the same way and the
// rules can be tested.
//
// One rule everywhere: a declined registration (status 'rejected') isn't a
// registration (countsAsRegistered). A student who cancels has no row left,
// so they don't count either.
// ─────────────────────────────────────────────────────────────────────────────

/// Days in the sign-ups chart: two weeks, so the last 7 days can be compared
/// with the 7 before.
const kSignupChartDays = 14;

/// One bar: a day and the registrations made on it.
typedef DailySignups = ({DateTime day, int count});

/// Registrations per day for the [days] days ending today, oldest first —
/// always [days] entries, so a quiet day is a real 0, never left out.
/// [eventId] narrows it to one event.
List<DailySignups> dailySignups(
  Iterable<Map<String, dynamic>> registrations, {
  String? eventId,
  DateTime? now,
  int days = kSignupChartDays,
}) {
  final at = now ?? DateTime.now();
  final today = DateTime(at.year, at.month, at.day);
  final first = DateTime(today.year, today.month, today.day - (days - 1));
  final counts = List<int>.filled(days, 0);
  for (final r in registrations) {
    if (eventId != null && r['event_id'] != eventId) continue;
    if (!countsAsRegistered(r)) continue;
    final t = DateTime.tryParse(r['registered_at'] as String? ?? '')?.toLocal();
    if (t == null) continue;
    final day = DateTime(t.year, t.month, t.day);
    if (day.isBefore(first) || day.isAfter(today)) continue;
    // Calendar days, not 24-hour blocks, so a daylight-saving shift (on a
    // phone set to another time zone) can't move a sign-up to the wrong bar.
    counts[DateTime.utc(day.year, day.month, day.day)
        .difference(DateTime.utc(first.year, first.month, first.day))
        .inDays]++;
  }
  return [
    for (var i = 0; i < days; i++)
      (day: DateTime(first.year, first.month, first.day + i), count: counts[i]),
  ];
}

/// The last 7 days against the 7 before them, from a [dailySignups] list.
({int last7, int previous7}) lastTwoWeeks(List<DailySignups> daily) {
  var last7 = 0, previous7 = 0;
  for (var i = 0; i < daily.length; i++) {
    if (i >= daily.length - 7) {
      last7 += daily[i].count;
    } else if (i >= daily.length - 14) {
      previous7 += daily[i].count;
    }
  }
  return (last7: last7, previous7: previous7);
}

/// "+12 vs previous 7 days", "−3 vs …", "Same as the previous 7 days".
String weekChangeLabel(({int last7, int previous7}) w) {
  final d = w.last7 - w.previous7;
  if (d == 0) return 'Same as the previous 7 days';
  return '${d > 0 ? '+' : '−'}${d.abs()} vs previous 7 days';
}

/// The events whose registration the card can follow: approved, not
/// cancelled or archived, and not over yet — soonest first. The first one is
/// the Dashboard's next event (nextApprovedEvent uses the same rule).
List<Map<String, dynamic>> registrationProgressEvents(
  Iterable<Map<String, dynamic>> events, {
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final out = <(DateTime, Map<String, dynamic>)>[];
  for (final e in events) {
    if (!eventIsApproved(e) || eventIsCancelled(e) || eventIsArchived(e)) continue;
    final w = eventWindow(e);
    if (w == null || !at.isBefore(w.end)) continue;
    out.add((w.start, e));
  }
  out.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final (_, e) in out) e];
}

/// Registrations for [eventId], declined ones left out.
int registeredFor(Iterable<Map<String, dynamic>> registrations, String eventId) =>
    registrations.where((r) => r['event_id'] == eventId && countsAsRegistered(r)).length;

/// Who the goal is: "students", "Senior High students", "Grade 12 students".
String audienceStudentsLabel(EventAudience audience) =>
    audience.isEveryone ? 'students' : '${audience.label} students';

/// "Closes today at 3:00 PM", "Closes tomorrow at 3:00 PM",
/// "Closes in 3 days (Nov 7)", "Registration closed" — null without a date.
String? registrationCloseLabel(Map<String, dynamic> event, {DateTime? now}) {
  final closes = registrationClosesAt(event);
  if (closes == null) return null;
  final at = now ?? DateTime.now();
  if (!at.isBefore(closes)) return 'Registration closed';
  final days = DateTime.utc(closes.year, closes.month, closes.day)
      .difference(DateTime.utc(at.year, at.month, at.day))
      .inDays;
  final h = closes.hour % 12 == 0 ? 12 : closes.hour % 12;
  final time = '$h:${closes.minute.toString().padLeft(2, '0')} '
      '${closes.hour < 12 ? 'AM' : 'PM'}';
  if (days == 0) return 'Closes today at $time';
  if (days == 1) return 'Closes tomorrow at $time';
  return 'Closes in $days days (${monthDayLabel(closes)})';
}

/// One row of the "By grade" list. [eligible] is null when the student
/// counts couldn't be read, or for students outside the event's group (an
/// organizer narrowed the group after they registered).
typedef GradeProgress = ({String label, int registered, int? eligible});

/// Registered against eligible students for each grade in the event's group
/// — Senior High split by strand — so the organizer can see which grades'
/// advisers to remind. [counts] are the active students per grade and
/// strand (StudentCountService.gradeCounts); [registrants] the grade and
/// strand of each registered student (RegistrationService.registrantGroups).
List<GradeProgress> gradeProgress({
  required EventAudience audience,
  required List<GradeCount>? counts,
  required List<StudentGroup> registrants,
}) {
  const outside = 'Not in the group';
  final eligible = <String, int>{};
  final registered = <String, int>{};
  final order = <String, int>{};

  String keyOf(int? grade, String? strand) {
    final label = grade == null
        ? 'Grade not on file'
        : !isSeniorHighGrade(grade)
            ? 'Grade $grade'
            : strand == null || strand.isEmpty
                ? 'Grade $grade · no strand'
                : 'Grade $grade · $strand';
    // Grade order, then HUMSS, GAS, STEM, then any other strand, then none.
    final known = strand == null ? -1 : kShsStrands.indexOf(strand);
    final strandRank = strand == null || strand.isEmpty
        ? kShsStrands.length + 1
        : known >= 0 ? known : kShsStrands.length;
    order[label] = grade == null ? 9999 : grade * 10 + strandRank;
    return label;
  }

  for (final c in counts ?? const <GradeCount>[]) {
    if (c.students <= 0 || !audience.allows(grade: c.grade, strand: c.strand)) continue;
    final k = keyOf(c.grade, c.strand);
    eligible[k] = (eligible[k] ?? 0) + c.students;
  }
  for (final s in registrants) {
    final k = audience.allows(grade: s.grade, strand: s.strand)
        ? keyOf(s.grade, s.strand)
        : outside;
    order.putIfAbsent(outside, () => 99999);
    registered[k] = (registered[k] ?? 0) + 1;
  }

  final keys = {...eligible.keys, ...registered.keys}.toList()
    ..sort((a, b) => order[a]!.compareTo(order[b]!));
  return [
    for (final k in keys)
      (
        label: k,
        registered: registered[k] ?? 0,
        eligible: k == outside || counts == null ? null : (eligible[k] ?? 0),
      ),
  ];
}

/// The group furthest behind, when it's under half — what the card suggests
/// reminding. Needs at least two groups with students to compare.
GradeProgress? gradeFurthestBehind(List<GradeProgress> rows) {
  final comparable = [
    for (final r in rows)
      if ((r.eligible ?? 0) > 0) r,
  ];
  if (comparable.length < 2) return null;
  double share(GradeProgress r) => r.registered / r.eligible!;
  final lowest = comparable.reduce((a, b) => share(b) < share(a) ? b : a);
  return share(lowest) < 0.5 ? lowest : null;
}

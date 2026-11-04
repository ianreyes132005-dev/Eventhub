import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/services/supabase_service.dart';
import '../organizer/web/web_shared.dart';
import 'admin_shared.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The admin dashboard's Student Participation: how many active students
// joined at least one event in a school year, overall and by grade.
//
// Counted in the database (admin_registration_trend, migration 202611040003),
// so it isn't cut off at Supabase's 1,000-row limit. Declined registrations
// and cancelled events don't count, and days are school days (Asia/Manila).
// ─────────────────────────────────────────────────────────────────────────────

/// Today in school time (Asia/Manila: UTC+8 all year), the days the database
/// counts by.
DateTime schoolToday([DateTime? now]) {
  final m = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 8));
  return DateTime(m.year, m.month, m.day);
}

/// School year [year] (June to May) up to today, and the year before it —
/// the database function asks for both.
({DateTime from, DateTime to, DateTime prevFrom, DateTime prevTo}) schoolYearDays(
  int year, {
  DateTime? today,
}) {
  final t = today ?? schoolToday();
  final start = DateTime(year, kSchoolYearStartMonth, 1);
  final end = DateTime(year + 1, kSchoolYearStartMonth, 0); // the last day of May
  final to = t.isBefore(start) ? start : t.isBefore(end) ? t : end;
  return (
    from: start,
    to: to,
    prevFrom: DateTime(year - 1, kSchoolYearStartMonth, 1),
    prevTo: DateTime(year, kSchoolYearStartMonth, 0),
  );
}

/// Active students in one grade and strand, and how many joined an event.
typedef ReachCount = ({int? grade, String? strand, int students, int reached});

/// What the card shows, as the database sends it.
class ParticipationData {
  final List<ReachCount> reach;

  /// The earliest sign-up: which school years can be picked.
  final DateTime? firstDay;

  const ParticipationData({required this.reach, required this.firstDay});

  static int _int(Object? v) => (v as num?)?.toInt() ?? 0;

  static List<Map<String, dynamic>> _rows(Object? v) => [
        for (final r in v is List ? v : const [])
          if (r is Map) Map<String, dynamic>.from(r),
      ];

  factory ParticipationData.fromJson(Map<String, dynamic> j) {
    final first = DateTime.tryParse(j['first_day'] as String? ?? '');
    return ParticipationData(
      reach: [
        for (final r in _rows(j['reach']))
          (
            grade: (r['grade'] as num?)?.toInt(),
            strand: r['strand'] as String?,
            students: _int(r['students']),
            reached: _int(r['reached']),
          ),
      ],
      firstDay: first == null ? null : DateTime(first.year, first.month, first.day),
    );
  }
}

/// One grade (Senior High strands together), and how many of its active
/// students joined an event.
typedef GradeReach = ({int? grade, int students, int reached});

/// One row per grade, 7 to 12, then students with no grade on file.
List<GradeReach> gradeReach(List<ReachCount> counts) {
  final students = <int?, int>{};
  final reached = <int?, int>{};
  for (final c in counts) {
    students[c.grade] = (students[c.grade] ?? 0) + c.students;
    reached[c.grade] = (reached[c.grade] ?? 0) + c.reached;
  }
  final grades = students.keys.where((g) => students[g]! > 0).toList()
    ..sort((a, b) => (a ?? 99).compareTo(b ?? 99));
  return [
    for (final g in grades) (grade: g, students: students[g]!, reached: reached[g]!),
  ];
}

/// "Grade 8", or "Grade not on file".
String gradeLabel(int? grade) => grade == null ? 'Grade not on file' : 'Grade $grade';

/// "1,240".
String formatCount(int n) {
  final s = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

int _percent(int part, int whole) => whole == 0 ? 0 : (part / whole * 100).round();

// ── Card ────────────────────────────────────────────────────────────────────

class AdminParticipationCard extends StatefulWidget {
  /// Changes when the dashboard reloads after a live change; the card
  /// reloads with it.
  final int refreshKey;

  /// For tests: answers instead of the database, for school year [year].
  final Future<Map<String, dynamic>> Function(int year)? load;

  /// For tests: the clock.
  final DateTime? now;

  const AdminParticipationCard({super.key, this.refreshKey = 0, this.load, this.now});

  @override
  State<AdminParticipationCard> createState() => _AdminParticipationCardState();
}

class _AdminParticipationCardState extends State<AdminParticipationCard> {
  // One colour for every bar.
  static const _blue = Color(0xFF3B82F6);

  int? _year; // the one picked; null = this school year
  ParticipationData? _data;
  bool _loading = true;
  Object? _error;
  int _request = 0;

  int get _currentYear => schoolYearOf(schoolToday(widget.now));
  int get _shownYear => math.min(_year ?? _currentYear, _currentYear);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AdminParticipationCard old) {
    super.didUpdateWidget(old);
    if (old.refreshKey != widget.refreshKey) _load(silent: true);
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}'
      '-${d.day.toString().padLeft(2, '0')}';

  Future<Map<String, dynamic>> _fromDatabase(int year) async {
    final days = schoolYearDays(year, today: schoolToday(widget.now));
    final res = await SupabaseService.client.rpc(
      'admin_registration_trend',
      params: {
        'p_from': _iso(days.from),
        'p_to': _iso(days.to),
        'p_prev_from': _iso(days.prevFrom),
        'p_prev_to': _iso(days.prevTo),
        'p_school_year': _iso(days.from),
      },
    );
    return Map<String, dynamic>.from(res as Map);
  }

  /// [silent] (a live update) keeps what's on screen while it reloads, and a
  /// failure keeps it too.
  Future<void> _load({bool silent = false}) async {
    final year = _shownYear;
    final id = ++_request;
    if (!silent && (!_loading || _error != null)) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final json = await (widget.load ?? _fromDatabase)(year);
      if (!mounted || id != _request) return;
      setState(() {
        _data = ParticipationData.fromJson(json);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      debugPrint('Student participation unavailable: $e');
      if (!mounted || id != _request) return;
      setState(() {
        _loading = false;
        if (!silent || _data == null) _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final data = _data;
    return WebCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Student Participation',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                          fontWeight: FontWeight.w700, color: t.text)),
                    const SizedBox(height: 2),
                    Text('Students who joined at least one event',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.sub)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _buildYearMenu(t),
            ],
          ),
          const SizedBox(height: 18),
          if (data == null && _error != null)
            _buildError(t)
          else if (data == null)
            const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator(color: kAdminAccent)),
            )
          else
            AnimatedOpacity(
              opacity: _loading ? 0.45 : 1,
              duration: const Duration(milliseconds: 150),
              child: _buildBody(t, data),
            ),
        ],
      ),
    );
  }

  Widget _buildYearMenu(WebTk t) {
    final current = _currentYear;
    final shown = _shownYear;
    final first = _data?.firstDay == null ? current : schoolYearOf(_data!.firstDay!);
    final years = [for (var y = current; y >= math.min(first, shown); y--) y];
    return PopupMenuButton<int>(
      tooltip: 'Choose a school year',
      initialValue: shown,
      position: PopupMenuPosition.under,
      onSelected: (y) {
        if (y == shown) return;
        setState(() => _year = y);
        _load();
      },
      itemBuilder: (_) => [
        for (final y in years)
          PopupMenuItem(
            value: y,
            child: Text(
              y == current ? '${schoolYearLabel(y)} (this year)' : schoolYearLabel(y),
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5),
            ),
          ),
      ],
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(schoolYearLabel(shown),
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                  fontWeight: FontWeight.w600, color: t.text)),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: t.sub),
          ],
        ),
      ),
    );
  }

  Widget _buildError(WebTk t) => SizedBox(
        height: 200,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 30, color: t.muted),
              const SizedBox(height: 10),
              Text('Couldn’t load student participation.',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                    fontWeight: FontWeight.w600, color: t.text)),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Try again'),
                style: TextButton.styleFrom(
                  foregroundColor: t.dark ? const Color(0xFFFB923C) : const Color(0xFFC2410C),
                  textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _bar(WebTk t, double share, Color color, {double height = 8}) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: LinearProgressIndicator(
          value: share.clamp(0.0, 1.0),
          minHeight: height,
          backgroundColor: color.withValues(alpha: t.dark ? 0.18 : 0.13),
          valueColor: AlwaysStoppedAnimation(color),
        ),
      );

  Widget _buildBody(WebTk t, ParticipationData data) {
    final rows = gradeReach(data.reach);
    final students = rows.fold<int>(0, (s, r) => s + r.students);
    final reached = rows.fold<int>(0, (s, r) => s + r.reached);
    if (students == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text('No active students yet.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: t.muted)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 65%  312 of 480 active students
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${_percent(reached, students)}%',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 30, height: 1,
                  fontWeight: FontWeight.w800, color: t.text)),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '${formatCount(reached)} of ${formatCount(students)} active students',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: t.sub),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _bar(t, reached / students, _blue, height: 10),
        const SizedBox(height: 20),
        Text('By grade',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
              fontWeight: FontWeight.w600, color: t.sub)),
        const SizedBox(height: 4),
        for (final r in rows) _gradeRow(t, r),
      ],
    );
  }

  Widget _gradeRow(WebTk t, GradeReach r) {
    final share = r.students == 0 ? 0.0 : r.reached / r.students;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 116,
            child: Text(gradeLabel(r.grade), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                  fontWeight: FontWeight.w500, color: t.text)),
          ),
          const SizedBox(width: 8),
          Expanded(child: _bar(t, share, _blue)),
          const SizedBox(width: 12),
          SizedBox(
            width: 64,
            child: Text('${formatCount(r.reached)}/${formatCount(r.students)}',
              textAlign: TextAlign.right,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                  fontWeight: FontWeight.w600, color: t.sub)),
          ),
        ],
      ),
    );
  }
}

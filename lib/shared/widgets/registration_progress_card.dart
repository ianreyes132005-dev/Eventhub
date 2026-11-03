import 'dart:async';
import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../core/app_colors.dart' show kGold;
import '../../core/event_audience.dart';
import '../utils/event_labels.dart' show monthDayLabel;
import '../utils/registration_progress.dart';

/// Theme colours from the screen that hosts the card (WebTk on the web,
/// AppTk in the app).
class RegistrationProgressColors {
  final bool dark;
  final Color text;
  final Color sub;
  final Color muted;
  final Color border;
  const RegistrationProgressColors({
    required this.dark,
    required this.text,
    required this.sub,
    required this.muted,
    required this.border,
  });
}

/// The organizer's "Registration progress": pick an event (the next one by
/// default) to see how many of the students it's for have registered, when
/// registration closes, new sign-ups per day for the last two weeks, and
/// which grades are behind. "All events" shows the sign-ups across every
/// event. The same card on the web Dashboard and the app's Home; the screen
/// draws the card around it. Counting rules: registration_progress.dart.
class RegistrationProgressCard extends StatefulWidget {
  /// The organizer's events.
  final List<Map<String, dynamic>> events;

  /// Their registrations: event_id, status, registered_at — at least those
  /// of the events still running and the last [kSignupChartDays] days.
  final List<Map<String, dynamic>> registrations;

  /// Active students per grade and strand, and in all — null while unknown.
  final List<GradeCount>? gradeCounts;
  final int? allStudents;

  /// The grade and strand of each student registered for an event
  /// (RegistrationService.registrantGroups).
  final Future<List<StudentGroup>> Function(String eventId) loadGroups;

  final RegistrationProgressColors colors;

  /// For tests: the clock.
  final DateTime? now;

  const RegistrationProgressCard({
    super.key,
    required this.events,
    required this.registrations,
    required this.gradeCounts,
    required this.allStudents,
    required this.loadGroups,
    required this.colors,
    this.now,
  });

  static const allEvents = '_all';

  @override
  State<RegistrationProgressCard> createState() =>
      _RegistrationProgressCardState();
}

class _RegistrationProgressCardState extends State<RegistrationProgressCard> {
  static const _purple = Color(0xFF7C3AED);
  static const _green = Color(0xFF10B981);
  static const _amber = Color(0xFFF59E0B);

  /// Purple for text and icons: #7C3AED is 5.7:1 on white but only ~2:1 on
  /// the dark cards, so dark mode uses a lighter violet.
  Color get _accent => widget.colors.dark ? const Color(0xFFA78BFA) : _purple;

  String? _picked;
  final _groups = <String, List<StudentGroup>>{};
  // How many were registered when an event's groups were read — read again
  // once that changes.
  final _groupsAt = <String, int>{};
  final _loading = <String>{};
  final _failed = <String>{};

  DateTime get _now => widget.now ?? DateTime.now();

  List<Map<String, dynamic>> get _options =>
      registrationProgressEvents(widget.events, now: _now);

  /// The picked event's id, or [RegistrationProgressCard.allEvents]: the
  /// next event until the organizer picks another, and All events when
  /// there's nothing running.
  String get _selected {
    final options = _options;
    final picked = _picked;
    if (picked == RegistrationProgressCard.allEvents) return picked!;
    if (picked != null && options.any((e) => e['event_id'] == picked))
      return picked;
    return options.isEmpty
        ? RegistrationProgressCard.allEvents
        : options.first['event_id'] as String;
  }

  @override
  void initState() {
    super.initState();
    _ensureGroups();
  }

  @override
  void didUpdateWidget(RegistrationProgressCard old) {
    super.didUpdateWidget(old);
    _ensureGroups();
  }

  void _select(String id) {
    setState(() => _picked = id);
    _ensureGroups();
  }

  void _ensureGroups() {
    final id = _selected;
    if (id == RegistrationProgressCard.allEvents || _loading.contains(id))
      return;
    final count = registeredFor(widget.registrations, id);
    if (_groups.containsKey(id) && _groupsAt[id] == count) return;
    _loading.add(id);
    _failed.remove(id);
    unawaited(
      widget
          .loadGroups(id)
          .then((groups) {
            _groups[id] = groups;
            _groupsAt[id] = count;
          })
          .catchError((Object e) {
            debugPrint('Registration progress: grades unavailable: $e');
            _failed.add(id);
          })
          .whenComplete(() {
            _loading.remove(id);
            if (mounted) setState(() {});
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final selected = _selected;
    final event = selected == RegistrationProgressCard.allEvents
        ? null
        : _options.firstWhere((e) => e['event_id'] == selected);
    final daily = dailySignups(
      widget.registrations,
      eventId: event?['event_id'] as String?,
      now: _now,
    );
    final weeks = lastTwoWeeks(daily);

    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 420;
        final picker = _buildPicker(c, selected, narrow);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _purple.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.how_to_reg_rounded,
                    color: _accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Registration progress',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: c.text,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!narrow) ...[const SizedBox(width: 12), picker],
              ],
            ),
            if (narrow) ...[const SizedBox(height: 12), picker],
            const SizedBox(height: 18),
            if (event != null) ...[
              _buildGoal(c, event),
              const SizedBox(height: 16),
            ],
            _buildKpis(c, daily, weeks),
            const SizedBox(height: 16),
            Text(
              'New sign-ups · ${monthDayLabel(daily.first.day)} – ${monthDayLabel(daily.last.day)}',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: c.sub,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(height: 170, child: _buildChart(c, daily, weeks)),
            const SizedBox(height: 16),
            if (event != null)
              _buildByGrade(c, event)
            else
              _note(
                c,
                Icons.touch_app_outlined,
                'Pick an event to see how close it is to the students it’s for, '
                'and which grades are behind.',
              ),
          ],
        );
      },
    );
  }

  // ── Event picker ───────────────────────────────────────────────────────────

  Widget _buildPicker(
    RegistrationProgressColors c,
    String selected,
    bool narrow,
  ) {
    final options = _options;
    String titleOf(Map<String, dynamic> e) =>
        (e['title'] as String?)?.trim().isNotEmpty == true
        ? e['title'] as String
        : 'Untitled event';
    final current = selected == RegistrationProgressCard.allEvents
        ? 'All events'
        : titleOf(options.firstWhere((e) => e['event_id'] == selected));
    final label = Row(
      mainAxisSize: narrow ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Icon(Icons.event_rounded, size: 15, color: _accent),
        const SizedBox(width: 6),
        Flexible(
          fit: narrow ? FlexFit.tight : FlexFit.loose,
          child: Text(
            current,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: c.text,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: c.sub),
      ],
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: narrow ? double.infinity : 230),
      child: PopupMenuButton<String>(
        tooltip: 'Choose an event',
        initialValue: selected,
        onSelected: _select,
        position: PopupMenuPosition.under,
        itemBuilder: (_) => [
          for (final e in options)
            PopupMenuItem(
              value: e['event_id'] as String,
              child: Text(
                titleOf(e),
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
              ),
            ),
          if (options.isNotEmpty) const PopupMenuDivider(),
          const PopupMenuItem(
            value: RegistrationProgressCard.allEvents,
            child: Text(
              'All events',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13),
            ),
          ),
        ],
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: label,
        ),
      ),
    );
  }

  // ── Toward the goal ────────────────────────────────────────────────────────

  Widget _buildGoal(RegistrationProgressColors c, Map<String, dynamic> event) {
    final audience = EventAudience.of(event);
    final registered = registeredFor(
      widget.registrations,
      event['event_id'] as String,
    );
    final goal = audience.capacity(
      allStudents: widget.allStudents,
      counts: widget.gradeCounts,
    );
    final share = goal != null && goal > 0
        ? (registered / goal).clamp(0.0, 1.0)
        : null;
    final closes = registrationCloseLabel(event, now: _now);
    final closed = closes == 'Registration closed';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$registered',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: c.text,
                      ),
                    ),
                    TextSpan(
                      text: goal != null
                          ? ' of $goal ${audienceStudentsLabel(audience)}'
                          : ' registered · ${audienceStudentsLabel(audience)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: c.sub,
                      ),
                    ),
                  ],
                ),
                style: const TextStyle(fontFamily: 'Poppins'),
              ),
            ),
            if (share != null)
              Text(
                '${(share * 100).round()}%',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _accent,
                ),
              ),
          ],
        ),
        if (share != null) ...[
          const SizedBox(height: 8),
          _bar(c, share, _accent, height: 8),
        ],
        if (closes != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                closed ? Icons.lock_rounded : Icons.lock_clock_rounded,
                size: 14,
                color: c.sub,
              ),
              const SizedBox(width: 5),
              Text(
                closes,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: c.sub,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ── Last 7 days / today ────────────────────────────────────────────────────

  Widget _buildKpis(
    RegistrationProgressColors c,
    List<DailySignups> daily,
    ({int last7, int previous7}) weeks,
  ) {
    final up = weeks.last7 >= weeks.previous7;
    final changeColor = weeks.last7 == weeks.previous7
        ? c.sub
        : up
        ? (c.dark ? const Color(0xFF34D399) : const Color(0xFF047857))
        : (c.dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309));
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _kpi(
            c,
            label: 'Last 7 days',
            value: '${weeks.last7}',
            extra: weekChangeLabel(weeks),
            extraColor: changeColor,
            extraIcon: weeks.last7 == weeks.previous7
                ? null
                : up
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: _kpi(c, label: 'Today', value: '${daily.last.count}'),
        ),
      ],
    );
  }

  Widget _kpi(
    RegistrationProgressColors c, {
    required String label,
    required String value,
    String? extra,
    Color? extraColor,
    IconData? extraIcon,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 74),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _purple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _purple.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: c.sub,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 20,
              height: 1.2,
              fontWeight: FontWeight.w800,
              color: c.text,
            ),
          ),
          if (extra != null)
            Row(
              children: [
                if (extraIcon != null) ...[
                  Icon(extraIcon, size: 12, color: extraColor),
                  const SizedBox(width: 2),
                ],
                Flexible(
                  child: Text(
                    extra,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: extraColor,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ── Sign-ups per day ───────────────────────────────────────────────────────

  Widget _buildChart(
    RegistrationProgressColors c,
    List<DailySignups> daily,
    ({int last7, int previous7}) weeks,
  ) {
    final total = daily.fold<int>(0, (s, d) => s + d.count);
    if (total == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bar_chart_rounded,
              size: 30,
              color: _accent.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 8),
            Text(
              'No sign-ups in the last 14 days',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: c.text,
              ),
            ),
          ],
        ),
      );
    }
    final busiest = daily.reduce((a, b) => b.count > a.count ? b : a);
    final top = daily.map((d) => d.count).reduce(math.max);
    final maxY = math.max(top + 1, 4).toDouble();
    const weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Semantics(
      label:
          'New sign-ups per day: ${weeks.last7} in the last 7 days, '
          '${weeks.previous7} in the 7 days before. Busiest day '
          '${monthDayLabel(busiest.day)}, ${busiest.count}.',
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (_, box) {
            final barWidth = (box.maxWidth / daily.length * 0.55).clamp(
              6.0,
              22.0,
            );
            return BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                minY: 0,
                barGroups: [
                  for (var i = 0; i < daily.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: daily[i].count.toDouble(),
                          width: barWidth,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(5),
                          ),
                          gradient: i == daily.length - 1
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFFC49230),
                                    Color(0xFFEAB866),
                                  ],
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                )
                              : LinearGradient(
                                  colors: [
                                    _purple.withValues(alpha: 0.55),
                                    _purple.withValues(alpha: 0.9),
                                  ],
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                ),
                        ),
                      ],
                    ),
                ],
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= daily.length)
                          return const SizedBox.shrink();
                        final d = daily[i].day;
                        final today = i == daily.length - 1;
                        final weekend = d.weekday >= DateTime.saturday;
                        final color = today
                            ? kGold
                            : weekend
                            ? c.muted.withValues(alpha: 0.7)
                            : c.sub;
                        return SideTitleWidget(
                          meta: meta,
                          space: 4,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                weekdays[d.weekday - 1],
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 9,
                                  color: color,
                                ),
                              ),
                              Text(
                                '${d.day}',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 9.5,
                                  fontWeight: today
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: color,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: math.max(1.0, (maxY / 4).ceilToDouble()),
                      getTitlesWidget: (value, meta) {
                        if (value == meta.max) return const SizedBox.shrink();
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(
                            '${value.toInt()}',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 9,
                              color: c.muted,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: math.max(1.0, (maxY / 4).ceilToDouble()),
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: c.border,
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ),
                borderData: FlBorderData(show: false),
                // A number only when the bar is hovered or touched.
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF1C1814),
                    tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    getTooltipItem: (group, _, _, _) {
                      final d = daily[group.x];
                      return BarTooltipItem(
                        '${d.count} sign-up${d.count == 1 ? '' : 's'}',
                        const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                        children: [
                          TextSpan(
                            text: group.x == daily.length - 1
                                ? '\nToday'
                                : '\n${monthDayLabel(d.day)}',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w400,
                              fontSize: 10,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              duration: const Duration(milliseconds: 300),
            );
          },
        ),
      ),
    );
  }

  // ── By grade ───────────────────────────────────────────────────────────────

  Widget _buildByGrade(
    RegistrationProgressColors c,
    Map<String, dynamic> event,
  ) {
    final id = event['event_id'] as String;
    final heading = Text(
      'By grade',
      style: TextStyle(
        fontFamily: 'Poppins',
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: c.sub,
      ),
    );
    final groups = _groups[id];
    if (groups == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading,
          const SizedBox(height: 8),
          _failed.contains(id)
              ? _note(
                  c,
                  Icons.cloud_off_rounded,
                  'The grade breakdown couldn’t be loaded.',
                )
              : Text(
                  'Loading…',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11.5,
                    color: c.muted,
                  ),
                ),
        ],
      );
    }
    final rows = gradeProgress(
      audience: EventAudience.of(event),
      counts: widget.gradeCounts,
      registrants: groups,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading,
        const SizedBox(height: 8),
        if (rows.isEmpty)
          Text(
            'No students in this event’s group yet.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11.5,
              color: c.muted,
            ),
          )
        else
          for (final r in rows)
            _gradeRow(c, r),
      ],
    );
  }

  Widget _gradeRow(RegistrationProgressColors c, GradeProgress r) {
    final eligible = r.eligible;
    final share = eligible != null && eligible > 0
        ? (r.registered / eligible).clamp(0.0, 1.0)
        : null;
    final color = share == null
        ? c.muted
        : share >= 0.75
        ? _green
        : share >= 0.5
        ? _accent
        : _amber;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 118,
            child: Text(
              r.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: c.text,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: share == null
                ? const SizedBox(height: 7)
                : _bar(c, share, color, height: 7),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 58,
            child: Text(
              eligible == null
                  ? '${r.registered}'
                  : '${r.registered}/$eligible',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: c.sub,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Pieces ─────────────────────────────────────────────────────────────────

  Widget _bar(
    RegistrationProgressColors c,
    double share,
    Color color, {
    required double height,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: share),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOut,
        builder: (_, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: height,
          backgroundColor: color.withValues(alpha: c.dark ? 0.18 : 0.12),
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    );
  }

  Widget _note(
    RegistrationProgressColors c,
    IconData icon,
    String text, {
    Color? color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, color: color ?? c.sub),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11.5,
              height: 1.45,
              fontWeight: color == null ? FontWeight.w400 : FontWeight.w600,
              color: color ?? c.sub,
            ),
          ),
        ),
      ],
    );
  }
}

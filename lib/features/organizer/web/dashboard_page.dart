import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/app_colors.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/account_session_guard.dart';
import '../../../shared/widgets/event_phase_pill.dart';
import 'web_shared.dart';

class WebDashboardPage extends StatefulWidget {
  final String? orgId;
  final String? name;
  /// Switches the shell to another tab (the stat cards link to Events and
  /// Registrations).
  final void Function(OrganizerPage page)? onNavigate;
  const WebDashboardPage({super.key, this.orgId, this.name, this.onNavigate});

  @override
  State<WebDashboardPage> createState() => _WebDashboardPageState();
}

class _WebDashboardPageState extends State<WebDashboardPage>
    with TickerProviderStateMixin {
  bool      _loading      = true;
  bool      _error        = false;
  Timer?           _autoRefreshTimer;
  RealtimeChannel? _rtChannel;

  // Stats
  int _activeEvents  = 0;
  int _totalRegs     = 0;
  // Attendance rate uses only past/completed events to avoid future-event dilution.
  int _pastEventRegs = 0;
  int _pastCheckedIn = 0;

  // Data
  List<Map<String, dynamic>> _upcomingEvents  = [];
  List<Map<String, dynamic>> _recentRegs      = [];
  List<int>                  _weeklyRegs      = List.filled(7, 0);
  List<String>               _weekDayLabels   = [];
  List<Map<String, dynamic>> _eventAttendance = [];

  // ── Animations ────────────────────────────────────────────────────────────
  late final AnimationController _staggerCtrl;

  @override
  void initState() {
    super.initState();
    _staggerCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _load();
    _subscribeRealtime();
    // 30 s fallback keeps stats fresh even if a realtime event is missed.
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) { if (mounted && !_loading) _load(silent: true); },
    );
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    if (_rtChannel != null) SupabaseService.client.removeChannel(_rtChannel!);
    _staggerCtrl.dispose();
    super.dispose();
  }

  void _subscribeRealtime() {
    _rtChannel = SupabaseService.client.channel('org-dashboard-${widget.orgId}');
    for (final table in ['events', 'registrations']) {
      _rtChannel!.on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(event: '*', schema: 'public', table: table),
        (_, [a]) { if (mounted && !_loading) _load(silent: true); },
      );
    }
    _rtChannel!.subscribe();
  }

  @override
  void didUpdateWidget(WebDashboardPage old) {
    super.didUpdateWidget(old);
    if (old.orgId != widget.orgId) _load();
  }

  // [silent] = true â†’ update data in-place (no full spinner, no stagger replay).
  Future<void> _load({bool silent = false}) async {
    if (widget.orgId == null) return;
    if (!mounted) return;
    if (!silent) setState(() { _loading = true; _error = false; });
    try {
      final client = SupabaseService.client;
      final now    = DateTime.now();
      final user = client.auth.currentUser;
      if (user == null) throw StateError('Your session has expired. Please sign in again.');
      final organizer = await client
          .from('organizers')
          .select('is_active')
          .eq('user_id', user.id)
          .maybeSingle();
      if (organizer == null) {
        throw StateError('Could not find your organizer profile.');
      }
      if (!await AccountSessionGuard.ensureActive(
        context,
        isActive: organizer['is_active'] == true,
      )) return;

      final eventRows = await client
          .from('events')
          .select('event_id, title, event_date, end_date, start_time, end_time, location, '
                  'event_status, approval_status, archived_at, organizer_id')
          .eq('organizer_id', widget.orgId!);

      final events   = List<Map<String, dynamic>>.from(eventRows as List);
      final eventIds = events.map((e) => e['event_id'] as String).toList();

      // Registrations filtered to this organizer's events
      List<Map<String, dynamic>> orgRegs = [];
      if (eventIds.isNotEmpty) {
        final regRows = await client
            .from('registrations')
            .select('id, event_id, student_name, event_title, status, registered_at')
            .in_('event_id', eventIds)
            .order('registered_at', ascending: false);
        orgRegs = List<Map<String, dynamic>>.from(regRows as List);
      }

      // ── Stats ─────────────────────────────────────────────────────────
      const activeStatuses = {'upcoming', 'ongoing'};
      _activeEvents = activeApprovedEventCount(events, now: now);
      _totalRegs    = orgRegs.length;

      // ── Upcoming events ───────────────────────────────────────────────
      final upcoming = events
          .where((e) =>
              eventIsApproved(e) &&
              !eventIsArchived(e) &&
              activeStatuses.contains(eventStatusValue(e, now: now)))
          .toList()
        ..sort((a, b) {
          final da = DateTime.tryParse(a['event_date'] ?? '') ?? DateTime(9999);
          final db = DateTime.tryParse(b['event_date'] ?? '') ?? DateTime(9999);
          return da.compareTo(db);
        });
      _upcomingEvents = upcoming.take(5).toList();
      _recentRegs     = orgRegs.take(6).toList();

      // ── Weekly registrations: Mon=0 … Sun=6 for the current ISO week ──
      final monday = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));
      final weekly = List.filled(7, 0);
      for (final reg in orgRegs) {
        final raw = reg['registered_at'] as String?;
        if (raw == null) continue;
        try {
          final d            = DateTime.parse(raw).toLocal();
          final dayDate      = DateTime(d.year, d.month, d.day);
          final daysSinceMon = dayDate.difference(monday).inDays;
          if (daysSinceMon >= 0 && daysSinceMon < 7) weekly[daysSinceMon]++;
        } catch (_) {}
      }
      _weeklyRegs    = weekly;
      _weekDayLabels = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

      // ── Past events (completed / cancelled / any non-active status) ───
      // Used for both the event-attendance breakdown and the attendance-rate
      // stat card.  Upcoming & ongoing events are excluded because no student
      // has had the chance to be checked in yet; including them would deflate
      // the rate misleadingly (e.g. an event with 100 registrations and 0
      // check-ins drags the school-wide rate to near zero).
      final today      = DateUtils.dateOnly(now);
      final pastEvents = List<Map<String, dynamic>>.from(events)
        ..retainWhere((e) {
          if (activeStatuses.contains(eventStatusValue(e))) return false;
          final d = DateTime.tryParse(e['event_date'] as String? ?? '');
          return d != null && !DateUtils.dateOnly(d).isAfter(today);
        })
        ..sort((a, b) {
          final da = DateTime.tryParse(a['event_date'] as String? ?? '') ?? DateTime(0);
          final db = DateTime.tryParse(b['event_date'] as String? ?? '') ?? DateTime(0);
          return da.compareTo(db);
        });

      final last5 = pastEvents.length > 5
          ? pastEvents.sublist(pastEvents.length - 5)
          : pastEvents;

      _eventAttendance = last5.map((e) {
        final eid       = e['event_id'] as String;
        // Declined registrations don't count as registered.
        final total     = orgRegs.where((r) =>
            r['event_id'] == eid && countsAsRegistered(r)).length;
        final checkedIn = orgRegs.where((r) =>
            r['event_id'] == eid && r['status'] == 'checked_in').length;
        String label = '—';
        final dStr = e['event_date'] as String?;
        if (dStr != null) {
          try {
            final dt = DateTime.parse(dStr);
            const m  = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                         'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
            label = '${m[dt.month - 1]}\n${dt.day}';
          } catch (_) {}
        }
        return <String, dynamic>{
          'label':           label,
          'title':           (e['title'] as String?) ?? '—',
          'checkedIn':       checkedIn,
          'total':           total,
        };
      }).toList();

      // ── Attendance rate — past events only ────────────────────────────
      // Use ALL past events (not just last 5) for a school-wide rate.
      // Upcoming & ongoing events are excluded because no student has had
      // the chance to be checked in yet; including them deflates the rate.
      final pastEventIdSet =
          pastEvents.map((e) => e['event_id'] as String).toSet();
      _pastEventRegs = orgRegs
          .where((r) =>
              pastEventIdSet.contains(r['event_id']) && countsAsRegistered(r))
          .length;
      _pastCheckedIn = orgRegs
          .where((r) =>
              pastEventIdSet.contains(r['event_id']) &&
              r['status'] == 'checked_in')
          .length;

      if (mounted) {
        setState(() => _loading = false);
        if (!silent) _staggerCtrl.forward(from: 0);
      }
    } catch (_) {
      if (mounted) {
        // A failed silent background refresh shouldn't blow away an already
        // -rendered dashboard — only the initial load surfaces the error state.
        setState(() { _loading = false; if (!silent) _error = true; });
        if (!silent) _staggerCtrl.forward(from: 0);
      }
    }
  }

  // Wraps [child] in a fade + upward-slide driven by [_staggerCtrl] over
  // the sub-interval [start, end] (both in [0, 1]).
  Widget _stagger(Widget child, {required double start, required double end}) {
    return AnimatedBuilder(
      animation: _staggerCtrl,
      builder: (_, c) {
        final raw = ((_staggerCtrl.value - start) / (end - start))
            .clamp(0.0, 1.0);
        final t  = Curves.easeOut.transform(raw);
        final ts = Curves.easeOutCubic.transform(raw);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 18.0 * (1 - ts)),
            child: c,
          ),
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kGold));
    }
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    if (_error) {
      return _buildErrorState(t);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(kWebPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stagger(_buildPageHeader(t),     start: 0.00, end: 0.40),
          const SizedBox(height: 24),
          _buildStatRow(t),   // individual card stagger handled inside
          const SizedBox(height: 28),
          _stagger(_buildAnalyticsLabel(t), start: 0.36, end: 0.76),
          const SizedBox(height: 16),
          _stagger(_buildContentGrid(t),    start: 0.46, end: 0.90),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildErrorState(WebTk t) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 68, height: 68,
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2), shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFFCA5A5), width: 1.5),
        ),
        child: const Icon(Icons.cloud_off_rounded, color: Color(0xFFEF4444), size: 32),
      ),
      const SizedBox(height: 18),
      Text('Could not load dashboard',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 16,
            fontWeight: FontWeight.w800, color: t.text)),
      const SizedBox(height: 8),
      Text('Check your connection and try again.',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.sub)),
      const SizedBox(height: 24),
      WebBtn(label: 'Retry', icon: Icons.refresh_rounded, onTap: () => _load()),
    ]),
  );

  // ── Page header ───────────────────────────────────────────────────────────
  Widget _buildPageHeader(WebTk t) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Dashboard',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: t.text,
            height: 1.1,
          ),
        ),
      ],
    );
  }

  // ── Stat cards ───────────────────────────────────────────────────────────
  Widget _buildStatRow(WebTk t) {
    final todayCount = _weeklyRegs[DateTime.now().weekday - 1];

    // Attendance rate is computed from past/completed events only.
    // Upcoming events have zero check-ins by definition and would
    // deflate the rate if included.
    final hasPastData = _pastEventRegs > 0;
    final rate        = hasPastData
        ? (_pastCheckedIn / _pastEventRegs * 100).round()
        : 0;
    final rateColor   = !hasPastData
        ? t.muted
        : rate >= 70
            ? const Color(0xFF10B981)
            : rate >= 40 ? kGold : const Color(0xFFEF4444);

    final nav = widget.onNavigate;
    final cards = [
      _DashStatCard(
        value:       '$_activeEvents',
        label:       'Active Events',
        icon:        Icons.event_available_rounded,
        accentColor: const Color(0xFF3B82F6),
        hint:        'Opens the Events tab',
        onTap:       nav == null ? null : () => nav(OrganizerPage.events),
      ),
      _DashStatCard(
        value:       '$_totalRegs',
        label:       'Total Registrations',
        icon:        Icons.how_to_reg_rounded,
        accentColor: const Color(0xFF8B5CF6),
        hint:        'Opens the Registrations tab',
        onTap:       nav == null ? null : () => nav(OrganizerPage.registrations),
      ),
      _DashStatCard(
        value:       hasPastData ? '$rate%' : '—',
        label:       'Attendance Rate',
        icon:        Icons.show_chart_rounded,
        accentColor: rateColor,
      ),
      _DashStatCard(
        value:       '$todayCount',
        label:       "Today's Sign-ups",
        icon:        Icons.person_add_rounded,
        accentColor: const Color(0xFFF59E0B),
      ),
    ];

    return LayoutBuilder(builder: (_, c) {
      final cols = c.maxWidth > 800 ? 4 : c.maxWidth > 500 ? 2 : 1;
      final rows = (cards.length / cols).ceil();
      return Column(
        children: List.generate(rows, (row) => Padding(
          padding: EdgeInsets.only(bottom: row < rows - 1 ? 16 : 0),
          child: Row(
            children: List.generate(cols, (col) {
              final idx = row * cols + col;
              if (idx >= cards.length) return const Expanded(child: SizedBox.shrink());
              final s = 0.09 + idx * 0.07;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: col > 0 ? 16 : 0),
                  child: _stagger(cards[idx],
                      start: s, end: (s + 0.38).clamp(0.0, 1.0)),
                ),
              );
            }),
          ),
        )),
      );
    });
  }

  // ── Analytics section label ───────────────────────────────────────────────
  Widget _buildAnalyticsLabel(WebTk t) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 3, height: 20,
          decoration: BoxDecoration(
            color: kGold,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Analytics',
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 16,
            fontWeight: FontWeight.w800, color: t.text, height: 1.1,
          ),
        ),
      ],
    );
  }

  // ── Content grid ──────────────────────────────────────────────────────────
  Widget _buildContentGrid(WebTk t) => LayoutBuilder(builder: (_, c) {
    final wide = c.maxWidth > 760;
    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              children: [
                _buildWeeklyRegsCard(t),
                const SizedBox(height: 16),
                _buildRecentRegs(t),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 4,
            child: Column(
              children: [
                _buildEventAttendanceCard(t),
                const SizedBox(height: 16),
                _buildUpcomingCard(),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        _buildWeeklyRegsCard(t),
        const SizedBox(height: 16),
        _buildEventAttendanceCard(t),
        const SizedBox(height: 16),
        _buildRecentRegs(t),
        const SizedBox(height: 16),
        _buildUpcomingCard(),
      ],
    );
  });

  Widget _buildUpcomingCard() => WebCard(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        WebSectionHeader(title: 'Upcoming Events', subtitle: '${_upcomingEvents.length} scheduled'),
        const SizedBox(height: 16),
        if (_upcomingEvents.isEmpty)
          const WebEmptyState(
            icon: Icons.event_busy_rounded,
            title: 'No upcoming events',
            subtitle: 'Create your first event to get started.',
          )
        else
          ..._upcomingEvents.map((e) => _EventListTile(event: e)),
      ],
    ),
  );

  Widget _buildRecentRegs(WebTk t) => WebCard(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        WebSectionHeader(title: 'Recent Registrations', subtitle: 'Latest sign-ups across your events'),
        const SizedBox(height: 16),
        if (_recentRegs.isEmpty)
          const WebEmptyState(
            icon: Icons.person_off_rounded,
            title: 'No registrations yet',
            subtitle: 'Registrations will appear here once students sign up.',
          )
        else
          ..._recentRegs.asMap().entries.map((entry) {
            final r = entry.value;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (entry.key > 0) Divider(color: t.border, height: 1),
                _RegRow(reg: r),
              ],
            );
          }),
      ],
    ),
  );

  // ── Weekly Registrations card (white + purple) ────────────────────────────

  Widget _buildWeeklyRegsCard(WebTk t) {
    const purple = Color(0xFF7C3AED);
    const indigo = Color(0xFF4F46E5);
    const green  = Color(0xFF059669);

    final todayCount = _weeklyRegs[DateTime.now().weekday - 1];
    final totalWeek  = _weeklyRegs.fold(0, (s, v) => s + v);

    int peakVal = 0;
    int peakIdx = -1;
    for (int i = 0; i < _weeklyRegs.length; i++) {
      if (_weeklyRegs[i] > peakVal) { peakVal = _weeklyRegs[i]; peakIdx = i; }
    }
    final peakLabel = peakIdx >= 0 && peakVal > 0 && peakIdx < _weekDayLabels.length
        ? _weekDayLabels[peakIdx]
        : null;

    return WebCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: purple.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.how_to_reg_rounded, color: purple, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Weekly Registrations',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700, color: t.text)),
                  Text('Sign-up activity · this week',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.sub)),
                ],
              ),
            ),
          ]),

          const SizedBox(height: 18),

          Row(children: [
            _analyticsKpiChip(t: t, value: '$totalWeek', label: 'This Week', icon: Icons.how_to_reg_rounded, color: purple),
            const SizedBox(width: 10),
            _analyticsKpiChip(
              t: t,
              value: peakLabel != null ? '$peakVal' : '—',
              label: peakLabel != null ? 'Peak · $peakLabel' : 'Peak Day',
              icon: Icons.trending_up_rounded, color: indigo,
            ),
            const SizedBox(width: 10),
            _analyticsKpiChip(t: t, value: '$todayCount', label: 'Today', icon: Icons.today_rounded, color: green),
          ]),

          if (totalWeek > 0) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Today vs. this week',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w500, color: t.sub)),
                Text('$todayCount of $totalWeek',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: purple)),
              ],
            ),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: (todayCount / totalWeek).clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOut,
                builder: (_, v, _) => LinearProgressIndicator(
                  value: v, minHeight: 6,
                  backgroundColor: purple.withValues(alpha: 0.10),
                  valueColor: const AlwaysStoppedAnimation<Color>(purple),
                ),
              ),
            ),
          ],

          const SizedBox(height: 18),
          SizedBox(height: 200, child: _buildWeeklyBarChart(t)),

          if (_weeklyRegs.any((v) => v > 0)) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _analyticsLegendItem(t: t, color: purple, label: 'Registrations'),
                const SizedBox(width: 20),
                _analyticsLegendItem(t: t, color: kGold, label: 'Today'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWeeklyBarChart(WebTk t) {
    const purple = Color(0xFF7C3AED);

    if (_weeklyRegs.every((v) => v == 0)) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 62, height: 62,
            decoration: BoxDecoration(
              color: purple.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(18)),
            child: const Icon(Icons.bar_chart_rounded, size: 30, color: purple),
          ),
          const SizedBox(height: 14),
          Text('No registrations this week',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: t.text)),
          const SizedBox(height: 4),
          Text('Appears once students sign up',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.sub)),
        ]),
      );
    }

    final rawMax      = _weeklyRegs.reduce(max);
    final barMaxY     = max(rawMax.toDouble() + 1.5, 5.0);
    final todayBarIdx = DateTime.now().weekday - 1;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: barMaxY, minY: 0,
        barGroups: List.generate(7, (i) {
          final isToday = i == todayBarIdx;
          final value   = _weeklyRegs[i].toDouble();
          return BarChartGroupData(
            x: i,
            showingTooltipIndicators: value > 0 ? [0] : [],
            barRods: [
              BarChartRodData(
                toY: value > 0 ? value : 0.18,
                gradient: isToday
                    ? const LinearGradient(
                        colors: [Color(0xFFC49230), Color(0xFFEAB866)],
                        begin: Alignment.bottomCenter, end: Alignment.topCenter)
                    : value > 0
                        ? LinearGradient(
                            colors: [purple.withValues(alpha: 0.50), purple.withValues(alpha: 0.85)],
                            begin: Alignment.bottomCenter, end: Alignment.topCenter)
                        : LinearGradient(
                            colors: [Colors.grey.withValues(alpha: 0.10), Colors.grey.withValues(alpha: 0.18)],
                            begin: Alignment.bottomCenter, end: Alignment.topCenter),
                width: 28,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              ),
            ],
          );
        }),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true, reservedSize: 36,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= _weekDayLabels.length) return const SizedBox();
                final isToday = i == todayBarIdx;
                return SideTitleWidget(
                  meta: meta,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 5, height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isToday ? kGold : Colors.transparent),
                    ),
                    const SizedBox(height: 3),
                    Text(_weekDayLabels[i], style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 10,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                      color: isToday ? kGold : t.sub,
                    )),
                  ]),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true, reservedSize: 32,
              interval: max(1.0, (barMaxY / 4).ceilToDouble()),
              getTitlesWidget: (value, meta) {
                if (value == meta.max) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  child: Text(value.toInt().toString(),
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 9, color: t.muted)),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true, drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: Colors.grey.withValues(alpha: 0.09), strokeWidth: 1, dashArray: [4, 4]),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF1C1814),
            tooltipBorder:   const BorderSide(color: Color(0xFF2C2419)),
            tooltipPadding:  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            getTooltipItem: (group, _, rod, _) {
              final v = _weeklyRegs[group.x];
              if (v <= 0) return null;
              final isToday = group.x == todayBarIdx;
              return BarTooltipItem(
                '$v reg${v == 1 ? '' : 's'}',
                const TextStyle(fontFamily: 'Poppins', color: Colors.white,
                  fontWeight: FontWeight.w700, fontSize: 12),
                children: [
                  TextSpan(
                    text: isToday ? '\nToday' : '\n${_weekDayLabels[group.x]}',
                    style: const TextStyle(fontFamily: 'Poppins',
                      fontWeight: FontWeight.w400, fontSize: 10, color: Colors.white60),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );
  }

  // ── Event Attendance card (white + blue) ──────────────────────────────────

  Widget _buildEventAttendanceCard(WebTk t) {
    const blue = Color(0xFF2563EB);

    final totalCheckedIn       = _eventAttendance.fold<int>(0, (s, e) => s + (e['checkedIn']       as int));
    final totalRegistered      = _eventAttendance.fold<int>(0, (s, e) => s + (e['total']           as int));
    // Checked in out of registered. Capacity is now the whole student body,
    // so measuring against it would make a full event look poorly attended.
    final hasRateData = totalRegistered > 0;
    final rate = hasRateData ? (totalCheckedIn / totalRegistered * 100).round() : 0;
    final rateColor = !hasRateData
        ? t.muted
        : rate >= 70
        ? const Color(0xFF16A34A)
        : rate >= 40
            ? kGold
            : const Color(0xFFDC2626);

    return WebCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: blue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.people_alt_rounded, color: blue, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Event Attendance',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700, color: t.text)),
                  Text('Check-in data · last 5 past events',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.sub)),
                ],
              ),
            ),
          ]),

          const SizedBox(height: 18),

          Row(children: [
            _analyticsKpiChip(t: t, value: '$totalCheckedIn', label: 'Checked In', icon: Icons.check_circle_rounded, color: blue),
            const SizedBox(width: 10),
            _analyticsKpiChip(t: t, value: hasRateData ? '$rate%' : '—', label: 'Avg Rate', icon: Icons.trending_up_rounded, color: rateColor),
          ]),

          if (_eventAttendance.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Overall attendance',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w500, color: t.sub)),
                Text(hasRateData ? '$rate%' : '—',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: rateColor)),
              ],
            ),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: totalRegistered > 0
                    ? totalCheckedIn / totalRegistered : 0.0),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOut,
                builder: (_, v, _) => LinearProgressIndicator(
                  value: v, minHeight: 6,
                  backgroundColor: t.divider,
                  valueColor: AlwaysStoppedAnimation<Color>(rateColor),
                ),
              ),
            ),
          ],

          const SizedBox(height: 18),
          _buildAttendanceBreakdown(t),
        ],
      ),
    );
  }

  Widget _buildAttendanceBreakdown(WebTk t) {
    const green = Color(0xFF16A34A);
    const red   = Color(0xFFDC2626);

    if (_eventAttendance.isEmpty) {
      return Column(
        children: [
          const SizedBox(height: 16),
          Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 62, height: 62,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(18)),
                child: const Icon(Icons.people_alt_rounded, size: 30, color: Color(0xFF2563EB)),
              ),
              const SizedBox(height: 14),
              Text('No attendance data yet',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  fontWeight: FontWeight.w600, color: t.text)),
              const SizedBox(height: 4),
              Text('Appears after your first check-in',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.sub)),
            ]),
          ),
          const SizedBox(height: 16),
        ],
      );
    }

    return Column(
      children: _eventAttendance.asMap().entries.map((entry) {
        final idx             = entry.key;
        final e               = entry.value;
        final total           = e['total']           as int;
        final checkedIn       = e['checkedIn']       as int;
        final title           = e['title']           as String;
        final dateLabel       = (e['label'] as String).replaceAll('\n', ' ');
        final hasRateData     = total > 0;
        final rate            = hasRateData ? (checkedIn / total * 100).round() : 0;
        final rateColor       = !hasRateData
            ? t.muted
            : rate >= 70 ? green : rate >= 40 ? kGold : red;
        final fraction        = total > 0 ? (checkedIn / total).clamp(0.0, 1.0) : 0.0;

        return Padding(
          padding: EdgeInsets.only(
            bottom: idx < _eventAttendance.length - 1 ? 14 : 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: rateColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                          style: TextStyle(fontFamily: 'Poppins',
                            fontSize: 12, fontWeight: FontWeight.w600, color: t.text),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(dateLabel,
                          style: TextStyle(fontFamily: 'Poppins',
                            fontSize: 10, color: t.muted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: rateColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: rateColor.withValues(alpha: 0.25)),
                        ),
                        child: Text(hasRateData ? '$rate%' : '—',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                            fontWeight: FontWeight.w700, color: rateColor)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        total > 0 ? '$checkedIn / $total' : 'No registrations',
                        style: TextStyle(fontFamily: 'Poppins',
                          fontSize: 10, fontWeight: FontWeight.w500, color: t.muted)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: fraction),
                  duration: Duration(milliseconds: 500 + idx * 80),
                  curve: Curves.easeOut,
                  builder: (_, v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: 7,
                    backgroundColor: rateColor.withValues(alpha: 0.10),
                    valueColor: AlwaysStoppedAnimation<Color>(rateColor),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Shared analytics helpers ──────────────────────────────────────────────

  Widget _analyticsKpiChip({
    required WebTk     t,
    required String   value,
    required String   label,
    required IconData icon,
    required Color    color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 13, 12, 13),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 8),
            Text(value,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 22,
                fontWeight: FontWeight.w800, color: color, height: 1.0)),
            const SizedBox(height: 4),
            Text(label,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: t.muted),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _analyticsLegendItem({required WebTk t, required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12, height: 12,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: t.muted)),
      ],
    );
  }
}

// ── Stat card with hover lift + animated progress ────────────────────────────

class _DashStatCard extends StatefulWidget {
  final String   value;
  final String   label;
  final IconData icon;
  final Color    accentColor;
  /// Makes the card a link: pointer, hover lift, arrow, keyboard focus.
  final VoidCallback? onTap;
  /// Where the link goes, for screen readers (e.g. 'Opens the Events tab').
  final String?  hint;

  const _DashStatCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.accentColor,
    this.onTap,
    this.hint,
  });

  @override
  State<_DashStatCard> createState() => _DashStatCardState();
}

class _DashStatCardState extends State<_DashStatCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final c    = widget.accentColor;
    final t    = WebTk(Theme.of(context).brightness == Brightness.dark);
    final link = widget.onTap != null;
    // Only cards that go somewhere react — a hand cursor and a lift on a
    // static card promise a click that does nothing.
    final lit  = link && (_hovered || _focused);

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve:    Curves.easeOut,
      transform: Matrix4.translationValues(0, lit ? -4 : 0, 0),
      transformAlignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color:      lit ? c.withValues(alpha: 0.14) : t.shadow,
            blurRadius: lit ? 24 : 10,
            offset:     Offset(0, lit ? 10 : 2),
          ),
        ],
      ),
      // Keyboard focus ring.
      foregroundDecoration: _focused
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c, width: 2),
            )
          : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: c),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
                  decoration: BoxDecoration(
                    color: t.card,
                    border: Border(
                      top:    BorderSide(color: lit ? c.withValues(alpha: 0.30) : t.border, width: 1.5),
                      right:  BorderSide(color: lit ? c.withValues(alpha: 0.30) : t.border, width: 1.5),
                      bottom: BorderSide(color: lit ? c.withValues(alpha: 0.30) : t.border, width: 1.5),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment:  MainAxisAlignment.center,
                          mainAxisSize:       MainAxisSize.min,
                          children: [
                            Text(
                              widget.value,
                              style: TextStyle(
                                fontFamily:    'Poppins',
                                fontSize:      28,
                                fontWeight:    FontWeight.w800,
                                color:         lit ? c : t.text,
                                height:        1.0,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    widget.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize:   12.5,
                                      fontWeight: FontWeight.w500,
                                      color:      lit ? c : t.sub,
                                    ),
                                  ),
                                ),
                                // Arrow slides in on hover / focus: "this opens a page".
                                if (link) ...[
                                  const SizedBox(width: 4),
                                  AnimatedSlide(
                                    duration: const Duration(milliseconds: 200),
                                    curve:    Curves.easeOut,
                                    offset:   lit ? Offset.zero : const Offset(-0.5, 0),
                                    child: AnimatedOpacity(
                                      duration: const Duration(milliseconds: 200),
                                      opacity:  lit ? 1 : 0,
                                      child: Icon(Icons.arrow_forward_rounded, size: 14, color: c),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Container(
                        width:  52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              c.withValues(alpha: 0.18),
                              c.withValues(alpha: 0.07),
                            ],
                            begin: Alignment.topLeft,
                            end:   Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: c.withValues(alpha: 0.20)),
                        ),
                        child: Icon(widget.icon, color: c, size: 24),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!link) return card;
    // Click, or Tab to it and press Enter / Space. Hover comes from a
    // MouseRegion (like the other web widgets) — the detector's own hover
    // highlight switches off after any touch input.
    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onTap!();
          return null;
        }),
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit:  (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Semantics(
            button: true,
            label: '${widget.label}: ${widget.value}',
            hint: widget.hint,
            onTap: widget.onTap,
            excludeSemantics: true,
            child: card,
          ),
        ),
      ),
    );
  }
}

// Returns the status to display for an event, overriding the database value
// with 'ended' when the event's end time (or the event day itself) has passed.
// This handles the case where the backend hasn't yet updated the status.
String _resolveDisplayStatus(Map<String, dynamic> event) {
  return eventStatusValue(event);
}

// ── Upcoming event row ────────────────────────────────────────────────────────
class _EventListTile extends StatelessWidget {
  final Map<String, dynamic> event;
  const _EventListTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final resolved = _resolveDisplayStatus(event);
    final color    = webEventStatusColor(resolved);
    final label    = webEventStatusLabel(resolved);
    final isLive   = resolved == 'ongoing';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 4, height: 48,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event['title'] as String? ?? '—',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                    fontWeight: FontWeight.w600, color: t.text),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(children: [
                  Icon(Icons.calendar_today_rounded, size: 11, color: t.muted),
                  const SizedBox(width: 4),
                  Text(webFmtDate(event['event_date'] as String?),
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.sub)),
                  const SizedBox(width: 8),
                  Icon(Icons.location_on_rounded, size: 11, color: t.muted),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(event['location'] as String? ?? '—',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.sub),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ],
            ),
          ),
          if (isLive) ...[
            const WebLiveDot(size: 8),
            const SizedBox(width: 6),
          ],
          WebStatusBadge(label: label, color: color),
        ],
      ),
    );
  }
}

// ── Recent registration row ───────────────────────────────────────────────────
class _RegRow extends StatelessWidget {
  final Map<String, dynamic> reg;
  const _RegRow({required this.reg});

  @override
  Widget build(BuildContext context) {
    final t           = WebTk(Theme.of(context).brightness == Brightness.dark);
    final status      = reg['status'] as String?;
    final statusColor = webStatusColor(status);
    final name        = reg['student_name'] as String? ?? '—';
    final initials    = name.split(' ').where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase()).take(2).join();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.10),
              shape: BoxShape.circle,
              border: Border.all(color: statusColor.withValues(alpha: 0.25)),
            ),
            child: Center(
              child: Text(initials, style: TextStyle(
                fontFamily: 'Poppins', fontSize: 12,
                fontWeight: FontWeight.w700, color: statusColor)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                    fontWeight: FontWeight.w600, color: t.text),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(reg['event_title'] as String? ?? '—',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.sub),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              WebStatusBadge(label: webStatusLabel(status), color: statusColor),
              const SizedBox(height: 3),
              Text(webTimeAgo(reg['registered_at'] as String?),
                style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: t.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/app_colors.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/account_session_guard.dart';
import '../../../core/event_audience.dart' show GradeCount;
import '../../../core/services/registration_service.dart';
import '../../../core/services/student_count_service.dart';
import '../../../shared/widgets/registration_progress_card.dart';
import '../../../shared/widgets/event_phase_pill.dart';
import '../mobile/dashboard/dashboard_metrics.dart' show nextApprovedEvent;
import 'web_shared.dart';

/// Selfies waiting for the organizer's review while their event's check-in
/// is open — the ones that can still be approved, the same count as the
/// sidebar badge. A photo still waiting when check-in closes can't be
/// approved, and the student stays absent.
({int waiting, bool checkInOpen}) photosToReview(
  Iterable<Map<String, dynamic>> events,
  Iterable<Map<String, dynamic>> registrations, {
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final open = {
    for (final e in events)
      if (checkInIsOpen(e, now: at)) e['event_id'],
  };
  final waiting = registrations
      .where(
        (r) => r['status'] == 'photo_submitted' && open.contains(r['event_id']),
      )
      .length;
  return (waiting: waiting, checkInOpen: open.isNotEmpty);
}

class WebDashboardPage extends StatefulWidget {
  final String? orgId;
  final String? name;

  /// Switches the shell to another tab (the stat cards link to Events and
  /// Registrations).
  final void Function(OrganizerPage page)? onNavigate;

  /// Opens one event's details on the Events tab (the Next event card).
  final void Function(String eventId)? onOpenEvent;
  const WebDashboardPage({
    super.key,
    this.orgId,
    this.name,
    this.onNavigate,
    this.onOpenEvent,
  });

  @override
  State<WebDashboardPage> createState() => _WebDashboardPageState();
}

class _WebDashboardPageState extends State<WebDashboardPage>
    with TickerProviderStateMixin {
  bool _loading = true;
  bool _error = false;
  Timer? _autoRefreshTimer;
  RealtimeChannel? _rtChannel;
  // A burst of live changes (a class registering at once) reloads once.
  Timer? _rtDebounce;

  // Stats
  int _activeEvents = 0;
  int _totalRegs = 0;
  // Photos to review card (photosToReview).
  int _photosToReview = 0;
  bool _checkInOpenNow = false;
  // Next event card: the next approved event that's on now or still ahead,
  // and how many students registered for it.
  Map<String, dynamic>? _nextEvent;
  int _nextRegistered = 0;

  // Data
  List<Map<String, dynamic>> _upcomingEvents = [];
  List<Map<String, dynamic>> _recentRegs = [];
  // Registration progress card: the organizer's events and registrations,
  // and the active students per grade and strand (each event's goal).
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _registrations = [];
  List<GradeCount>? _gradeCounts;
  int? _allStudents;

  // ── Animations ────────────────────────────────────────────────────────────
  late final AnimationController _staggerCtrl;

  @override
  void initState() {
    super.initState();
    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _load();
    _subscribeRealtime();
    // 30 s fallback keeps stats fresh even if a realtime event is missed.
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_loading) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _rtDebounce?.cancel();
    if (_rtChannel != null) SupabaseService.client.removeChannel(_rtChannel!);
    _staggerCtrl.dispose();
    super.dispose();
  }

  void _subscribeRealtime() {
    _rtChannel = SupabaseService.client.channel(
      'org-dashboard-${widget.orgId}',
    );
    for (final table in ['events', 'registrations']) {
      _rtChannel!.on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(event: '*', schema: 'public', table: table),
        (_, [a]) {
          _rtDebounce?.cancel();
          _rtDebounce = Timer(const Duration(milliseconds: 800), () {
            if (mounted && !_loading) _load(silent: true);
          });
        },
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
    if (!silent)
      setState(() {
        _loading = true;
        _error = false;
      });
    try {
      final client = SupabaseService.client;
      final now = DateTime.now();
      final user = client.auth.currentUser;
      if (user == null)
        throw StateError('Your session has expired. Please sign in again.');
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
      ))
        return;

      final eventRows = await client
          .from('events')
          .select(
            'event_id, title, event_date, end_date, start_time, end_time, location, '
            'event_status, approval_status, archived_at, organizer_id, '
            'registration_deadline, audience_grades, audience_strands',
          )
          .eq('organizer_id', widget.orgId!);

      final events = List<Map<String, dynamic>>.from(eventRows as List);
      final eventIds = events.map((e) => e['event_id'] as String).toList();

      // Each event's goal: the active students in its group (cached a minute).
      final countsFuture = StudentCountService.gradeCounts();
      final studentsFuture = StudentCountService.activeStudents();

      // Registrations filtered to this organizer's events
      List<Map<String, dynamic>> orgRegs = [];
      if (eventIds.isNotEmpty) {
        final regRows = await client
            .from('registrations')
            .select(
              'id, event_id, student_user_id, student_name, student_school_id, '
              'event_title, status, registered_at, checked_in_at, attendance_note, corrected_at',
            )
            .in_('event_id', eventIds)
            .order('registered_at', ascending: false);
        orgRegs = List<Map<String, dynamic>>.from(regRows as List);
      }

      // ── Stats ─────────────────────────────────────────────────────────
      const activeStatuses = {'upcoming', 'ongoing'};
      _activeEvents = activeApprovedEventCount(events, now: now);
      // Declined registrations aren't registrations in the progress card.
      _totalRegs = orgRegs.where(countsAsRegistered).length;

      // ── Upcoming events ───────────────────────────────────────────────
      final upcoming =
          events
              .where(
                (e) =>
                    eventIsApproved(e) &&
                    !eventIsArchived(e) &&
                    activeStatuses.contains(eventStatusValue(e, now: now)),
              )
              .toList()
            ..sort((a, b) {
              final da =
                  DateTime.tryParse(a['event_date'] ?? '') ?? DateTime(9999);
              final db =
                  DateTime.tryParse(b['event_date'] ?? '') ?? DateTime(9999);
              return da.compareTo(db);
            });
      _upcomingEvents = upcoming.take(5).toList();
      _recentRegs = orgRegs.take(6).toList();

      _events = events;
      _registrations = orgRegs;
      _gradeCounts = await countsFuture;
      _allStudents = await studentsFuture;

      // ── Photos to review ──────────────────────────────────────────────
      final review = photosToReview(events, orgRegs, now: now);
      _photosToReview = review.waiting;
      _checkInOpenNow = review.checkInOpen;

      // ── Next event ────────────────────────────────────────────────────
      // The same event the app's Dashboard counts down to.
      _nextEvent = nextApprovedEvent(events, now: now);
      final nextId = _nextEvent?['event_id'];
      _nextRegistered = orgRegs
          .where((r) => r['event_id'] == nextId && countsAsRegistered(r))
          .length;

      if (mounted) {
        setState(() => _loading = false);
        if (!silent) _staggerCtrl.forward(from: 0);
      }
    } catch (_) {
      if (mounted) {
        // A failed silent background refresh shouldn't blow away an already
        // -rendered dashboard — only the initial load surfaces the error state.
        setState(() {
          _loading = false;
          if (!silent) _error = true;
        });
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
        final raw = ((_staggerCtrl.value - start) / (end - start)).clamp(
          0.0,
          1.0,
        );
        final t = Curves.easeOut.transform(raw);
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
          _stagger(_buildPageHeader(t), start: 0.00, end: 0.40),
          const SizedBox(height: 24),
          _buildStatRow(t), // individual card stagger handled inside
          const SizedBox(height: 28),
          _stagger(_buildAnalyticsLabel(t), start: 0.36, end: 0.76),
          const SizedBox(height: 16),
          _stagger(_buildContentGrid(t), start: 0.46, end: 0.90),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildErrorState(WebTk t) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFFCA5A5), width: 1.5),
          ),
          child: const Icon(
            Icons.cloud_off_rounded,
            color: Color(0xFFEF4444),
            size: 32,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Could not load dashboard',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: t.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Check your connection and try again.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.sub),
        ),
        const SizedBox(height: 24),
        WebBtn(
          label: 'Retry',
          icon: Icons.refresh_rounded,
          onTap: () => _load(),
        ),
      ],
    ),
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
    final nav = widget.onNavigate;
    final open = widget.onOpenEvent;
    final next = _nextEvent;
    final nextId = next?['event_id'] as String?;
    final cards = [
      _DashStatCard(
        value: '$_activeEvents',
        label: 'Active Events',
        icon: Icons.event_available_rounded,
        accentColor: const Color(0xFF3B82F6),
        hint: 'Opens the Events tab',
        onTap: nav == null ? null : () => nav(OrganizerPage.events),
      ),
      _DashStatCard(
        value: '$_totalRegs',
        label: 'Total Registrations',
        icon: Icons.how_to_reg_rounded,
        accentColor: const Color(0xFF8B5CF6),
        hint: 'Opens the Registrations tab',
        onTap: nav == null ? null : () => nav(OrganizerPage.registrations),
      ),
      // The one number here that needs the organizer: a photo still waiting
      // when check-in closes can't be approved, and the student stays absent.
      _DashStatCard(
        value: '$_photosToReview',
        label: 'Photos to review',
        icon: Icons.photo_camera_rounded,
        accentColor: _photosToReview > 0
            ? const Color(0xFFF59E0B)
            : _checkInOpenNow
            ? const Color(0xFF10B981)
            : t.muted,
        hint: 'Opens the Registrations tab',
        onTap: nav == null ? null : () => nav(OrganizerPage.registrations),
      ),
      if (next == null)
        _DashStatCard(
          value: '—',
          label: 'No upcoming events',
          icon: Icons.event_note_rounded,
          accentColor: t.muted,
          hint: 'Opens the Events tab',
          onTap: nav == null ? null : () => nav(OrganizerPage.events),
        )
      else
        _DashStatCard(
          value: '$_nextRegistered',
          label: 'Registered · ${next['title'] as String? ?? 'Next event'}',
          icon: Icons.event_note_rounded,
          accentColor: eventStatusValue(next) == 'ongoing'
              ? const Color(0xFF10B981)
              : const Color(0xFF0EA5E9),
          hint: 'Opens this event',
          onTap: open == null || nextId == null ? null : () => open(nextId),
        ),
    ];

    return LayoutBuilder(
      builder: (_, c) {
        final cols = c.maxWidth > 800
            ? 4
            : c.maxWidth > 500
            ? 2
            : 1;
        final rows = (cards.length / cols).ceil();
        return Column(
          children: List.generate(
            rows,
            (row) => Padding(
              padding: EdgeInsets.only(bottom: row < rows - 1 ? 16 : 0),
              child: Row(
                children: List.generate(cols, (col) {
                  final idx = row * cols + col;
                  if (idx >= cards.length)
                    return const Expanded(child: SizedBox.shrink());
                  final s = 0.09 + idx * 0.07;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: col > 0 ? 16 : 0),
                      child: _stagger(
                        cards[idx],
                        start: s,
                        end: (s + 0.38).clamp(0.0, 1.0),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Analytics section label ───────────────────────────────────────────────
  Widget _buildAnalyticsLabel(WebTk t) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 3,
          height: 20,
          decoration: BoxDecoration(
            color: kGold,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Analytics',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: t.text,
            height: 1.1,
          ),
        ),
      ],
    );
  }

  // ── Content grid ──────────────────────────────────────────────────────────
  Widget _buildContentGrid(WebTk t) => LayoutBuilder(
    builder: (_, c) {
      final wide = c.maxWidth > 760;
      if (wide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: Column(children: [_buildProgressCard(t)])),
            const SizedBox(width: 16),
            Expanded(
              flex: 4,
              child: Column(
                children: [
                  _buildRecentRegs(t),
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
          _buildProgressCard(t),
          const SizedBox(height: 16),
          _buildRecentRegs(t),
          const SizedBox(height: 16),
          _buildUpcomingCard(),
        ],
      );
    },
  );

  Widget _buildUpcomingCard() => WebCard(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        WebSectionHeader(title: 'Upcoming Events'),
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
        WebSectionHeader(title: 'Recent Registrations'),
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

  // ── Registration progress card (shared with the app's Home) ──────────────

  Widget _buildProgressCard(WebTk t) => WebCard(
    padding: const EdgeInsets.all(22),
    child: RegistrationProgressCard(
      events: _events,
      registrations: _registrations,
      gradeCounts: _gradeCounts,
      allStudents: _allStudents,
      loadGroups: RegistrationService.registrantGroups,
      colors: RegistrationProgressColors(
        dark: t.dark,
        text: t.text,
        sub: t.sub,
        muted: t.muted,
        border: t.border,
      ),
    ),
  );
}

// ── Stat card with hover lift + animated progress ────────────────────────────

class _DashStatCard extends StatefulWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color accentColor;

  /// Makes the card a link: pointer, hover lift, arrow, keyboard focus.
  final VoidCallback? onTap;

  /// Where the link goes, for screen readers (e.g. 'Opens the Events tab').
  final String? hint;

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
    final c = widget.accentColor;
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final link = widget.onTap != null;
    // Only cards that go somewhere react — a hand cursor and a lift on a
    // static card promise a click that does nothing.
    final lit = link && (_hovered || _focused);

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      transform: Matrix4.translationValues(0, lit ? -4 : 0, 0),
      transformAlignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: lit ? c.withValues(alpha: 0.14) : t.shadow,
            blurRadius: lit ? 24 : 10,
            offset: Offset(0, lit ? 10 : 2),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 20,
                  ),
                  decoration: BoxDecoration(
                    color: t.card,
                    border: Border(
                      top: BorderSide(
                        color: lit ? c.withValues(alpha: 0.30) : t.border,
                        width: 1.5,
                      ),
                      right: BorderSide(
                        color: lit ? c.withValues(alpha: 0.30) : t.border,
                        width: 1.5,
                      ),
                      bottom: BorderSide(
                        color: lit ? c.withValues(alpha: 0.30) : t.border,
                        width: 1.5,
                      ),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.value,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: lit ? c : t.text,
                                height: 1.0,
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
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      color: lit ? c : t.sub,
                                    ),
                                  ),
                                ),
                                // Arrow slides in on hover / focus: "this opens a page".
                                if (link) ...[
                                  const SizedBox(width: 4),
                                  AnimatedSlide(
                                    duration: const Duration(milliseconds: 200),
                                    curve: Curves.easeOut,
                                    offset: lit
                                        ? Offset.zero
                                        : const Offset(-0.5, 0),
                                    child: AnimatedOpacity(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      opacity: lit ? 1 : 0,
                                      child: Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 14,
                                        color: c,
                                      ),
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
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              c.withValues(alpha: 0.18),
                              c.withValues(alpha: 0.07),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
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
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap!();
            return null;
          },
        ),
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
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
    final color = webEventStatusColor(resolved);
    final label = webEventStatusLabel(resolved);
    final isLive = resolved == 'ongoing';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event['title'] as String? ?? '—',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 11,
                      color: t.muted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      webFmtDate(event['event_date'] as String?),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        color: t.sub,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.location_on_rounded, size: 11, color: t.muted),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        event['location'] as String? ?? '—',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: t.sub,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isLive) ...[const WebLiveDot(size: 8), const SizedBox(width: 6)],
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
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final status = reg['status'] as String?;
    final statusColor = webStatusColor(status);
    final name = reg['student_name'] as String? ?? '—';
    final initials = name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase())
        .take(2)
        .join();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.10),
              shape: BoxShape.circle,
              border: Border.all(color: statusColor.withValues(alpha: 0.25)),
            ),
            child: Center(
              child: Text(
                initials,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  reg['event_title'] as String? ?? '—',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: t.sub,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              WebStatusBadge(label: webStatusLabel(status), color: statusColor),
              const SizedBox(height: 3),
              Text(
                webTimeAgo(reg['registered_at'] as String?),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  color: t.muted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../registrations/organizer_registrations_ui.dart'
    show registrationInitials, registrationStatusColor, registrationStatusLabel;
import '../registrations/organizer_registrations.dart' as regs;
import '../events/organizer_events.dart' as events;
import '../profile/profile.dart';
import '../announcements/announcements.dart';
import '../registrations/qr_scanner_screen.dart';
import '../../../../shared/widgets/ai_chat_fab.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../../../shared/widgets/live_countdown.dart';
import '../../../../shared/widgets/notification_sheet.dart';
import '../../../../shared/widgets/registration_progress_card.dart';
import '../../../../shared/utils/registration_progress.dart'
    show dailySignups, kSignupChartDays, registrationProgressEvents;
import '../../../../core/app_colors.dart';
import '../../../../core/services/org_notif_prefs.dart';
import '../../../../core/services/account_session_guard.dart';
import '../../../../core/services/organizer_notices.dart';
import '../../../../core/services/registration_service.dart';
import '../../../../core/services/student_count_service.dart';
import '../../../../core/event_audience.dart' show GradeCount;
import '../../../../shared/widgets/error_alert.dart';
import '../../../../shared/utils/realtime_utils.dart';
import 'dashboard_metrics.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

String _greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

String _fmtNotifTime(String? t) {
  if (t == null || t.isEmpty) return '';
  try {
    final parts = t.split(':');
    final h = int.parse(parts[0]);
    final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h == 0
        ? 12
        : h > 12
        ? h - 12
        : h;
    return '$h12:${m.toString().padLeft(2, '0')} $period';
  } catch (_) {
    return '';
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class OrganizerDashboardScreen extends StatefulWidget {
  const OrganizerDashboardScreen({super.key});

  @override
  State<OrganizerDashboardScreen> createState() =>
      _OrganizerDashboardScreenState();
}

class _OrganizerDashboardScreenState extends State<OrganizerDashboardScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int _selectedIndex = 0;

  late final AnimationController _staggerCtrl;

  // Home tab state
  bool _homeLoading = true;
  bool _dashError = false;
  bool _hasAnyEvents = false;
  String? _organizerName;
  // Registration progress card (shared with the web Dashboard).
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _registrations = [];
  List<Map<String, dynamic>> _recentRegistrations = [];
  List<GradeCount>? _gradeCounts;
  int? _allStudents;

  Map<String, dynamic>? _nextEvent;
  List<NotificationItem> _notifs = [];
  Set<String> _unreadIds = {};

  /// Read in this session — counted as read even before the prefs write
  /// lands, so a refresh racing it can't bring the badge back.
  final Set<String> _seenIds = {};

  // Live updates — see _watchLive.
  RealtimeChannel? _eventsChannel;

  /// This organizer's events, from the last load — keeps the registrations
  /// listener to them.
  Set<String> _myEventIds = {};

  /// Sign-ups or check-ins came in while another tab was open — Home
  /// reloads when it's opened again instead of after every one of them.
  bool _homeStale = false;
  RealtimeChannel? _accountChannel;
  String? _watchedOrgId;
  Timer? _liveDebounce;
  Timer? _refreshTimer;
  Future<void>? _inFlight;
  bool _fetchAgain = false;

  @override
  void initState() {
    super.initState();
    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    WidgetsBinding.instance.addObserver(this);
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      _accountChannel = AccountSessionGuard.watch(
        context,
        table: 'organizers',
        userId: userId,
        // An admin edit to the name or photo shows in the header at once.
        onUpdate: (_) {
          if (mounted && !_homeLoading) _loadData(silent: true);
        },
      );
    }
    _loadData();
    _startRefreshTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _liveDebounce?.cancel();
    _stopWatching();
    if (_accountChannel != null) {
      Supabase.instance.client.removeChannel(_accountChannel!);
    }
    _staggerCtrl.dispose();
    super.dispose();
  }

  // ── Live updates ──────────────────────────────────────────────────────────
  // Everything Home shows follows the database at once: the admin's
  // decisions (events, change requests, removed announcements — the bell),
  // new sign-ups and check-ins (the week's chart, attendance) and events
  // added or deleted elsewhere. The one-minute timer stays for what follows
  // the clock ("Starting today", "Event is live") and as a safety net.

  void _watchLive(String organizerId) {
    if (_watchedOrgId == organizerId) return;
    _stopWatching();
    _watchedOrgId = organizerId;
    // [whenOnHome]: check-in day brings a sign-up or check-in every few
    // seconds; while another tab is open they only mark Home stale. The
    // admin's decisions always reload it — the Dashboard tab's badge needs
    // them — and the one-minute timer still runs.
    void soon({bool whenOnHome = false}) {
      if (whenOnHome && _selectedIndex != 0) {
        _homeStale = true;
        return;
      }
      _liveDebounce?.cancel();
      _liveDebounce = Timer(const Duration(milliseconds: 800), () {
        if (mounted) _loadData(silent: true);
      });
    }

    final channel = Supabase.instance.client.channel(
      'org-mobile-dashboard-$organizerId',
    );
    for (final (table, column) in const [
      ('events', 'organizer_id'),
      ('event_revisions', 'organizer_id'),
      ('notifications', 'user_id'),
    ]) {
      channel.on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(
          event: '*',
          schema: 'public',
          table: table,
          filter: '$column=eq.$organizerId',
        ),
        (_, [_]) => soon(),
      );
    }
    // Deletes can't be filtered and carry only the row's id.
    channel.on(
      RealtimeListenTypes.postgresChanges,
      ChannelFilter(event: 'DELETE', schema: 'public', table: 'events'),
      (payload, [_]) {
        if (_myEventIds.contains(realtimeRow(payload)?['event_id'])) soon();
      },
    );
    // Registrations can't be filtered by organizer: keep to this
    // organizer's events (a deleted one has no event id — reload anyway).
    channel.on(
      RealtimeListenTypes.postgresChanges,
      ChannelFilter(event: '*', schema: 'public', table: 'registrations'),
      (payload, [_]) {
        final eventId = realtimeRow(payload)?['event_id'];
        if (eventId == null || _myEventIds.contains(eventId)) {
          soon(whenOnHome: true);
        }
      },
    );
    _eventsChannel = channel..subscribe();
  }

  void _stopWatching() {
    if (_eventsChannel != null) {
      Supabase.instance.client.removeChannel(_eventsChannel!);
    }
    _eventsChannel = null;
    _watchedOrgId = null;
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted && !_homeLoading) _loadData(silent: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_homeLoading) _loadData(silent: true);
      _startRefreshTimer();
    } else if (state == AppLifecycleState.paused) {
      _refreshTimer?.cancel();
    }
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  /// [silent] refreshes in the background (live updates, the timer, app
  /// resume, pull to refresh): no full-screen loader, no entrance animation,
  /// and a failure keeps what's already on screen — [userInitiated] (pull
  /// to refresh) reports it. One fetch runs at a time; a request in the
  /// meantime runs once after it.
  Future<void> _loadData({
    bool silent = false,
    bool userInitiated = false,
  }) async {
    final running = _inFlight;
    if (running != null) {
      _fetchAgain = true;
      return running;
    }
    final done = Completer<void>();
    _inFlight = done.future;
    Object? error;
    try {
      error = await _fetchData(silent: silent);
    } finally {
      _inFlight = null;
      done.complete();
    }
    if (!mounted) return;
    if (error != null && userInitiated) {
      showErrorAlert(context, error, title: 'Couldn’t refresh the dashboard');
    }
    if (_fetchAgain) {
      _fetchAgain = false;
      _loadData(silent: true);
    }
  }

  /// Returns the error when the load failed.
  Future<Object?> _fetchData({required bool silent}) async {
    if (!silent) {
      setState(() {
        _homeLoading = true;
        _dashError = false;
      });
    }
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) {
        setState(() => _homeLoading = false);
        if (!silent) _staggerCtrl.forward(from: 0);
        return null;
      }

      final orgRow = await client
          .from('organizers')
          .select('organizer_id, full_name, organization, is_active')
          .eq('user_id', user.id)
          .maybeSingle();

      if (orgRow == null)
        throw StateError('Could not find your organizer profile.');
      if (!await AccountSessionGuard.ensureActive(
        context,
        isActive: orgRow['is_active'] == true,
      ))
        return null;

      final organizerId = orgRow['organizer_id'] as String;

      final eventRows = await client
          .from('events')
          .select(
            'event_id, title, event_date, end_date, start_time, end_time, location, '
            'event_status, event_image_url, approval_status, rejection_reason, reviewed_at, '
            'archived_at, registration_deadline, audience_grades, audience_strands',
          )
          .eq('organizer_id', organizerId)
          .order('event_date', ascending: true);

      final allEvents = List<Map<String, dynamic>>.from(eventRows as List);
      final eventIds = allEvents.map((e) => e['event_id'] as String).toList();
      final now = DateTime.now();
      // Each event's goal: the active students in its group (cached a minute).
      final countsFuture = StudentCountService.gradeCounts();
      final studentsFuture = StudentCountService.activeStudents();

      // Registration progress: every registration of the events still
      // running, plus the last two weeks' across all events (the chart).
      final runningIds = registrationProgressEvents(
        allEvents,
        now: now,
      ).map((e) => e['event_id'] as String).toList();
      final chartStart = DateTime(
        now.year,
        now.month,
        now.day - (kSignupChartDays - 1),
      );
      final byId = <String, Map<String, dynamic>>{};
      var recentRegistrations = <Map<String, dynamic>>[];
      if (eventIds.isNotEmpty) {
        const columns = 'id, event_id, status, registered_at';
        final Future<dynamic> recent = client
            .from('registrations')
            .select(columns)
            .in_('event_id', eventIds)
            .gte('registered_at', chartStart.toUtc().toIso8601String());
        final Future<dynamic> running = runningIds.isEmpty
            ? Future.value(const [])
            : client
                  .from('registrations')
                  .select(columns)
                  .in_('event_id', runningIds);
        for (final rows in [await recent, await running]) {
          for (final r in rows as List) {
            final row = Map<String, dynamic>.from(r as Map);
            byId[row['id'] as String] = row;
          }
        }
        final recentRows = await client
            .from('registrations')
            .select(
              'id, event_id, student_name, student_school_id, event_title, '
              'status, registered_at',
            )
            .in_('event_id', eventIds)
            .order('registered_at', ascending: false)
            .limit(5);
        recentRegistrations = List<Map<String, dynamic>>.from(
          recentRows as List,
        );
      }
      final progressRegistrations = byId.values.toList();
      final gradeCounts = await countsFuture;
      final allStudents = await studentsFuture;
      // Next event: the earliest approved one that's on now or still ahead,
      // by date and start time.
      final nextEvt = nextApprovedEvent(allEvents, now: now);

      // Build notifications from already-loaded data (no extra queries needed)
      final notifTodayStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final notifTomDt = now.add(const Duration(days: 1));
      final notifTomStr =
          '${notifTomDt.year}-${notifTomDt.month.toString().padLeft(2, '0')}-${notifTomDt.day.toString().padLeft(2, '0')}';
      final notifResult = <NotificationItem>[];

      // Today's bar of the Registration progress chart (all events).
      final todayRegCount = dailySignups(
        progressRegistrations,
        now: now,
      ).last.count;
      if (todayRegCount > 0) {
        notifResult.add(
          NotificationItem(
            id: 'signups_today_$notifTodayStr',
            title:
                '$todayRegCount new sign-up${todayRegCount == 1 ? '' : 's'} today',
            message: 'Students registered for your events',
            icon: Icons.how_to_reg_rounded,
            color: const Color(0xFF8B5CF6),
          ),
        );
      }

      // Reminders only for approved events — students can't register for
      // the others, so there's no one to check in.
      for (final e
          in allEvents
              .where(
                (e) => eventIsApproved(e) && eventStatusValue(e) == 'ongoing',
              )
              .take(3)) {
        notifResult.add(
          NotificationItem(
            id: 'event_live_${e['event_id']}',
            title: e['title'] as String? ?? '—',
            message: 'Event is live · check in students now',
            icon: Icons.radio_button_checked_rounded,
            color: const Color(0xFF10B981),
          ),
        );
      }

      for (final e
          in allEvents
              .where(
                (e) =>
                    eventIsApproved(e) &&
                    eventStatusValue(e) == 'upcoming' &&
                    (e['event_date'] as String?) == notifTodayStr,
              )
              .take(3)) {
        final t = _fmtNotifTime(e['start_time'] as String?);
        notifResult.add(
          NotificationItem(
            id: 'event_today_${e['event_id']}',
            title: e['title'] as String? ?? '—',
            message: 'Starting today${t.isNotEmpty ? ' at $t' : ''}',
            icon: Icons.today_rounded,
            color: const Color(0xFF3B82F6),
          ),
        );
      }

      for (final e
          in allEvents
              .where(
                (e) =>
                    eventIsApproved(e) &&
                    eventStatusValue(e) == 'upcoming' &&
                    (e['event_date'] as String?) == notifTomStr,
              )
              .take(2)) {
        final t = _fmtNotifTime(e['start_time'] as String?);
        notifResult.add(
          NotificationItem(
            id: 'event_tomorrow_${e['event_id']}',
            title: e['title'] as String? ?? '—',
            message: 'Starting tomorrow${t.isNotEmpty ? ' at $t' : ''}',
            icon: Icons.calendar_month_rounded,
            color: const Color(0xFFF59E0B),
          ),
        );
      }

      // Admin decisions (approved / rejected events and change requests,
      // removed announcements) — listed first, newest first. Deliberately NOT
      // gated by OrgNotifPrefs: like the selfie-required notifications for
      // students, what happened to *your own* submission isn't something an
      // organizer should be able to silence. Same items as the web bell.
      final decisions = [
        for (final n in await OrganizerNotices.load(
          organizerId: organizerId,
          events: allEvents,
        ))
          NotificationItem(
            id: n.id,
            title: n.title,
            message: n.message,
            icon: n.icon,
            color: n.color,
            at: n.at,
          ),
      ];

      // Respect per-user preferences (Profile → Notifications).
      final disabledCats = await OrgNotifPrefs.disabled(user.id);
      if (disabledCats.isNotEmpty) {
        notifResult.removeWhere(
          (n) =>
              (disabledCats.contains(OrgNotifPrefs.signups) &&
                  n.id.startsWith('signups_today_')) ||
              (disabledCats.contains(OrgNotifPrefs.live) &&
                  n.id.startsWith('event_live_')) ||
              (disabledCats.contains(OrgNotifPrefs.today) &&
                  n.id.startsWith('event_today_')) ||
              (disabledCats.contains(OrgNotifPrefs.tomorrow) &&
                  n.id.startsWith('event_tomorrow_')),
        );
      }
      notifResult.insertAll(0, decisions);

      if (mounted) {
        final readIds = await _readIds(user.id);
        if (!mounted) return null;
        final recovering = _dashError;
        setState(() {
          _organizerName = orgRow['full_name'] as String? ?? 'Organizer';
          _myEventIds = eventIds.toSet();
          _homeStale = false;
          _nextEvent = nextEvt;
          _hasAnyEvents = allEvents.isNotEmpty;
          _events = allEvents;
          _registrations = progressRegistrations;
          _recentRegistrations = recentRegistrations;
          _gradeCounts = gradeCounts;
          _allStudents = allStudents;
          _notifs = notifResult;
          _unreadIds = {
            for (final n in notifResult)
              if (!readIds.contains(n.id) && !_seenIds.contains(n.id)) n.id,
          };
          _homeLoading = false;
          _dashError = false; // a background refresh can recover the screen
        });
        // The content fades in on first show — including after an error.
        if (!silent || recovering) _staggerCtrl.forward(from: 0);
        _watchLive(organizerId);
      }
    } catch (e) {
      debugPrint('OrganizerDashboard load error: $e');
      // A failed background refresh keeps what's already on screen.
      if (mounted && !silent) {
        setState(() {
          _homeLoading = false;
          _dashError = true;
        });
      }
      return e;
    }
    return null;
  }

  // ── Camera / QR ───────────────────────────────────────────────────────────

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      if (mounted) {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const QRScannerScreen()));
      }
    } else if (status.isDenied || status.isPermanentlyDenied) {
      if (mounted) {
        AppAlert.warning(
          context,
          title: 'Camera Permission Required',
          message: status.isPermanentlyDenied
              ? 'Camera access has been permanently denied. Enable it in your device settings to scan QR codes.'
              : 'Camera access is needed to scan student QR codes for check-in.',
          buttonText: 'Dismiss',
          actionText: status.isPermanentlyDenied ? 'Open Settings' : null,
          onAction: status.isPermanentlyDenied ? openAppSettings : null,
        );
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final t = AppTk(Theme.of(context).brightness == Brightness.dark);
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        // IndexedStack keeps all tabs alive so they preserve scroll position
        // and don't re-fetch when the user switches tabs.
        // Indices: 0=Home, 1=Events, 2=Registrations, 3=Profile
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            _buildHomeContent(t),
            const events.OrganizerEventsScreen(showAsEmbedded: true),
            const regs.RegistrationsScreen(showAsEmbedded: true),
            OrganizerProfileScreen(isVisible: _selectedIndex == 3),
          ],
        ),
      ),
      floatingActionButton: const AiChatFab(userRole: 'organizer'),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

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

  // ── Home content ──────────────────────────────────────────────────────────

  // ── Notification read-state persistence (per-ID) ──────────────────────

  static String _prefKey(String userId) => 'org_notif_read_ids_$userId';

  Future<void> _persistReadState() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || _seenIds.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final existing = Set<String>.from(
      prefs.getStringList(_prefKey(userId)) ?? [],
    );
    existing.addAll(_seenIds);
    final list = existing.toList();
    final trimmed = list.length > 200 ? list.sublist(list.length - 200) : list;
    await prefs.setStringList(_prefKey(userId), trimmed);
  }

  Future<Set<String>> _readIds(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return Set<String>.from(prefs.getStringList(_prefKey(userId)) ?? []);
  }

  Widget _buildHomeContent(AppTk t) {
    if (_homeLoading) {
      return const AppFullScreenLoader(message: 'Loading your dashboard…');
    }

    if (_dashError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.cloud_off_rounded,
                  size: 36,
                  color: Color(0xFFEF4444),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Could not load dashboard',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: t.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Check your connection and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: t.sub,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text(
                  'Retry',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGold,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: kGold,
      // Quiet: keeps the dashboard on screen while it reloads.
      onRefresh: () => _loadData(silent: true, userInitiated: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _stagger(_buildHeader(), start: 0.00, end: 0.38),
          ),
          SliverToBoxAdapter(
            child: _stagger(_buildUpcomingCountdown(), start: 0.10, end: 0.48),
          ),
          SliverToBoxAdapter(
            child: _stagger(_buildAnnouncementsCard(t), start: 0.20, end: 0.58),
          ),
          if (_hasAnyEvents)
            SliverToBoxAdapter(
              child: _stagger(
                _buildAnalyticsHeading(t),
                start: 0.26,
                end: 0.62,
              ),
            ),
          if (_hasAnyEvents)
            SliverToBoxAdapter(
              child: _stagger(_buildProgressCard(t), start: 0.28, end: 0.66),
            ),
          if (_hasAnyEvents)
            SliverToBoxAdapter(
              child: _stagger(
                _buildRecentRegistrationsCard(t),
                start: 0.32,
                end: 0.70,
              ),
            ),
          if (_hasAnyEvents)
            SliverToBoxAdapter(
              child: _stagger(
                _buildUpcomingEventsCard(t),
                start: 0.36,
                end: 0.74,
              ),
            ),
          if (!_hasAnyEvents)
            SliverToBoxAdapter(
              child: _stagger(_buildEmptyStateCTA(t), start: 0.32, end: 0.72),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final t = AppTk(Theme.of(context).brightness == Brightness.dark);
    final displayName = (_organizerName?.isNotEmpty ?? false)
        ? _organizerName!
        : 'Organizer';
    final firstName = displayName.split(' ').first;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Gold accent bar
          Container(
            width: 3,
            height: 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFC49230), kGold, Color(0xFFEAB866)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      _greeting(),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: t.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  firstName,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: t.text,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
          _buildBellButton(t),
        ],
      ),
    );
  }

  // ── Notification bell button ──────────────────────────────────────────────

  Widget _buildBellButton(AppTk t) {
    final unread = _unreadIds.length;
    final hasUnread = unread > 0;
    return GestureDetector(
      onTap: _showNotificationSheet,
      child: Semantics(
        button: true,
        label: hasUnread
            ? '$unread new notification${unread == 1 ? '' : 's'}'
            : 'Notifications',
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hasUnread ? kGold.withValues(alpha: 0.35) : t.border,
                ),
                boxShadow: [
                  BoxShadow(
                    color: t.shadow,
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  hasUnread
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_none_rounded,
                  color: hasUnread ? kGold : t.sub,
                  size: 22,
                ),
              ),
            ),
            if (hasUnread)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    // #DC2626 keeps the white count at 4.8:1.
                    color: const Color(0xFFDC2626),
                    shape: BoxShape.circle,
                    border: Border.all(color: t.bg, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      unread > 9 ? '9+' : '$unread',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Opening the sheet doesn't read anything (same as the web bell): an
  // unread row stays gold until it's tapped or "Mark all as read" is used.
  void _showNotificationSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => NotificationSheet(
        items: _notifs,
        // Not a tear-off: _markRead swaps in a new set.
        isUnread: (id) => _unreadIds.contains(id),
        onRead: _markRead,
        emptyHint:
            'Admin approvals, sign-ups and event reminders show up here.',
      ),
    );
  }

  /// Marks [ids] read: the bell's number drops.
  void _markRead(Iterable<String> ids) {
    final fresh = ids.where(_unreadIds.contains).toList();
    if (fresh.isEmpty || !mounted) return;
    setState(() {
      _seenIds.addAll(fresh);
      _unreadIds = {..._unreadIds}..removeAll(fresh);
    });
    _persistReadState(); // fire-and-forget — survives logout/login
  }

  // ── Announcements card ────────────────────────────────────────────────────

  Widget _buildAnnouncementsCard(AppTk t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Actions',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AnnouncementsScreen()),
              ),
              borderRadius: BorderRadius.circular(16),
              child: Ink(
                decoration: BoxDecoration(
                  color: t.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFE87A00).withValues(alpha: 0.2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: t.shadow,
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE87A00).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.campaign_rounded,
                          color: Color(0xFFE87A00),
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Announcements',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: t.text,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Post updates and notices for students',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color: t.sub.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFE87A00,
                          ).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: Color(0xFFE87A00),
                          size: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Registration progress — the same card as the web Dashboard's.
  Widget _buildProgressCard(AppTk t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: t.border),
          boxShadow: [
            BoxShadow(
              color: t.shadow,
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
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
      ),
    );
  }

  List<Map<String, dynamic>> get _upcomingEventsPreview {
    final events =
        _events.where((event) {
          if (!eventIsApproved(event) || eventIsArchived(event)) return false;
          return const {
            'upcoming',
            'ongoing',
          }.contains(eventStatusValue(event));
        }).toList()..sort((a, b) {
          final aWindow = eventWindow(a);
          final bWindow = eventWindow(b);
          final byStart = (aWindow?.start ?? DateTime(9999)).compareTo(
            bWindow?.start ?? DateTime(9999),
          );
          if (byStart != 0) return byStart;
          return (a['title'] as String? ?? '').compareTo(
            b['title'] as String? ?? '',
          );
        });
    return events.take(5).toList();
  }

  Widget _buildRecentRegistrationsCard(AppTk t) {
    return _dashboardListCard(
      t,
      icon: Icons.how_to_reg_rounded,
      accent: const Color(0xFF16A34A),
      title: 'Recent Registrations',
      child: _recentRegistrations.isEmpty
          ? _dashboardEmptyMessage(
              t,
              'Students who register for your events will appear here.',
            )
          : Column(
              children: _recentRegistrations.asMap().entries.map((entry) {
                final registration = entry.value;
                final event = _events.cast<Map<String, dynamic>?>().firstWhere(
                  (event) => event?['event_id'] == registration['event_id'],
                  orElse: () => null,
                );
                final row = {
                  ...registration,
                  if (registration['event_title'] == null)
                    'event_title': event?['title'],
                };
                return Column(
                  children: [
                    if (entry.key > 0) Divider(height: 1, color: t.divider),
                    _buildRecentRegistrationRow(row, t),
                  ],
                );
              }).toList(),
            ),
    );
  }

  Widget _buildRecentRegistrationRow(Map<String, dynamic> row, AppTk t) {
    final name = (row['student_name'] as String?)?.trim();
    final displayName = name == null || name.isEmpty ? 'Student' : name;
    final status = row['status'] as String? ?? 'pending';
    final color = registrationStatusColor(status);
    final eventTitle = row['event_title'] as String? ?? 'Event';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Text(
              registrationInitials(displayName),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  eventTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: t.sub,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                registrationStatusLabel(status),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _relativeRegistrationTime(row['registered_at'] as String?),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 9.5,
                  color: t.muted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUpcomingEventsCard(AppTk t) {
    final upcoming = _upcomingEventsPreview;
    return _dashboardListCard(
      t,
      icon: Icons.event_available_rounded,
      accent: const Color(0xFF2563EB),
      title: 'Upcoming Events',
      child: upcoming.isEmpty
          ? _dashboardEmptyMessage(t, 'No upcoming events scheduled.')
          : Column(
              children: upcoming.asMap().entries.map((entry) {
                final event = entry.value;
                final status = eventStatusValue(event);
                final statusColor = status == 'ongoing'
                    ? const Color(0xFF16A34A)
                    : const Color(0xFF2563EB);
                final date = DateTime.tryParse(
                  event['event_date'] as String? ?? '',
                );
                final dateLabel = date == null
                    ? 'Date to be announced'
                    : '${_monthNames[date.month - 1]} ${date.day}, ${date.year}';
                final time = _fmtNotifTime(event['start_time'] as String?);
                final location = (event['location'] as String?)?.trim() ?? '';
                return Column(
                  children: [
                    if (entry.key > 0) Divider(height: 1, color: t.divider),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 4,
                            height: 46,
                            decoration: BoxDecoration(
                              color: statusColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  event['title'] as String? ?? 'Untitled event',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: t.text,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 4,
                                  children: [
                                    _eventMeta(
                                      Icons.calendar_today_rounded,
                                      '$dateLabel${time.isEmpty ? '' : ' · $time'}',
                                      t,
                                    ),
                                    if (location.isNotEmpty)
                                      _eventMeta(
                                        Icons.location_on_rounded,
                                        location,
                                        t,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            status == 'ongoing' ? 'Live' : 'Upcoming',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
    );
  }

  Widget _dashboardListCard(
    AppTk t, {
    required IconData icon,
    required Color accent,
    required String title,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: t.border),
          boxShadow: [
            BoxShadow(
              color: t.shadow,
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 19, color: accent),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: t.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _dashboardEmptyMessage(AppTk t, String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
    child: Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: t.muted),
      ),
    ),
  );

  Widget _eventMeta(IconData icon, String label, AppTk t) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 11, color: t.muted),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: t.sub),
        ),
      ),
    ],
  );

  String _relativeRegistrationTime(String? value) {
    final date = DateTime.tryParse(value ?? '')?.toLocal();
    if (date == null) return '';
    final difference = DateTime.now().difference(date);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    if (difference.inDays < 30) return '${difference.inDays}d ago';
    return '${_monthNames[date.month - 1]} ${date.day}';
  }

  static const _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  Widget _buildAnalyticsHeading(AppTk t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Text(
        'Analytics',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: t.text,
        ),
      ),
    );
  }

  Widget _buildEmptyStateCTA(AppTk t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: kGold.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: t.shadow,
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: kGoldGradient,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: kGold.withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.event_note_rounded,
                size: 38,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No events yet',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first event to start managing\nregistrations and tracking attendance.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: t.sub,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () => setState(() => _selectedIndex = 1),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text(
                  'Create Your First Event',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGold,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Upcoming event countdown card ────────────────────────────────────────

  Widget _buildUpcomingCountdown() {
    final e = _nextEvent;
    if (e == null) return const SizedBox.shrink();

    final title = e['title'] as String? ?? '—';
    final dStr = e['event_date'] as String?;
    if (dStr == null) return const SizedBox.shrink();

    DateTime start;
    DateTime? end;
    try {
      final d = DateTime.parse(dStr);
      final sTime = e['start_time'] as String?;
      if (sTime != null) {
        final p = sTime.split(':');
        final h = int.tryParse(p[0]) ?? 0;
        final m = p.length > 1 ? (int.tryParse(p[1]) ?? 0) : 0;
        start = DateTime(d.year, d.month, d.day, h, m);
      } else {
        start = DateTime(d.year, d.month, d.day, 8);
      }
      final endDateRaw = e['end_date'] as String?;
      final endDate = endDateRaw == null || endDateRaw.isEmpty
          ? d
          : DateTime.tryParse(endDateRaw) ?? d;
      final eTime = e['end_time'] as String?;
      if (eTime != null && eTime.isNotEmpty) {
        final p = eTime.split(':');
        final h = int.tryParse(p[0]) ?? 0;
        final m = p.length > 1 ? (int.tryParse(p[1]) ?? 0) : 0;
        end = DateTime(endDate.year, endDate.month, endDate.day, h, m);
      } else {
        end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
      }
    } catch (_) {
      return const SizedBox.shrink();
    }

    final imageUrl = e['event_image_url'] as String?;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final fmtDate = '${months[start.month - 1]} ${start.day}, ${start.year}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Container(
        height: 188,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: kGold.withValues(alpha: 0.30),
              blurRadius: 20,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Background: banner image or gold gradient fallback ─────────
            hasImage
                ? Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _goldGradientBg(),
                  )
                : _goldGradientBg(),

            // ── Dark scrim so text stays readable over any photo ──────────
            if (hasImage)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.05),
                      Colors.black.withValues(alpha: 0.72),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.25, 1.0],
                  ),
                ),
              ),

            // ── Animated status + countdown overlay ───────────────────────
            _NextEventBanner(
              start: start,
              end: end,
              title: title,
              fmtDate: fmtDate,
            ),
          ],
        ),
      ),
    );
  }

  Widget _goldGradientBg() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFC49230), Color(0xFFD6A742), Color(0xFFEAB866)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Bottom navigation
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildBottomNavigationBar() {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1C1814),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
              blurRadius: 16,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: _OrganizerBottomNavItem(
                activeIcon: Icons.dashboard_rounded,
                inactiveIcon: Icons.dashboard_outlined,
                label: 'Dashboard',
                active: _selectedIndex == 0,
                activeColor: kGold,
                // The bell lives on the Dashboard — flag new notifications
                // (e.g. an admin decision) while another tab is open.
                badge: _selectedIndex != 0 && _unreadIds.isNotEmpty,
                onTap: () {
                  setState(() => _selectedIndex = 0);
                  if (_homeStale && !_homeLoading) {
                    _homeStale = false;
                    _loadData(silent: true);
                  }
                },
              ),
            ),
            Flexible(
              child: _OrganizerBottomNavItem(
                activeIcon: Icons.event_rounded,
                inactiveIcon: Icons.event_outlined,
                label: 'Events',
                active: _selectedIndex == 1,
                activeColor: kGold,
                onTap: () => setState(() => _selectedIndex = 1),
              ),
            ),
            GestureDetector(
              onTap: _requestCameraPermission,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFC49230),
                          Color(0xFFD6A742),
                          Color(0xFFEAB866),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: kGold.withValues(alpha: 0.50),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.qr_code_scanner_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Scan QR',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: kGold,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: _OrganizerBottomNavItem(
                activeIcon: Icons.how_to_reg_rounded,
                inactiveIcon: Icons.how_to_reg_outlined,
                label: 'Registrations',
                active: _selectedIndex == 2,
                activeColor: kGold,
                onTap: () => setState(() => _selectedIndex = 2),
              ),
            ),
            Flexible(
              child: _OrganizerBottomNavItem(
                activeIcon: Icons.person_rounded,
                inactiveIcon: Icons.person_outline_rounded,
                label: 'Profile',
                active: _selectedIndex == 3,
                activeColor: kGold,
                onTap: () => setState(() => _selectedIndex = 3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Nav item widget ───────────────────────────────────────────────────────────

class _OrganizerBottomNavItem extends StatelessWidget {
  final IconData activeIcon;
  final IconData inactiveIcon;
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  /// Small red dot on the icon — unread notifications on that tab.
  final bool badge;

  const _OrganizerBottomNavItem({
    required this.activeIcon,
    required this.inactiveIcon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
    this.badge = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: active
                  ? activeColor.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  active ? activeIcon : inactiveIcon,
                  size: 22,
                  color: active
                      ? activeColor
                      : Colors.white.withValues(alpha: 0.45),
                ),
                if (badge)
                  Positioned(
                    top: -1,
                    right: -3,
                    child: Semantics(
                      label: 'New notifications',
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF1C1814),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              color: active
                  ? activeColor
                  : Colors.white.withValues(alpha: 0.45),
            ),
            maxLines: 1,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Event banner overlay (badge + countdown, time-aware) ─────────────────────
// Replaces the static "NEXT EVENT / STARTS IN" labels with a per-second timer
// that reflects the current phase: upcoming → live → ended.

class _NextEventBanner extends StatefulWidget {
  final DateTime start;
  final DateTime? end;
  final String title;
  final String fmtDate;

  const _NextEventBanner({
    required this.start,
    required this.end,
    required this.title,
    required this.fmtDate,
  });

  @override
  State<_NextEventBanner> createState() => _NextEventBannerState();
}

class _NextEventBannerState extends State<_NextEventBanner> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final started = now.isAfter(widget.start);
    final ended = widget.end != null && now.isAfter(widget.end!);

    // Badge chip
    final String badgeText;
    final Color badgeColor;
    if (ended) {
      badgeText = 'ENDED';
      badgeColor = const Color(0xFF6B7280);
    } else if (started) {
      badgeText = 'ONGOING';
      badgeColor = const Color(0xFF10B981);
    } else {
      badgeText = 'NEXT EVENT';
      badgeColor = kGold;
    }

    // Right-column header label
    final String topLabel;
    if (ended) {
      topLabel = 'ENDED';
    } else if (started && widget.end != null) {
      topLabel = 'ENDS IN';
    } else if (started) {
      topLabel = 'LIVE';
    } else {
      topLabel = 'STARTS IN';
    }

    // Right-column bottom widget
    Widget bottomRight;
    if (ended) {
      bottomRight = const Text(
        'Ended',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Colors.white60,
        ),
      );
    } else if (started && widget.end != null) {
      final diff = widget.end!.difference(now);
      final h = diff.inHours;
      final m = diff.inMinutes.remainder(60).toString().padLeft(2, '0');
      final s = diff.inSeconds.remainder(60).toString().padLeft(2, '0');
      bottomRight = Text(
        h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s',
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      );
    } else {
      bottomRight = LiveCountdown(
        target: widget.start,
        textColor: Colors.white,
      );
    }

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badgeText,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 11,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.fmtDate,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  topLabel,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: Colors.white60,
                  ),
                ),
                const SizedBox(height: 4),
                bottomRight,
              ],
            ),
          ],
        ),
      ),
    );
  }
}

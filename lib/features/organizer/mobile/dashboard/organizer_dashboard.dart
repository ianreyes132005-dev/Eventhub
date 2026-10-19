import 'dart:async';
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../registrations/organizer_registrations.dart' as regs;
import '../events/organizer_events.dart' as events;
import '../profile/profile.dart';
import '../announcements/announcements.dart';
import '../registrations/qr_scanner_screen.dart';
import '../../../../shared/widgets/ai_chat_fab.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../../../shared/widgets/live_countdown.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/services/org_notif_prefs.dart';
import '../../../../core/services/organizer_session_guard.dart';
import '../../../../core/services/organizer_notices.dart';
import '../../../../shared/utils/event_labels.dart' show monthDayLabel;
import '../../../../shared/widgets/error_alert.dart';
import 'dashboard_metrics.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

String _greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

String _todayFormatted() {
  final now = DateTime.now();
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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
  return '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
}

// ── Notification data model ───────────────────────────────────────────────────

class _AppNotif {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  /// When it happened — set for admin decisions; reminders have none.
  final DateTime? at;
  const _AppNotif({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  }) : at = null;

  _AppNotif.notice(OrgNotice n)
    : id = n.id,
      title = n.title,
      subtitle = n.message,
      icon = n.icon,
      color = n.color,
      at = n.at;
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
  String? _photoUrl;

  // Analytics data — sign-ups per day for the last 7 days (index 6 = today)
  // and for the 7 days before them (same weekday a week earlier).
  List<double> _dailyRegistrations = List.filled(7, 0);
  List<double> _prevDailyRegistrations = List.filled(7, 0);
  int _regsLast7 = 0;
  int _regsPrev7 = 0;
  List<Map<String, dynamic>> _eventAttendance = [];
  DateTime? _lastUpdated;
  Map<String, dynamic>? _nextEvent;
  List<_AppNotif> _notifs = [];
  Set<String> _unreadIds = {};

  /// Opened in this session — counted as read even before the prefs write
  /// lands, so a refresh racing it can't bring the badge back.
  final Set<String> _seenIds = {};

  // Live updates — see _watchEvents.
  RealtimeChannel? _eventsChannel;
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
    _loadData();
    _startRefreshTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _liveDebounce?.cancel();
    _stopWatching();
    _staggerCtrl.dispose();
    super.dispose();
  }

  // ── Live updates ──────────────────────────────────────────────────────────
  // An admin approving or rejecting one of this organizer's events (or
  // applying their change request) updates the event row, so the bell picks
  // it up without a pull-to-refresh. A one-minute timer and returning to the
  // app catch the rest (rejected change requests, removed announcements).

  void _watchEvents(String organizerId) {
    if (_watchedOrgId == organizerId) return;
    _stopWatching();
    _watchedOrgId = organizerId;
    _eventsChannel =
        Supabase.instance.client.channel('org-mobile-dashboard-$organizerId')
          ..on(
            RealtimeListenTypes.postgresChanges,
            ChannelFilter(
              event: 'UPDATE',
              schema: 'public',
              table: 'events',
              filter: 'organizer_id=eq.$organizerId',
            ),
            (_, [_]) {
              _liveDebounce?.cancel();
              _liveDebounce = Timer(const Duration(milliseconds: 800), () {
                if (mounted) _loadData(silent: true);
              });
            },
          )
          ..subscribe();
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
          .select('organizer_id, full_name, organization, profile_image_url, is_active')
          .eq('user_id', user.id)
          .maybeSingle();

      if (orgRow == null) throw StateError('Could not find your organizer profile.');
      if (!await OrganizerSessionGuard.ensureActive(
        context,
        isActive: orgRow['is_active'] == true,
      )) return null;

      final organizerId = orgRow['organizer_id'] as String;

      final eventRows = await client
          .from('events')
          .select(
            'event_id, title, event_date, end_date, start_time, end_time, event_status, '
            'event_image_url, approval_status, rejection_reason, reviewed_at',
          )
          .eq('organizer_id', organizerId)
          .order('event_date', ascending: true);

      final allEvents = List<Map<String, dynamic>>.from(eventRows as List);
      final eventIds = allEvents.map((e) => e['event_id'] as String).toList();

      List<Map<String, dynamic>> regList = [];
      if (eventIds.isNotEmpty) {
        final regRows = await client
            .from('registrations')
            .select('id, status, event_id, registered_at')
            .in_('event_id', eventIds);
        regList = List<Map<String, dynamic>>.from(regRows as List);
      }

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      // Sign-ups: the last 7 days next to the 7 days before them.
      final signups = signupsByDay(regList, now: now);

      // Attendance: the last 5 events whose attendance is final — approved,
      // not cancelled, had registrations, check-in closed. An event still
      // running, a cancelled one or one nobody could join would only drag
      // the rate down.
      final regCounts = <String, int>{};
      final checkedInCounts = <String, int>{};
      for (final r in regList) {
        final eid = r['event_id'] as String?;
        if (eid == null) continue;
        regCounts[eid] = (regCounts[eid] ?? 0) + 1;
        if (r['status'] == 'checked_in') {
          checkedInCounts[eid] = (checkedInCounts[eid] ?? 0) + 1;
        }
      }
      final finished = attendanceEvents(allEvents, regCounts, now: now);
      final last5 = finished.length > 5
          ? finished.sublist(finished.length - 5)
          : finished;

      final attendance = last5.map((e) {
        final eid = e['event_id'] as String;
        return <String, dynamic>{
          // "Oct\n25"
          'label': monthDayLabel(eventWindow(e)!.start).replaceFirst(' ', '\n'),
          'title': (e['title'] as String?) ?? '—',
          'checkedIn': checkedInCounts[eid] ?? 0,
          'total': regCounts[eid] ?? 0,
        };
      }).toList();

      // Next event: the earliest approved one that's on now or still ahead,
      // by date and start time.
      final nextEvt = nextApprovedEvent(allEvents, now: now);

      // Build notifications from already-loaded data (no extra queries needed)
      final notifTodayStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final notifTomDt = now.add(const Duration(days: 1));
      final notifTomStr =
          '${notifTomDt.year}-${notifTomDt.month.toString().padLeft(2, '0')}-${notifTomDt.day.toString().padLeft(2, '0')}';
      final notifResult = <_AppNotif>[];

      final todayRegCount = regList.where((r) {
        final ds = r['registered_at'] as String?;
        if (ds == null) return false;
        try {
          return !DateTime.parse(ds).toLocal().isBefore(todayStart);
        } catch (_) {
          return false;
        }
      }).length;
      if (todayRegCount > 0) {
        notifResult.add(
          _AppNotif(
            id: 'signups_today_$notifTodayStr',
            title:
                '$todayRegCount new sign-up${todayRegCount == 1 ? '' : 's'} today',
            subtitle: 'Students registered for your events',
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
          _AppNotif(
            id: 'event_live_${e['event_id']}',
            title: e['title'] as String? ?? '—',
            subtitle: 'Event is live · check in students now',
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
          _AppNotif(
            id: 'event_today_${e['event_id']}',
            title: e['title'] as String? ?? '—',
            subtitle: 'Starting today${t.isNotEmpty ? ' at $t' : ''}',
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
          _AppNotif(
            id: 'event_tomorrow_${e['event_id']}',
            title: e['title'] as String? ?? '—',
            subtitle: 'Starting tomorrow${t.isNotEmpty ? ' at $t' : ''}',
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
          _AppNotif.notice(n),
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
          _photoUrl = orgRow['profile_image_url'] as String?;
          _dailyRegistrations = [for (final v in signups.last7) v.toDouble()];
          _prevDailyRegistrations = [
            for (final v in signups.prev7) v.toDouble(),
          ];
          _regsLast7 = signups.last7.fold(0, (s, v) => s + v);
          _regsPrev7 = signups.prev7.fold(0, (s, v) => s + v);
          _eventAttendance = attendance;
          _nextEvent = nextEvt;
          _hasAnyEvents = allEvents.isNotEmpty;
          _notifs = notifResult;
          _unreadIds = {
            for (final n in notifResult)
              if (!readIds.contains(n.id) && !_seenIds.contains(n.id)) n.id,
          };
          _lastUpdated = DateTime.now();
          _homeLoading = false;
          _dashError = false; // a background refresh can recover the screen
        });
        // The content fades in on first show — including after an error.
        if (!silent || recovering) _staggerCtrl.forward(from: 0);
        _watchEvents(organizerId);
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

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Updated just now';
    if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Updated ${diff.inHours}h ago';
    return 'Updated ${diff.inDays}d ago';
  }

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
            OrganizerProfileScreen(
              isVisible: _selectedIndex == 3,
              onPhotoUpdated: (url) {
                if (mounted) setState(() => _photoUrl = url);
              },
            ),
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
    if (userId == null || _notifs.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final existing = Set<String>.from(
      prefs.getStringList(_prefKey(userId)) ?? [],
    );
    existing.addAll(_notifs.map((n) => n.id));
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
          SliverToBoxAdapter(
            child: _stagger(
              _hasAnyEvents
                  ? _buildAnalyticsSection(t)
                  : _buildEmptyStateCTA(t),
              start: 0.32,
              end: 0.72,
            ),
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
                    const SizedBox(width: 8),
                    _OrgDateChip(t: t),
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
          const SizedBox(width: 10),
          _buildHeaderAvatar(displayName),
          const SizedBox(width: 10),
          _buildBellButton(t),
        ],
      ),
    );
  }

  // ── Header avatar — taps through to the Profile tab ───────────────────────

  Widget _buildHeaderAvatar(String displayName) {
    final initials = displayName
        .trim()
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase())
        .take(2)
        .join();
    final url = _photoUrl;
    final fallback = Center(
      child: Text(
        initials.isEmpty ? 'O' : initials,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = 3),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          gradient: kGoldGradient,
          shape: BoxShape.circle,
          border: Border.all(color: kGold.withValues(alpha: 0.40), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: kGold.withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAliasWithSaveLayer,
        child: (url != null && url.isNotEmpty)
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              )
            : fallback,
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

  void _showNotificationSheet() {
    // Highlight what's new in the sheet, then count everything as read.
    final fresh = {..._unreadIds};
    setState(() {
      _seenIds.addAll(_notifs.map((n) => n.id));
      _unreadIds = {};
    });
    _persistReadState(); // fire-and-forget — survives logout/login
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _NotifSheet(notifs: _notifs, fresh: fresh),
    );
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

  // ══════════════════════════════════════════════════════════════════════════
  // Analytics section
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildAnalyticsSection(AppTk t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAnalyticsHeader(t),
          const SizedBox(height: 16),
          _buildRegistrationsCard(t),
          const SizedBox(height: 14),
          _buildAttendanceCard(t),
        ],
      ),
    );
  }

  // ── Section header ────────────────────────────────────────────────────────

  Widget _buildAnalyticsHeader(AppTk t) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: const Color(0xFF16A34A),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF16A34A).withValues(alpha: 0.50),
                blurRadius: 5,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Analytics',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: t.text,
                  height: 1.1,
                ),
              ),
              Text(
                'Live event performance data',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: t.muted,
                ),
              ),
            ],
          ),
        ),
        if (_lastUpdated != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: t.border),
              boxShadow: [
                BoxShadow(
                  color: t.shadow,
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.access_time_rounded, size: 11, color: t.muted),
                const SizedBox(width: 4),
                Text(
                  _timeAgo(_lastUpdated!),
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    color: t.muted,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── Registrations card: the last 7 days vs. the 7 days before ────────────

  Widget _buildRegistrationsCard(AppTk t) {
    const purple = Color(0xFF7C3AED);
    const indigo = Color(0xFF4F46E5);
    const up = Color(0xFF047857);
    const down = Color(0xFFDC2626);

    // ▲ / ▼ percentage; "New" when the 7 days before had no sign-ups.
    final diff = _regsLast7 - _regsPrev7;
    final String change;
    final Color changeColor;
    final IconData changeIcon;
    if (_regsPrev7 == 0) {
      change = _regsLast7 == 0 ? '—' : 'New';
      changeColor = _regsLast7 == 0 ? t.sub : up;
      changeIcon = _regsLast7 == 0
          ? Icons.trending_flat_rounded
          : Icons.trending_up_rounded;
    } else {
      final pct = (diff / _regsPrev7 * 100).round();
      change = '${pct > 0 ? '+' : ''}$pct%';
      changeColor = pct > 0
          ? up
          : pct < 0
          ? down
          : t.sub;
      changeIcon = pct > 0
          ? Icons.trending_up_rounded
          : pct < 0
          ? Icons.trending_down_rounded
          : Icons.trending_flat_rounded;
    }
    final summary = diff == 0
        ? 'Same number of sign-ups as the 7 days before'
        : '${diff.abs()} ${diff > 0 ? 'more' : 'fewer'} sign-up'
              '${diff.abs() == 1 ? '' : 's'} than the 7 days before';

    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.border),
        boxShadow: [
          BoxShadow(
            color: t.shadow,
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card header ──────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: purple.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.how_to_reg_rounded,
                  color: purple,
                  size: 19,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Registrations',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                    Text(
                      'Last 7 days vs. the 7 days before',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        color: t.sub,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── KPI chips ────────────────────────────────────────────────
          Row(
            children: [
              _kpiChip(
                t: t,
                value: '$_regsLast7',
                label: 'Last 7 days',
                icon: Icons.how_to_reg_rounded,
                color: purple,
              ),
              const SizedBox(width: 10),
              _kpiChip(
                t: t,
                value: '$_regsPrev7',
                label: 'Previous 7 days',
                icon: Icons.history_rounded,
                color: indigo,
              ),
              const SizedBox(width: 10),
              _kpiChip(
                t: t,
                value: change,
                label: 'Change',
                icon: changeIcon,
                color: changeColor,
              ),
            ],
          ),

          if (_regsLast7 + _regsPrev7 > 0) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(changeIcon, size: 15, color: changeColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    summary,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: t.sub,
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),

          // ── Bar chart: each day next to the same weekday a week earlier ─
          SizedBox(height: 185, child: _buildDailyBarChart(t)),

          if (_regsLast7 + _regsPrev7 > 0) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendItem(t: t, color: purple, label: 'Last 7 days'),
                const SizedBox(width: 20),
                _legendItem(
                  t: t,
                  color: purple.withValues(alpha: 0.25),
                  label: 'Previous 7 days',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Bar chart: last 7 days (solid) beside the 7 days before (light) ─────

  Widget _buildDailyBarChart(AppTk t) {
    const purple = Color(0xFF7C3AED);
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = DateTime.now();
    // Index 6 is today; the light bar at index i is 7 days earlier.
    String label(int i) => i == 6
        ? 'Today'
        : weekdays[now.subtract(Duration(days: 6 - i)).weekday - 1];
    final rawMax = [
      ..._dailyRegistrations,
      ..._prevDailyRegistrations,
    ].reduce(max);
    final barMaxY = max(rawMax + 1.5, 5.0);

    if (rawMax == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: purple.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.bar_chart_rounded,
                size: 30,
                color: purple,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'No sign-ups in the last 14 days',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: t.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Appears once students sign up',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: t.sub,
              ),
            ),
          ],
        ),
      );
    }

    LinearGradient empty() => LinearGradient(
      colors: [
        Colors.grey.withValues(alpha: 0.10),
        Colors.grey.withValues(alpha: 0.18),
      ],
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
    );

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: barMaxY,
        minY: 0,
        barGroups: List.generate(7, (i) {
          final value = _dailyRegistrations[i];
          final before = _prevDailyRegistrations[i];
          return BarChartGroupData(
            x: i,
            barsSpace: 3,
            // The day's number above its (solid) bar.
            showingTooltipIndicators: value > 0 ? [1] : [],
            barRods: [
              // The same weekday a week earlier.
              BarChartRodData(
                toY: before > 0 ? before : 0.18,
                gradient: before > 0
                    ? LinearGradient(
                        colors: [
                          purple.withValues(alpha: 0.16),
                          purple.withValues(alpha: 0.30),
                        ],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      )
                    : empty(),
                width: 11,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(5),
                ),
              ),
              BarChartRodData(
                toY: value > 0 ? value : 0.18,
                gradient: value > 0
                    ? LinearGradient(
                        colors: [
                          purple.withValues(alpha: 0.55),
                          purple.withValues(alpha: 0.95),
                        ],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      )
                    : empty(),
                width: 13,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                ),
              ),
            ],
          );
        }),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i > 6) return const SizedBox();
                final isToday = i == 6;
                return SideTitleWidget(
                  meta: meta,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isToday ? kGold : Colors.transparent,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        label(i),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          fontWeight: isToday
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: isToday ? t.text : t.sub,
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
              interval: max(1, (barMaxY / 4).ceilToDouble()),
              getTitlesWidget: (value, meta) {
                if (value == meta.max) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    value.toInt().toString(),
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 9,
                      color: t.sub,
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
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: t.divider, strokeWidth: 1, dashArray: [4, 4]),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF1C1814),
            tooltipBorder: const BorderSide(color: Color(0xFF2C2419)),
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 3,
            ),
            tooltipMargin: 4,
            // One small number per day, over the solid (last 7 days) bar.
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              if (rodIndex != 1) return null;
              final v = _dailyRegistrations[group.x].toInt();
              if (v <= 0) return null;
              return BarTooltipItem(
                '$v',
                const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              );
            },
          ),
        ),
      ),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );
  }

  // ── Attendance card (white + blue) ────────────────────────────────────────

  Widget _buildAttendanceCard(AppTk t) {
    const blue = Color(0xFF2563EB);

    final totalCheckedIn = _eventAttendance.fold<int>(
      0,
      (s, e) => s + (e['checkedIn'] as int),
    );
    final totalRegistered = _eventAttendance.fold<int>(
      0,
      (s, e) => s + (e['total'] as int),
    );
    // Checked in out of registered. Capacity is now the whole student body,
    // so measuring against it would make a full event look poorly attended.
    final rate = totalRegistered > 0
        ? (totalCheckedIn / totalRegistered * 100).round()
        : 0;
    final rateColor = rate >= 70
        ? const Color(0xFF16A34A)
        : rate >= 40
        ? kGold
        : const Color(0xFFDC2626);

    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.border),
        boxShadow: [
          BoxShadow(
            color: t.shadow,
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card header ──────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: blue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.people_alt_rounded,
                  color: blue,
                  size: 19,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Event Attendance',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                    Text(
                      'Attendance per event · last 5 past events',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        color: t.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── KPI chips ────────────────────────────────────────────────
          Row(
            children: [
              _kpiChip(
                t: t,
                value: '$totalCheckedIn',
                label: 'Checked In',
                icon: Icons.check_circle_rounded,
                color: blue,
              ),
              const SizedBox(width: 10),
              _kpiChip(
                t: t,
                value: '$rate%',
                label: 'Avg Rate',
                icon: Icons.trending_up_rounded,
                color: rateColor,
              ),
            ],
          ),

          if (_eventAttendance.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Overall attendance',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: t.sub,
                  ),
                ),
                Text(
                  '$rate%',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: rateColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: TweenAnimationBuilder<double>(
                tween: Tween(
                  begin: 0,
                  end: totalRegistered > 0
                      ? totalCheckedIn / totalRegistered
                      : 0.0,
                ),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOut,
                builder: (_, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 6,
                  backgroundColor: t.divider,
                  valueColor: AlwaysStoppedAnimation<Color>(rateColor),
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),
          _buildAttendanceBreakdown(t),
        ],
      ),
    );
  }

  Widget _kpiChip({
    required AppTk t,
    required String value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 11, 10, 11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: color.withValues(alpha: 0.16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 15),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: color,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 9,
                color: t.muted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendItem({
    required AppTk t,
    required Color color,
    required String label,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: t.muted),
        ),
      ],
    );
  }

  // ── Per-event attendance breakdown (horizontal progress rows) ───────────

  Widget _buildAttendanceBreakdown(AppTk t) {
    const blue = Color(0xFF2563EB);
    const green = Color(0xFF16A34A);
    const red = Color(0xFFDC2626);

    if (_eventAttendance.isEmpty) {
      return Column(
        children: [
          const SizedBox(height: 8),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: blue.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.people_alt_rounded,
                    size: 26,
                    color: blue,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'No attendance data yet',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Appears after your first check-in',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: t.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      );
    }

    return Column(
      children: _eventAttendance.asMap().entries.map((entry) {
        final idx = entry.key;
        final e = entry.value;
        final total = e['total'] as int;
        final checkedIn = e['checkedIn'] as int;
        final title = e['title'] as String;
        final dateLabel = (e['label'] as String).replaceAll('\n', ' ');
        final rate = total > 0 ? (checkedIn / total * 100).round() : 0;
        final rateColor = rate >= 70
            ? green
            : rate >= 40
            ? kGold
            : red;
        final fraction = total > 0 ? (checkedIn / total).clamp(0.0, 1.0) : 0.0;

        return Padding(
          padding: EdgeInsets.only(
            bottom: idx < _eventAttendance.length - 1 ? 14 : 0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: rateColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: t.text,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          dateLabel,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10,
                            color: t.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: rateColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: rateColor.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          '$rate%',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: rateColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        total > 0 ? '$checkedIn / $total' : '$checkedIn',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: t.muted,
                        ),
                      ),
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
                    minHeight: 6,
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

  // ── Empty dashboard CTA (shown to new organizers with no events) ─────────

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
                onTap: () => setState(() => _selectedIndex = 0),
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

// ── Notification bottom sheet (mobile) ────────────────────────────────────────

class _NotifSheet extends StatelessWidget {
  final List<_AppNotif> notifs;

  /// Unread when the sheet opened — highlighted.
  final Set<String> fresh;
  const _NotifSheet({required this.notifs, this.fresh = const {}});

  @override
  Widget build(BuildContext context) {
    final t = AppTk(Theme.of(context).brightness == Brightness.dark);

    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: t.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.notifications_rounded, size: 18, color: t.text),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Notifications',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                  ),
                  Text(
                    fresh.isNotEmpty
                        ? '${fresh.length} new'
                        : 'Recent activity',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: fresh.isNotEmpty
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: t.sub,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: t.divider),
            // Content
            if (notifs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 36,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle_outline_rounded,
                        size: 26,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      "You're all caught up!",
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: t.text,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Admin approvals, sign-ups and event reminders show up here.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: t.sub,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.65,
                ),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shrinkWrap: true,
                  itemCount: notifs.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: t.divider),
                  itemBuilder: (_, i) => _buildItem(notifs[i], t),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(_AppNotif n, AppTk t) {
    final isNew = fresh.contains(n.id);
    return Container(
      color: isNew ? kGold.withValues(alpha: t.dark ? 0.10 : 0.07) : null,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: n.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(n.icon, size: 19, color: n.color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        n.title,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: t.text,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (n.at != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        noticeTimeAgo(n.at!),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10.5,
                          color: t.sub,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                // Admin decisions carry the reason — show it in full.
                Text(
                  n.subtitle,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11.5,
                    height: 1.45,
                    color: t.sub,
                  ),
                  maxLines: n.at != null ? 6 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (isNew)
            Padding(
              padding: const EdgeInsets.only(left: 10, top: 6),
              child: Semantics(
                label: 'New',
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: kGold,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Date chip (matches student dashboard style) ───────────────────────────────

class _OrgDateChip extends StatelessWidget {
  final AppTk t;
  const _OrgDateChip({required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: kGold.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kGold.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_today_rounded, size: 9, color: kGold),
          const SizedBox(width: 4),
          Text(
            _todayFormatted(),
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: kGold,
            ),
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

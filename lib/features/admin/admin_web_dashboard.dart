import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_colors.dart';
import '../../core/theme_store.dart';
import '../../core/services/event_archive_service.dart';
import '../../core/services/supabase_service.dart';
import '../organizer/web/web_shared.dart';
import '../../shared/widgets/event_phase_pill.dart';
import 'admin_shared.dart';
import 'admin_web_students.dart';
import 'admin_web_organizers.dart';
import 'admin_web_events.dart';
import 'admin_web_registrations.dart';
import 'admin_web_announcements.dart';
import 'admin_web_archives.dart';
import 'admin_web_logs.dart';

// ─── Admin palette ────────────────────────────────────────────────────────────
// kAdminAccent now lives in admin_shared.dart (shared by every tab file);
// kept as a local const alias so the many existing `_kAccent` references in
// this file's shell/overview code don't all need touching.
const _kAccent = kAdminAccent;

// Admin web content now uses the shared `WebTk` token class (in
// organizer/web/web_layout.dart, imported transitively via web_shared.dart
// below) so the admin and organizer web dashboards render an identical dark
// theme — a cool graphite "SaaS dashboard" look, deliberately different from
// the warm espresso/gold `AppTk` dark mode used by the mobile apps.

// Sidebar tokens — light mode is a pure-white panel with the organizer web's
// nav styling; dark is the same cool graphite family as WebTk, a shade
// darker than the content canvas for a layered nav → page → card hierarchy.
class _STk {
  final bool dark;
  const _STk(this.dark);
  Color get top      => dark ? const Color(0xFF080A0E) : Colors.white;
  Color get mid      => dark ? const Color(0xFF0A0C11) : Colors.white;
  Color get bot      => dark ? const Color(0xFF0D0F15) : Colors.white;
  Color get border   => dark ? const Color(0xFF1C212B) : const Color(0xFFCBD5E1);
  Color get navText  => dark ? const Color(0xFFE4E7EC) : const Color(0xFF3A3324);
  Color get navIcon  => dark ? const Color(0xFF7E8695) : const Color(0xFF6B5E47);
  Color get navLabel => dark ? const Color(0xFF565E6C) : const Color(0xFF7A6A52);
  LinearGradient get grad => LinearGradient(
    colors: [top, mid, bot],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

// ─── Navigation ───────────────────────────────────────────────────────────────
// AdminPage enum now lives in admin_shared.dart (shared by every tab file);
// the sidebar's groups are _navGroups in the shell state.

// ═════════════════════════════════════════════════════════════════════════════
// Shell
// ═════════════════════════════════════════════════════════════════════════════

class AdminWebDashboard extends StatefulWidget {
  const AdminWebDashboard({super.key});
  @override
  State<AdminWebDashboard> createState() => _AdminWebDashboardState();
}

class _AdminWebDashboardState extends State<AdminWebDashboard>
    with SingleTickerProviderStateMixin {
  AdminPage _page      = AdminPage.overview;
  // Sidebar left collapsed on wide / medium windows (WebNavPrefs).
  bool      _collapsedWide   = false;
  bool      _collapsedMedium = true;
  final     _scaffoldKey = GlobalKey<ScaffoldState>();
  bool      _loading   = true;
  bool      _error     = false;
  String?   _name;

  // Live "needs review" count shown as a badge on the Events nav item —
  // kept at the shell level (not inside AdminEventsPage) so it's visible
  // from every tab, not just once you've already clicked into Events.
  int              _pendingEventsCount = 0;
  RealtimeChannel? _eventsChannel;
  Timer?           _eventsDebounce;

  // Events ready to archive, on the Archives nav item. The loaded events are
  // kept so the number follows the clock (an event becomes ready when its
  // check-in closes) between loads.
  ArchiveReadiness? _readiness;
  int               _readyToArchive = 0;
  Timer?            _archiveClock;

  late final AnimationController _entryCt;
  late final Animation<double>   _sidebarFade;
  late final Animation<Offset>   _sidebarSlide;
  late final Animation<double>   _topbarFade;
  late final Animation<Offset>   _topbarSlide;
  late final Animation<double>   _contentFade;

  @override
  void initState() {
    super.initState();
    _entryCt = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 520));
    _sidebarFade  = CurvedAnimation(parent: _entryCt,
        curve: const Interval(0.00, 0.65, curve: Curves.easeOut));
    _sidebarSlide = Tween<Offset>(begin: const Offset(-0.04, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryCt,
            curve: const Interval(0.00, 0.65, curve: Curves.easeOutCubic)));
    _topbarFade   = CurvedAnimation(parent: _entryCt,
        curve: const Interval(0.00, 0.60, curve: Curves.easeOut));
    _topbarSlide  = Tween<Offset>(begin: const Offset(0, -0.65), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryCt,
            curve: const Interval(0.00, 0.60, curve: Curves.easeOutCubic)));
    _contentFade  = CurvedAnimation(parent: _entryCt,
        curve: const Interval(0.12, 0.78, curve: Curves.easeOut));
    _loadProfile();
    WebNavPrefs.load('admin').then((v) {
      if (mounted) {
        setState(() { _collapsedWide = v.wide; _collapsedMedium = v.medium; });
      }
    });
  }

  @override
  void dispose() {
    _entryCt.dispose();
    _eventsDebounce?.cancel();
    _archiveClock?.cancel();
    if (_eventsChannel != null) SupabaseService.client.removeChannel(_eventsChannel!);
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) { _goLogin(); return; }
      final row = await SupabaseService.client
          .from('admins').select('full_name').eq('user_id', user.id).maybeSingle();
      if (!mounted) return;
      if (row == null) { _goLogin(); return; }
      await ThemeStore.loadForUser(user.id, 'admin');
      setState(() { _name = row['full_name'] as String?; _loading = false; });
      _entryCt.forward();
      _loadPendingEventsCount();
      _loadReadyToArchive();
      _subscribePendingEvents();
      _archiveClock = Timer.periodic(const Duration(minutes: 1), (_) => _recountReady());
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  Future<void> _loadPendingEventsCount() async {
    try {
      // Pending events that reached their start without a decision are
      // rejected automatically. Settle them first so they leave the queue.
      try {
        await SupabaseService.client.rpc('reject_unreviewed_events');
      } catch (_) {} // migration 202610210001 not run yet: left out below
      final rows = await SupabaseService.client
          .from('events')
          .select()
          .eq('approval_status', 'pending');
      final waiting = List<Map<String, dynamic>>.from(rows as List)
          .where((e) => !pendingPastStart(e))
          .length;
      // Edits to live events waiting for review — counted separately so a
      // missing event_revisions table (migration 007 not run) can't zero the badge.
      var changes = 0;
      try {
        final revs = await SupabaseService.client
            .from('event_revisions')
            .select('id')
            .eq('status', 'pending');
        changes = (revs as List).length;
      } catch (_) {}
      if (mounted) setState(() => _pendingEventsCount = waiting + changes);
    } catch (_) {
      // Badge is a convenience indicator, not the source of truth — the
      // Events tab's own load still surfaces a real error if this table is
      // genuinely unreachable, so this failure can stay silent.
    }
  }

  Future<void> _loadReadyToArchive() async {
    try {
      _readiness = await EventArchiveService.loadReadiness();
      _recountReady();
    } catch (_) {
      // A convenience number like the Events badge: the Archives tab shows
      // the real list (and any error) itself.
    }
  }

  void _recountReady() {
    final n = _readiness?.readyCount() ?? 0;
    if (mounted && n != _readyToArchive) setState(() => _readyToArchive = n);
  }

  void _subscribePendingEvents() {
    _eventsChannel = SupabaseService.client.channel('admin-shell-pending-events');
    for (final table in ['events', 'event_revisions']) {
      _eventsChannel!.on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(event: '*', schema: 'public', table: table),
        (_, [_]) {
          _eventsDebounce?.cancel();
          _eventsDebounce = Timer(const Duration(milliseconds: 600), () {
            if (!mounted) return;
            _loadPendingEventsCount();
            _loadReadyToArchive();
          });
        },
      );
    }
    _eventsChannel!.subscribe();
  }

  void _goLogin() {
    if (mounted) Navigator.of(context).pushReplacementNamed('/');
  }

  Future<void> _signOut() async {
    final ok = await WebAlert.confirm(
      context: context, title: 'Sign Out?',
      message: 'You will be returned to the login screen.',
      confirmLabel: 'Sign Out',
      icon: Icons.logout_rounded,
    );
    if (ok != true) return;
    await SupabaseService.client.auth.signOut();
    if (!mounted) return;
    await Swal.fire(
      context,
      icon: SwalIcon.success,
      title: 'Signed out',
      text: 'You have been signed out successfully.',
      showConfirmButton: false,
      timer: const Duration(milliseconds: 1200),
      timerProgressBar: true,
      allowOutsideClick: false,
    );
    if (mounted) _goLogin();
  }

  void _navigate(AdminPage p) => setState(() => _page = p);

  bool _collapsedFor(WebNavLayout layout) => switch (layout) {
    WebNavLayout.wide   => _collapsedWide,
    WebNavLayout.medium => _collapsedMedium,
    WebNavLayout.drawer => false,
  };

  // « Collapse / » Expand, remembered per browser.
  void _toggleCollapse(WebNavLayout layout) {
    final next = !_collapsedFor(layout);
    setState(() {
      if (layout == WebNavLayout.wide) {
        _collapsedWide = next;
      } else {
        _collapsedMedium = next;
      }
    });
    WebNavPrefs.save('admin', layout, next);
  }

  // Dark mode from the account menu.
  Future<void> _toggleTheme() async {
    try {
      await ThemeStore.toggle();
    } catch (e) {
      if (mounted) adminErrorAlert(context, e, title: 'Couldn’t save theme preference');
    }
  }

  static const _pageTitles = <AdminPage, String>{
    AdminPage.overview:      'Dashboard',
    AdminPage.students:      'Students',
    AdminPage.organizers:    'Organizers',
    AdminPage.events:        'Events',
    AdminPage.registrations: 'Registrations',
    AdminPage.announcements: 'Announcements',
    AdminPage.archives:      'Archives',
    AdminPage.logs:          'Logs',
  };

  // Dashboard, then EVENTS, PEOPLE and RECORDS — the layout the user chose.
  List<WebNavGroup<AdminPage>> get _navGroups {
    final review = _pendingEventsCount;
    final ready  = _readyToArchive;
    return [
      const WebNavGroup(entries: [
        WebNavEntry(
          page: AdminPage.overview,
          icon: Icons.dashboard_rounded,
          label: 'Dashboard',
        ),
      ]),
      WebNavGroup(title: 'Events', entries: [
        WebNavEntry(
          page: AdminPage.events,
          icon: Icons.event_rounded,
          label: 'Events',
          badge: review,
          badgeTip: review == 1
              ? '1 event or change waiting for your review'
              : '$review events or changes waiting for your review',
        ),
        const WebNavEntry(
          page: AdminPage.registrations,
          icon: Icons.how_to_reg_rounded,
          label: 'Registrations',
        ),
        const WebNavEntry(
          page: AdminPage.announcements,
          icon: Icons.campaign_rounded,
          label: 'Announcements',
        ),
      ]),
      const WebNavGroup(title: 'People', entries: [
        WebNavEntry(
          page: AdminPage.students,
          icon: Icons.people_rounded,
          label: 'Students',
        ),
        WebNavEntry(
          page: AdminPage.organizers,
          icon: Icons.badge_rounded,
          label: 'Organizers',
        ),
      ]),
      WebNavGroup(title: 'Records', entries: [
        WebNavEntry(
          page: AdminPage.archives,
          icon: Icons.inventory_2_rounded,
          label: 'Archives',
          badge: ready,
          badgeTip: ready == 1
              ? '1 event ready to archive'
              : '$ready events ready to archive',
        ),
        const WebNavEntry(
          page: AdminPage.logs,
          icon: Icons.history_rounded,
          label: 'Logs',
        ),
      ]),
    ];
  }

  // [onClose]: the drawer — choosing a page closes it.
  Widget _sideNav({
    required bool collapsed,
    VoidCallback? onToggleCollapse,
    VoidCallback? onClose,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final s    = _STk(dark);
    return WebSideNav<AdminPage>(
      portalLabel:      'Admin console',
      groups:           _navGroups,
      current:          _page,
      collapsed:        collapsed,
      headerHeight:     kWebTopH,
      onToggleCollapse: onToggleCollapse,
      onClose:          onClose,
      logoFallbackIcon: Icons.admin_panel_settings_rounded,
      onSelect: (page) {
        onClose?.call();
        _navigate(page);
      },
      palette: WebNavPalette(
        background:   s.grad,
        border:       s.border,
        text:         s.navText,
        activeText:   dark ? Colors.white : kText,
        icon:         s.navIcon,
        // Group titles readable on the dark sidebar too (4.5:1).
        label:        dark ? const Color(0xFF8E97A5) : s.navLabel,
        hover:        dark ? Colors.white.withValues(alpha: 0.07) : const Color(0xFFF1F5F9),
        accent:       _kAccent,
        accentStrong: dark ? const Color(0xFFFB923C) : const Color(0xFFC2410C),
        focus:        dark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final t    = WebTk(dark);
    if (_loading) {
      return Scaffold(
        backgroundColor: t.bg,
        body: const Center(child: CircularProgressIndicator(color: _kAccent)),
      );
    }
    if (_error) {
      return Scaffold(
        backgroundColor: t.bg,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2), shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFFCA5A5), width: 1.5),
              ),
              child: const Icon(Icons.cloud_off_rounded, color: Color(0xFFEF4444), size: 34),
            ),
            const SizedBox(height: 20),
            Text('Could not load admin profile',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 17,
                  fontWeight: FontWeight.w800, color: t.text)),
            const SizedBox(height: 8),
            Text('Check your connection and try again.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.sub)),
            const SizedBox(height: 28),
            WebBtn(label: 'Retry', icon: Icons.refresh_rounded, onTap: () {
              setState(() { _error = false; _loading = true; });
              _loadProfile();
            }),
          ]),
        ),
      );
    }

    // Wide: the sidebar (or its icon rail); narrow: no sidebar, a menu button
    // in the top bar opens it as a drawer.
    final layout    = webNavLayoutFor(MediaQuery.sizeOf(context).width);
    final drawer    = layout == WebNavLayout.drawer;
    final collapsed = _collapsedFor(layout);
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: t.bg,
      drawer: drawer
          ? Drawer(
              width: 288,
              backgroundColor: Colors.transparent,
              shape: const RoundedRectangleBorder(),
              child: _sideNav(
                collapsed: false,
                onClose: () => _scaffoldKey.currentState?.closeDrawer(),
              ),
            )
          : null,
      body: Row(children: [
        if (!drawer)
          FadeTransition(
            opacity: _sidebarFade,
            child: SlideTransition(
              position: _sidebarSlide,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                width: collapsed ? kWebSideWc : kWebSideW,
                child: _sideNav(
                  collapsed: collapsed,
                  onToggleCollapse: () => _toggleCollapse(layout),
                ),
              ),
            ),
          ),
        Expanded(
          child: Column(children: [
            ClipRect(
              child: SlideTransition(
                position: _topbarSlide,
                child: FadeTransition(
                  opacity: _topbarFade,
                  child: _AdminTopBar(
                    title:         _pageTitles[_page] ?? '',
                    name:          _name,
                    compact:       drawer,
                    onMenuTap:     drawer
                        ? () => _scaffoldKey.currentState?.openDrawer()
                        : null,
                    onToggleTheme: _toggleTheme,
                    onSignOut:     _signOut,
                  ),
                ),
              ),
            ),
            Expanded(
              child: FadeTransition(
                opacity: _contentFade,
                child: _buildPage(),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildPage() => switch (_page) {
    AdminPage.overview       => _AdminOverviewPage(onNavigate: _navigate),
    AdminPage.students       => const AdminStudentsPage(),
    AdminPage.organizers     => const AdminOrganizersPage(),
    AdminPage.events         => const AdminEventsPage(),
    AdminPage.registrations  => const AdminRegistrationsPage(),
    AdminPage.announcements  => const AdminAnnouncementsPage(),
    AdminPage.archives       => const AdminArchivesPage(),
    AdminPage.logs           => const AdminLogsPage(),
  };
}

// ═════════════════════════════════════════════════════════════════════════════
// Top bar
// ═════════════════════════════════════════════════════════════════════════════

// Page title and the account menu (Dark mode, Sign out). On a narrow window a
// menu button opens the sidebar as a drawer.
class _AdminTopBar extends StatelessWidget {
  final String        title;
  final String?       name;
  /// Narrow window: the account button shows only the initials.
  final bool          compact;
  /// Set on narrow windows: opens the sidebar drawer.
  final VoidCallback? onMenuTap;
  final VoidCallback  onToggleTheme;
  final VoidCallback  onSignOut;

  const _AdminTopBar({
    required this.title,
    required this.name,
    required this.compact,
    this.onMenuTap,
    required this.onToggleTheme,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final avatar = Container(
      width: 34, height: 34,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFC2410C), _kAccent, Color(0xFFF97316)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
      ),
      child: Center(child: Text(_initials(name),
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
            fontWeight: FontWeight.w700, color: Colors.white))),
    );
    return Container(
      height: kWebTopH,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 20),
      decoration: BoxDecoration(
        color: t.card,
        border: Border(bottom: BorderSide(color: t.border)),
        boxShadow: [BoxShadow(color: t.shadow, blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        if (onMenuTap != null) ...[
          IconButton(
            onPressed: onMenuTap,
            tooltip: 'Open menu',
            icon: Icon(Icons.menu_rounded, size: 20, color: t.sub),
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 17,
                  fontWeight: FontWeight.w700, color: t.text)),
          ),
        ),
        ValueListenableBuilder<ThemeMode>(
          valueListenable: ThemeStore.notifier,
          builder: (_, mode, _) => WebAccountMenu(
            name:    name ?? 'Administrator',
            role:    'Administrator',
            avatar:  avatar,
            accent:  _kAccent,
            compact: compact,
            actions: [
              WebAccountAction(
                icon: Icons.dark_mode_outlined,
                label: 'Dark mode',
                toggled: mode == ThemeMode.dark,
                onSelected: onToggleTheme,
              ),
              WebAccountAction(
                icon: Icons.logout_rounded,
                label: 'Sign out',
                danger: true,
                onSelected: onSignOut,
              ),
            ],
          ),
        ),
      ]),
    );
  }

  static String _initials(String? name) {
    final i = (name ?? 'Admin').trim().split(' ')
        .where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).take(2).join();
    return i.isEmpty ? 'A' : i;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Overview page
// ═════════════════════════════════════════════════════════════════════════════

class _TopEvent {
  final String title;
  final int    count;
  final int    capacity;
  const _TopEvent({required this.title, required this.count, required this.capacity});
}

class _AdminOverviewPage extends StatefulWidget {
  final ValueChanged<AdminPage> onNavigate;
  const _AdminOverviewPage({required this.onNavigate});
  @override State<_AdminOverviewPage> createState() => _AdminOverviewPageState();
}

class _AdminOverviewPageState extends State<_AdminOverviewPage> {
  bool      _loading = true;
  bool      _dashError = false;
  DateTime? _chartWindowStart;

  int    _studentTotal = 0, _studentActive = 0;
  int    _orgTotal = 0, _orgActive = 0;
  int    _eventTotal = 0, _eventUpcoming = 0;
  int    _regTotal = 0;
  double _checkInRate = 0;

  List<double>               _weeklyRegs     = List.filled(7, 0);
  List<double>               _monthlyRegs    = List.filled(30, 0);
  int                        _chartDays      = 7;
  List<double>               _weeklyEvents   = List.filled(7, 0);
  List<_TopEvent>            _topEvents      = [];
  List<Map<String, dynamic>> _recentRegs     = [];
  List<Map<String, dynamic>> _upcomingEvents = [];

  RealtimeChannel? _channel;
  Timer?           _debounce;

  @override
  void initState() { super.initState(); _load(); _subscribeRealtime(); }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_channel != null) SupabaseService.client.removeChannel(_channel!);
    super.dispose();
  }

  void _subscribeRealtime() {
    _channel = SupabaseService.client.channel('admin-overview');
    for (final table in ['students', 'organizers', 'events', 'registrations']) {
      _channel!.on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(event: '*', schema: 'public', table: table),
        (_, [__]) => _debounceLoad(),
      );
    }
    _channel!.subscribe();
  }

  void _debounceLoad() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted) _load(silent: true);
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (mounted) setState(() { if (!silent) _loading = true; _dashError = false; });
    try {
      final client  = SupabaseService.client;
      final results = await Future.wait([
        client.from('students').select('is_active'),
        client.from('organizers').select('is_active'),
        // Only approved events count toward Overview's stats/lists — a
        // still-pending submission (see the Events tab's approval queue)
        // isn't live yet and would otherwise inflate Total/Upcoming and
        // show up in the Upcoming Events tile indistinguishable from a
        // real, student-visible event.
        client.from('events')
            .select('event_id, title, event_status, approval_status, archived_at, event_date, '
                'end_date, start_time, end_time, current_participants, organizers(full_name)')
            .eq('approval_status', 'approved')
            .order('event_date', ascending: true),
      ]);

      // Two lightweight reg queries in parallel:
      // 1. Stat counts — 3 columns, all rows (much less data than full rows)
      // 2. Recent 10 — full display columns, limited (for activity feed)
      List<Map<String, dynamic>> statsRegs = [], recentRows = [];
      try {
        final regResults = await Future.wait([
          client.from('registrations')
              .select('status, registered_at, checked_in_at'),
          client.from('registrations')
              .select('student_name, event_title, status, registered_at')
              .order('registered_at', ascending: false)
              .limit(10),
        ]);
        statsRegs  = List<Map<String, dynamic>>.from(regResults[0] as List);
        recentRows = List<Map<String, dynamic>>.from(regResults[1] as List);
      } catch (_) {}

      if (!mounted) return;

      final students = results[0] as List;
      final orgs     = results[1] as List;
      final events   = List<Map<String, dynamic>>.from(results[2] as List);

      final now       = DateTime.now();
      final todayMid  = DateTime(now.year, now.month, now.day);
      final weekStart = todayMid.subtract(const Duration(days: 6));
      final studentActive = students.where((s) => s['is_active'] == true).length;
      final orgActive     = orgs.where((o) => o['is_active'] == true).length;

      // ── Event stats ───────────────────────────────────────────────────
      // By the clock: the stored event_status only records a cancellation,
      // so it says "upcoming" for ended (and archived) events too.
      final upcomingList  = upcomingApprovedEvents(events);
      final upcomingCount = upcomingList.length;

      // ── Registration stats ────────────────────────────────────────────
      final checkedInTotal = statsRegs.where((r) => r['status'] == 'checked_in').length;
      // Declined registrations don't count as registered (countsAsRegistered).
      final countedRegs    = statsRegs.where(countsAsRegistered).length;
      final checkInRate    = countedRegs == 0 ? 0.0 : checkedInTotal / countedRegs * 100;

      final weeklyRegs  = List<double>.filled(7, 0);
      final monthlyRegs = List<double>.filled(30, 0);
      final monthStart  = todayMid.subtract(const Duration(days: 29));
      for (final r in statsRegs) {
        final regStr = r['registered_at'] as String?;
        if (regStr != null) {
          try {
            final d    = DateTime.parse(regStr).toLocal();
            final dMid = DateTime(d.year, d.month, d.day);
            if (!dMid.isBefore(weekStart) && !dMid.isAfter(todayMid)) {
              weeklyRegs[dMid.difference(weekStart).inDays]++;
            }
            if (!dMid.isBefore(monthStart) && !dMid.isAfter(todayMid)) {
              monthlyRegs[dMid.difference(monthStart).inDays]++;
            }
          } catch (_) {}
        }
      }

      // ── Per-day event counts (by event_date, last 7 days) ────────────
      final weeklyEvents = List<double>.filled(7, 0);
      for (final e in events) {
        final dStr = e['event_date'] as String?;
        if (dStr != null) {
          try {
            final d    = DateTime.parse(dStr);
            final dMid = DateTime(d.year, d.month, d.day);
            if (!dMid.isBefore(weekStart) && !dMid.isAfter(todayMid)) {
              weeklyEvents[dMid.difference(weekStart).inDays]++;
            }
          } catch (_) {}
        }
      }

      // ── Top 5 events by registration count ───────────────────────────
      // Top 5 events by current_participants — already in events query, no extra reg fetch needed
      final topEvents = (events
          .where((e) => (e['current_participants'] as int? ?? 0) > 0)
          .toList()
            ..sort((a, b) => (b['current_participants'] as int? ?? 0)
                .compareTo(a['current_participants'] as int? ?? 0)))
          .take(5)
          .map((e) => _TopEvent(
              title:    e['title'] as String? ?? '—',
              count:    e['current_participants'] as int? ?? 0,
              // Every event's capacity is the active student count.
              capacity: studentActive))
          .toList();

      if (mounted) {
        setState(() {
          _studentTotal   = students.length;
          _studentActive  = studentActive;
          _orgTotal       = orgs.length;
          _orgActive      = orgActive;
          _eventTotal     = events.length;
          _eventUpcoming  = upcomingCount;
          _regTotal       = statsRegs.length;
          _checkInRate    = checkInRate;
          _weeklyRegs     = weeklyRegs;
          _monthlyRegs    = monthlyRegs;
          _weeklyEvents   = weeklyEvents;
          _topEvents      = topEvents;
          _recentRegs       = recentRows;
          _upcomingEvents   = upcomingList.take(4).toList();
          _chartWindowStart = weekStart;
          _loading          = false;
        });
      }
    } catch (e) {
      debugPrint('AdminOverview load error: $e');
      if (mounted) setState(() { _loading = false; _dashError = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    if (_loading) return const Center(child: CircularProgressIndicator(color: _kAccent));
    if (_dashError) return _buildDashError(t);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(kWebPad),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildHeader(t),
        const SizedBox(height: 20),
        _buildKpiRow(t),
        const SizedBox(height: 20),
        _buildChartsRow(t),
        const SizedBox(height: 20),
        _buildBottomRow(t),
        const SizedBox(height: 20),
        _buildRecentRegs(t),
        const SizedBox(height: 16),
      ]),
    );
  }

  // ── Photo review alert ──────────────────────────────────────────────────────


  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(WebTk t) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Dashboard Overview',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 22,
            fontWeight: FontWeight.w800, color: t.text)),
    ]);
  }

  // ── KPI row ────────────────────────────────────────────────────────────────

  Widget _buildKpiRow(WebTk t) => Row(children: [
    Expanded(child: AdminKpiCard(
      icon: Icons.people_rounded, color: _kAccent,
      label: 'Total Students', value: '$_studentTotal',
      subtitle: '$_studentActive Active',
      subtitleColor: const Color(0xFF10B981),
      onTap: () => widget.onNavigate(AdminPage.students),
    )),
    const SizedBox(width: 14),
    Expanded(child: AdminKpiCard(
      icon: Icons.badge_rounded, color: kGold,
      label: 'Organizers', value: '$_orgTotal',
      subtitle: '$_orgActive Active',
      subtitleColor: const Color(0xFF10B981),
      onTap: () => widget.onNavigate(AdminPage.organizers),
    )),
    const SizedBox(width: 14),
    Expanded(child: AdminKpiCard(
      icon: Icons.event_rounded, color: const Color(0xFF10B981),
      label: 'Total Events', value: '$_eventTotal',
      subtitle: '$_eventUpcoming Upcoming / Ongoing',
      subtitleColor: _kAccent,
      onTap: () => widget.onNavigate(AdminPage.events),
    )),
    const SizedBox(width: 14),
    Expanded(child: AdminKpiCard(
      icon: Icons.how_to_reg_rounded, color: const Color(0xFF8B5CF6),
      label: 'Registrations', value: '$_regTotal',
      subtitle: '${_checkInRate.toStringAsFixed(0)}% Check-in Rate',
      subtitleColor: _checkInRate >= 70
          ? const Color(0xFF10B981)
          : _checkInRate >= 40
              ? const Color(0xFFF59E0B)
              : const Color(0xFFEF4444),
      onTap: () => widget.onNavigate(AdminPage.registrations),
    )),
  ]);

  // ── Today snapshot row ───────────────────────────────────────────────────────


  // ── Charts row ─────────────────────────────────────────────────────────────

  Widget _buildChartsRow(WebTk t) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Expanded(
      flex: 3,
      child: WebCard(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Registration Trend',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                      fontWeight: FontWeight.w700, color: t.text)),
                const SizedBox(height: 2),
                Text('Daily sign-ups · Last ${_chartDays == 7 ? '7 days' : '30 days'}',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.sub)),
              ])),
              _ChartWindowToggle(
                selected: _chartDays,
                onSelect: (v) => setState(() => _chartDays = v),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          SizedBox(height: 220, child: _RegTrendChart(
            dailyRegs:   _chartDays == 7 ? _weeklyRegs : _monthlyRegs,
            windowStart: _chartDays == 7
                ? (_chartWindowStart ?? DateTime.now().subtract(const Duration(days: 6)))
                : DateTime.now().subtract(const Duration(days: 29)),
          )),
          const SizedBox(height: 12),
        ]),
      ),
    ),
    const SizedBox(width: 16),
    Expanded(
      flex: 2,
      child: WebCard(
        padding: const EdgeInsets.all(22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Events This Week',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                fontWeight: FontWeight.w700, color: t.text)),
          const SizedBox(height: 2),
          Text('Daily event distribution over the last 7 days',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.sub)),
          const SizedBox(height: 16),
          SizedBox(height: 220, child: _EventsTrendChart(
            dailyEvents: _weeklyEvents,
            windowStart: _chartWindowStart ?? DateTime.now().subtract(const Duration(days: 6)),
          )),
          const SizedBox(height: 12),
        ]),
      ),
    ),
  ]);

  // ── Bottom row ─────────────────────────────────────────────────────────────

  Widget _buildBottomRow(WebTk t) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Expanded(
      flex: 3,
      child: WebCard(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Top Events by Registrations',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                    fontWeight: FontWeight.w700, color: t.text)),
              const SizedBox(height: 3),
              Text('Most registered events across all organizers',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.sub)),
            ])),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => widget.onNavigate(AdminPage.events),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('View all ($_eventTotal)', style: const TextStyle(fontFamily: 'Poppins',
                      fontSize: 12, fontWeight: FontWeight.w600, color: _kAccent)),
                  const Icon(Icons.chevron_right_rounded, size: 14, color: _kAccent),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          _topEvents.isEmpty
              ? const _PlaceholderNote(text: 'No registration data yet.')
              : _TopEventsChart(events: _topEvents),
        ]),
      ),
    ),
    const SizedBox(width: 16),
    Expanded(
      flex: 2,
      child: WebCard(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Row(children: [
              Expanded(child: Text('Upcoming Events',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                    fontWeight: FontWeight.w700, color: t.text))),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => widget.onNavigate(AdminPage.events),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('View all ($_eventUpcoming)', style: const TextStyle(fontFamily: 'Poppins',
                        fontSize: 12, fontWeight: FontWeight.w600, color: _kAccent)),
                    const Icon(Icons.chevron_right_rounded, size: 14, color: _kAccent),
                  ]),
                ),
              ),
            ]),
          ),
          Divider(height: 1, color: t.border),
          _upcomingEvents.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: _PlaceholderNote(text: 'No upcoming events.'))
              : Column(
                  children: _upcomingEvents.asMap().entries.map((entry) =>
                    _UpcomingEventTile(
                      event:  entry.value,
                      isLast: entry.key == _upcomingEvents.length - 1,
                    )).toList(),
                ),
        ]),
      ),
    ),
  ]);

  // ── Recent registrations ───────────────────────────────────────────────────

  Widget _buildRecentRegs(WebTk t) => WebCard(
    padding: EdgeInsets.zero,
    child: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Recent Registrations',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                  fontWeight: FontWeight.w700, color: t.text)),
            const SizedBox(height: 2),
            Text('Latest sign-ups across all events',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.sub)),
          ])),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => widget.onNavigate(AdminPage.registrations),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Text('View all', style: TextStyle(fontFamily: 'Poppins',
                    fontSize: 12, fontWeight: FontWeight.w600, color: _kAccent)),
                Icon(Icons.chevron_right_rounded, size: 14, color: _kAccent),
              ]),
            ),
          ),
        ]),
      ),
      Divider(height: 1, color: t.border),
      if (_recentRegs.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.how_to_reg_rounded, size: 36, color: t.border),
            const SizedBox(height: 12),
            Text('No registrations yet',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  fontWeight: FontWeight.w600, color: t.text)),
            const SizedBox(height: 4),
            Text('Sign-ups will appear here as students register for events.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: t.sub)),
          ])),
        )
      else
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _recentRegs.length,
          separatorBuilder: (_, _) => Divider(height: 1, color: t.border),
          itemBuilder: (_, i) {
            final r      = _recentRegs[i];
            final status = r['status'] as String? ?? '';
            final icon   = switch (status) {
              'checked_in'      => Icons.verified_rounded,
              'photo_submitted' => Icons.photo_camera_outlined,
              'rejected'        => Icons.cancel_outlined,
              _                 => Icons.person_rounded,
            };
            final sc = webStatusColor(status);
            return Container(
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: sc, width: 3)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(17, 12, 20, 12),
                child: Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: sc.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 18, color: sc),
                  ),
                  const SizedBox(width: 12),
                  Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r['student_name'] as String? ?? '—',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                          fontWeight: FontWeight.w600, color: t.text),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(r['event_title'] as String? ?? '—',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.sub),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ])),
                  const SizedBox(width: 12),
                  WebStatusBadge(label: webStatusLabel(status), color: sc),
                  const SizedBox(width: 16),
                  Text(webTimeAgo(r['registered_at'] as String?),
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: t.muted)),
                ]),
              ),
            );
          },
        ),
    ]),
  );

  Widget _buildDashError(WebTk t) => Center(
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
      Text('Could not load dashboard data',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 16,
            fontWeight: FontWeight.w800, color: t.text)),
      const SizedBox(height: 8),
      Text('Check your connection and try again.',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.sub)),
      const SizedBox(height: 24),
      WebBtn(label: 'Retry', icon: Icons.refresh_rounded, onTap: () {
        setState(() => _dashError = false);
        _load();
      }),
    ]),
  );

}

// ─── KPI card ─────────────────────────────────────────────────────────────────

// ─── Registration trend line chart ────────────────────────────────────────────

class _RegTrendChart extends StatelessWidget {
  final List<double> dailyRegs;
  final DateTime     windowStart;
  const _RegTrendChart({required this.dailyRegs, required this.windowStart});

  @override
  Widget build(BuildContext context) {
    final t      = WebTk(Theme.of(context).brightness == Brightness.dark);
    final n      = dailyRegs.length;
    final rawMax = dailyRegs.reduce((a, b) => a > b ? a : b);
    if (rawMax < 1) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.show_chart_rounded, size: 32, color: t.border),
          const SizedBox(height: 10),
          Text('No registrations in this period',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: t.muted)),
        ]),
      );
    }
    final effectiveMax = (rawMax * 1.3).ceilToDouble();
    final spots        = dailyRegs.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();
    final todayIdx = n - 1;
    final labelInterval = n <= 7 ? 1.0 : 5.0;
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final axisLabels = List.generate(n, (i) {
      final d = windowStart.add(Duration(days: i));
      return '${months[d.month]} ${d.day}';
    });

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 20, 8),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: t.border.withValues(alpha: 0.35),
              strokeWidth: 1,
              dashArray: [4, 4],
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                interval: (effectiveMax / 4).ceilToDouble(),
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
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: labelInterval,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= n) return const SizedBox.shrink();
                  final isToday = i == todayIdx;
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(axisLabels[i],
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 10,
                        fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                        color: isToday ? _kAccent : t.muted,
                      )),
                  );
                },
              ),
            ),
            topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF1E293B),
              getTooltipItems: (spots) => spots.map((s) {
                final count = s.y.toInt();
                return LineTooltipItem(
                  '$count sign-up${count == 1 ? '' : 's'}\n',
                  const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                      fontWeight: FontWeight.w700, color: Colors.white),
                  children: [
                    TextSpan(
                      text: axisLabels[s.x.toInt()],
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                          fontWeight: FontWeight.w400, color: Color(0xFF94A3B8)),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          minX: 0, maxX: (n - 1).toDouble(), minY: 0, maxY: effectiveMax,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: _kAccent,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                  radius: spot.x.toInt() == todayIdx ? 5 : 3.5,
                  color: _kAccent,
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    _kAccent.withValues(alpha: 0.18),
                    _kAccent.withValues(alpha: 0.0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Events trend bar chart ───────────────────────────────────────────────────

class _EventsTrendChart extends StatelessWidget {
  final List<double> dailyEvents;
  final DateTime     windowStart;
  const _EventsTrendChart({required this.dailyEvents, required this.windowStart});

  static const _kEventColor = Color(0xFF10B981);

  @override
  Widget build(BuildContext context) {
    final t      = WebTk(Theme.of(context).brightness == Brightness.dark);
    final n      = dailyEvents.length;
    final rawMax = dailyEvents.reduce((a, b) => a > b ? a : b);
    if (rawMax < 1) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.bar_chart_rounded, size: 32, color: t.border),
          const SizedBox(height: 10),
          Text('No events in this period',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: t.muted)),
        ]),
      );
    }
    final effectiveMax   = (rawMax * 1.3).ceilToDouble();
    final labelInterval  = n <= 7 ? 1.0 : 5.0;
    final todayIdx       = n - 1;
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final axisLabels = List.generate(n, (i) {
      final d = windowStart.add(Duration(days: i));
      return '${months[d.month]} ${d.day}';
    });

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 20, 8),
      child: BarChart(
        BarChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: t.border.withValues(alpha: 0.35),
              strokeWidth: 1,
              dashArray: [4, 4],
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                interval: (effectiveMax / 4).ceilToDouble(),
                getTitlesWidget: (value, meta) {
                  if (value == meta.max) return const SizedBox.shrink();
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(value.toInt().toString(),
                      style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 9, color: t.muted)),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: labelInterval,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= n) return const SizedBox.shrink();
                  final isToday = i == todayIdx;
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(axisLabels[i],
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 10,
                        fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                        color: isToday ? _kEventColor : t.muted,
                      )),
                  );
                },
              ),
            ),
            topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF1E293B),
              getTooltipItem: (group, _, rod, __) {
                final count = rod.toY.toInt();
                return BarTooltipItem(
                  '$count event${count == 1 ? '' : 's'}\n',
                  const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                      fontWeight: FontWeight.w700, color: Colors.white),
                  children: [
                    TextSpan(
                      text: axisLabels[group.x],
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                          fontWeight: FontWeight.w400, color: Color(0xFF94A3B8)),
                    ),
                  ],
                );
              },
            ),
          ),
          maxY: effectiveMax,
          minY: 0,
          barGroups: List.generate(n, (i) {
            final isToday = i == todayIdx;
            return BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: dailyEvents[i],
                color: isToday
                    ? _kEventColor
                    : _kEventColor.withValues(alpha: 0.40),
                width: n <= 7 ? 20.0 : 7.0,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ]);
          }),
        ),
      ),
    );
  }
}

// ─── Chart window toggle (7D / 30D) ──────────────────────────────────────────

class _ChartWindowToggle extends StatelessWidget {
  final int                selected;
  final ValueChanged<int>  onSelect;
  const _ChartWindowToggle({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: t.border.withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _tab(t, 7,  '7D'),
        _tab(t, 30, '30D'),
      ]),
    );
  }

  Widget _tab(WebTk t, int days, String label) {
    final active = selected == days;
    return GestureDetector(
      onTap: () => onSelect(days),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color:        active ? t.card : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          boxShadow: active
              ? [BoxShadow(color: t.shadow,
                           blurRadius: 4, offset: const Offset(0, 1))]
              : null,
        ),
        child: Text(label,
          style: TextStyle(
            fontFamily:  'Poppins',
            fontSize:    11,
            fontWeight:  active ? FontWeight.w700 : FontWeight.w500,
            color:       active ? _kAccent : t.muted,
          )),
      ),
    );
  }
}

// ─── Top events progress bars ─────────────────────────────────────────────────

class _TopEventsChart extends StatelessWidget {
  final List<_TopEvent> events;
  const _TopEventsChart({required this.events});

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return Column(
      children: events.asMap().entries.map((entry) {
        final idx      = entry.key;
        final e        = entry.value;
        final hasCap   = e.capacity > 0;
        final fillRate = capacityFill(e.count, e.capacity);
        // One colour: capacity is the whole student body, so a fuller event
        // is just a popular one — nobody is ever turned away.
        final barColor = hasCap ? const Color(0xFF10B981) : _kAccent;
        final pct      = hasCap ? '${(fillRate * 100).round()}% of students' : '';

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: _kAccent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(child: Text('${idx + 1}',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
                      fontWeight: FontWeight.w800, color: _kAccent))),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(e.title,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                    fontWeight: FontWeight.w600, color: t.text),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 10),
              Text(
                hasCap ? '${e.count} / ${e.capacity}' : '${e.count} reg${e.count == 1 ? '' : 's'}',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w700, color: hasCap ? barColor : _kAccent)),
            ]),
            const SizedBox(height: 7),
            LayoutBuilder(builder: (_, constraints) {
              final barWidth = hasCap
                  ? constraints.maxWidth * fillRate
                  : constraints.maxWidth;
              return Stack(children: [
                Container(
                  height: 6, width: constraints.maxWidth,
                  decoration: BoxDecoration(
                    color: t.border, borderRadius: BorderRadius.circular(6)),
                ),
                if (barWidth > 0)
                  Container(
                    height: 6, width: barWidth,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
              ]);
            }),
            if (pct.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(pct,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 9.5,
                    fontWeight: FontWeight.w600, color: barColor)),
            ],
          ]),
        );
      }).toList(),
    );
  }
}

// ─── Today snapshot stat cell ─────────────────────────────────────────────────────


// ─── Upcoming event tile ──────────────────────────────────────────────────────

class _UpcomingEventTile extends StatelessWidget {
  final Map<String, dynamic> event;
  final bool                  isLast;
  const _UpcomingEventTile({required this.event, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final t       = WebTk(Theme.of(context).brightness == Brightness.dark);
    final title   = event['title']         as String? ?? '—';
    final dStr    = event['event_date']    as String?;
    // By the clock (the stored status is 'upcoming' even while it's on).
    final status  = eventStatusValue(event);
    final orgName = (event['organizers']   as Map<String, dynamic>?)?['full_name'] as String? ?? '—';
    final rawTime = event['start_time']    as String?;
    String timeLabel = '';
    if (rawTime != null && rawTime.isNotEmpty) {
      try {
        final parts = rawTime.split(':');
        var   hour  = int.parse(parts[0]);
        final min   = int.parse(parts[1]);
        final amPm  = hour >= 12 ? 'PM' : 'AM';
        if (hour > 12) hour -= 12;
        if (hour == 0) hour = 12;
        timeLabel = '$hour:${min.toString().padLeft(2, '0')} $amPm';
      } catch (_) {}
    }

    String monthLabel = '', dayLabel = '', contextLabel = '';
    if (dStr != null) {
      try {
        final dt      = DateTime.parse(dStr);
        final dtMid   = DateTime(dt.year, dt.month, dt.day);
        final now     = DateTime.now();
        final todayMid = DateTime(now.year, now.month, now.day);
        final diff    = dtMid.difference(todayMid).inDays;
        if (diff == 0) {
          contextLabel = 'TODAY';
        } else if (diff == 1) {
          contextLabel = 'TOMORROW';
        } else {
          const months = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
          monthLabel = months[dt.month - 1];
          dayLabel   = '${dt.day}';
        }
      } catch (_) {}
    }

    final sc     = webEventStatusColor(status);
    final isLive = status == 'ongoing';

    // For ongoing events happening today, replace the date box with a LIVE indicator
    final showLiveBox = isLive && contextLabel == 'TODAY';

    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: showLiveBox
                  ? const Color(0xFF10B981).withValues(alpha: 0.10)
                  : contextLabel.isNotEmpty
                      ? _kAccent.withValues(alpha: 0.10)
                      : sc.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: showLiveBox
                  ? const Color(0xFF10B981).withValues(alpha: 0.30)
                  : contextLabel.isNotEmpty
                      ? _kAccent.withValues(alpha: 0.25)
                      : sc.withValues(alpha: 0.20)),
            ),
            child: showLiveBox
                ? const Center(child: WebLiveDot(size: 10))
                : contextLabel.isNotEmpty
                    ? Center(child: Text(contextLabel,
                        style: TextStyle(fontFamily: 'Poppins', fontSize: contextLabel == 'TODAY' ? 9 : 7.5,
                            fontWeight: FontWeight.w800, color: _kAccent),
                        textAlign: TextAlign.center))
                    : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(monthLabel,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 8,
                              fontWeight: FontWeight.w700, color: sc)),
                        Text(dayLabel,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 16,
                              fontWeight: FontWeight.w800, color: sc, height: 1.1)),
                      ]),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                  fontWeight: FontWeight.w600, color: t.text),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(
              timeLabel.isNotEmpty ? '$timeLabel  ·  by $orgName' : 'by $orgName',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          const SizedBox(width: 8),
          if (isLive) ...[
            const WebLiveDot(size: 8),
            const SizedBox(width: 6),
          ],
          WebStatusBadge(label: webEventStatusLabel(status), color: sc),
        ]),
      ),
      if (!isLast) Divider(height: 1, color: t.border),
    ]);
  }
}

// ─── Placeholder note ─────────────────────────────────────────────────────────

class _PlaceholderNote extends StatelessWidget {
  final String text;
  const _PlaceholderNote({required this.text});
  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return Center(
      child: Text(text,
        style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: t.muted)),
    );
  }
}

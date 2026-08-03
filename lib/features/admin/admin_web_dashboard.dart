import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_colors.dart';
import '../../core/theme_store.dart';
import '../../core/services/supabase_service.dart';
import '../organizer/web/web_shared.dart';
import '../../shared/widgets/event_phase_pill.dart';
import 'admin_shared.dart';
import 'admin_web_students.dart';
import 'admin_web_organizers.dart';
import 'admin_web_events.dart';
import 'admin_web_registrations.dart';
import 'admin_web_announcements.dart';
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
// AdminPage enum now lives in admin_shared.dart (shared by every tab file).

const _kNavItems = [
  (AdminPage.overview,       Icons.dashboard_rounded,     'Dashboard'),
  (AdminPage.students,       Icons.people_rounded,        'Students'),
  (AdminPage.organizers,     Icons.badge_rounded,         'Organizers'),
  (AdminPage.events,         Icons.event_rounded,         'Events'),
  (AdminPage.registrations,  Icons.how_to_reg_rounded,    'Registrations'),
  (AdminPage.announcements,  Icons.campaign_rounded,      'Announcements'),
  (AdminPage.logs,           Icons.history_rounded,       'Logs'),
];

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
  bool      _collapsed = false;
  bool      _loading   = true;
  bool      _error     = false;
  String?   _name;

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
  }

  @override
  void dispose() { _entryCt.dispose(); super.dispose(); }

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
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  void _goLogin() {
    if (mounted) Navigator.of(context).pushReplacementNamed('/');
  }

  Future<void> _signOut() async {
    final ok = await WebAlert.confirm(
      context: context, title: 'Sign Out?',
      message: 'You will be returned to the login screen.',
      confirmLabel: 'Sign Out',
    );
    if (ok != true) return;
    await SupabaseService.client.auth.signOut();
    if (mounted) _goLogin();
  }

  void _navigate(AdminPage p) => setState(() => _page = p);

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

    return Scaffold(
      backgroundColor: t.bg,
      body: Row(children: [
        FadeTransition(
          opacity: _sidebarFade,
          child: SlideTransition(
            position: _sidebarSlide,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              width: _collapsed ? kWebSideWc : kWebSideW,
              child: _AdminSidebar(
                collapsed:    _collapsed,
                currentPage:  _page,
                name:         _name,
                onPageChanged: _navigate,
                onToggle:     () => setState(() => _collapsed = !_collapsed),
                onSignOut:    _signOut,
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
                    collapsed:  _collapsed,
                    page:       _page,
                    onMenuTap:  () => setState(() => _collapsed = !_collapsed),
                    onSignOut:  _signOut,
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
    AdminPage.logs           => const AdminLogsPage(),
  };
}

// ═════════════════════════════════════════════════════════════════════════════
// Sidebar
// ═════════════════════════════════════════════════════════════════════════════

class _AdminSidebar extends StatefulWidget {
  final bool      collapsed;
  final AdminPage currentPage;
  final String?   name;
  final ValueChanged<AdminPage> onPageChanged;
  final VoidCallback onToggle;
  final VoidCallback onSignOut;

  const _AdminSidebar({
    required this.collapsed, required this.currentPage, required this.name,
    required this.onPageChanged, required this.onToggle, required this.onSignOut,
  });

  @override
  State<_AdminSidebar> createState() => _AdminSidebarState();
}

class _AdminSidebarState extends State<_AdminSidebar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sc;

  @override
  void initState() {
    super.initState();
    _sc = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _sc.forward();
  }

  @override
  void dispose() { _sc.dispose(); super.dispose(); }

  Widget _cascade(Widget child, int idx) {
    final start = (idx * 0.067).clamp(0.0, 1.0);
    final end   = (start + 0.38).clamp(0.0, 1.0);
    return AnimatedBuilder(
      animation: _sc,
      builder: (_, c) {
        final raw = ((_sc.value - start) / (end - start)).clamp(0.0, 1.0);
        final t   = Curves.easeOut.transform(raw);
        final ts  = Curves.easeOutCubic.transform(raw);
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 10.0 * (1 - ts)), child: c),
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _STk(Theme.of(context).brightness == Brightness.dark);
    return Container(
      decoration: BoxDecoration(
        gradient: s.grad,
        border: Border(right: BorderSide(color: s.border, width: 1)),
      ),
      child: Column(children: [
        _cascade(_buildHeader(s), 0),
        const SizedBox(height: 4),
        _cascade(_buildNavLabel(s), 1),
        Expanded(child: _buildNavItems()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Divider(color: s.border.withValues(alpha: 0.35), height: 1),
        ),
        _buildDarkToggle(s),
        _cascade(_buildUserSection(s), widget.collapsed ? 6 : 7),
      ]),
    );
  }

  Widget _buildHeader(_STk s) {
    final bDeco = BoxDecoration(
      border: Border(bottom: BorderSide(
        color: s.dark ? s.border : s.border.withValues(alpha: 0.40), width: 1)),
    );
    if (widget.collapsed) {
      return Container(
        height: kWebTopH, decoration: bDeco, alignment: Alignment.center,
        child: _logoCircle(36),
      );
    }
    return Container(
      height: kWebTopH,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: bDeco,
      child: Row(children: [
        _logoCircle(38),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('J-Jireh',
                style: TextStyle(
                  fontFamily: 'Playball', fontSize: 21,
                  color: s.navText, fontWeight: FontWeight.w700, height: 1.1,
                )),
              const SizedBox(height: 3),
              Row(children: [
                Container(
                  width: 16, height: 1.5,
                  decoration: BoxDecoration(
                    color: _kAccent.withValues(alpha: s.dark ? 1.0 : 0.55),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                const SizedBox(width: 8),
                Text('EVENTHUB',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: s.dark
                        ? s.navText.withValues(alpha: 0.70)
                        : _kAccent.withValues(alpha: 0.70),
                    letterSpacing: 2.0,
                  )),
              ]),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _logoCircle(double size) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: _kAccent.withValues(alpha: 0.40), width: 2.0),
      boxShadow: [
        BoxShadow(color: _kAccent.withValues(alpha: 0.20), blurRadius: 10, offset: const Offset(0, 3)),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: Image.asset('assets/logo.jpg', fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFC2410C), _kAccent, Color(0xFFF97316)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.admin_panel_settings_rounded,
              color: Colors.white, size: size * 0.44),
        ),
      ),
    ),
  );

  Widget _buildNavLabel(_STk s) {
    if (widget.collapsed) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 2),
      child: Row(children: [
        Container(
          width: 5, height: 5,
          decoration: BoxDecoration(
            color: _kAccent.withValues(alpha: 0.50), shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text('NAVIGATION',
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w700,
            color: s.navLabel, letterSpacing: 1.8,
          )),
      ]),
    );
  }

  Widget _buildNavItems() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      children: _kNavItems.asMap().entries.map((entry) {
        final i             = entry.key;
        final (page, icon, label) = entry.value;
        final cIdx = widget.collapsed ? i + 1 : i + 2;
        return _cascade(
          _AdminNavItem(
            icon: icon, label: label,
            isActive:  widget.currentPage == page,
            collapsed: widget.collapsed,
            onTap: () => widget.onPageChanged(page),
          ),
          cIdx,
        );
      }).toList(),
    );
  }

  Widget _buildDarkToggle(_STk s) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeStore.notifier,
      builder: (_, mode, __) {
        final isDark = mode == ThemeMode.dark;
        if (widget.collapsed) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: ThemeStore.toggle,
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: s.dark
                        ? Colors.white.withValues(alpha: 0.05)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: s.border.withValues(alpha: s.dark ? 0.70 : 0.50)),
                  ),
                  child: Center(
                    child: Icon(
                      isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                      size: 16, color: s.navIcon,
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: ThemeStore.toggle,
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: s.dark
                      ? Colors.white.withValues(alpha: 0.05)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: s.border.withValues(alpha: s.dark ? 0.70 : 0.50)),
                ),
                child: Row(children: [
                  Icon(
                    isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                    size: 15, color: s.navIcon,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Dark Mode',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                        fontWeight: FontWeight.w500, color: s.navText))),
                  Switch.adaptive(
                    value: isDark,
                    onChanged: (_) => ThemeStore.toggle(),
                    activeThumbColor: _kAccent,
                    activeTrackColor: _kAccent.withValues(alpha: 0.35),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildUserSection(_STk s) {
    final initials = ((_name ?? 'A').trim().split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase())
        .take(2)
        .join());

    if (widget.collapsed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
        child: Column(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFC2410C), _kAccent, Color(0xFFF97316)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(
                color: _kAccent.withValues(alpha: 0.30), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Center(child: Text(initials,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                  fontWeight: FontWeight.w700, color: Colors.white))),
          ),
          const SizedBox(height: 6),
          _SignOutIconBtn(onTap: widget.onSignOut),
          const SizedBox(height: 2),
        ]),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      child: Container(
        decoration: BoxDecoration(
          color: s.dark
              ? Colors.white.withValues(alpha: 0.07)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: s.border.withValues(alpha: s.dark ? 0.80 : 0.50)),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: s.dark ? 0.18 : 0.04),
            blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                width: 3,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [_kAccent, Color(0xFFF97316)],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
                  child: Row(children: [
                    Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFC2410C), _kAccent, Color(0xFFF97316)],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(
                          color: _kAccent.withValues(alpha: 0.30),
                          blurRadius: 6, offset: const Offset(0, 2))],
                      ),
                      child: Center(child: Text(initials,
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                            fontWeight: FontWeight.w700, color: Colors.white))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_name ?? 'Administrator',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                                fontWeight: FontWeight.w700, color: s.navText),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 1),
                          Text('System Admin',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 9.5, color: s.navIcon)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    _InlineSignOutBtn(onTap: widget.onSignOut),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  String? get _name => widget.name;
}

// ═════════════════════════════════════════════════════════════════════════════
// Nav item
// ═════════════════════════════════════════════════════════════════════════════

class _AdminNavItem extends StatefulWidget {
  final IconData icon; final String label;
  final bool isActive; final bool collapsed;
  final VoidCallback onTap;

  const _AdminNavItem({
    required this.icon, required this.label,
    required this.isActive, required this.collapsed, required this.onTap,
  });

  @override
  State<_AdminNavItem> createState() => _AdminNavItemState();
}

class _AdminNavItemState extends State<_AdminNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final s      = _STk(Theme.of(context).brightness == Brightness.dark);
    final active = widget.isActive;
    final Color itemBg     = active
        ? _kAccent.withValues(alpha: s.dark ? 0.18 : 0.13)
        : _hovered
            ? (s.dark
                ? Colors.white.withValues(alpha: 0.07)
                : const Color(0xFFF1F5F9))
            : Colors.transparent;
    final Color itemBorder = active
        ? _kAccent.withValues(alpha: s.dark ? 0.32 : 0.24)
        : _hovered
            ? (s.dark
                ? Colors.white.withValues(alpha: 0.13)
                : s.border.withValues(alpha: 0.26))
            : Colors.transparent;
    final Color iconColor  = active ? _kAccent : _hovered ? s.navText : s.navIcon;
    final Color labelColor = active
        ? (s.dark ? Colors.white : kText)
        : _hovered ? s.navText : s.navIcon;

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit:  (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Tooltip(
            message: widget.collapsed ? widget.label : '',
            preferBelow: false,
            waitDuration: const Duration(milliseconds: 500),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 170),
              curve: Curves.easeOut,
              height: 44,
              decoration: BoxDecoration(
                color: itemBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: itemBorder, width: 1.0),
              ),
              child: widget.collapsed
                  ? Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 170),
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: active ? _kAccent.withValues(alpha: 0.16) : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Center(child: Icon(widget.icon, size: 19, color: iconColor)),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 170),
                          width: 30, height: 30,
                          decoration: BoxDecoration(
                            color: active ? _kAccent.withValues(alpha: 0.15) : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(child: Icon(widget.icon, size: 18, color: iconColor)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 150),
                            style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 13,
                              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                              color: labelColor,
                            ),
                            child: Text(widget.label),
                          ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width:  active ? 6.0 : 0.0,
                          height: active ? 6.0 : 0.0,
                          decoration: const BoxDecoration(color: _kAccent, shape: BoxShape.circle),
                        ),
                      ]),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Sign-out buttons ──────────────────────────────────────────────────────

class _SignOutIconBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _SignOutIconBtn({required this.onTap});
  @override State<_SignOutIconBtn> createState() => _SignOutIconBtnState();
}
class _SignOutIconBtnState extends State<_SignOutIconBtn> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final s = _STk(Theme.of(context).brightness == Brightness.dark);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: _h
                ? const Color(0xFFFEE2E2)
                : s.dark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: _h
                  ? const Color(0xFFFCA5A5)
                  : s.dark
                      ? Colors.white.withValues(alpha: 0.15)
                      : const Color(0xFFFECACA)),
          ),
          child: Icon(Icons.logout_rounded, size: 15,
              color: s.dark && !_h ? s.navIcon : const Color(0xFFEF4444)),
        ),
      ),
    );
  }
}

class _InlineSignOutBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _InlineSignOutBtn({required this.onTap});
  @override State<_InlineSignOutBtn> createState() => _InlineSignOutBtnState();
}
class _InlineSignOutBtnState extends State<_InlineSignOutBtn> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final s = _STk(Theme.of(context).brightness == Brightness.dark);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Tooltip(
          message: 'Sign out',
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: _h
                  ? const Color(0xFFFEE2E2)
                  : s.dark ? Colors.transparent : const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _h
                    ? const Color(0xFFFCA5A5)
                    : s.dark ? Colors.transparent : const Color(0xFFFECACA)),
            ),
            child: Icon(Icons.logout_rounded, size: 14,
                color: s.dark && !_h ? s.navIcon : const Color(0xFFEF4444)),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Top bar
// ═════════════════════════════════════════════════════════════════════════════

class _AdminTopBar extends StatelessWidget {
  final bool         collapsed;
  final AdminPage    page;
  final VoidCallback onMenuTap;
  final VoidCallback onSignOut;

  const _AdminTopBar({
    required this.collapsed, required this.page,
    required this.onMenuTap, required this.onSignOut,
  });

  String _label() => switch (page) {
    AdminPage.overview       => 'Dashboard',
    AdminPage.students       => 'Students',
    AdminPage.organizers     => 'Organizers',
    AdminPage.events         => 'Events',
    AdminPage.registrations  => 'Registrations',
    AdminPage.announcements  => 'Announcements',
    AdminPage.logs           => 'Logs',
  };

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return Container(
    height: kWebTopH,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    decoration: BoxDecoration(
      color: t.card,
      border: Border(bottom: BorderSide(color: t.border)),
      boxShadow: [BoxShadow(color: t.shadow, blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: Row(children: [
      _TopIconBtn(
        icon: collapsed ? Icons.menu_open_rounded : Icons.menu_rounded,
        onTap: onMenuTap,
      ),
      const SizedBox(width: 14),
      Text('Admin',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.muted, fontWeight: FontWeight.w500)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Icon(Icons.chevron_right_rounded, size: 16, color: t.muted),
      ),
      Text(_label(),
        style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
            fontWeight: FontWeight.w700, color: t.text)),
      const Spacer(),
      // System Admin badge
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _kAccent.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kAccent.withValues(alpha: 0.22)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 6, height: 6,
            decoration: const BoxDecoration(color: _kAccent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          const Text('System Admin',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                fontWeight: FontWeight.w600, color: _kAccent)),
        ]),
      ),
      const SizedBox(width: 12),
      _TopIconBtn(icon: Icons.logout_rounded, onTap: onSignOut, danger: true),
    ]),
  );
}
}

class _TopIconBtn extends StatefulWidget {
  final IconData icon; final VoidCallback onTap; final bool danger;
  const _TopIconBtn({required this.icon, required this.onTap, this.danger = false});
  @override State<_TopIconBtn> createState() => _TopIconBtnState();
}
class _TopIconBtnState extends State<_TopIconBtn> {
  bool _h = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _h = true),
    onExit:  (_) => setState(() => _h = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: _h ? (widget.danger ? const Color(0xFFFEF2F2) : const Color(0xFFF1F5F9)) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _h ? (widget.danger ? const Color(0xFFFCA5A5) : kCardBorder) : Colors.transparent),
        ),
        child: Icon(widget.icon, size: 18,
          color: _h ? (widget.danger ? const Color(0xFFEF4444) : kText) : kSubText),
      ),
    ),
  );
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

  int _regNeedsReview = 0;

  List<double>               _weeklyRegs     = List.filled(7, 0);
  List<double>               _monthlyRegs    = List.filled(30, 0);
  int                        _chartDays      = 7;
  List<double>               _weeklyEvents   = List.filled(7, 0);
  Map<String, int>           _statusCounts   = {};
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
        client.from('events')
            .select('event_id, title, event_status, event_date, start_time, current_participants, max_participants, organizers(full_name)')
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
      final statusCounts = <String, int>{};
      var upcomingCount = 0;
      final upcomingList = <Map<String, dynamic>>[];

      for (final e in events) {
        final s    = (e['event_status'] as String? ?? 'unknown').toLowerCase();
        statusCounts[s] = (statusCounts[s] ?? 0) + 1;
        final dStr = e['event_date'] as String?;
        if (s == 'upcoming' || s == 'ongoing') {
          upcomingCount++;
          if (dStr != null) {
            try {
              final d    = DateTime.parse(dStr);
              final dMid = DateTime(d.year, d.month, d.day);
              if (!dMid.isBefore(todayMid)) upcomingList.add(e);
            } catch (_) {}
          }
        }
      }

      // ── Registration stats ────────────────────────────────────────────
      final checkedInTotal = statsRegs.where((r) => r['status'] == 'checked_in').length;
      final checkInRate    = statsRegs.isEmpty ? 0.0 : checkedInTotal / statsRegs.length * 100;

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

      final regNeedsReview = statsRegs.where((r) => r['status'] == 'photo_submitted').length;

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
              capacity: e['max_participants']    as int? ?? 0))
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
          _statusCounts   = statusCounts;
          _weeklyRegs     = weeklyRegs;
          _monthlyRegs    = monthlyRegs;
          _weeklyEvents   = weeklyEvents;
          _topEvents      = topEvents;
          _recentRegs       = recentRows;
          _upcomingEvents   = upcomingList.take(4).toList();
          _regNeedsReview   = regNeedsReview;
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
      const SizedBox(height: 2),
      Text('J-Jireh EventHub  ·  Administration',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.muted)),
    ]);
  }

  // ── KPI row ────────────────────────────────────────────────────────────────

  Widget _buildKpiRow(WebTk t) => Row(children: [
    Expanded(child: _KpiCard(
      icon: Icons.people_rounded, color: _kAccent,
      label: 'Total Students', value: '$_studentTotal',
      sub1: '$_studentActive Active', sub2: '${_studentTotal - _studentActive} Inactive',
      sub1Color: const Color(0xFF10B981), sub2Color: t.muted,
      onTap: () => widget.onNavigate(AdminPage.students),
    )),
    const SizedBox(width: 14),
    Expanded(child: _KpiCard(
      icon: Icons.badge_rounded, color: kGold,
      label: 'Organizers', value: '$_orgTotal',
      sub1: '$_orgActive Active', sub2: '${_orgTotal - _orgActive} Inactive',
      sub1Color: const Color(0xFF10B981), sub2Color: t.muted,
      onTap: () => widget.onNavigate(AdminPage.organizers),
    )),
    const SizedBox(width: 14),
    Expanded(child: _KpiCard(
      icon: Icons.event_rounded, color: const Color(0xFF10B981),
      label: 'Total Events', value: '$_eventTotal',
      sub1: '$_eventUpcoming Upcoming / Ongoing',
      sub2: '${_statusCounts['completed'] ?? 0} Completed',
      sub1Color: _kAccent, sub2Color: t.muted,
      onTap: () => widget.onNavigate(AdminPage.events),
    )),
    const SizedBox(width: 14),
    Expanded(child: _KpiCard(
      icon: Icons.how_to_reg_rounded, color: const Color(0xFF8B5CF6),
      label: 'Registrations', value: '$_regTotal',
      sub1: '${_checkInRate.toStringAsFixed(0)}% Check-in Rate',
      sub2: '$_regNeedsReview Needs Review',
      sub1Color: _checkInRate >= 70
          ? const Color(0xFF10B981)
          : _checkInRate >= 40
              ? const Color(0xFFF59E0B)
              : const Color(0xFFEF4444),
      sub2Color: _regNeedsReview > 0 ? const Color(0xFF8B5CF6) : t.muted,
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

class _KpiCard extends StatefulWidget {
  final IconData      icon;
  final Color         color;
  final String        label, value, sub1, sub2;
  final Color         sub1Color, sub2Color;
  final VoidCallback? onTap;

  const _KpiCard({
    required this.icon,      required this.color,
    required this.label,     required this.value,
    required this.sub1,      required this.sub2,
    required this.sub1Color, required this.sub2Color,
    this.onTap,
  });

  @override
  State<_KpiCard> createState() => _KpiCardState();
}

class _KpiCardState extends State<_KpiCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale:    _hovered ? 1.016 : 1.0,
          duration: const Duration(milliseconds: 140),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(
                color: t.shadow,
                blurRadius: 12, offset: const Offset(0, 2),
              )],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: t.card,
                  border: Border.all(color: t.border),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(height: 3, color: widget.color),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 15, 18, 18),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: Text(widget.label,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                              color: t.muted, fontWeight: FontWeight.w500))),
                        Container(
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            color: widget.color.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(widget.icon, color: widget.color, size: 18),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Text(widget.value,
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 30,
                            fontWeight: FontWeight.w800, color: t.text, height: 1.0)),
                      const SizedBox(height: 14),
                      Divider(height: 1, color: t.border),
                      const SizedBox(height: 10),
                      Row(children: [
                        Container(
                          width: 7, height: 7,
                          decoration: BoxDecoration(
                              color: widget.sub1Color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Expanded(child: Text(widget.sub1,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                              fontWeight: FontWeight.w600, color: widget.sub1Color),
                          overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        Text(widget.sub2,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                              color: widget.sub2Color)),
                      ]),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
        final fillRate = hasCap ? (e.count / e.capacity).clamp(0.0, 1.0) : 0.0;
        final barColor = !hasCap
            ? _kAccent
            : fillRate >= 0.90
                ? const Color(0xFFEF4444)
                : fillRate >= 0.70
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF10B981);
        final pct      = hasCap ? '${(fillRate * 100).round()}%' : '';

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
    final status  = (event['event_status'] as String? ?? '').toLowerCase();
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

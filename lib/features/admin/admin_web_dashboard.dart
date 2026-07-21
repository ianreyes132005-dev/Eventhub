import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:eventhub/shared/utils/csv_download.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_colors.dart';
import '../../core/theme_store.dart';
import '../../core/services/supabase_service.dart';
import '../organizer/web/web_shared.dart';
import '../../shared/widgets/event_phase_pill.dart';

// ─── Admin palette ────────────────────────────────────────────────────────────
const _kAccent = Color(0xFFEA580C); // orange

// ─── Admin web content tokens ──────────────────────────────────────────────────
// A dedicated web dashboard theme — deliberately NOT the shared `AppTk` that
// organizer/student mobile screens use for dark mode. Mobile dark mode is a
// warm espresso/gold palette suited to a touch app; this is a cool graphite
// "SaaS dashboard" dark theme (in the spirit of Linear/GitHub/Vercel), so the
// admin web dark mode reads as its own product, not a reskinned mobile screen.
// Light values intentionally mirror AppTk's light palette — only dark changes.
class AdminTk {
  final bool dark;
  const AdminTk(this.dark);

  Color get bg       => dark ? const Color(0xFF0B0D12) : kBackground;
  Color get card     => dark ? const Color(0xFF12151B) : Colors.white;
  Color get border   => dark ? const Color(0xFF232833) : const Color(0xFFF0E8D8);
  Color get text     => dark ? const Color(0xFFE7EAEE) : kText;
  Color get sub      => dark ? const Color(0xFF9AA3B2) : kSubText;
  Color get muted    => dark ? const Color(0xFF666E7D) : kMuted;
  Color get divider  => dark ? const Color(0xFF1B1F27) : const Color(0xFFF0EBE0);
  Color get shadow   => dark
      ? Colors.black.withValues(alpha: 0.55)
      : Colors.black.withValues(alpha: 0.055);
  Color get inputBg  => dark ? const Color(0xFF0E1116) : Colors.white;
}

// Sidebar tokens — light mode is a pure-white panel with the organizer web's
// nav styling; dark is the same cool graphite family as AdminTk, a shade
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
enum AdminPage { overview, students, organizers, events, registrations, announcements, logs }

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
    final t    = AdminTk(dark);
    if (_loading) {
      return Scaffold(
        backgroundColor: dark ? t.bg : kWebBg,
        body: const Center(child: CircularProgressIndicator(color: _kAccent)),
      );
    }
    if (_error) {
      return Scaffold(
        backgroundColor: dark ? t.bg : kWebBg,
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
      backgroundColor: dark ? t.bg : kWebBg,
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
    AdminPage.students       => const _AdminStudentsPage(),
    AdminPage.organizers     => const _AdminOrganizersPage(),
    AdminPage.events         => const _AdminEventsPage(),
    AdminPage.registrations  => const _AdminRegistrationsPage(),
    AdminPage.announcements  => const _AdminAnnouncementsPage(),
    AdminPage.logs           => const _AdminLogsPage(),
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
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
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
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
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

  Widget _buildHeader(AdminTk t) {
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

  Widget _buildKpiRow(AdminTk t) => Row(children: [
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

  Widget _buildChartsRow(AdminTk t) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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

  Widget _buildBottomRow(AdminTk t) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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

  Widget _buildRecentRegs(AdminTk t) => WebCard(
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

  Widget _buildDashError(AdminTk t) => Center(
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
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
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
    final t      = AdminTk(Theme.of(context).brightness == Brightness.dark);
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
    final t      = AdminTk(Theme.of(context).brightness == Brightness.dark);
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
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
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

  Widget _tab(AdminTk t, int days, String label) {
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
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
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
    final t       = AdminTk(Theme.of(context).brightness == Brightness.dark);
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
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
    return Center(
      child: Text(text,
        style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: t.muted)),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Students page
// ═════════════════════════════════════════════════════════════════════════════

class _AdminStudentsPage extends StatefulWidget {
  const _AdminStudentsPage();
  @override State<_AdminStudentsPage> createState() => _AdminStudentsPageState();
}

class _AdminStudentsPageState extends State<_AdminStudentsPage> {
  bool   _loading = true, _error = false;
  String _errorMsg = '';
  List<Map<String, dynamic>> _all = [], _filtered = [];
  Map<String, int>           _regCounts = {};
  String _search       = '';
  String _statusFilter = 'All';
  String _yearFilter   = 'All';
  String _sortField    = 'created_at';
  bool   _sortAsc      = false;
  final _searchCtrl = TextEditingController();

  RealtimeChannel? _channel;
  Timer?           _debounce;

  List<String> get _yearOptions {
    final years = _all
        .map((s) => s['year_level'])
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();
    return ['All', ...years.map((y) => 'Grade $y')];
  }

  @override
  void initState() { super.initState(); _load(); _subscribeRealtime(); }
  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    if (_channel != null) SupabaseService.client.removeChannel(_channel!);
    super.dispose();
  }

  void _subscribeRealtime() {
    _channel = SupabaseService.client.channel('admin-students');
    for (final table in ['students', 'registrations']) {
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
    if (mounted) setState(() { if (!silent) _loading = true; _error = false; });
    try {
      final results = await Future.wait([
        SupabaseService.client
            .from('students')
            .select('lrn, user_id, full_name, year_level, is_active, created_at')
            .order('created_at', ascending: false),
        SupabaseService.client
            .from('registrations')
            .select('student_school_id'),
      ]);
      if (!mounted) return;
      _all = List<Map<String, dynamic>>.from(results[0] as List);
      final regRows = results[1] as List;
      final counts  = <String, int>{};
      for (final r in regRows) {
        final id = (r as Map<String, dynamic>)['student_school_id'] as String?;
        if (id != null) counts[id] = (counts[id] ?? 0) + 1;
      }
      _regCounts = counts;
      _loading   = false;
      _applyFilter();
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = true; _errorMsg = e.toString(); });
    }
  }

  void _applyFilter() {
    final q = _search.toLowerCase();
    var list = _all.where((s) {
      if (_statusFilter == 'Active'   && s['is_active'] != true) return false;
      if (_statusFilter == 'Inactive' && s['is_active'] == true) return false;
      if (_statusFilter == 'No Auth'  && s['user_id']  != null)  return false;
      if (_statusFilter == 'No Regs'  &&
          (_regCounts[s['lrn'] as String? ?? ''] ?? 0) > 0) { return false; }
      if (_yearFilter != 'All') {
        final yr = int.tryParse(_yearFilter.replaceAll('Grade ', ''));
        if ((s['year_level'] as int?) != yr) return false;
      }
      if (q.isNotEmpty) {
        final name = (s['full_name'] as String? ?? '').toLowerCase();
        final lrn  = (s['lrn']       as String? ?? '').toLowerCase();
        if (!name.contains(q) && !lrn.contains(q)) return false;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      int cmp;
      if (_sortField == 'full_name') {
        cmp = (a['full_name'] as String? ?? '').compareTo(b['full_name'] as String? ?? '');
      } else if (_sortField == 'lrn') {
        cmp = (a['lrn'] as String? ?? '').compareTo(b['lrn'] as String? ?? '');
      } else if (_sortField == 'year_level') {
        cmp = ((a['year_level'] as int?) ?? 0).compareTo((b['year_level'] as int?) ?? 0);
      } else if (_sortField == 'is_active') {
        final ai = a['is_active'] == true ? 1 : 0;
        final bi = b['is_active'] == true ? 1 : 0;
        cmp = bi.compareTo(ai);
      } else if (_sortField == 'reg_count') {
        final ac = _regCounts[a['lrn'] as String? ?? ''] ?? 0;
        final bc = _regCounts[b['lrn'] as String? ?? ''] ?? 0;
        cmp = ac.compareTo(bc);
      } else {
        cmp = ((a['created_at'] as String?) ?? '').compareTo((b['created_at'] as String?) ?? '');
      }
      return _sortAsc ? cmp : -cmp;
    });

    setState(() => _filtered = list);
  }

  void _setSort(String field) {
    if (_sortField == field) {
      _sortAsc = !_sortAsc;
    } else {
      _sortField = field;
      _sortAsc   = field == 'full_name' || field == 'lrn' ||
                   field == 'year_level' || field == 'is_active';
    }
    _applyFilter();
  }

  Future<void> _toggleActive(String lrn, bool cur) async {
    final ok = await WebAlert.confirm(
      context:      context,
      title:        cur ? 'Deactivate Student?' : 'Activate Student?',
      message:      cur
          ? 'This student will no longer be able to log in.'
          : 'This student will regain access to their account.',
      confirmLabel: cur ? 'Deactivate' : 'Activate',
      confirmColor: cur ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
      iconColor:    cur ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
      iconBg:       cur ? const Color(0xFFFFFBEB) : const Color(0xFFECFDF5),
      icon:         cur ? Icons.person_off_outlined : Icons.person_add_outlined,
    );
    if (ok != true) return;
    try {
      await SupabaseService.client.from('students')
          .update({'is_active': !cur}).eq('lrn', lrn);
      final idx = _all.indexWhere((s) => s['lrn'] == lrn);
      if (idx != -1) { _all[idx] = {..._all[idx], 'is_active': !cur}; _applyFilter(); }
    } catch (e) {
      if (mounted) _snack('Failed: $e');
    }
  }

  Future<void> _editStudent(Map<String, dynamic> student) async {
    final result = await showDialog<Map<String, dynamic>?>(
      context: context, builder: (_) => _StudentDialog(student: student));
    if (result == null) return;
    try {
      await SupabaseService.client.from('students')
          .update(result).eq('lrn', student['lrn'] as String);
      final idx = _all.indexWhere((s) => s['lrn'] == student['lrn']);
      if (idx != -1) { _all[idx] = {..._all[idx], ...result}; _applyFilter(); }
      if (mounted) WebAlert.success(context: context, title: 'Saved', message: 'Student profile updated.');
    } catch (e) { if (mounted) _snack('Failed: $e'); }
  }

  Future<void> _addStudent() async {
    String? createdName;
    final ok = await showDialog<bool?>(
      context: context,
      builder: (_) => _StudentDialog(
        student: null,
        onCreate: (data) async {
          try {
            createdName      = data['full_name'] as String?;
            final password   = data['password'] as String;
            final studentData = Map<String, dynamic>.from(data)..remove('password');
            final res = await SupabaseService.client.functions.invoke(
              'create-student',
              body: {...studentData, 'password': password},
            );
            final body = res.data is Map
                ? Map<String, dynamic>.from(res.data as Map)
                : null;
            if (res.status != 200) {
              return body?['message'] as String? ?? 'Failed to create account.';
            }
            return null; // success
          } catch (e) {
            return 'Failed: $e';
          }
        },
      ),
    );
    if (ok != true || !mounted) return;
    await _load();
    if (mounted) {
      WebAlert.success(
        context: context,
        title: 'Account Created',
        message: 'Student account for ${createdName ?? 'student'} has been created.',
      );
    }
  }

  Future<void> _deleteStudent(String lrn, String name) async {
    final ok = await WebAlert.confirm(
      context: context, title: 'Delete Student?',
      message: 'This will permanently remove $name\'s profile and all their event registration history.',
      confirmLabel: 'Delete',
    );
    if (ok != true) return;
    try {
      await SupabaseService.client.from('students').delete().eq('lrn', lrn);
      _all.removeWhere((s) => s['lrn'] == lrn);
      _applyFilter();
      if (mounted) WebAlert.success(context: context, title: 'Deleted', message: 'Student record removed.');
    } catch (e) { if (mounted) _snack('Failed: $e'); }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: const Color(0xFFEF4444)));

  @override
  Widget build(BuildContext context) {
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
    final totalCount        = _all.length;
    final activeCount       = _all.where((s) => s['is_active'] == true).length;
    final inactiveCount     = totalCount - activeCount;
    final noAuthCount       = _all.where((s) => s['user_id'] == null).length;
    final unregisteredCount = _all.where((s) =>
        (_regCounts[s['lrn'] as String? ?? ''] ?? 0) == 0).length;
    final hasFilter         = _search.isNotEmpty || _statusFilter != 'All' || _yearFilter != 'All';
    final yearOpts          = _yearOptions;
    final filterDesc = [
      if (_statusFilter != 'All') _statusFilter,
      if (_yearFilter   != 'All') _yearFilter,
      if (_search.isNotEmpty)     '"$_search"',
    ].join(' · ');
    final emptySubtitle = filterDesc.isEmpty
        ? 'Add your first student to get started.'
        : 'No students match $filterDesc.';

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    if (_error) {
      return _ErrorState(message: _errorMsg, onRetry: _load);
    }

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Page header ───────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.fromLTRB(kWebPad, 20, kWebPad, 16),
        color: t.card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Students',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 22,
                    fontWeight: FontWeight.w800, color: t.text)),
              const SizedBox(height: 2),
              Text('$totalCount enrolled · $activeCount active · $noAuthCount unlinked',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.sub)),
            ])),
            WebBtn(label: 'Add Student', icon: Icons.add_rounded, onTap: _addStudent),
          ]),
          const SizedBox(height: 16),
          // ── Stat tiles ────────────────────────────────────────────────
          Row(children: [
            _StudentStatCard(label: 'Total Enrolled', value: '$totalCount',
                color: _kAccent, icon: Icons.people_rounded),
            const SizedBox(width: 10),
            _StudentStatCard(label: 'Active', value: '$activeCount',
                color: const Color(0xFF10B981), icon: Icons.check_circle_rounded),
            const SizedBox(width: 10),
            _StudentStatCard(
              label: 'Inactive',
              value: '$inactiveCount',
              color: inactiveCount > 0 ? kMuted : const Color(0xFF10B981),
              icon:  Icons.person_off_outlined,
            ),
            const SizedBox(width: 10),
            _StudentStatCard(
              label: 'No Auth',
              value: '$noAuthCount',
              color: noAuthCount > 0 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
              icon:  Icons.no_accounts_rounded,
            ),
            const SizedBox(width: 10),
            _StudentStatCard(
              label: 'Never Registered',
              value: '$unregisteredCount',
              color: unregisteredCount > 0 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
              icon:  Icons.event_busy_rounded,
            ),
          ]),
          const SizedBox(height: 14),
          // ── Grade breakdown strip ──────────────────────────────────────
          // flex:4 JHS + flex:2 SHS → each chip gets equal width naturally
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 4,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('JHS',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 9.5,
                      fontWeight: FontWeight.w700, color: Color(0xFF6D28D9),
                      letterSpacing: 0.8)),
                const SizedBox(height: 5),
                Row(children: [
                  for (final g in [7, 8, 9, 10]) ...[
                    Expanded(child: _GradeChip(
                      grade: g,
                      count: _all.where((s) => (s['year_level'] as int?) == g).length,
                      isJhs: true,
                    )),
                    if (g < 10) const SizedBox(width: 8),
                  ],
                ]),
              ]),
            ),
            const SizedBox(width: 16),
            Container(width: 1, height: 58,
                margin: const EdgeInsets.only(top: 14), color: t.border),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('SHS',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 9.5,
                      fontWeight: FontWeight.w700, color: Color(0xFF0EA5E9),
                      letterSpacing: 0.8)),
                const SizedBox(height: 5),
                Row(children: [
                  for (final g in [11, 12]) ...[
                    Expanded(child: _GradeChip(
                      grade: g,
                      count: _all.where((s) => (s['year_level'] as int?) == g).length,
                      isJhs: false,
                    )),
                    if (g < 12) const SizedBox(width: 8),
                  ],
                ]),
              ]),
            ),
          ]),
        ]),
      ),
      // ── Filter bar ───────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.fromLTRB(kWebPad, 8, kWebPad, 8),
        decoration: BoxDecoration(
          color: t.bg,
          border: Border(bottom: BorderSide(color: t.border)),
        ),
        child: Row(children: [
          WebSearchField(
            controller: _searchCtrl, hint: 'Search name or LRN…',
            onChanged: (v) { _search = v; _applyFilter(); }, width: 200),
          const SizedBox(width: 14),
          Container(width: 1, height: 18, color: t.border),
          const SizedBox(width: 14),
          Text('Status:',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                fontWeight: FontWeight.w600, color: t.text)),
          const SizedBox(width: 8),
          for (final f in ['All', 'Active', 'Inactive', 'No Auth', 'No Regs']) ...[
            WebFilterChip(
              label: f, selected: _statusFilter == f,
              onTap: () { _statusFilter = f; _applyFilter(); },
              count: f == 'All'      ? totalCount
                   : f == 'Active'   ? activeCount
                   : f == 'Inactive' ? inactiveCount
                   : f == 'No Auth'  ? noAuthCount
                   :                   unregisteredCount,
              selectedColor: f == 'No Auth'  ? const Color(0xFFF59E0B)
                           : f == 'No Regs'  ? const Color(0xFFF59E0B)
                           : f == 'Inactive' ? kMuted
                           : f == 'Active'   ? const Color(0xFF10B981)
                           : null,
            ),
            const SizedBox(width: 6),
          ],
          if (yearOpts.length > 1) ...[
            const SizedBox(width: 12),
            Container(width: 1, height: 18, color: t.border),
            const SizedBox(width: 12),
            Text('Grade:',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  fontWeight: FontWeight.w600, color: t.text)),
            const SizedBox(width: 8),
            Container(
              height: 28,
              padding: const EdgeInsets.only(left: 10, right: 6),
              decoration: BoxDecoration(
                color: _yearFilter != 'All'
                    ? _kAccent.withValues(alpha: 0.07)
                    : t.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _yearFilter != 'All'
                      ? _kAccent.withValues(alpha: 0.45)
                      : t.border,
                  width: _yearFilter != 'All' ? 1.5 : 1.0,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: yearOpts.contains(_yearFilter) ? _yearFilter : 'All',
                  isDense: true,
                  icon: Icon(Icons.keyboard_arrow_down_rounded, size: 14,
                      color: _yearFilter != 'All' ? _kAccent : t.muted),
                  onChanged: (v) {
                    if (v != null) { _yearFilter = v; _applyFilter(); }
                  },
                  selectedItemBuilder: (ctx) => yearOpts.map((y) => Center(
                    child: Text(y,
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: _yearFilter != 'All' ? _kAccent : t.text,
                      )),
                  )).toList(),
                  items: yearOpts.map((y) {
                    final cnt = y == 'All'
                        ? totalCount
                        : _all.where((s) {
                            final yr = int.tryParse(y.replaceAll('Grade ', ''));
                            return (s['year_level'] as int?) == yr;
                          }).length;
                    return DropdownMenuItem<String>(
                      value: y,
                      child: Text('$y ($cnt)',
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 12,
                          fontWeight: y == _yearFilter ? FontWeight.w700 : FontWeight.w400,
                          color: y == _yearFilter ? _kAccent : t.text,
                        )),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
          if (hasFilter) ...[
            const Spacer(),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  _search = ''; _statusFilter = 'All'; _yearFilter = 'All';
                  _searchCtrl.clear();
                  _applyFilter();
                },
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.close_rounded, size: 13, color: t.muted),
                  const SizedBox(width: 4),
                  Text('Clear filters', style: TextStyle(fontFamily: 'Poppins',
                      fontSize: 11.5, fontWeight: FontWeight.w600, color: t.muted)),
                ]),
              ),
            ),
          ],
        ]),
      ),
      // ── Body ─────────────────────────────────────────────────────────
        if (_filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(kWebPad),
            child: WebEmptyState(
              icon: Icons.people_outline_rounded,
              title: 'No students found',
              subtitle: emptySubtitle,
              action: hasFilter
                  ? TextButton(
                      onPressed: () {
                        _search = ''; _statusFilter = 'All'; _yearFilter = 'All';
                        _searchCtrl.clear();
                        _applyFilter();
                      },
                      child: const Text('Clear all filters',
                        style: TextStyle(fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600, color: _kAccent)))
                  : null),
          )
        else
          Padding(
            padding: const EdgeInsets.all(kWebPad),
            child: WebCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                _StudentTableHeader(
                  sortField: _sortField,
                  sortAsc:   _sortAsc,
                  onSort:    _setSort,
                ),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: t.border),
                  itemBuilder: (_, i) => _StudentRow(
                    student:  _filtered[i],
                    regCount: _regCounts[_filtered[i]['lrn'] as String? ?? ''] ?? 0,
                    onEdit:   () => _editStudent(_filtered[i]),
                    onToggle: () => _toggleActive(
                      _filtered[i]['lrn'] as String,
                      _filtered[i]['is_active'] == true),
                    onDelete: () => _deleteStudent(
                      _filtered[i]['lrn'] as String,
                      _filtered[i]['full_name'] as String? ?? '—'),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: t.border))),
                  child: Text(
                    hasFilter
                        ? 'Showing ${_filtered.length} of $totalCount students'
                        : '${_filtered.length} students total',
                    style: TextStyle(fontFamily: 'Poppins',
                        fontSize: 11.5, color: t.muted)),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _StudentRow extends StatefulWidget {
  final Map<String, dynamic> student;
  final int          regCount;
  final VoidCallback onEdit, onToggle, onDelete;
  const _StudentRow({required this.student, required this.regCount, required this.onEdit, required this.onToggle, required this.onDelete});
  @override State<_StudentRow> createState() => _StudentRowState();
}
class _StudentRowState extends State<_StudentRow> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final t           = AdminTk(Theme.of(context).brightness == Brightness.dark);
    final s           = widget.student;
    final active      = s['is_active'] == true;
    final linked      = s['user_id'] != null;
    final yr          = s['year_level'] as int?;
    final initials    = (s['full_name'] as String? ?? '?').trim().split(' ')
        .where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).take(2).join();
    final avatarColor = active ? _kAccent : t.muted;

    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _h ? _kAccent.withValues(alpha: 0.03) : Colors.transparent,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 3, color: active ? Colors.transparent : t.muted.withValues(alpha: 0.30)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(children: [
          // Avatar
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: avatarColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: avatarColor.withValues(alpha: 0.18)),
            ),
            child: Center(child: Text(initials,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                  fontWeight: FontWeight.w700, color: avatarColor))),
          ),
          const SizedBox(width: 12),
          // Name + "no auth" warning
          Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s['full_name'] as String? ?? '—',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? t.text : t.muted),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            if (!linked)
              const Text('No auth account',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                    color: Color(0xFFF59E0B), fontWeight: FontWeight.w600)),
          ])),
          // LRN
          Expanded(flex: 2, child: Text(formatLrn(s['lrn'] as String? ?? '—'),
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.sub),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
          // Year level badge
          Expanded(child: yr != null
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF6D28D9).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF6D28D9).withValues(alpha: 0.18)),
                ),
                child: Text('G$yr',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                      fontWeight: FontWeight.w700, color: Color(0xFF6D28D9))))
            : Text('—', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.muted))),
          // Registration count
          Expanded(child: widget.regCount > 0
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.how_to_reg_rounded, size: 11,
                        color: const Color(0xFF10B981).withValues(alpha: 0.80)),
                    const SizedBox(width: 4),
                    Text('${widget.regCount}',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                          fontWeight: FontWeight.w700, color: Color(0xFF10B981))),
                  ]),
                )
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: t.muted.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('0',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                        fontWeight: FontWeight.w500, color: t.muted)))),
          // Status badge
          Expanded(child: WebStatusBadge(
            label: active ? 'Active' : 'Inactive',
            color: active ? const Color(0xFF10B981) : t.muted)),
          // Account link status — amber when unlinked
          Expanded(child: Row(children: [
            Container(width: 7, height: 7,
                decoration: BoxDecoration(
                  color: linked ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                  shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(linked ? 'Linked' : 'No account',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                  fontWeight: linked ? FontWeight.w400 : FontWeight.w600,
                  color: linked ? const Color(0xFF10B981) : const Color(0xFFF59E0B))),
          ])),
          // Created date
          Expanded(flex: 2, child: Text(webFmtDate(s['created_at'] as String?),
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: t.muted))),
          // Actions — fade in on row hover
          AnimatedOpacity(
            opacity: _h ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 150),
            child: SizedBox(
              width: 108,
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                _ActBtn(icon: Icons.edit_outlined,
                    color: _kAccent, tip: 'Edit', onTap: widget.onEdit),
                const SizedBox(width: 6),
                _ActBtn(
                  icon:  active ? Icons.person_off_outlined : Icons.person_add_outlined,
                  color: active ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                  tip:   active ? 'Deactivate' : 'Activate',
                  onTap: widget.onToggle),
                const SizedBox(width: 6),
                _ActBtn(icon: Icons.delete_outline_rounded,
                    color: const Color(0xFFEF4444), tip: 'Delete', onTap: widget.onDelete),
              ]),
            ),
          ),
                ]),      // closes inner Row (Padding child)
              ),         // closes Padding
            ),           // closes Expanded
          ]),            // closes outer Row (IntrinsicHeight child)
        ),               // closes IntrinsicHeight
      ),                 // closes AnimatedContainer
    );                   // closes MouseRegion
  }
}

// ─── Mini stat tile ────────────────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  final String   label, value;
  final Color    color;
  final IconData icon;
  const _MiniStat({
    required this.label, required this.value,
    required this.color, required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 9),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(value,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 18,
                fontWeight: FontWeight.w800, color: color, height: 1.0)),
          Text(label,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 9.5, color: t.sub)),
        ]),
      ]),
    );
  }
}

// ─── Student stat card (Students tab — full-width Expanded KPI style) ─────────

class _StudentStatCard extends StatelessWidget {
  final String   label, value;
  final Color    color;
  final IconData icon;
  const _StudentStatCard({
    required this.label, required this.value,
    required this.color, required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: t.shadow,
              blurRadius: 8, offset: const Offset(0, 1))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: t.card,
              border: Border.all(color: t.border),
            ),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(width: 3, color: color),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                  child: Row(children: [
                    Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(icon, size: 17, color: color),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(value,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 20,
                              fontWeight: FontWeight.w800, color: t.text, height: 1.0)),
                        const SizedBox(height: 2),
                        Text(label,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                              color: t.sub)),
                      ],
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Grade breakdown chip (used in the per-grade strip) ──────────────────────

class _GradeChip extends StatelessWidget {
  final int  grade, count;
  final bool isJhs;
  const _GradeChip({required this.grade, required this.count, required this.isJhs});

  @override
  Widget build(BuildContext context) {
    final color = isJhs ? const Color(0xFF6D28D9) : const Color(0xFF0EA5E9);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('$count',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 15,
              fontWeight: FontWeight.w800, color: color, height: 1.1)),
        const SizedBox(height: 2),
        Text('Grade $grade',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.70))),
      ]),
    );
  }
}

// ─── Sortable table header for Students ────────────────────────────────────

class _StudentTableHeader extends StatelessWidget {
  final String sortField;
  final bool   sortAsc;
  final void Function(String) onSort;
  const _StudentTableHeader({
    required this.sortField, required this.sortAsc, required this.onSort});

  Widget _sortCol(String label, String field, {int flex = 1}) => Expanded(
    flex: flex,
    child: _SortColBtn(
      label: label, field: field,
      active: sortField == field,
      asc:    sortAsc && sortField == field,
      onSort: onSort,
    ),
  );

  Widget _staticCol(String label, Color color, {int flex = 1}) => Expanded(
    flex: flex,
    child: Text(label, style: TextStyle(fontFamily: 'Poppins',
        fontSize: 10.5, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.8)),
  );

  @override
  Widget build(BuildContext context) {
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
    return Container(
      padding: const EdgeInsets.only(left: 23, right: 20, top: 10, bottom: 10),
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(children: [
        const SizedBox(width: 52),
        _sortCol('FULL NAME',  'full_name',  flex: 3),
        _sortCol('LRN',        'lrn',        flex: 2),
        _sortCol('GRADE',      'year_level'),
        _sortCol('REGS',       'reg_count'),
        _sortCol('STATUS',     'is_active'),
        _staticCol('AUTH',     t.sub),
        _sortCol('CREATED',    'created_at', flex: 2),
        const SizedBox(width: 108),
      ]),
    );
  }
}

class _SortColBtn extends StatefulWidget {
  final String   label, field;
  final bool     active, asc;
  final void Function(String) onSort;
  const _SortColBtn({
    required this.label, required this.field,
    required this.active, required this.asc, required this.onSort});
  @override State<_SortColBtn> createState() => _SortColBtnState();
}
class _SortColBtnState extends State<_SortColBtn> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: () => widget.onSort(widget.field),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.label,
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 10.5,
              fontWeight: FontWeight.w700, letterSpacing: 0.8,
              color: widget.active ? _kAccent : _h ? t.text : t.sub,
            )),
          const SizedBox(width: 3),
          Icon(
            widget.active
                ? (widget.asc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded)
                : Icons.unfold_more_rounded,
            size: 11,
            color: widget.active ? _kAccent : _h ? t.sub : t.border,
          ),
        ]),
      ),
    );
  }
}

// ─── Student dialog ────────────────────────────────────────────────────────

class _StudentDialog extends StatefulWidget {
  final Map<String, dynamic>? student;
  // For add mode only: called with the validated form data.
  // Returns an error message string on failure, or null on success.
  final Future<String?> Function(Map<String, dynamic>)? onCreate;
  const _StudentDialog({required this.student, this.onCreate});
  @override State<_StudentDialog> createState() => _StudentDialogState();
}
class _StudentDialogState extends State<_StudentDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _scale, _fade;
  final _lrnCtrl        = TextEditingController();
  final _nameCtrl       = TextEditingController();
  final _pwCtrl         = TextEditingController();
  final _confirmPwCtrl  = TextEditingController();
  bool  _pwHidden        = true;
  bool  _confirmPwHidden = true;
  bool  _saving          = false;
  int?  _selectedYear;

  bool get _isEdit => widget.student != null;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    _scale = Tween<double>(begin: 0.87, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    if (_isEdit) {
      _lrnCtrl.text  = widget.student!['lrn']       as String? ?? '';
      _nameCtrl.text = widget.student!['full_name']  as String? ?? '';
      _selectedYear  = widget.student!['year_level'] as int?;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _lrnCtrl.dispose();
    _nameCtrl.dispose();
    _pwCtrl.dispose();
    _confirmPwCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final lrn  = _lrnCtrl.text.replaceAll(RegExp(r'\D'), '');
    final name = _nameCtrl.text.trim();
    final pw   = _pwCtrl.text;
    if (!_isEdit && !RegExp(r'^\d{12}$').hasMatch(lrn)) {
      _snack('LRN must be exactly 12 digits'); return;
    }
    if (name.isEmpty) { _snack('Full name is required'); return; }
    if (!_isEdit && pw.length < 6) {
      _snack('Password must be at least 6 characters'); return;
    }
    if (!_isEdit && _confirmPwCtrl.text != pw) {
      _snack('Passwords do not match'); return;
    }
    final data = <String, dynamic>{'full_name': name, 'year_level': _selectedYear};
    if (!_isEdit) {
      data['lrn']       = lrn;
      data['password']  = pw;
      data['is_active'] = true;
    }

    if (_isEdit) {
      // Edit mode: pop immediately with data for the parent to save.
      Navigator.of(context).pop(data);
      return;
    }

    // Add mode: call onCreate inside the dialog so we can show a loading state.
    setState(() => _saving = true);
    final err = await widget.onCreate!(data);
    if (!mounted) return;
    if (err != null) {
      setState(() => _saving = false);
      _snack(err);
      return;
    }
    Navigator.of(context).pop(true); // true = success
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: Colors.red));

  @override
  Widget build(BuildContext context) {
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
    return FadeTransition(
    opacity: _fade,
    child: ScaleTransition(
      scale: _scale,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 680),
          child: _dialogShell(
            icon: Icons.people_rounded, iconColor: _kAccent,
            title: _isEdit ? 'Edit Student' : 'Add Student',
            loading: _saving,
            body: Column(children: [
              if (!_isEdit) ...[
                _InfoNote('Admin-provisioned account. The student will log in using the last 4 digits of their LRN as their username.'),
                const SizedBox(height: 14),
                TextField(
                  controller: _lrnCtrl,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_LrnFormatter()],
                  decoration: webInputDeco('e.g. 123456 - 26 - 1234', icon: Icons.badge_outlined, dark: t.dark),
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.text)),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _nameCtrl,
                enabled: !_saving,
                decoration: webInputDeco('Full Name', icon: Icons.person_outline_rounded, dark: t.dark),
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.text)),
              const SizedBox(height: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Grade Level',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                      fontWeight: FontWeight.w600, color: t.sub)),
                const SizedBox(height: 10),
                // Junior High School row
                Text('Junior High School',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                      fontWeight: FontWeight.w600, color: t.muted, letterSpacing: 0.4)),
                const SizedBox(height: 6),
                Row(children: [
                  for (final y in [7, 8, 9, 10]) ...[
                    Expanded(
                      child: GestureDetector(
                        onTap: _saving ? null : () => setState(
                            () => _selectedYear = _selectedYear == y ? null : y),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _selectedYear == y
                                ? _kAccent.withValues(alpha: 0.10)
                                : t.inputBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _selectedYear == y ? _kAccent : t.border,
                              width: _selectedYear == y ? 1.5 : 1.0,
                            ),
                          ),
                          child: Text('Grade $y',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 12,
                              fontWeight: _selectedYear == y
                                  ? FontWeight.w700 : FontWeight.w400,
                              color: _selectedYear == y ? _kAccent : t.sub,
                            )),
                        ),
                      ),
                    ),
                    if (y < 10) const SizedBox(width: 8),
                  ],
                ]),
                const SizedBox(height: 10),
                // Senior High School row
                Text('Senior High School',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                      fontWeight: FontWeight.w600, color: t.muted, letterSpacing: 0.4)),
                const SizedBox(height: 6),
                Row(children: [
                  for (final y in [11, 12]) ...[
                    Expanded(
                      child: GestureDetector(
                        onTap: _saving ? null : () => setState(
                            () => _selectedYear = _selectedYear == y ? null : y),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _selectedYear == y
                                ? _kAccent.withValues(alpha: 0.10)
                                : t.inputBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _selectedYear == y ? _kAccent : t.border,
                              width: _selectedYear == y ? 1.5 : 1.0,
                            ),
                          ),
                          child: Text('Grade $y',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 12,
                              fontWeight: _selectedYear == y
                                  ? FontWeight.w700 : FontWeight.w400,
                              color: _selectedYear == y ? _kAccent : t.sub,
                            )),
                        ),
                      ),
                    ),
                    if (y < 12) const SizedBox(width: 8),
                  ],
                  // Spacer to prevent Grade 11 / 12 from stretching across full width
                  const Expanded(flex: 2, child: SizedBox()),
                ]),
              ]),
              if (!_isEdit) ...[
                const SizedBox(height: 14),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _lrnCtrl,
                  builder: (_, v, __) {
                    final lrn   = v.text.replaceAll(RegExp(r'\D'), '');
                    final last4 = lrn.length >= 4
                        ? lrn.substring(lrn.length - 4)
                        : lrn.isEmpty ? '—' : lrn;
                    return _CredentialPreview(username: last4, isReady: lrn.length == 12);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pwCtrl,
                  obscureText: _pwHidden,
                  enabled: !_saving,
                  decoration: webInputDeco('Password', icon: Icons.lock_outline_rounded, dark: t.dark).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _pwHidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        size: 18, color: t.sub,
                      ),
                      onPressed: () => setState(() => _pwHidden = !_pwHidden),
                    ),
                  ),
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.text),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _pwCtrl,
                  builder: (_, v, __) => _PasswordStrengthBar(password: v.text),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmPwCtrl,
                  obscureText: _confirmPwHidden,
                  enabled: !_saving,
                  decoration: webInputDeco('Confirm Password', icon: Icons.lock_outline_rounded, dark: t.dark).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _confirmPwHidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        size: 18, color: t.sub,
                      ),
                      onPressed: () => setState(() => _confirmPwHidden = !_confirmPwHidden),
                    ),
                  ),
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.text),
                ),
              ],
            ]),
            confirmLabel: _isEdit ? 'Save Changes' : 'Add Student',
            confirmColor: _kAccent,
            onConfirm: _submit,
          ),
        ),
      ),
    ),
  );
}
}

// ─── LRN auto-formatter ───────────────────────────────────────────────────────
// As admin types 12 digits, inserts " - " separators: XXXXXX - XX - XXXX.
class _LrnFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final capped = digits.length > 12 ? digits.substring(0, 12) : digits;
    final buf    = StringBuffer();
    for (var i = 0; i < capped.length; i++) {
      if (i == 6 || i == 8) buf.write(' - ');
      buf.write(capped[i]);
    }
    final out = buf.toString();
    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: out.length),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Organizers page
// ═════════════════════════════════════════════════════════════════════════════

class _AdminOrganizersPage extends StatefulWidget {
  const _AdminOrganizersPage();
  @override State<_AdminOrganizersPage> createState() => _AdminOrganizersPageState();
}

class _AdminOrganizersPageState extends State<_AdminOrganizersPage> {
  bool   _loading = true, _error = false;
  String _errorMsg = '';
  List<Map<String, dynamic>> _all = [], _filtered = [];
  Map<String, int> _eventCounts = {};
  String _search       = '';
  String _statusFilter = 'All';
  String _sortField    = 'created_at';
  bool   _sortAsc      = false;
  final _searchCtrl = TextEditingController();

  RealtimeChannel? _channel;
  Timer?           _debounce;

  @override
  void initState() { super.initState(); _load(); _subscribeRealtime(); }
  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    if (_channel != null) SupabaseService.client.removeChannel(_channel!);
    super.dispose();
  }

  void _subscribeRealtime() {
    _channel = SupabaseService.client.channel('admin-organizers');
    for (final table in ['organizers', 'events']) {
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
    if (mounted) setState(() { if (!silent) _loading = true; _error = false; });
    try {
      final results = await Future.wait([
        SupabaseService.client.from('organizers')
            .select('organizer_id, user_id, full_name, organization, is_active, created_at')
            .order('created_at', ascending: false),
        SupabaseService.client.from('events').select('organizer_id'),
      ]);
      if (!mounted) return;
      final organizers = List<Map<String, dynamic>>.from(results[0] as List);
      final eventRows  = results[1] as List;
      final counts = <String, int>{};
      for (final r in eventRows) {
        final id = (r as Map<String, dynamic>)['organizer_id'] as String?;
        if (id != null) counts[id] = (counts[id] ?? 0) + 1;
      }
      _all         = organizers;
      _eventCounts = counts;
      _loading     = false;
      _applyFilter();
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = true; _errorMsg = e.toString(); });
    }
  }

  void _applyFilter() {
    final q = _search.toLowerCase();
    var list = _all.where((o) {
      if (_statusFilter == 'Active'    && o['is_active'] != true) return false;
      if (_statusFilter == 'Inactive'  && o['is_active'] == true) return false;
      if (_statusFilter == 'No Auth'   && o['user_id']  != null)  return false;
      if (_statusFilter == '0 Events' &&
          (_eventCounts[o['organizer_id'] as String? ?? ''] ?? 0) > 0) { return false; }
      if (q.isNotEmpty) {
        final name = (o['full_name']    as String? ?? '').toLowerCase();
        final id   = (o['organizer_id'] as String? ?? '').toLowerCase();
        final org  = (o['organization'] as String? ?? '').toLowerCase();
        if (!name.contains(q) && !id.contains(q) && !org.contains(q)) return false;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      int cmp;
      if (_sortField == 'full_name') {
        cmp = (a['full_name'] as String? ?? '').compareTo(b['full_name'] as String? ?? '');
      } else if (_sortField == 'organizer_id') {
        cmp = (a['organizer_id'] as String? ?? '').compareTo(b['organizer_id'] as String? ?? '');
      } else if (_sortField == 'event_count') {
        final ac = _eventCounts[a['organizer_id'] as String? ?? ''] ?? 0;
        final bc = _eventCounts[b['organizer_id'] as String? ?? ''] ?? 0;
        cmp = ac.compareTo(bc);
      } else if (_sortField == 'is_active') {
        final ai = a['is_active'] == true ? 1 : 0;
        final bi = b['is_active'] == true ? 1 : 0;
        cmp = bi.compareTo(ai);
      } else {
        cmp = ((a['created_at'] as String?) ?? '').compareTo((b['created_at'] as String?) ?? '');
      }
      return _sortAsc ? cmp : -cmp;
    });

    setState(() => _filtered = list);
  }

  void _setSort(String field) {
    if (_sortField == field) {
      _sortAsc = !_sortAsc;
    } else {
      _sortField = field;
      _sortAsc   = field == 'full_name' || field == 'organizer_id' || field == 'is_active';
    }
    _applyFilter();
  }

  Future<void> _toggleActive(String id, bool cur) async {
    final ok = await WebAlert.confirm(
      context:      context,
      title:        cur ? 'Deactivate Organizer?' : 'Activate Organizer?',
      message:      cur
          ? 'This organizer will lose access and cannot manage events.'
          : 'This organizer will regain access to manage events.',
      confirmLabel: cur ? 'Deactivate' : 'Activate',
      confirmColor: cur ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
      iconColor:    cur ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
      iconBg:       cur ? const Color(0xFFFFFBEB) : const Color(0xFFECFDF5),
      icon:         cur ? Icons.person_off_outlined : Icons.person_add_outlined,
    );
    if (ok != true) return;
    try {
      await SupabaseService.client.from('organizers')
          .update({'is_active': !cur}).eq('organizer_id', id);
      final idx = _all.indexWhere((o) => o['organizer_id'] == id);
      if (idx != -1) { _all[idx] = {..._all[idx], 'is_active': !cur}; _applyFilter(); }
    } catch (e) { if (mounted) _snack('Failed: $e'); }
  }

  Future<void> _editOrganizer(Map<String, dynamic> org) async {
    final result = await showDialog<Map<String, dynamic>?>(
      context: context, builder: (_) => _OrganizerDialog(
        organizer: org,
        eventCount: _eventCounts[org['organizer_id'] as String? ?? ''] ?? 0,
      ));
    if (result == null) return;
    try {
      await SupabaseService.client.from('organizers')
          .update(result).eq('organizer_id', org['organizer_id'] as String);
      final idx = _all.indexWhere((o) => o['organizer_id'] == org['organizer_id']);
      if (idx != -1) { _all[idx] = {..._all[idx], ...result}; _applyFilter(); }
      if (mounted) WebAlert.success(context: context, title: 'Saved', message: 'Organizer profile updated.');
    } catch (e) { if (mounted) _snack('Failed: $e'); }
  }

  Future<void> _addOrganizer() async {
    final nextId = await _nextOrgId();
    if (!mounted) return;
    String? createdName;
    final ok = await showDialog<bool?>(
      context: context,
      builder: (_) => _OrganizerDialog(
        organizer: null,
        suggestedId: nextId,
        onCreate: (data) async {
          try {
            createdName = data['full_name'] as String?;
            final password     = data['password'] as String;
            final organizerData = Map<String, dynamic>.from(data)..remove('password');
            final res = await SupabaseService.client.functions.invoke(
              'create-organizer',
              body: {...organizerData, 'password': password},
            );
            final body = res.data is Map
                ? Map<String, dynamic>.from(res.data as Map)
                : null;
            if (res.status != 200) {
              return body?['message'] as String? ?? 'Failed to create account.';
            }
            return null; // success
          } catch (e) {
            return 'Failed: $e';
          }
        },
      ),
    );
    if (ok != true || !mounted) return;
    await _load();
    if (mounted) {
      WebAlert.success(
        context: context,
        title: 'Account Created',
        message: 'Organizer account for ${createdName ?? 'organizer'} has been created.',
      );
    }
  }

  Future<String> _nextOrgId() async {
    try {
      final rows = await SupabaseService.client.from('organizers')
          .select('organizer_id').order('organizer_id', ascending: false).limit(1);
      final list = rows as List;
      if (list.isEmpty) return 'Org0001';
      final last = list.first['organizer_id'] as String? ?? 'Org0000';
      final num  = int.tryParse(last.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return 'Org${(num + 1).toString().padLeft(4, '0')}';
    } catch (_) { return 'Org0001'; }
  }

  Future<void> _deleteOrganizer(String id, String name) async {
    final eventCount = _eventCounts[id] ?? 0;
    final message = eventCount > 0
        ? 'This will permanently delete $name\'s profile, their $eventCount event${eventCount == 1 ? '' : 's'}, and all student registrations for those events.'
        : 'This will permanently remove $name\'s profile and their account link.';
    final ok = await WebAlert.confirm(
      context: context, title: 'Delete Organizer?',
      message: message,
      confirmLabel: 'Delete',
    );
    if (ok != true) return;
    try {
      await SupabaseService.client.from('organizers').delete().eq('organizer_id', id);
      _all.removeWhere((o) => o['organizer_id'] == id);
      _eventCounts.remove(id);
      _applyFilter();
      if (mounted) WebAlert.success(context: context, title: 'Deleted', message: 'Organizer removed.');
    } catch (e) { if (mounted) _snack('Failed: $e'); }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: const Color(0xFFEF4444)));

  @override
  Widget build(BuildContext context) {
    final t             = AdminTk(Theme.of(context).brightness == Brightness.dark);
    final totalCount    = _all.length;
    final activeCount   = _all.where((o) => o['is_active'] == true).length;
    final inactiveCount = totalCount - activeCount;
    final noAuthCount   = _all.where((o) => o['user_id'] == null).length;
    final noEventsCount = _all.where((o) =>
        (_eventCounts[o['organizer_id'] as String? ?? ''] ?? 0) == 0).length;
    final hasFilter     = _search.isNotEmpty || _statusFilter != 'All';
    final filterDesc    = [
      if (_statusFilter != 'All') _statusFilter,
      if (_search.isNotEmpty)     '"$_search"',
    ].join(' · ');
    final emptySubtitle = filterDesc.isEmpty
        ? 'Add your first organizer to get started.'
        : 'No organizers match $filterDesc.';

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    if (_error) {
      return _ErrorState(message: _errorMsg, onRetry: _load);
    }

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Page header ───────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.fromLTRB(kWebPad, 20, kWebPad, 16),
        color: t.card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Organizers',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 22,
                    fontWeight: FontWeight.w800, color: t.text)),
              const SizedBox(height: 2),
              Text('$totalCount total · $activeCount active · $noAuthCount unlinked',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.sub)),
            ])),
            WebBtn(label: 'Add Organizer', icon: Icons.add_rounded, onTap: _addOrganizer),
          ]),
          const SizedBox(height: 16),
          // ── Stat tiles ────────────────────────────────────────────────
          Row(children: [
            _StudentStatCard(label: 'Total Organizers', value: '$totalCount',
                color: kGold, icon: Icons.badge_rounded),
            const SizedBox(width: 10),
            _StudentStatCard(label: 'Active', value: '$activeCount',
                color: const Color(0xFF10B981), icon: Icons.check_circle_rounded),
            const SizedBox(width: 10),
            _StudentStatCard(
              label: 'Inactive',
              value: '$inactiveCount',
              color: inactiveCount > 0 ? t.muted : const Color(0xFF10B981),
              icon: Icons.person_off_outlined,
            ),
            const SizedBox(width: 10),
            _StudentStatCard(
              label: 'No Auth',
              value: '$noAuthCount',
              color: noAuthCount > 0 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
              icon: Icons.warning_amber_rounded,
            ),
            const SizedBox(width: 10),
            _StudentStatCard(
              label: 'No Events',
              value: '$noEventsCount',
              color: noEventsCount > 0 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
              icon: Icons.event_busy_rounded,
            ),
          ]),
        ]),
      ),
      // ── Filter bar ───────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.fromLTRB(kWebPad, 8, kWebPad, 8),
        decoration: BoxDecoration(
          color: t.inputBg,
          border: Border(bottom: BorderSide(color: t.border)),
        ),
        child: Row(children: [
          WebSearchField(
            controller: _searchCtrl, hint: 'Search name, ID, or org…',
            onChanged: (v) { _search = v; _applyFilter(); }, width: 200),
          const SizedBox(width: 14),
          Container(width: 1, height: 18, color: t.border),
          const SizedBox(width: 14),
          Text('Status:',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                fontWeight: FontWeight.w600, color: t.text)),
          const SizedBox(width: 8),
          for (final f in ['All', 'Active', 'Inactive', 'No Auth', '0 Events']) ...[
            WebFilterChip(
              label: f, selected: _statusFilter == f,
              onTap: () { _statusFilter = f; _applyFilter(); },
              count: f == 'All'       ? totalCount
                   : f == 'Active'    ? activeCount
                   : f == 'Inactive'  ? inactiveCount
                   : f == 'No Auth'   ? noAuthCount
                   :                    noEventsCount,
              selectedColor: f == 'No Auth'   ? const Color(0xFFF59E0B)
                           : f == '0 Events'  ? _kAccent
                           : f == 'Inactive'  ? t.muted
                           : f == 'Active'    ? const Color(0xFF10B981)
                           :                    kGold,
            ),
            const SizedBox(width: 6),
          ],
          if (hasFilter) ...[
            const Spacer(),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  _search = ''; _statusFilter = 'All';
                  _searchCtrl.clear();
                  _applyFilter();
                },
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.close_rounded, size: 13, color: t.muted),
                  const SizedBox(width: 4),
                  Text('Clear filters', style: TextStyle(fontFamily: 'Poppins',
                      fontSize: 11.5, fontWeight: FontWeight.w600, color: t.muted)),
                ]),
              ),
            ),
          ],
        ]),
      ),
      // ── Body ─────────────────────────────────────────────────────────
        if (_filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(kWebPad),
            child: WebEmptyState(
              icon: Icons.badge_outlined,
              title: 'No organizers found',
              subtitle: emptySubtitle,
              action: hasFilter
                  ? TextButton(
                      onPressed: () {
                        _search = ''; _statusFilter = 'All';
                        _searchCtrl.clear();
                        _applyFilter();
                      },
                      child: const Text('Clear all filters',
                        style: TextStyle(fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600, color: _kAccent)))
                  : null),
          )
        else
          Padding(
            padding: const EdgeInsets.all(kWebPad),
            child: WebCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                _OrganizerTableHeader(
                  sortField: _sortField,
                  sortAsc:   _sortAsc,
                  onSort:    _setSort,
                ),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: t.border),
                  itemBuilder: (_, i) {
                    final o  = _filtered[i];
                    final id = o['organizer_id'] as String? ?? '';
                    return _OrganizerRow(
                      org:        o,
                      eventCount: _eventCounts[id] ?? 0,
                      onEdit:   () => _editOrganizer(o),
                      onToggle: () => _toggleActive(id, o['is_active'] == true),
                      onDelete: () => _deleteOrganizer(id, o['full_name'] as String? ?? ''),
                    );
                  },
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: t.border))),
                  child: Text(
                    hasFilter
                        ? 'Showing ${_filtered.length} of $totalCount organizers'
                        : '${_filtered.length} organizers total',
                    style: TextStyle(fontFamily: 'Poppins',
                        fontSize: 11.5, color: t.muted)),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

// ─── Sortable table header for Organizers ──────────────────────────────────

class _OrganizerTableHeader extends StatelessWidget {
  final String sortField;
  final bool   sortAsc;
  final void Function(String) onSort;
  const _OrganizerTableHeader({
    required this.sortField, required this.sortAsc, required this.onSort});

  Widget _sortCol(String label, String field, {int flex = 1}) => Expanded(
    flex: flex,
    child: _SortColBtn(
      label: label, field: field,
      active: sortField == field,
      asc:    sortAsc && sortField == field,
      onSort: onSort,
    ),
  );

  Widget _staticCol(String label, Color subColor, {int flex = 1}) => Expanded(
    flex: flex,
    child: Text(label, style: TextStyle(fontFamily: 'Poppins',
        fontSize: 10.5, fontWeight: FontWeight.w700, color: subColor, letterSpacing: 0.8)),
  );

  @override
  Widget build(BuildContext context) {
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
    return Container(
      padding: const EdgeInsets.only(left: 23, right: 20, top: 10, bottom: 10),
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(children: [
        const SizedBox(width: 52),
        _sortCol('FULL NAME',  'full_name',    flex: 3),
        _sortCol('ORG ID',     'organizer_id'),
        _sortCol('EVENTS',     'event_count'),
        _sortCol('STATUS',     'is_active'),
        _staticCol('AUTH', t.sub),
        _sortCol('CREATED',    'created_at',   flex: 2),
        const SizedBox(width: 108),
      ]),
    );
  }
}

class _OrganizerRow extends StatefulWidget {
  final Map<String, dynamic> org;
  final int          eventCount;
  final VoidCallback onEdit, onToggle, onDelete;
  const _OrganizerRow({
    required this.org, required this.eventCount,
    required this.onEdit, required this.onToggle, required this.onDelete});
  @override State<_OrganizerRow> createState() => _OrganizerRowState();
}
class _OrganizerRowState extends State<_OrganizerRow> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final t           = AdminTk(Theme.of(context).brightness == Brightness.dark);
    final o           = widget.org;
    final active      = o['is_active'] == true;
    final linked      = o['user_id'] != null;
    final orgName     = o['organization'] as String?;
    final orgId       = o['organizer_id'] as String? ?? '—';
    final initials    = (o['full_name'] as String? ?? '?').trim().split(' ')
        .where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).take(2).join();
    final avatarColor = active ? kGold : t.muted;

    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _h ? kGold.withValues(alpha: 0.04) : Colors.transparent,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 3, color: active ? Colors.transparent : t.muted.withValues(alpha: 0.30)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(children: [
                  // Avatar
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: avatarColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: avatarColor.withValues(alpha: 0.22)),
                    ),
                    child: Center(child: Text(initials,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: avatarColor.withValues(alpha: active ? 1.0 : 0.55)))),
                  ),
                  const SizedBox(width: 12),
                  // Name + organization + auth warning
                  Expanded(flex: 3, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(o['full_name'] as String? ?? '—',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                            fontWeight: FontWeight.w600, color: active ? t.text : t.muted),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (orgName != null && orgName.isNotEmpty)
                        Text(orgName,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5,
                              color: t.sub),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (!linked)
                        const Text('No auth account',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                              color: Color(0xFFF59E0B), fontWeight: FontWeight.w600)),
                    ],
                  )),
                  // Org ID — gold-tinted badge, hugs content
                  Expanded(child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: kGold.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: kGold.withValues(alpha: 0.22)),
                      ),
                      child: Text(orgId,
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: kGold.withValues(alpha: 0.90), letterSpacing: 0.4),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  )),
                  // Events count
                  Expanded(child: widget.eventCount > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: kGold.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.event_rounded, size: 11,
                              color: kGold.withValues(alpha: 0.80)),
                          const SizedBox(width: 4),
                          Text('${widget.eventCount}',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: kGold.withValues(alpha: 0.90))),
                        ]))
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: t.muted.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('0', style: TextStyle(fontFamily: 'Poppins',
                            fontSize: 11, fontWeight: FontWeight.w500, color: t.muted)))),
                  // Status badge
                  Expanded(child: WebStatusBadge(
                    label: active ? 'Active' : 'Inactive',
                    color: active ? const Color(0xFF10B981) : t.muted)),
                  // Account link status
                  Expanded(child: Row(children: [
                    Container(width: 7, height: 7,
                        decoration: BoxDecoration(
                          color: linked ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                          shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(linked ? 'Linked' : 'No account',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                          fontWeight: linked ? FontWeight.w400 : FontWeight.w600,
                          color: linked ? const Color(0xFF10B981) : const Color(0xFFF59E0B))),
                  ])),
                  // Created date
                  Expanded(flex: 2, child: Text(webFmtDate(o['created_at'] as String?),
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: t.muted))),
                  // Actions — fade in on row hover
                  AnimatedOpacity(
                    opacity: _h ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: SizedBox(
                      width: 108,
                      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        _ActBtn(icon: Icons.edit_outlined,
                            color: _kAccent, tip: 'Edit', onTap: widget.onEdit),
                        const SizedBox(width: 6),
                        _ActBtn(
                          icon:  active ? Icons.person_off_outlined : Icons.person_add_outlined,
                          color: active ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                          tip:   active ? 'Deactivate' : 'Activate',
                          onTap: widget.onToggle),
                        const SizedBox(width: 6),
                        _ActBtn(icon: Icons.delete_outline_rounded,
                            color: const Color(0xFFEF4444), tip: 'Delete', onTap: widget.onDelete),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─── Organizer dialog ──────────────────────────────────────────────────────

class _OrganizerDialog extends StatefulWidget {
  final Map<String, dynamic>? organizer;
  final String?               suggestedId;
  final int                   eventCount;
  // For add mode only: returns an error message on failure, null on success.
  final Future<String?> Function(Map<String, dynamic>)? onCreate;
  const _OrganizerDialog({
    required this.organizer,
    this.suggestedId,
    this.eventCount = 0,
    this.onCreate,
  });
  @override State<_OrganizerDialog> createState() => _OrganizerDialogState();
}
class _OrganizerDialogState extends State<_OrganizerDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _scale, _fade;
  final _idCtrl         = TextEditingController();
  final _nameCtrl       = TextEditingController();
  final _orgCtrl        = TextEditingController();
  final _pwCtrl         = TextEditingController();
  final _confirmPwCtrl  = TextEditingController();
  bool  _pwHidden        = true;
  bool  _confirmPwHidden = true;
  bool  _saving          = false;

  bool get _isEdit => widget.organizer != null;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    _scale = Tween<double>(begin: 0.87, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    if (_isEdit) {
      _idCtrl.text   = widget.organizer!['organizer_id'] as String? ?? '';
      _nameCtrl.text = widget.organizer!['full_name']    as String? ?? '';
      _orgCtrl.text  = widget.organizer!['organization'] as String? ?? '';
    } else if (widget.suggestedId != null) {
      _idCtrl.text = widget.suggestedId!;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _idCtrl.dispose(); _nameCtrl.dispose(); _orgCtrl.dispose();
    _pwCtrl.dispose(); _confirmPwCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final rawId = _idCtrl.text.trim();
    final name  = _nameCtrl.text.trim();
    final org   = _orgCtrl.text.trim();
    final pw    = _pwCtrl.text;
    if (!_isEdit && !RegExp(r'^Org\d{4}$', caseSensitive: false).hasMatch(rawId)) {
      _snack('ID must be Org followed by 4 digits (e.g. Org0001)'); return;
    }
    // Normalize to consistent Org#### casing regardless of what user typed
    final id = 'Org${rawId.substring(3)}';
    if (name.isEmpty) { _snack('Full name is required'); return; }
    if (!_isEdit && pw.length < 6) {
      _snack('Password must be at least 6 characters'); return;
    }
    if (!_isEdit && _confirmPwCtrl.text != pw) {
      _snack('Passwords do not match'); return;
    }

    if (_isEdit) {
      Navigator.of(context).pop(<String, dynamic>{
        'full_name':    name,
        'organization': org.isEmpty ? null : org,
      });
      return;
    }

    // Add mode: call onCreate inside the dialog so we can show a loading state.
    setState(() => _saving = true);
    final err = await widget.onCreate!(<String, dynamic>{
      'organizer_id': id,
      'full_name':    name,
      'organization': org.isEmpty ? null : org,
      'password':     pw,
      'is_active':    true,
    });
    if (!mounted) return;
    if (err != null) {
      setState(() => _saving = false);
      _snack(err);
      return;
    }
    Navigator.of(context).pop(true); // true = success
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: Colors.red));

  @override
  Widget build(BuildContext context) {
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440, maxHeight: 680),
            child: _dialogShell(
              icon: Icons.badge_rounded, iconColor: kGold,
              title: _isEdit ? 'Edit Organizer' : 'Add Organizer',
              loading: _saving,
              body: Column(children: [
                if (_isEdit) ...[
                  _InfoNote(widget.eventCount > 0
                      ? 'This organizer has ${widget.eventCount} event${widget.eventCount == 1 ? '' : 's'}. Name and organization changes apply immediately.'
                      : 'This organizer has no events yet.'),
                  const SizedBox(height: 12),
                ],
                if (!_isEdit) ...[
                  _InfoNote('Admin-provisioned account. The organizer will log in using their ID in lowercase (e.g. org0001) as their username.'),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _idCtrl,
                    enabled: !_saving,
                    decoration: webInputDeco('Organizer ID (e.g. Org0001)', icon: Icons.tag_rounded, dark: t.dark),
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.text)),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _nameCtrl,
                  enabled: !_saving,
                  decoration: webInputDeco('Full Name', icon: Icons.person_outline_rounded, dark: t.dark),
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.text)),
                const SizedBox(height: 12),
                TextField(
                  controller: _orgCtrl,
                  enabled: !_saving,
                  decoration: webInputDeco('Organization / Department (optional)', icon: Icons.business_outlined, dark: t.dark),
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.text)),
                if (!_isEdit) ...[
                  const SizedBox(height: 14),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _idCtrl,
                    builder: (_, v, __) {
                      final id = v.text.trim().toLowerCase();
                      return _CredentialPreview(
                        username: id.isEmpty ? '—' : id,
                        isReady:  RegExp(r'^org\d{4}$').hasMatch(id),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pwCtrl,
                    obscureText: _pwHidden,
                    enabled: !_saving,
                    decoration: webInputDeco('Password', icon: Icons.lock_outline_rounded, dark: t.dark).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          _pwHidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          size: 18, color: t.sub,
                        ),
                        onPressed: () => setState(() => _pwHidden = !_pwHidden),
                      ),
                    ),
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.text),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _pwCtrl,
                    builder: (_, v, __) => _PasswordStrengthBar(password: v.text),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmPwCtrl,
                    obscureText: _confirmPwHidden,
                    enabled: !_saving,
                    decoration: webInputDeco('Confirm Password', icon: Icons.lock_outline_rounded, dark: t.dark).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          _confirmPwHidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          size: 18, color: t.sub,
                        ),
                        onPressed: () => setState(() => _confirmPwHidden = !_confirmPwHidden),
                      ),
                    ),
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.text),
                  ),
                ],
              ]),
              confirmLabel: _isEdit ? 'Save Changes' : 'Add Organizer',
              confirmColor: kGold,
              onConfirm: _submit,
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Events page (read-only)
// ═════════════════════════════════════════════════════════════════════════════

class _AdminEventsPage extends StatefulWidget {
  const _AdminEventsPage();
  @override State<_AdminEventsPage> createState() => _AdminEventsPageState();
}

class _AdminEventsPageState extends State<_AdminEventsPage> {
  bool   _loading = true, _error = false;
  String _errorMsg = '';
  List<Map<String, dynamic>> _all = [], _filtered = [];
  String _search       = '';
  String _statusFilter = 'All';
  String _typeFilter   = 'All';
  String _fillFilter   = 'All';
  String _sortField    = 'event_date';
  bool   _sortAsc      = false;
  final _searchCtrl = TextEditingController();

  RealtimeChannel? _channel;
  Timer?           _debounce;

  List<String> get _typeOptions {
    final types = _all
        .map((e) => e['event_type'] as String?)
        .whereType<String>()
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['All', ...types];
  }

  @override
  void initState() { super.initState(); _load(); _subscribeRealtime(); }
  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    if (_channel != null) SupabaseService.client.removeChannel(_channel!);
    super.dispose();
  }

  void _subscribeRealtime() {
    _channel = SupabaseService.client.channel('admin-events');
    for (final table in ['events', 'registrations']) {
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
    if (mounted) setState(() { if (!silent) _loading = true; _error = false; });
    try {
      final rows = await SupabaseService.client.from('events')
          .select('event_id, title, event_type, event_date, start_time, end_time, event_status, current_participants, max_participants, organizer_id, organizers(full_name, organization)')
          .order('event_date', ascending: false);
      if (!mounted) return;
      _all     = List<Map<String, dynamic>>.from(rows as List);
      _loading = false;
      _applyFilter();
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = true; _errorMsg = e.toString(); });
    }
  }

  void _applyFilter() {
    final q = _search.toLowerCase();
    var list = _all.where((e) {
      if (_statusFilter != 'All') {
        if (_statusFilter == 'ended') {
          if (_resolveDisplayStatus(e) != 'ended') return false;
        } else {
          if (e['event_status'] != _statusFilter) return false;
        }
      }
      if (_typeFilter   != 'All' && (e['event_type'] as String? ?? '') != _typeFilter) return false;
      if (_fillFilter == 'At Capacity') {
        final cur = (e['current_participants'] as int?) ?? 0;
        final max = (e['max_participants']     as int?) ?? 0;
        if (max == 0 || cur < max) return false;
      }
      if (q.isNotEmpty) {
        final title = (e['title']      as String? ?? '').toLowerCase();
        final org   = ((e['organizers'] as Map<String, dynamic>?)?['full_name'] as String? ?? '').toLowerCase();
        final type  = (e['event_type'] as String? ?? '').toLowerCase();
        if (!title.contains(q) && !org.contains(q) && !type.contains(q)) return false;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      int cmp;
      if (_sortField == 'title') {
        cmp = (a['title'] as String? ?? '').compareTo(b['title'] as String? ?? '');
      } else if (_sortField == 'organizer_name') {
        final an = ((a['organizers'] as Map<String, dynamic>?)?['full_name'] as String? ?? '');
        final bn = ((b['organizers'] as Map<String, dynamic>?)?['full_name'] as String? ?? '');
        cmp = an.compareTo(bn);
      } else if (_sortField == 'fill_rate') {
        final maxA = (a['max_participants'] as int?) ?? 0;
        final maxB = (b['max_participants'] as int?) ?? 0;
        final rA   = maxA > 0 ? ((a['current_participants'] as int? ?? 0) / maxA) : 0.0;
        final rB   = maxB > 0 ? ((b['current_participants'] as int? ?? 0) / maxB) : 0.0;
        cmp = rA.compareTo(rB);
      } else if (_sortField == 'event_status') {
        const order = {'ongoing': 0, 'upcoming': 1, 'ended': 2, 'completed': 3, 'cancelled': 4};
        final ao = order[_resolveDisplayStatus(a)] ?? 5;
        final bo = order[_resolveDisplayStatus(b)] ?? 5;
        cmp = ao.compareTo(bo);
      } else {
        cmp = ((a['event_date'] as String?) ?? '').compareTo((b['event_date'] as String?) ?? '');
      }
      return _sortAsc ? cmp : -cmp;
    });

    setState(() => _filtered = list);
  }

  void _setSort(String field) {
    if (_sortField == field) {
      _sortAsc = !_sortAsc;
    } else {
      _sortField = field;
      _sortAsc   = field == 'title' || field == 'event_status' || field == 'organizer_name';
    }
    _applyFilter();
  }

  Future<void> _cancelEvent(String id, String title) async {
    final ok = await WebAlert.confirm(
      context:      context,
      title:        'Cancel Event?',
      message:      '"$title" will be marked as Cancelled. Registered students will be affected. This cannot be undone.',
      confirmLabel: 'Cancel Event',
      confirmColor: const Color(0xFFEF4444),
      iconColor:    const Color(0xFFEF4444),
      iconBg:       const Color(0xFFFEF2F2),
      icon:         Icons.cancel_rounded,
    );
    if (ok != true) return;
    try {
      await SupabaseService.client.from('events')
          .update({'event_status': 'cancelled'}).eq('event_id', id);
      final idx = _all.indexWhere((e) => e['event_id'] == id);
      if (idx != -1) { _all[idx] = {..._all[idx], 'event_status': 'cancelled'}; _applyFilter(); }
      if (mounted) WebAlert.success(context: context, title: 'Cancelled', message: 'Event has been cancelled.');
    } catch (e) { if (mounted) _snack('Failed: $e'); }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: const Color(0xFFEF4444)));

  @override
  Widget build(BuildContext context) {
    final t              = AdminTk(Theme.of(context).brightness == Brightness.dark);
    final totalCount     = _all.length;
    final upcomingCount  = _all.where((e) => _resolveDisplayStatus(e) == 'upcoming').length;
    final ongoingCount   = _all.where((e) => _resolveDisplayStatus(e) == 'ongoing').length;
    final endedCount     = _all.where((e) => _resolveDisplayStatus(e) == 'ended').length;
    final completedCount = _all.where((e) => e['event_status'] == 'completed').length;
    final cancelledCount = _all.where((e) => e['event_status'] == 'cancelled').length;
    final atCapacityCount = _all.where((e) {
      final cur = (e['current_participants'] as int?) ?? 0;
      final max = (e['max_participants']     as int?) ?? 0;
      return max > 0 && cur >= max;
    }).length;
    final hasFilter = _search.isNotEmpty || _statusFilter != 'All' ||
                      _typeFilter != 'All'   || _fillFilter  != 'All';
    final typeOpts  = _typeOptions;
    final filterDesc = [
      if (_statusFilter != 'All') webEventStatusLabel(_statusFilter),
      if (_typeFilter   != 'All' && _typeFilter.isNotEmpty)
          '${_typeFilter[0].toUpperCase()}${_typeFilter.substring(1)}',
      if (_fillFilter   != 'All') _fillFilter,
      if (_search.isNotEmpty)     '"$_search"',
    ].join(' · ');
    final emptySubtitle = filterDesc.isEmpty
        ? 'No events have been created yet.'
        : 'No events match $filterDesc.';

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    if (_error) {
      return _ErrorState(message: _errorMsg, onRetry: _load);
    }

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Page header ───────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.fromLTRB(kWebPad, 20, kWebPad, 16),
        color: t.card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Events',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 22,
                    fontWeight: FontWeight.w800, color: t.text)),
              const SizedBox(height: 2),
              Text('$totalCount total · $upcomingCount upcoming · $ongoingCount ongoing',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.sub)),
            ])),
          ]),
          const SizedBox(height: 16),
          // ── Stat tiles ────────────────────────────────────────────────
          Row(children: [
            _StudentStatCard(label: 'Total Events', value: '$totalCount',
                color: _kAccent, icon: Icons.event_rounded),
            const SizedBox(width: 10),
            _StudentStatCard(label: 'Upcoming', value: '$upcomingCount',
                color: const Color(0xFF3B82F6), icon: Icons.schedule_rounded),
            const SizedBox(width: 10),
            _StudentStatCard(label: 'Ongoing', value: '$ongoingCount',
                color: const Color(0xFF10B981), icon: Icons.play_circle_rounded),
            const SizedBox(width: 10),
            _StudentStatCard(label: 'Ended', value: '${endedCount + completedCount}',
                color: const Color(0xFF6B7280), icon: Icons.check_circle_rounded),
            const SizedBox(width: 10),
            _StudentStatCard(
              label: 'Cancelled',
              value: '$cancelledCount',
              color: cancelledCount > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
              icon: Icons.cancel_rounded,
            ),
          ]),
        ]),
      ),
      // ── Filter bar ───────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.fromLTRB(kWebPad, 10, kWebPad, 10),
        decoration: BoxDecoration(
          color: t.inputBg,
          border: Border(bottom: BorderSide(color: t.border)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Status filter row
          Row(children: [
            WebSearchField(
              controller: _searchCtrl, hint: 'Search title, organizer, or type…',
              onChanged: (v) { _search = v; _applyFilter(); }, width: 200),
            const SizedBox(width: 14),
            Container(width: 1, height: 18, color: t.border),
            const SizedBox(width: 14),
            Text('Status:',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  fontWeight: FontWeight.w600, color: t.text)),
            const SizedBox(width: 8),
            WebFilterChip(
              label: 'All', selected: _statusFilter == 'All',
              onTap: () { _statusFilter = 'All'; _applyFilter(); },
              count: totalCount),
            const SizedBox(width: 6),
            for (final s in ['upcoming', 'ongoing', 'ended', 'completed', 'cancelled']) ...[
              WebFilterChip(
                label: webEventStatusLabel(s),
                selected: _statusFilter == s,
                onTap: () { _statusFilter = s; _applyFilter(); },
                count: s == 'upcoming' || s == 'ongoing' || s == 'ended'
                    ? _all.where((e) => _resolveDisplayStatus(e) == s).length
                    : _all.where((e) => e['event_status'] == s).length,
                selectedColor: webEventStatusColor(s)),
              const SizedBox(width: 6),
            ],
            if (hasFilter) ...[
              const Spacer(),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    _search = ''; _statusFilter = 'All';
                    _typeFilter = 'All'; _fillFilter = 'All';
                    _searchCtrl.clear();
                    _applyFilter();
                  },
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.close_rounded, size: 13, color: t.muted),
                  const SizedBox(width: 4),
                  Text('Clear filters', style: TextStyle(fontFamily: 'Poppins',
                      fontSize: 11.5, fontWeight: FontWeight.w600, color: t.muted)),
                ]),
              ),
            ),
          ],
        ]),
        // Type + Capacity — single compact row
        if (typeOpts.length > 1 || atCapacityCount > 0) ...[
          const SizedBox(height: 8),
          Row(children: [
            if (typeOpts.length > 1) ...[
              Text('Type:',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w600, color: t.text)),
              const SizedBox(width: 8),
              Container(
                height: 28,
                padding: const EdgeInsets.only(left: 10, right: 6),
                decoration: BoxDecoration(
                  color: _typeFilter != 'All'
                      ? _eventTypeColor(_typeFilter).withValues(alpha: 0.07)
                      : t.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _typeFilter != 'All'
                        ? _eventTypeColor(_typeFilter).withValues(alpha: 0.45)
                        : t.border,
                    width: _typeFilter != 'All' ? 1.5 : 1.0,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: typeOpts.contains(_typeFilter) ? _typeFilter : 'All',
                    isDense: true,
                    icon: Icon(Icons.keyboard_arrow_down_rounded, size: 14,
                        color: _typeFilter != 'All'
                            ? _eventTypeColor(_typeFilter) : t.muted),
                    onChanged: (v) {
                      if (v != null) { _typeFilter = v; _applyFilter(); }
                    },
                    selectedItemBuilder: (ctx) => typeOpts.map((typ) => Center(
                      child: Text(
                        typ == 'All' ? 'All Types'
                            : '${typ[0].toUpperCase()}${typ.substring(1)}',
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: _typeFilter != 'All'
                              ? _eventTypeColor(_typeFilter) : t.text,
                        )),
                    )).toList(),
                    items: typeOpts.map((typ) {
                      final cnt = typ == 'All' ? totalCount
                          : _all.where((e) =>
                              (e['event_type'] as String? ?? '') == typ).length;
                      final lbl = typ == 'All' ? 'All Types'
                          : '${typ[0].toUpperCase()}${typ.substring(1)}';
                      return DropdownMenuItem<String>(
                        value: typ,
                        child: Text('$lbl ($cnt)',
                          style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 12,
                            fontWeight: typ == _typeFilter
                                ? FontWeight.w700 : FontWeight.w400,
                            color: typ == 'All' ? t.text : _eventTypeColor(typ),
                          )),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
            if (typeOpts.length > 1 && atCapacityCount > 0) ...[
              const SizedBox(width: 12),
              Container(width: 1, height: 18, color: t.border),
              const SizedBox(width: 12),
            ],
            if (atCapacityCount > 0) ...[
              Text('Capacity:',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w600, color: t.text)),
                const SizedBox(width: 8),
                WebFilterChip(
                  label: 'At Capacity',
                  selected: _fillFilter == 'At Capacity',
                  onTap: () {
                    _fillFilter = _fillFilter == 'At Capacity' ? 'All' : 'At Capacity';
                    _applyFilter();
                  },
                  count: atCapacityCount,
                  selectedColor: const Color(0xFFEF4444)),
              ],
            ]),
          ],
        ]),
      ),
      // ── Body ─────────────────────────────────────────────────────────
        if (_filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(kWebPad),
            child: WebEmptyState(
              icon: Icons.event_outlined,
              title: 'No events found',
              subtitle: emptySubtitle,
              action: hasFilter
                  ? TextButton(
                      onPressed: () {
                        _search = ''; _statusFilter = 'All';
                        _typeFilter = 'All'; _fillFilter = 'All';
                        _searchCtrl.clear();
                        _applyFilter();
                      },
                      child: const Text('Clear all filters',
                        style: TextStyle(fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600, color: _kAccent)))
                  : null),
          )
        else
          Padding(
            padding: const EdgeInsets.all(kWebPad),
            child: WebCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                _EventTableHeader(
                  sortField: _sortField,
                  sortAsc:   _sortAsc,
                  onSort:    _setSort,
                ),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: t.border),
                  itemBuilder: (_, i) {
                    final e           = _filtered[i];
                    final dispStatus  = _resolveDisplayStatus(e);
                    return _EventRow(
                      event: e,
                      onCancel: (dispStatus == 'upcoming' || dispStatus == 'ongoing')
                          ? () => _cancelEvent(
                              e['event_id'] as String? ?? '',
                              e['title']    as String? ?? 'this event')
                          : null,
                    );
                  },
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: t.border))),
                  child: Text(
                    hasFilter
                        ? 'Showing ${_filtered.length} of $totalCount events'
                        : '${_filtered.length} events total',
                    style: TextStyle(fontFamily: 'Poppins',
                        fontSize: 11.5, color: t.muted)),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

// ─── Event display-status helper ─────────────────────────────────────────────
// Returns 'ended' when an 'upcoming'/'ongoing' event's date/time has passed,
// otherwise returns the raw DB status unchanged.

String _resolveDisplayStatus(Map<String, dynamic> event) {
  final db = (event['event_status'] as String? ?? '').toLowerCase();
  if (db != 'upcoming' && db != 'ongoing') return db;

  final dStr = event['event_date'] as String?;
  if (dStr == null) return db;
  try {
    final d    = DateTime.parse(dStr);
    final eDay = DateTime(d.year, d.month, d.day);
    final now  = DateTime.now();
    final nDay = DateTime(now.year, now.month, now.day);

    if (nDay.isAfter(eDay)) return 'ended';

    if (nDay == eDay) {
      final eStr = event['end_time'] as String?;
      if (eStr != null) {
        final p = eStr.split(':');
        final h = int.tryParse(p[0]) ?? 0;
        final m = p.length > 1 ? (int.tryParse(p[1]) ?? 0) : 0;
        if (now.isAfter(DateTime(d.year, d.month, d.day, h, m))) return 'ended';
      }
    }
  } catch (_) {}
  return db;
}

// ─── Event type color helper ──────────────────────────────────────────────────

String _fmtEventTime(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  try {
    final parts = raw.split(':');
    final h      = int.parse(parts[0]);
    final m      = int.parse(parts[1]);
    final period = h >= 12 ? 'PM' : 'AM';
    final h12    = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${m.toString().padLeft(2, '0')} $period';
  } catch (_) { return ''; }
}

String _fmtIsoTime(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  try {
    final dt     = DateTime.parse(iso).toLocal();
    final h      = dt.hour;
    final m      = dt.minute;
    final period = h >= 12 ? 'PM' : 'AM';
    final h12    = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${m.toString().padLeft(2, '0')} $period';
  } catch (_) { return ''; }
}

Color _eventTypeColor(String? type) => switch ((type ?? '').toLowerCase()) {
  'academic'  => const Color(0xFF6366F1),
  'cultural'  => const Color(0xFF9333EA),
  'sports'    => const Color(0xFF10B981),
  'seminar'   => const Color(0xFF0EA5E9),
  'workshop'  => const Color(0xFFF59E0B),
  'community' => const Color(0xFF14B8A6),
  _           => kMuted,
};

// ─── Sortable table header for Events ────────────────────────────────────────

class _EventTableHeader extends StatelessWidget {
  final String sortField;
  final bool   sortAsc;
  final void Function(String) onSort;
  const _EventTableHeader({
    required this.sortField, required this.sortAsc, required this.onSort});

  Widget _sortCol(String label, String field, {int flex = 1}) => Expanded(
    flex: flex,
    child: _SortColBtn(
      label: label, field: field,
      active: sortField == field,
      asc:    sortAsc && sortField == field,
      onSort: onSort,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
    return Container(
      padding: const EdgeInsets.only(left: 23, right: 20, top: 10, bottom: 10),
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(children: [
        const SizedBox(width: 52),
        _sortCol('EVENT',     'title',          flex: 3),
        _sortCol('ORGANIZER', 'organizer_name', flex: 2),
        _sortCol('DATE',      'event_date',     flex: 2),
        _sortCol('STATUS',    'event_status'),
        _sortCol('FILL RATE', 'fill_rate',      flex: 2),
        const SizedBox(width: 44),
      ]),
    );
  }
}

class _EventRow extends StatefulWidget {
  final Map<String, dynamic> event;
  final VoidCallback?         onCancel;
  const _EventRow({required this.event, this.onCancel});
  @override State<_EventRow> createState() => _EventRowState();
}
class _EventRowState extends State<_EventRow> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final e            = widget.event;
    final dbStatus     = e['event_status'] as String? ?? '';
    final dispStatus   = _resolveDisplayStatus(e);
    final type         = e['event_type']   as String? ?? '';
    final orgMap       = e['organizers']   as Map<String, dynamic>?;
    final orgName      = orgMap?['full_name']    as String? ?? '—';
    final orgSub       = orgMap?['organization'] as String?;
    final cur          = e['current_participants'] as int? ?? 0;
    final max          = e['max_participants']     as int? ?? 0;
    final pct          = max > 0 ? (cur / max).clamp(0.0, 1.0) : 0.0;
    final isFull       = max > 0 && cur >= max;
    final isAlmostFull = !isFull && pct >= 0.8;
    final isCancelled  = dbStatus == 'cancelled';
    final t            = AdminTk(Theme.of(context).brightness == Brightness.dark);
    final typeColor    = type.isEmpty ? t.muted : _eventTypeColor(type);
    final timeStr      = _fmtEventTime(e['start_time'] as String?);
    final barColor     = isCancelled  ? t.muted
                       : isFull       ? const Color(0xFFEF4444)
                       : isAlmostFull ? const Color(0xFFF59E0B)
                       :                const Color(0xFF10B981);

    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _h ? _kAccent.withValues(alpha: 0.025) : Colors.transparent,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: 3,
              color: isCancelled
                  ? const Color(0xFFEF4444).withValues(alpha: 0.35)
                  : Colors.transparent,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(children: [
                  // Event type icon container
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: typeColor.withValues(alpha: 0.18)),
                    ),
                    child: Icon(
                      type.isEmpty ? Icons.event_note_rounded : Icons.event_rounded,
                      size: 20,
                      color: typeColor.withValues(alpha: isCancelled ? 0.45 : 1.0),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Event title + type badge
                  Expanded(flex: 3, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(e['title'] as String? ?? '—',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isCancelled ? t.muted : t.text),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (type.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: typeColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('${type[0].toUpperCase()}${type.substring(1)}',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                                fontWeight: FontWeight.w700, color: typeColor,
                                letterSpacing: 0.3)),
                        ),
                      ],
                    ],
                  )),
                  // Organizer name + org subtitle
                  Expanded(flex: 2, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(orgName,
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                            fontWeight: FontWeight.w500, color: t.sub),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (orgSub != null && orgSub.isNotEmpty)
                        Text(orgSub,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5,
                              color: t.muted),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  )),
                  // Date + time
                  Expanded(flex: 2, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(webFmtDate(e['event_date'] as String?),
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                            color: isCancelled ? t.muted : t.sub)),
                      if (timeStr.isNotEmpty)
                        Text(timeStr, style: TextStyle(fontFamily: 'Poppins',
                            fontSize: 10.5, color: t.muted)),
                    ],
                  )),
                  // Status badge
                  Expanded(child: WebStatusBadge(
                    label: webEventStatusLabel(dispStatus),
                    color: webEventStatusColor(dispStatus))),
                  // Fill rate: count + capacity badge + gradient bar
                  Expanded(flex: 2, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(children: [
                        Text(max > 0 ? '$cur / $max' : '$cur / ∞',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isCancelled ? t.muted : t.text)),
                        const SizedBox(width: 6),
                        if (isFull)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('Full',
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFEF4444))),
                          )
                        else if (isAlmostFull)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('Almost Full',
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFF59E0B))),
                          ),
                      ]),
                      const SizedBox(height: 5),
                      Container(
                        height: 4,
                        clipBehavior: Clip.hardEdge,
                        decoration: BoxDecoration(
                          color: t.border,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: pct > 0
                          ? Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: pct,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [barColor.withValues(alpha: 0.60), barColor],
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : null,
                      ),
                    ],
                  )),
                  // Cancel action — fades in on hover; placeholder keeps layout stable
                  AnimatedOpacity(
                    opacity: _h && widget.onCancel != null ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: SizedBox(
                      width: 44,
                      child: widget.onCancel != null
                          ? _ActBtn(
                              icon:  Icons.cancel_outlined,
                              color: const Color(0xFFEF4444),
                              tip:   'Cancel Event',
                              onTap: widget.onCancel!,
                            )
                          : null,
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Registrations page (read-only)
// ═════════════════════════════════════════════════════════════════════════════

class _AdminRegistrationsPage extends StatefulWidget {
  const _AdminRegistrationsPage();
  @override State<_AdminRegistrationsPage> createState() => _AdminRegistrationsPageState();
}

class _AdminRegistrationsPageState extends State<_AdminRegistrationsPage> {
  bool   _loading = true, _error = false;
  String _errorMsg = '';
  List<Map<String, dynamic>> _all = [], _filtered = [];
  String _search       = '';
  String _statusFilter = 'All';
  String _eventFilter  = 'All';
  String _sortField    = 'registered_at';
  bool   _sortAsc      = false;
  final _searchCtrl = TextEditingController();

  RealtimeChannel? _channel;
  Timer?           _debounce;

  static const _kStatuses = [
    'pending', 'qr_scanned', 'photo_required',
    'photo_submitted', 'checked_in', 'rejected',
  ];

  List<String> get _eventOptions {
    final titles = _all
        .map((r) => r['event_title'] as String?)
        .whereType<String>()
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['All', ...titles];
  }

  @override
  void initState() { super.initState(); _load(); _subscribeRealtime(); }
  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    if (_channel != null) SupabaseService.client.removeChannel(_channel!);
    super.dispose();
  }

  void _subscribeRealtime() {
    _channel = SupabaseService.client.channel('admin-registrations')
      ..on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(event: '*', schema: 'public', table: 'registrations'),
        (_, [__]) => _debounceLoad(),
      )
      ..subscribe();
  }

  void _debounceLoad() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted) _load(silent: true);
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (mounted) setState(() { if (!silent) _loading = true; _error = false; });
    try {
      final rows = await SupabaseService.client.from('registrations')
          .select('id, student_name, student_school_id, event_title, status, registered_at, checked_in_at, selfie_url, student_user_id')
          .order('registered_at', ascending: false)
          .limit(300);
      if (!mounted) return;
      _all     = List<Map<String, dynamic>>.from(rows as List);
      _loading = false;
      _applyFilter();
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = true; _errorMsg = e.toString(); });
    }
  }

  void _applyFilter() {
    final q = _search.toLowerCase();
    var list = _all.where((r) {
      if (_statusFilter != 'All' && r['status'] != _statusFilter) return false;
      if (_eventFilter  != 'All' && (r['event_title'] as String? ?? '') != _eventFilter) return false;
      if (q.isNotEmpty) {
        final name  = (r['student_name']      as String? ?? '').toLowerCase();
        final lrn   = (r['student_school_id'] as String? ?? '').toLowerCase();
        final event = (r['event_title']        as String? ?? '').toLowerCase();
        if (!name.contains(q) && !lrn.contains(q) && !event.contains(q)) return false;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      int cmp;
      if (_sortField == 'student_name') {
        cmp = (a['student_name'] as String? ?? '').compareTo(b['student_name'] as String? ?? '');
      } else if (_sortField == 'event_title') {
        cmp = (a['event_title'] as String? ?? '').compareTo(b['event_title'] as String? ?? '');
      } else if (_sortField == 'status') {
        const order = {
          'photo_submitted': 0, 'pending': 1, 'qr_scanned': 2,
          'photo_required': 3,  'checked_in': 4, 'rejected': 5,
        };
        final ao = order[a['status'] as String? ?? ''] ?? 6;
        final bo = order[b['status'] as String? ?? ''] ?? 6;
        cmp = ao.compareTo(bo);
      } else if (_sortField == 'checked_in_at') {
        final aDate = (a['checked_in_at'] as String?) ?? '';
        final bDate = (b['checked_in_at'] as String?) ?? '';
        if (aDate.isEmpty && bDate.isEmpty) { cmp = 0; }
        else if (aDate.isEmpty) { return 1; }
        else if (bDate.isEmpty) { return -1; }
        else { cmp = aDate.compareTo(bDate); }
      } else {
        cmp = ((a['registered_at'] as String?) ?? '').compareTo((b['registered_at'] as String?) ?? '');
      }
      return _sortAsc ? cmp : -cmp;
    });

    setState(() => _filtered = list);
  }

  void _setSort(String field) {
    if (_sortField == field) {
      _sortAsc = !_sortAsc;
    } else {
      _sortField = field;
      _sortAsc   = field == 'student_name' || field == 'event_title' || field == 'status';
    }
    _applyFilter();
  }

  Future<void> _reviewPhoto(Map<String, dynamic> reg) async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _PhotoReviewDialog(reg: reg),
    );
    if (result == null || !mounted) return;
    final id    = reg['id']           as String? ?? '';
    final sName = reg['student_name'] as String? ?? 'Student';
    try {
      if (result == 'approve') {
        final now = DateTime.now().toUtc().toIso8601String();
        await SupabaseService.client.from('registrations')
            .update({'status': 'checked_in', 'checked_in_at': now}).eq('id', id);
        final idx = _all.indexWhere((r) => r['id'] == id);
        if (idx != -1) {
          _all[idx] = {..._all[idx], 'status': 'checked_in', 'checked_in_at': now};
          _applyFilter();
        }
        if (mounted) { WebAlert.success(context: context, title: 'Approved',
            message: '$sName has been checked in.'); }
      } else {
        await SupabaseService.client.from('registrations')
            .update({'status': 'rejected'}).eq('id', id);
        final idx = _all.indexWhere((r) => r['id'] == id);
        if (idx != -1) { _all[idx] = {..._all[idx], 'status': 'rejected'}; _applyFilter(); }
        if (mounted) { WebAlert.success(context: context, title: 'Rejected',
            message: "$sName's submission has been rejected."); }
      }
    } catch (e) { if (mounted) _snack('Failed: $e'); }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: const Color(0xFFEF4444)));

  @override
  Widget build(BuildContext context) {
    final t              = AdminTk(Theme.of(context).brightness == Brightness.dark);
    final totalCount     = _all.length;
    final pendingCount   = _all.where((r) => r['status'] == 'pending').length;
    final checkedInCount = _all.where((r) => r['status'] == 'checked_in').length;
    final rejectedCount  = _all.where((r) => r['status'] == 'rejected').length;
    final needsReview    = _all.where((r) => r['status'] == 'photo_submitted').length;
    final checkInRate    = totalCount > 0
        ? (checkedInCount / totalCount * 100).toStringAsFixed(0)
        : '0';
    final eventOpts = _eventOptions;
    final hasFilter = _search.isNotEmpty || _statusFilter != 'All' || _eventFilter != 'All';
    final filterDesc = [
      if (_statusFilter != 'All') webStatusLabel(_statusFilter),
      if (_eventFilter  != 'All') _eventFilter,
      if (_search.isNotEmpty)     '"$_search"',
    ].join(' · ');
    final emptySubtitle = filterDesc.isEmpty
        ? 'No registrations have been recorded yet.'
        : 'No registrations match $filterDesc.';

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    if (_error) {
      return _ErrorState(message: _errorMsg, onRetry: _load);
    }

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Page header ───────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.fromLTRB(kWebPad, 20, kWebPad, 16),
        color: t.card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Registrations',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 22,
                    fontWeight: FontWeight.w800, color: t.text)),
              const SizedBox(height: 2),
              Text('$totalCount total · $checkedInCount checked in · $checkInRate% rate',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.sub)),
            ])),
          ]),
          const SizedBox(height: 16),
          // ── Stat tiles ────────────────────────────────────────────────
          Row(children: [
            _StudentStatCard(label: 'Total', value: '$totalCount',
                color: _kAccent, icon: Icons.how_to_reg_rounded),
            const SizedBox(width: 10),
            _StudentStatCard(
              label: 'Pending',
              value: '$pendingCount',
              color: pendingCount > 0 ? const Color(0xFF3B82F6) : const Color(0xFF10B981),
              icon: Icons.hourglass_top_rounded,
            ),
            const SizedBox(width: 10),
            _StudentStatCard(label: 'Checked In', value: '$checkedInCount',
                color: const Color(0xFF10B981), icon: Icons.verified_rounded),
            const SizedBox(width: 10),
            _StudentStatCard(
              label: 'Needs Review',
              value: '$needsReview',
              color: needsReview > 0 ? const Color(0xFF8B5CF6) : const Color(0xFF10B981),
              icon: Icons.photo_camera_outlined,
            ),
            const SizedBox(width: 10),
            _StudentStatCard(
              label: 'Rejected',
              value: '$rejectedCount',
              color: rejectedCount > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
              icon: Icons.cancel_outlined,
            ),
          ]),
          // ── Check-in pipeline bar ───────────────────────────────────────
          if (totalCount > 0) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 6,
                child: Row(children: [
                  if (checkedInCount > 0) Flexible(flex: checkedInCount,
                      child: Container(color: const Color(0xFF10B981))),
                  if (needsReview > 0) Flexible(flex: needsReview,
                      child: Container(color: const Color(0xFF8B5CF6))),
                  if (pendingCount > 0) Flexible(flex: pendingCount,
                      child: Container(color: const Color(0xFF3B82F6))),
                  if (rejectedCount > 0) Flexible(flex: rejectedCount,
                      child: Container(color: const Color(0xFFEF4444))),
                  Flexible(
                    flex: (totalCount - checkedInCount - needsReview - pendingCount - rejectedCount)
                        .clamp(0, totalCount),
                    child: Container(color: t.border),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 5),
            Wrap(spacing: 12, runSpacing: 4, children: [
              _RegLegend(color: const Color(0xFF10B981), label: '$checkInRate% checked in'),
              if (needsReview > 0)
                _RegLegend(color: const Color(0xFF8B5CF6), label: '$needsReview need review'),
              _RegLegend(color: const Color(0xFF3B82F6), label: '$pendingCount pending'),
              if (rejectedCount > 0)
                _RegLegend(color: const Color(0xFFEF4444), label: '$rejectedCount rejected'),
            ]),
          ],
          // ── Needs-review urgent banner ──────────────────────────────────
          if (needsReview > 0) ...[
            const SizedBox(height: 10),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () { _statusFilter = 'photo_submitted'; _applyFilter(); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.22)),
                  ),
                  child: Row(children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.photo_camera_outlined, size: 16, color: Color(0xFF8B5CF6)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        '$needsReview ${needsReview == 1 ? 'registration needs' : 'registrations need'} photo review',
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                            fontWeight: FontWeight.w700, color: Color(0xFF8B5CF6))),
                      Text('Tap to filter and review submitted selfies',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5, color: t.sub)),
                    ])),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Review Now', style: TextStyle(fontFamily: 'Poppins',
                          fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ]),
                ),
              ),
            ),
          ],
        ]),
      ),
      // ── Filter bar ───────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.fromLTRB(kWebPad, 8, kWebPad, 8),
        decoration: BoxDecoration(
          color: t.inputBg,
          border: Border(bottom: BorderSide(color: t.border)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Status filter row
          Row(children: [
            WebSearchField(
              controller: _searchCtrl, hint: 'Search student, LRN, or event…',
              onChanged: (v) { _search = v; _applyFilter(); }, width: 200),
            const SizedBox(width: 14),
            Container(width: 1, height: 18, color: t.border),
            const SizedBox(width: 14),
            Text('Status:',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  fontWeight: FontWeight.w600, color: t.text)),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  WebFilterChip(
                    label: 'All', selected: _statusFilter == 'All',
                    onTap: () { _statusFilter = 'All'; _applyFilter(); },
                    count: totalCount),
                  const SizedBox(width: 6),
                  for (final s in _kStatuses) ...[
                    WebFilterChip(
                      label: webStatusLabel(s),
                      selected: _statusFilter == s,
                      onTap: () { _statusFilter = s; _applyFilter(); },
                      count: _all.where((r) => r['status'] == s).length,
                      selectedColor: webStatusColor(s)),
                    const SizedBox(width: 6),
                  ],
                ]),
              ),
            ),
            if (hasFilter) ...[
              const SizedBox(width: 8),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    _search = ''; _statusFilter = 'All'; _eventFilter = 'All';
                    _searchCtrl.clear();
                    _applyFilter();
                  },
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.close_rounded, size: 13, color: t.muted),
                    const SizedBox(width: 4),
                    Text('Clear filters', style: TextStyle(fontFamily: 'Poppins',
                        fontSize: 11.5, fontWeight: FontWeight.w600, color: t.muted)),
                  ]),
                ),
              ),
            ],
          ]),
          // Event filter row — shown only when there are multiple distinct events
          if (eventOpts.length > 1) ...[
            const SizedBox(height: 8),
            Row(children: [
              Text('Event:',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w600, color: t.text)),
              const SizedBox(width: 8),
              Container(
                height: 28,
                padding: const EdgeInsets.only(left: 10, right: 6),
                decoration: BoxDecoration(
                  color: _eventFilter != 'All'
                      ? _kAccent.withValues(alpha: 0.07) : t.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _eventFilter != 'All'
                        ? _kAccent.withValues(alpha: 0.45) : t.border,
                    width: _eventFilter != 'All' ? 1.5 : 1.0,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: eventOpts.contains(_eventFilter) ? _eventFilter : 'All',
                    isDense: true,
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                        fontWeight: FontWeight.w600, color: t.text),
                    selectedItemBuilder: (_) => eventOpts.map((opt) => Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        opt == 'All' ? 'All Events' : opt,
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _eventFilter != 'All' ? _kAccent : t.text,
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    )).toList(),
                    items: eventOpts.map((opt) {
                      final lbl = opt == 'All' ? 'All Events' : opt;
                      final cnt = opt == 'All'
                          ? totalCount
                          : _all.where((r) =>
                              (r['event_title'] as String? ?? '') == opt).length;
                      return DropdownMenuItem<String>(
                        value: opt,
                        child: Text('$lbl  ($cnt)',
                          style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 11)),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) { setState(() { _eventFilter = v; _applyFilter(); }); }
                    },
                  ),
                ),
              ),
            ]),
          ],
        ]),
      ),
      // ── Body ─────────────────────────────────────────────────────────
        if (_filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(kWebPad),
            child: WebEmptyState(
              icon: Icons.how_to_reg_outlined,
              title: 'No registrations found',
              subtitle: emptySubtitle,
              action: hasFilter
                  ? TextButton(
                      onPressed: () {
                        _search = ''; _statusFilter = 'All'; _eventFilter = 'All';
                        _searchCtrl.clear();
                        _applyFilter();
                      },
                      child: const Text('Clear all filters',
                        style: TextStyle(fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600, color: _kAccent)))
                  : null),
          )
        else
          Padding(
            padding: const EdgeInsets.all(kWebPad),
            child: WebCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                _RegTableHeader(
                  sortField: _sortField,
                  sortAsc:   _sortAsc,
                  onSort:    _setSort,
                ),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: t.border),
                  itemBuilder: (_, i) {
                    final r             = _filtered[i];
                    final isNeedsReview = r['status'] == 'photo_submitted';
                    return _RegistrationRow(
                      reg:      r,
                      onReview: isNeedsReview ? () => _reviewPhoto(r) : null,
                    );
                  },
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: t.border))),
                  child: Text(
                    hasFilter
                        ? 'Showing ${_filtered.length} of $totalCount registrations'
                        : '${_filtered.length} of up to 300 most recent registrations',
                    style: TextStyle(fontFamily: 'Poppins',
                        fontSize: 11.5, color: t.muted)),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

// ─── Sortable table header for Registrations ─────────────────────────────────

class _RegLegend extends StatelessWidget {
  final Color  color;
  final String label;
  const _RegLegend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 7, height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: t.sub)),
    ]);
  }
}

class _ReviewBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _ReviewBtn({required this.onTap});
  @override State<_ReviewBtn> createState() => _ReviewBtnState();
}
class _ReviewBtnState extends State<_ReviewBtn> {
  bool _h = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _h = true),
    onExit:  (_) => setState(() => _h = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: _h ? const Color(0xFF8B5CF6) : const Color(0xFF8B5CF6).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: _h ? 0 : 0.28)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.photo_camera_outlined, size: 12,
              color: _h ? Colors.white : const Color(0xFF8B5CF6)),
          const SizedBox(width: 5),
          Text('Review', style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: _h ? Colors.white : const Color(0xFF8B5CF6))),
        ]),
      ),
    ),
  );
}

class _RegTableHeader extends StatelessWidget {
  final String sortField;
  final bool   sortAsc;
  final void Function(String) onSort;
  const _RegTableHeader({
    required this.sortField, required this.sortAsc, required this.onSort});

  Widget _sortCol(String label, String field, {int flex = 1}) => Expanded(
    flex: flex,
    child: _SortColBtn(
      label: label, field: field,
      active: sortField == field,
      asc:    sortAsc && sortField == field,
      onSort: onSort,
    ),
  );


  @override
  Widget build(BuildContext context) {
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
    return Container(
      padding: const EdgeInsets.only(left: 23, right: 20, top: 10, bottom: 10),
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(children: [
        const SizedBox(width: 52), // 3(rail strip) + 20(padding) + 40(avatar) + 12(gap) - 23(left inset) = 52
        _sortCol('STUDENT',    'student_name',  flex: 4),
        _sortCol('EVENT',      'event_title',   flex: 3),
        _sortCol('STATUS',     'status',        flex: 2),
        _sortCol('REGISTERED', 'registered_at', flex: 2),
        _sortCol('CHECKED IN', 'checked_in_at', flex: 2),
        SizedBox(width: 76, child: Text('ACTION',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5,
              fontWeight: FontWeight.w700, color: t.sub, letterSpacing: 0.8),
          textAlign: TextAlign.center)),
      ]),
    );
  }
}

class _RegistrationRow extends StatefulWidget {
  final Map<String, dynamic> reg;
  final VoidCallback?         onReview;
  const _RegistrationRow({required this.reg, this.onReview});
  @override State<_RegistrationRow> createState() => _RegistrationRowState();
}
class _RegistrationRowState extends State<_RegistrationRow> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final r           = widget.reg;
    final status      = r['status'] as String? ?? '';
    final isCheckedIn = status == 'checked_in';
    final isRejected  = status == 'rejected';
    final checkedInAt = r['checked_in_at'] as String?;
    final name        = r['student_name'] as String? ?? '?';
    final lrn         = r['student_school_id'] as String? ?? '—';
    final initials    = name.trim().split(' ')
        .where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).take(2).join();

    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
    final avatarColor = switch (status) {
      'checked_in'      => const Color(0xFF10B981),
      'photo_submitted' => const Color(0xFF8B5CF6),
      'rejected'        => const Color(0xFFEF4444),
      'pending'         => const Color(0xFF3B82F6),
      'qr_scanned'      => const Color(0xFFF59E0B),
      'photo_required'  => const Color(0xFFF59E0B),
      _                 => t.muted,
    };
    final railColor = switch (status) {
      'photo_submitted' => const Color(0xFF8B5CF6).withValues(alpha: 0.45),
      'rejected'        => const Color(0xFFEF4444).withValues(alpha: 0.35),
      'checked_in'      => const Color(0xFF10B981).withValues(alpha: 0.30),
      _                 => Colors.transparent,
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _h ? _kAccent.withValues(alpha: 0.030)
            : (status == 'photo_submitted'
                ? const Color(0xFF8B5CF6).withValues(alpha: 0.035)
                : Colors.transparent),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 3, color: railColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                child: Row(children: [
                  // Status-colored avatar
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: avatarColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: avatarColor.withValues(alpha: 0.18)),
                    ),
                    child: Center(child: Text(initials,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: avatarColor.withValues(alpha: isRejected ? 0.55 : 1.0)))),
                  ),
                  const SizedBox(width: 12),
                  // Student name + LRN badge
                  Expanded(flex: 4, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(name,
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isRejected ? t.muted : t.text),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: t.muted.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('LRN',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                                fontWeight: FontWeight.w700, color: t.muted, letterSpacing: 0.5)),
                        ),
                        const SizedBox(width: 5),
                        Flexible(child: Text(lrn,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5, color: t.sub),
                          overflow: TextOverflow.ellipsis)),
                      ]),
                    ],
                  )),
                  // Event title
                  Expanded(flex: 3, child: Row(children: [
                    Icon(Icons.calendar_today_rounded, size: 11,
                        color: isRejected ? t.muted.withValues(alpha: 0.4) : t.muted.withValues(alpha: 0.55)),
                    const SizedBox(width: 5),
                    Flexible(child: Text(r['event_title'] as String? ?? '—',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                          color: isRejected ? t.muted : t.sub),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ])),
                  // Status badge
                  Expanded(flex: 2, child: WebStatusBadge(
                    label: webStatusLabel(status), color: webStatusColor(status))),
                  // Registered date
                  Expanded(flex: 2, child: Text(webFmtDate(r['registered_at'] as String?),
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: t.muted))),
                  // Check-in date — green with time if checked in
                  Expanded(flex: 2, child: isCheckedIn && checkedInAt != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(children: [
                            const Icon(Icons.check_circle_rounded,
                                size: 13, color: Color(0xFF10B981)),
                            const SizedBox(width: 5),
                            Text(webFmtDate(checkedInAt),
                              style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                                  color: Color(0xFF10B981), fontWeight: FontWeight.w600)),
                          ]),
                          Text(_fmtIsoTime(checkedInAt),
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: t.muted)),
                        ],
                      )
                    : Text('—', style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 11.5, color: t.muted))),
                  // Review Photo action
                  SizedBox(
                    width: 76,
                    child: widget.onReview != null
                      ? Center(child: _ReviewBtn(onTap: widget.onReview!))
                      : null,
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Shared helper widgets
// ═════════════════════════════════════════════════════════════════════════════

// Row action button
class _ActBtn extends StatefulWidget {
  final IconData icon; final Color color; final String tip; final VoidCallback onTap;
  const _ActBtn({required this.icon, required this.color, required this.tip, required this.onTap});
  @override State<_ActBtn> createState() => _ActBtnState();
}
class _ActBtnState extends State<_ActBtn> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
    return Tooltip(
      message: widget.tip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _h = true),
        onExit:  (_) => setState(() => _h = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: _h ? widget.color.withValues(alpha: 0.10) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _h ? widget.color.withValues(alpha: 0.25) : Colors.transparent),
            ),
            child: Icon(widget.icon, size: 16,
                color: _h ? widget.color : t.muted.withValues(alpha: 0.70)),
          ),
        ),
      ),
    );
  }
}

// Error state
class _ErrorState extends StatelessWidget {
  final String message; final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 68, height: 68,
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2), shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFFCA5A5), width: 1.5),
            ),
            child: const Icon(Icons.lock_outline_rounded, color: Color(0xFFEF4444), size: 30),
          ),
          const SizedBox(height: 16),
          Text('Permission Required',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 15,
                fontWeight: FontWeight.w700, color: t.text)),
          const SizedBox(height: 8),
          Text(
            'Run the admin RLS policies SQL in Supabase to grant\nthe admin account read access to this table.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                color: t.sub, height: 1.6),
            textAlign: TextAlign.center),
          const SizedBox(height: 20),
          WebBtn(label: 'Retry', icon: Icons.refresh_rounded, onTap: onRetry),
        ]),
      ),
    );
  }
}

// Info note box used inside dialogs
// ─── Credential preview chip (live login-ID display in add dialogs) ──────────

class _CredentialPreview extends StatelessWidget {
  final String username;
  final bool   isReady;
  const _CredentialPreview({required this.username, required this.isReady});

  @override
  Widget build(BuildContext context) {
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: isReady
            ? (t.dark
                ? const Color(0xFF10B981).withValues(alpha: 0.12)
                : const Color(0xFFF0FDF4))
            : t.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isReady
              ? const Color(0xFF10B981).withValues(alpha: 0.35)
              : t.border,
        ),
      ),
      child: Row(children: [
        Icon(Icons.login_rounded, size: 13,
            color: isReady ? const Color(0xFF10B981) : t.muted),
        const SizedBox(width: 8),
        Text('Login ID ',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.sub)),
        Text(username,
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: isReady ? const Color(0xFF10B981) : t.muted,
          )),
      ]),
    );
  }
}

// ─── Password strength bar ────────────────────────────────────────────────────

class _PasswordStrengthBar extends StatelessWidget {
  final String password;
  const _PasswordStrengthBar({required this.password});

  @override
  Widget build(BuildContext context) {
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
    if (password.isEmpty) return const SizedBox(height: 4);
    int score = 0;
    if (password.length >= 6)  score++;
    if (password.length >= 10) score++;
    if (RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[0-9]').hasMatch(password)) score++;

    const red   = Color(0xFFEF4444);
    const amber = Color(0xFFF59E0B);
    const green = Color(0xFF10B981);
    final color = score <= 1 ? red : score == 2 ? amber : green;
    final label = score == 0 ? 'Too short' : score == 1 ? 'Weak' : score == 2 ? 'Fair' : 'Strong';

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        for (int i = 0; i < 3; i++) ...[
          Expanded(child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            height: 3,
            decoration: BoxDecoration(
              color: i < score ? color : t.border,
              borderRadius: BorderRadius.circular(2),
            ),
          )),
          if (i < 2) const SizedBox(width: 4),
        ],
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
            fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

class _InfoNote extends StatelessWidget {
  final String text;
  const _InfoNote(this.text);

  @override
  Widget build(BuildContext context) {
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.inputBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF0EA5E9).withValues(alpha: 0.25)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline_rounded, size: 15, color: Color(0xFF0EA5E9)),
        const SizedBox(width: 8),
        Expanded(child: Text(text,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
              color: t.dark ? const Color(0xFF7DD3FC) : const Color(0xFF0369A1),
              height: 1.5))),
      ]),
    );
  }
}

// Shared dialog chrome (header + form body + buttons)
Widget _dialogShell({
  required IconData  icon,
  required Color     iconColor,
  required String    title,
  required Widget    body,
  required String    confirmLabel,
  required Color     confirmColor,
  required VoidCallback? onConfirm,
  bool loading = false,
}) {
  return Builder(builder: (context) {
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 40, offset: const Offset(0, 14)),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.max, children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border))),
          child: _DialogHeader(icon: icon, iconColor: iconColor, title: title),
        ),
        // Body (scrollable so tall content never overflows)
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: body,
          ),
        ),
        // Buttons
        Divider(height: 1, color: t.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: Row(children: [
            Expanded(
              child: Builder(builder: (ctx) => OutlinedButton(
                onPressed: loading ? null : () => Navigator.of(ctx).pop(),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: t.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: Text('Cancel',
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: t.sub)),
              )),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: loading ? null : onConfirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: confirmColor, foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: loading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(confirmLabel,
                      style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ]),
    );
  });
}

// Dialog header row
class _DialogHeader extends StatelessWidget {
  final IconData icon; final Color iconColor; final String title;
  const _DialogHeader({required this.icon, required this.iconColor, required this.title});

  @override
  Widget build(BuildContext context) {
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
    return Row(children: [
      Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 19, color: iconColor),
      ),
      const SizedBox(width: 12),
      Expanded(child: Text(title,
        style: TextStyle(fontFamily: 'Poppins', fontSize: 16,
            fontWeight: FontWeight.w800, color: t.text))),
      Builder(builder: (ctx) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: Colors.transparent, borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.close_rounded, size: 18, color: t.muted),
          ),
        ),
      )),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Photo review dialog — shown when admin clicks "Review Photo" on a
// photo_submitted registration. Generates a signed URL for the private selfie
// and presents approve / reject choices in one step (no double-confirm).
// ═══════════════════════════════════════════════════════════════════════════════

class _PhotoReviewDialog extends StatefulWidget {
  final Map<String, dynamic> reg;
  const _PhotoReviewDialog({required this.reg});
  @override State<_PhotoReviewDialog> createState() => _PhotoReviewDialogState();
}

class _PhotoReviewDialogState extends State<_PhotoReviewDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _scale, _fade;

  String? _imageUrl;
  bool    _urlLoading = true;
  bool    _urlError   = false;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    _scale = Tween<double>(begin: 0.88, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    _loadSignedUrl();
  }

  Future<void> _loadSignedUrl() async {
    final path = widget.reg['selfie_url'] as String?;
    if (path == null || path.isEmpty) {
      if (mounted) setState(() { _urlLoading = false; _urlError = true; });
      return;
    }
    try {
      final url = await SupabaseService.client.storage
          .from('selfies')
          .createSignedUrl(path, 3600);
      if (mounted) setState(() { _imageUrl = url; _urlLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _urlLoading = false; _urlError = true; });
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final t           = AdminTk(Theme.of(context).brightness == Brightness.dark);
    final reg         = widget.reg;
    final studentName = reg['student_name']      as String? ?? '—';
    final lrn         = reg['student_school_id'] as String? ?? '—';
    final eventTitle  = reg['event_title']        as String? ?? '—';
    final regDate     = webFmtDate(reg['registered_at'] as String?);

    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 40, offset: const Offset(0, 14)),
                ],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: t.border))),
                  child: _DialogHeader(
                    icon:      Icons.photo_camera_outlined,
                    iconColor: const Color(0xFF8B5CF6),
                    title:     'Photo Verification',
                  ),
                ),
                // Student + event info
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(studentName,
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 15,
                            fontWeight: FontWeight.w700, color: t.text)),
                      const SizedBox(height: 3),
                      Row(children: [
                        Text('LRN ',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                              fontWeight: FontWeight.w700, color: t.muted, letterSpacing: 0.5)),
                        Text(lrn,
                          style: TextStyle(fontFamily: 'Poppins',
                              fontSize: 11.5, color: t.sub)),
                      ]),
                      const SizedBox(height: 4),
                      Text(eventTitle,
                        style: TextStyle(fontFamily: 'Poppins',
                            fontSize: 12, color: t.sub),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('Registered $regDate',
                        style: TextStyle(fontFamily: 'Poppins',
                            fontSize: 11, color: t.muted)),
                    ])),
                    const SizedBox(width: 12),
                    WebStatusBadge(label: 'Needs Review', color: const Color(0xFF8B5CF6)),
                  ]),
                ),
                // Photo area
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 340),
                      color: t.inputBg,
                      child: _urlLoading
                          ? const SizedBox(
                              height: 200,
                              child: Center(
                                child: CircularProgressIndicator(
                                    color: Color(0xFF8B5CF6), strokeWidth: 2.5)))
                          : _urlError || _imageUrl == null
                              ? SizedBox(
                                  height: 160,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.broken_image_rounded,
                                          size: 44, color: t.muted),
                                      const SizedBox(height: 10),
                                      Text('Photo unavailable',
                                        style: TextStyle(fontFamily: 'Poppins',
                                            fontSize: 13, color: t.muted)),
                                    ],
                                  ))
                              : Image.network(
                                  _imageUrl!,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => SizedBox(
                                    height: 160,
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.broken_image_rounded,
                                            size: 44, color: t.muted),
                                        const SizedBox(height: 10),
                                        Text('Failed to load image',
                                          style: TextStyle(fontFamily: 'Poppins',
                                              fontSize: 13, color: t.muted)),
                                      ],
                                    )),
                                ),
                    ),
                  ),
                ),
                // Action buttons
                Divider(height: 1, color: t.border),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                  child: Row(children: [
                    // Dismiss
                    Builder(builder: (ctx) => OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: t.border),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                      ),
                      child: Text('Cancel',
                        style: TextStyle(fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600, color: t.sub)),
                    )),
                    const SizedBox(width: 8),
                    // Reject
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop('reject'),
                        icon: const Icon(Icons.cancel_outlined,
                            size: 16, color: Color(0xFFEF4444)),
                        label: const Text('Reject',
                          style: TextStyle(fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700, color: Color(0xFFEF4444))),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFEF4444)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Approve
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.of(context).pop('approve'),
                        icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                        label: const Text('Approve',
                          style: TextStyle(fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Logs page — helpers
// ═════════════════════════════════════════════════════════════════════════════

String _logRelTime(String? ts) {
  if (ts == null || ts.isEmpty) return '—';
  try {
    final d    = DateTime.parse(ts).toLocal();
    final diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60)  return 'Just now';
    if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
    if (diff.inHours   < 24)  return '${diff.inHours}h ago';
    if (diff.inDays    < 7)   return '${diff.inDays}d ago';
    const m = ['Jan','Feb','Mar','Apr','May','Jun',
                'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[d.month - 1]} ${d.day}';
  } catch (_) { return '—'; }
}

String _logFullTime(String? ts) {
  if (ts == null || ts.isEmpty) return '—';
  try {
    final d  = DateTime.parse(ts).toLocal();
    const m  = ['Jan','Feb','Mar','Apr','May','Jun',
                 'Jul','Aug','Sep','Oct','Nov','Dec'];
    final h  = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    final mi = d.minute.toString().padLeft(2, '0');
    final ap = d.hour >= 12 ? 'PM' : 'AM';
    return '${m[d.month - 1]} ${d.day}, ${d.year} · $h:$mi $ap';
  } catch (_) { return '—'; }
}

Color _logRoleColor(String? role) => switch (role) {
  'admin'     => _kAccent,
  'organizer' => const Color(0xFF7C3AED),
  'student'   => const Color(0xFF0EA5E9),
  _           => kMuted,
};

String _logRoleLabel(String? role) => switch (role) {
  'admin'     => 'Admin',
  'organizer' => 'Organizer',
  'student'   => 'Student',
  _           => role?.toUpperCase() ?? '—',
};

IconData _logRoleIcon(String? role) => switch (role) {
  'admin'     => Icons.admin_panel_settings_rounded,
  'organizer' => Icons.badge_rounded,
  'student'   => Icons.school_rounded,
  _           => Icons.person_rounded,
};

Color _logActionColor(String? action) => switch (action) {
  'created' => const Color(0xFF10B981),
  'updated' => const Color(0xFF3B82F6),
  'deleted' => const Color(0xFFEF4444),
  _         => kMuted,
};

String _logActionLabel(String? action) => switch (action) {
  'created' => 'Created',
  'updated' => 'Updated',
  'deleted' => 'Deleted',
  _         => action?.toUpperCase() ?? '—',
};

IconData _logActionIcon(String? action) => switch (action) {
  'created' => Icons.add_circle_outline_rounded,
  'updated' => Icons.edit_outlined,
  'deleted' => Icons.delete_outline_rounded,
  _         => Icons.event_note_outlined,
};

// ═════════════════════════════════════════════════════════════════════════════
// Announcements page
// ═════════════════════════════════════════════════════════════════════════════

class _AdminAnnouncementsPage extends StatefulWidget {
  const _AdminAnnouncementsPage();
  @override State<_AdminAnnouncementsPage> createState() => _AdminAnnouncementsPageState();
}

class _AdminAnnouncementsPageState extends State<_AdminAnnouncementsPage> {
  bool   _loading   = true;
  bool   _error     = false;
  String _search    = '';
  String _orgFilter = 'All';
  bool   _sortDesc  = true;
  List<Map<String, dynamic>> _all      = [];
  List<Map<String, dynamic>> _filtered = [];
  final _searchCtrl = TextEditingController();
  RealtimeChannel? _channel;
  Timer?           _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    if (_channel != null) SupabaseService.client.removeChannel(_channel!);
    super.dispose();
  }

  void _subscribeRealtime() {
    _channel = SupabaseService.client.channel('admin-announcements')
      ..on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(event: '*', schema: 'public', table: 'announcements'),
        (_, [_]) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 600), () {
            if (mounted) _load(silent: true);
          });
        },
      )
      ..subscribe();
  }

  Future<void> _load({bool silent = false}) async {
    if (mounted) setState(() { if (!silent) _loading = true; _error = false; });
    try {
      final rows = List<Map<String, dynamic>>.from(
        await SupabaseService.client
            .from('announcements')
            .select('id, title, message, created_by, created_at')
            .order('created_at', ascending: false),
      );

      // Batch-resolve organizer display names
      final uids = rows
          .map((r) => r['created_by'] as String?)
          .whereType<String>()
          .toSet()
          .toList();
      final Map<String, String> orgNames = {};
      if (uids.isNotEmpty) {
        final orgRows = List<Map<String, dynamic>>.from(
          await SupabaseService.client
              .from('organizers')
              .select('user_id, full_name')
              .filter('user_id', 'in', '(${uids.join(',')})'),
        );
        for (final o in orgRows) {
          orgNames[o['user_id'] as String] = o['full_name'] as String? ?? '—';
        }
      }

      final enriched = rows.map((r) => <String, dynamic>{
        ...r,
        '_org': orgNames[r['created_by'] as String? ?? ''] ?? '—',
      }).toList();

      if (!mounted) return;
      setState(() {
        _all      = enriched;
        _filtered = _apply(enriched);
        _loading  = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  List<Map<String, dynamic>> _apply(List<Map<String, dynamic>> src) {
    final q = _search.trim().toLowerCase();
    var list = src.where((a) {
      if (_orgFilter != 'All' && a['_org'] != _orgFilter) return false;
      if (q.isEmpty) return true;
      final title   = (a['title']   as String? ?? '').toLowerCase();
      final message = (a['message'] as String? ?? '').toLowerCase();
      final org     = (a['_org']    as String? ?? '').toLowerCase();
      return title.contains(q) || message.contains(q) || org.contains(q);
    }).toList();
    return _sortDesc ? list : list.reversed.toList();
  }

  Future<void> _delete(Map<String, dynamic> ann) async {
    final ok = await WebAlert.confirm(
      context:      context,
      title:        'Delete Announcement?',
      message:      'This announcement will be permanently removed and will '
                    'no longer be visible to students. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (ok != true || !mounted) return;
    try {
      await SupabaseService.client
          .from('announcements')
          .delete()
          .eq('id', ann['id'] as int);
      SupabaseService.announcementsVersion.value++;
      await _load(silent: true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to delete announcement.',
              style: TextStyle(fontFamily: 'Poppins')),
          backgroundColor: Color(0xFFEF4444),
        ));
      }
    }
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '—';
    try {
      final dt   = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60)  return 'just now';
      if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
      if (diff.inHours   < 24)  return '${diff.inHours}h ago';
      if (diff.inDays    < 30)  return '${diff.inDays}d ago';
      const mn = ['Jan','Feb','Mar','Apr','May','Jun',
                  'Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${mn[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) { return iso; }
  }

  void _clearFilters() {
    _searchCtrl.clear();
    setState(() { _search = ''; _orgFilter = 'All'; _filtered = _apply(_all); });
  }

  @override
  Widget build(BuildContext context) {
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    if (_error) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_rounded, size: 44, color: Color(0xFFEF4444)),
          const SizedBox(height: 16),
          Text('Failed to load announcements',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 15,
                fontWeight: FontWeight.w800, color: t.text)),
          const SizedBox(height: 12),
          WebBtn(label: 'Retry', icon: Icons.refresh_rounded, onTap: _load),
        ]),
      );
    }

    // ── Computed stats ─────────────────────────────────────────────────────
    final now        = DateTime.now();
    final weekAgo    = now.subtract(const Duration(days: 7));
    final thisWeek   = _all.where((a) {
      final dt = DateTime.tryParse(a['created_at'] as String? ?? '')?.toLocal();
      return dt != null && dt.isAfter(weekAgo);
    }).length;
    final activeOrgs = _all.map((a) => a['created_by']).toSet().length;
    final hasFilter  = _search.isNotEmpty || _orgFilter != 'All';
    final orgOpts    = <String>[
      'All',
      ..._all.map((a) => a['_org'] as String? ?? '—').toSet().toList()..sort(),
    ];

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ══ Band 1: White header ════════════════════════════════════════════
        Container(
          color: t.card,
          padding: const EdgeInsets.fromLTRB(kWebPad, 20, kWebPad, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Title row
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Announcements',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 22,
                    fontWeight: FontWeight.w800, color: t.text)),
              const SizedBox(height: 2),
              Text(
                '${_all.length} total · broadcast to all registered students',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.sub),
              ),
            ]),
            const SizedBox(height: 16),
            // Stat tiles — same widget as Students / Registrations / Events
            Row(children: [
              _StudentStatCard(
                label: 'Total Posted',
                value: '${_all.length}',
                color: _kAccent,
                icon:  Icons.campaign_rounded,
              ),
              const SizedBox(width: 10),
              _StudentStatCard(
                label: 'This Week',
                value: '$thisWeek',
                color: const Color(0xFF8B5CF6),
                icon:  Icons.today_rounded,
              ),
              const SizedBox(width: 10),
              _StudentStatCard(
                label: 'Active Organizers',
                value: '$activeOrgs',
                color: const Color(0xFF10B981),
                icon:  Icons.people_rounded,
              ),
            ]),
          ]),
        ),

        // ══ Band 2: Filter bar ══════════════════════════════════════════════
        Container(
          padding: const EdgeInsets.fromLTRB(kWebPad, 8, kWebPad, 8),
          decoration: BoxDecoration(
            color: t.bg,
            border: Border(bottom: BorderSide(color: t.border)),
          ),
          child: Row(children: [
            // Search
            WebSearchField(
              controller: _searchCtrl,
              hint: 'Search title, message or organizer…',
              onChanged: (v) => setState(() { _search = v; _filtered = _apply(_all); }),
              width: 240,
            ),
            const SizedBox(width: 14),
            Container(width: 1, height: 18, color: t.border),
            const SizedBox(width: 14),

            // Organizer filter
            Text('Organizer:',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  fontWeight: FontWeight.w600, color: t.text)),
            const SizedBox(width: 8),
            Container(
              height: 28,
              padding: const EdgeInsets.only(left: 10, right: 6),
              decoration: BoxDecoration(
                color: _orgFilter != 'All'
                    ? _kAccent.withValues(alpha: 0.07)
                    : t.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _orgFilter != 'All'
                      ? _kAccent.withValues(alpha: 0.45)
                      : t.border,
                  width: _orgFilter != 'All' ? 1.5 : 1.0,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: orgOpts.contains(_orgFilter) ? _orgFilter : 'All',
                  isDense: true,
                  icon: Icon(Icons.keyboard_arrow_down_rounded, size: 14,
                      color: _orgFilter != 'All' ? _kAccent : t.muted),
                  onChanged: (v) {
                    if (v != null) setState(() { _orgFilter = v; _filtered = _apply(_all); });
                  },
                  selectedItemBuilder: (ctx) => orgOpts.map((n) => Center(
                    child: Text(n == 'All' ? 'All Organizers' : n,
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: _orgFilter != 'All' ? _kAccent : t.text,
                      )),
                  )).toList(),
                  items: orgOpts.map((n) => DropdownMenuItem<String>(
                    value: n,
                    child: Text(n == 'All' ? 'All Organizers' : n,
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 12,
                        fontWeight: n == _orgFilter ? FontWeight.w700 : FontWeight.w400,
                        color: n == _orgFilter ? _kAccent : t.text,
                      )),
                  )).toList(),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Container(width: 1, height: 18, color: t.border),
            const SizedBox(width: 14),

            // Sort toggle
            Text('Sort:',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  fontWeight: FontWeight.w600, color: t.text)),
            const SizedBox(width: 8),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => setState(() { _sortDesc = !_sortDesc; _filtered = _apply(_all); }),
                child: Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color:        t.card,
                    borderRadius: BorderRadius.circular(20),
                    border:       Border.all(color: t.border),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      _sortDesc ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                      size: 12, color: t.sub,
                    ),
                    const SizedBox(width: 4),
                    Text(_sortDesc ? 'Newest first' : 'Oldest first',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                          fontWeight: FontWeight.w600, color: t.sub)),
                  ]),
                ),
              ),
            ),

            // Clear filters
            if (hasFilter) ...[
              const Spacer(),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _clearFilters,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.close_rounded, size: 13, color: t.muted),
                    const SizedBox(width: 4),
                    Text('Clear filters',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                          fontWeight: FontWeight.w600, color: t.muted)),
                  ]),
                ),
              ),
            ],
          ]),
        ),

        // ══ Band 3: Body ════════════════════════════════════════════════════
        if (_filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(kWebPad),
            child: WebEmptyState(
              icon:     Icons.campaign_outlined,
              title:    hasFilter ? 'No results found' : 'No announcements yet',
              subtitle: hasFilter
                  ? 'Try adjusting your search or organizer filter.'
                  : 'Organizers have not posted any announcements yet.',
              action: hasFilter
                  ? TextButton(
                      onPressed: _clearFilters,
                      child: const Text('Clear all filters',
                        style: TextStyle(fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600, color: _kAccent)),
                    )
                  : null,
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.all(kWebPad),
            child: WebCard(
              padding: EdgeInsets.zero,
              child: Column(children: [

                // Card section header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                  child: Row(children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFC2410C), _kAccent, Color(0xFFF97316)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(Icons.campaign_rounded, size: 15, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Text('All Announcements',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 13.5,
                          fontWeight: FontWeight.w700, color: t.text)),
                    if (hasFilter) ...[
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color:        t.divider,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('${_filtered.length} of ${_all.length}',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                              fontWeight: FontWeight.w600, color: t.sub)),
                      ),
                    ],
                  ]),
                ),
                Divider(height: 1, color: t.border),

                // Rows
                ListView.separated(
                  shrinkWrap:  true,
                  physics:     const NeverScrollableScrollPhysics(),
                  itemCount:   _filtered.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: t.border),
                  itemBuilder: (_, i) => _AdminAnnRow(
                    ann:      _filtered[i],
                    timeAgo:  _timeAgo(_filtered[i]['created_at'] as String?),
                    onDelete: () => _delete(_filtered[i]),
                  ),
                ),

                // Footer count row — matches Organizers/Registrations pattern
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: t.border))),
                  child: Text(
                    hasFilter
                        ? 'Showing ${_filtered.length} of ${_all.length} announcements'
                        : '${_all.length} announcements total',
                    style: TextStyle(fontFamily: 'Poppins',
                        fontSize: 11.5, color: t.muted)),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

// ── Announcement row ──────────────────────────────────────────────────────────

class _AdminAnnRow extends StatefulWidget {
  final Map<String, dynamic> ann;
  final String               timeAgo;
  final VoidCallback         onDelete;
  const _AdminAnnRow({
    required this.ann,
    required this.timeAgo,
    required this.onDelete,
  });
  @override State<_AdminAnnRow> createState() => _AdminAnnRowState();
}

class _AdminAnnRowState extends State<_AdminAnnRow> {
  bool _hover    = false;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t       = AdminTk(Theme.of(context).brightness == Brightness.dark);
    final title   = widget.ann['title']   as String? ?? '';
    final message = widget.ann['message'] as String? ?? '';
    final org     = widget.ann['_org']    as String? ?? '—';
    final isLong  = message.length > 160;
    final preview = isLong ? '${message.substring(0, 160)}…' : message;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit:  (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: _hover ? _kAccent.withValues(alpha: 0.03) : Colors.transparent,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Left accent bar
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 3,
              color: _hover ? _kAccent : _kAccent.withValues(alpha: 0.28),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Organizer initial avatar
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color:        _kAccent.withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(10),
                      border:       Border.all(color: _kAccent.withValues(alpha: 0.22)),
                    ),
                    child: Center(
                      child: Text(
                        org.isNotEmpty ? org[0].toUpperCase() : '?',
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 16,
                            fontWeight: FontWeight.w800, color: _kAccent),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Content
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title,
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 13.5,
                            fontWeight: FontWeight.w700, color: t.text),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      Text(_expanded ? message : preview,
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                            color: t.sub, height: 1.55)),
                      if (isLong) ...[
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () => setState(() => _expanded = !_expanded),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Text(
                              _expanded ? 'Show less' : 'Read more',
                              style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                                  fontWeight: FontWeight.w600, color: _kAccent),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      // Meta row
                      Row(children: [
                        Icon(Icons.person_outline_rounded, size: 12, color: t.muted),
                        const SizedBox(width: 4),
                        Text(org,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                              fontWeight: FontWeight.w500, color: t.sub)),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          width: 3, height: 3,
                          decoration: BoxDecoration(
                              color: t.muted, shape: BoxShape.circle),
                        ),
                        Icon(Icons.access_time_rounded, size: 11, color: t.muted),
                        const SizedBox(width: 4),
                        Text(widget.timeAgo,
                          style: TextStyle(fontFamily: 'Poppins',
                              fontSize: 11, color: t.muted)),
                        const Spacer(),
                      ]),
                    ]),
                  ),

                  // Delete button
                  const SizedBox(width: 12),
                  _AnnDeleteBtn(onTap: widget.onDelete),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _AnnDeleteBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _AnnDeleteBtn({required this.onTap});
  @override State<_AnnDeleteBtn> createState() => _AnnDeleteBtnState();
}

class _AnnDeleteBtnState extends State<_AnnDeleteBtn> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
    return MouseRegion(
      cursor:  SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 34, height: 34,
          decoration: BoxDecoration(
            color:        _h ? const Color(0xFFFEF2F2) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border:       Border.all(
              color: _h ? const Color(0xFFFCA5A5) : Colors.transparent),
          ),
          child: Icon(Icons.delete_outline_rounded, size: 16,
            color: _h ? const Color(0xFFEF4444) : t.muted),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Logs page
// ═════════════════════════════════════════════════════════════════════════════

class _AdminLogsPage extends StatefulWidget {
  const _AdminLogsPage();
  @override State<_AdminLogsPage> createState() => _AdminLogsPageState();
}

class _AdminLogsPageState extends State<_AdminLogsPage>
    with TickerProviderStateMixin {
  late final TabController       _tab;
  late final AnimationController _pulseCtrl;
  final _searchCtrl = TextEditingController();
  String _search    = '';
  String _dateRange = 'all';

  // ── Login logs ─────────────────────────────────────────────────────────────
  bool   _loginLoading = true;
  bool   _loginError   = false;
  String _loginRole    = 'All';
  String _loginPlat    = 'All';
  List<Map<String, dynamic>> _loginAll      = [];
  List<Map<String, dynamic>> _loginFiltered = [];

  // ── Event logs ─────────────────────────────────────────────────────────────
  bool   _eventLoading = true;
  bool   _eventError   = false;
  String _eventAction  = 'All';
  String _eventOrg     = 'All';
  List<Map<String, dynamic>> _eventAll      = [];
  List<Map<String, dynamic>> _eventFiltered = [];

  RealtimeChannel? _loginCh;
  RealtimeChannel? _eventCh;
  Timer?           _debounce;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this)
      ..addListener(() { if (mounted) setState(() {}); });
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _searchCtrl.addListener(_onSearch);
    _loadLogin();
    _loadEvent();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pulseCtrl.dispose();
    _tab.dispose();
    _searchCtrl.dispose();
    if (_loginCh != null) SupabaseService.client.removeChannel(_loginCh!);
    if (_eventCh != null) SupabaseService.client.removeChannel(_eventCh!);
    super.dispose();
  }

  void _onSearch() {
    _search = _searchCtrl.text;
    _applyLogin();
    _applyEvent();
  }

  DateTime? get _cutoff {
    final now = DateTime.now();
    return switch (_dateRange) {
      'today' => DateTime(now.year, now.month, now.day),
      '7d'    => now.subtract(const Duration(days: 7)),
      '30d'   => now.subtract(const Duration(days: 30)),
      _       => null,
    };
  }

  void _subscribeRealtime() {
    _loginCh = SupabaseService.client.channel('admin-login-logs')
      ..on(RealtimeListenTypes.postgresChanges,
          ChannelFilter(event: '*', schema: 'public', table: 'login_logs'),
          (_, [a]) => _debouncedLoad())
      ..subscribe();
    _eventCh = SupabaseService.client.channel('admin-event-logs')
      ..on(RealtimeListenTypes.postgresChanges,
          ChannelFilter(event: '*', schema: 'public', table: 'event_logs'),
          (_, [a]) => _debouncedLoad())
      ..subscribe();
  }

  void _debouncedLoad() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted) { _loadLogin(silent: true); _loadEvent(silent: true); }
    });
  }

  Future<void> _loadLogin({bool silent = false}) async {
    if (!silent && mounted) setState(() { _loginLoading = true; _loginError = false; });
    try {
      final rows = await SupabaseService.client
          .from('login_logs')
          .select('id, user_role, full_name, identifier, platform, created_at')
          .order('created_at', ascending: false)
          .limit(500);
      if (!mounted) return;
      _loginAll = List<Map<String, dynamic>>.from(rows as List);
      _applyLogin();
      if (mounted) setState(() => _loginLoading = false);
    } catch (_) {
      if (mounted) setState(() { _loginLoading = false; _loginError = true; });
    }
  }

  Future<void> _loadEvent({bool silent = false}) async {
    if (!silent && mounted) setState(() { _eventLoading = true; _eventError = false; });
    try {
      final rows = await SupabaseService.client
          .from('event_logs')
          .select('id, event_title, organizer_id, organizer_name, action, details, created_at')
          .order('created_at', ascending: false)
          .limit(500);
      if (!mounted) return;
      _eventAll = List<Map<String, dynamic>>.from(rows as List);
      _applyEvent();
      if (mounted) setState(() => _eventLoading = false);
    } catch (_) {
      if (mounted) setState(() { _eventLoading = false; _eventError = true; });
    }
  }

  void _applyLogin() {
    final cut = _cutoff;
    final q   = _search.toLowerCase();
    setState(() {
      _loginFiltered = _loginAll.where((r) {
        if (cut != null) {
          final d = DateTime.tryParse(r['created_at'] as String? ?? '')?.toLocal();
          if (d == null || d.isBefore(cut)) return false;
        }
        if (_loginRole != 'All' &&
            r['user_role'] != _loginRole.toLowerCase()) return false;
        if (_loginPlat != 'All' &&
            r['platform']  != _loginPlat.toLowerCase())  return false;
        if (q.isNotEmpty) {
          final name  = (r['full_name']  as String? ?? '').toLowerCase();
          final ident = (r['identifier'] as String? ?? '').toLowerCase();
          if (!name.contains(q) && !ident.contains(q)) return false;
        }
        return true;
      }).toList();
    });
  }

  void _applyEvent() {
    final cut = _cutoff;
    final q   = _search.toLowerCase();
    setState(() {
      _eventFiltered = _eventAll.where((r) {
        if (cut != null) {
          final d = DateTime.tryParse(r['created_at'] as String? ?? '')?.toLocal();
          if (d == null || d.isBefore(cut)) return false;
        }
        if (_eventAction != 'All' &&
            r['action'] != _eventAction.toLowerCase()) return false;
        if (_eventOrg != 'All') {
          final nm = (r['organizer_name'] as String? ?? '');
          final id = (r['organizer_id']   as String? ?? '');
          if (nm != _eventOrg && id != _eventOrg) return false;
        }
        if (q.isNotEmpty) {
          final title  = (r['event_title']    as String? ?? '').toLowerCase();
          final org    = (r['organizer_name'] as String? ?? '').toLowerCase();
          final detail = (r['details']        as String? ?? '').toLowerCase();
          if (!title.contains(q) && !org.contains(q) && !detail.contains(q)) return false;
        }
        return true;
      }).toList();
    });
  }

  void _setDateRange(String v) {
    setState(() => _dateRange = v);
    _applyLogin();
    _applyEvent();
  }

  // Count entries in [list] that fall within [bucket] ("today"/"7d"/"30d"/"all").
  int _countFor(List<Map<String, dynamic>> list, String bucket) {
    final now = DateTime.now();
    final cut = switch (bucket) {
      'today' => DateTime(now.year, now.month, now.day),
      '7d'    => now.subtract(const Duration(days: 7)),
      '30d'   => now.subtract(const Duration(days: 30)),
      _       => null,
    };
    if (cut == null) return list.length;
    return list.where((r) {
      final d = DateTime.tryParse(r['created_at'] as String? ?? '')?.toLocal();
      return d != null && !d.isBefore(cut);
    }).length;
  }

  // ── CSV export ─────────────────────────────────────────────────────────────

  void _exportLoginCsv() {
    final sb = StringBuffer();
    sb.writeln('Name,Identifier,Role,Platform,Login Time');
    for (final r in _loginFiltered) {
      final name  = (r['full_name']  as String? ?? '').replaceAll('"', '""');
      final ident = (r['identifier'] as String? ?? '').replaceAll('"', '""');
      final role  = r['user_role']  as String? ?? '';
      final plat  = r['platform']   as String? ?? '';
      final ts    = r['created_at'] as String? ?? '';
      sb.writeln('"$name","$ident","$role","$plat","$ts"');
    }
    _downloadCsv(sb.toString(), 'login_logs');
  }

  void _exportEventCsv() {
    final sb = StringBuffer();
    sb.writeln('Event Title,Organizer,Action,Details,Time');
    for (final r in _eventFiltered) {
      final title  = (r['event_title']    as String? ?? '').replaceAll('"', '""');
      final org    = (r['organizer_name'] as String? ?? '').replaceAll('"', '""');
      final action = r['action']         as String? ?? '';
      final detail = (r['details']       as String? ?? '').replaceAll('"', '""');
      final ts     = r['created_at']     as String? ?? '';
      sb.writeln('"$title","$org","$action","$detail","$ts"');
    }
    _downloadCsv(sb.toString(), 'event_logs');
  }

  void _downloadCsv(String content, String name) => downloadCsv(content, name);

  @override
  Widget build(BuildContext context) {
    final t             = AdminTk(Theme.of(context).brightness == Brightness.dark);
    final loginFiltered = _loginFiltered.length;
    final eventFiltered = _eventFiltered.length;
    final loginTotal    = _loginAll.length;
    final eventTotal    = _eventAll.length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Header ───────────────────────────────────────────────────────────
      Container(
        color: t.card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Title row + stat chips
          Padding(
            padding: const EdgeInsets.fromLTRB(kWebPad, 20, kWebPad, 16),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Logs',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 22,
                        fontWeight: FontWeight.w800, color: t.text)),
                  const SizedBox(height: 2),
                  Row(children: [
                    Text(
                      '${loginTotal + eventTotal} total entries · real-time audit trail',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                          color: t.sub)),
                    const SizedBox(width: 8),
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, _c) => Opacity(
                        opacity: 0.45 + 0.55 * _pulseCtrl.value,
                        child: Container(
                          width: 6, height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981), shape: BoxShape.circle),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text('Live',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF10B981), letterSpacing: 0.5)),
                  ]),
                ]),
              ),
              _LogStatChip(
                icon: Icons.login_rounded, label: 'Logins',
                count: loginFiltered, color: const Color(0xFF0EA5E9)),
              const SizedBox(width: 8),
              _LogStatChip(
                icon: Icons.event_note_rounded, label: 'Event Actions',
                count: eventFiltered, color: const Color(0xFF7C3AED)),
              const SizedBox(width: 12),
              WebBtn(
                label: 'Export CSV',
                icon:  Icons.download_rounded,
                onTap: _tab.index == 0 ? _exportLoginCsv : _exportEventCsv,
                small: true, outlined: true, color: _kAccent,
              ),
            ]),
          ),
          // Filter bar — search first, period dropdown
          Padding(
            padding: const EdgeInsets.fromLTRB(kWebPad, 0, kWebPad, 12),
            child: Row(children: [
              WebSearchField(
                controller: _searchCtrl,
                hint: _tab.index == 0
                    ? 'Search name or identifier…'
                    : 'Search event or organizer…',
                onChanged: (_) {}, width: 220),
              const SizedBox(width: 14),
              Container(width: 1, height: 18, color: t.border),
              const SizedBox(width: 14),
              Text('Period:',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w600, color: t.text)),
              const SizedBox(width: 8),
              Container(
                height: 28,
                padding: const EdgeInsets.only(left: 10, right: 6),
                decoration: BoxDecoration(
                  color: _dateRange != 'all'
                      ? _kAccent.withValues(alpha: 0.07) : t.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _dateRange != 'all'
                        ? _kAccent.withValues(alpha: 0.45) : t.border,
                    width: _dateRange != 'all' ? 1.5 : 1.0,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _dateRange,
                    isDense: true,
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                        fontWeight: FontWeight.w600, color: t.text),
                    selectedItemBuilder: (_) => [
                      for (final (label, _) in [
                        ('Today', 'today'), ('Last 7 days', '7d'),
                        ('Last 30 days', '30d'), ('All time', 'all'),
                      ])
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(label,
                            style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _dateRange != 'all' ? _kAccent : t.text,
                            ),
                          ),
                        ),
                    ],
                    items: [
                      for (final (label, val) in [
                        ('Today', 'today'), ('Last 7 days', '7d'),
                        ('Last 30 days', '30d'), ('All time', 'all'),
                      ])
                        DropdownMenuItem<String>(
                          value: val,
                          child: Text(
                            '$label  (${_countFor(_tab.index == 0 ? _loginAll : _eventAll, val)})',
                            style: const TextStyle(
                                fontFamily: 'Poppins', fontSize: 11)),
                        ),
                    ],
                    onChanged: (v) { if (v != null) _setDateRange(v); },
                  ),
                ),
              ),
            ]),
          ),
          // Tab bar
          Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border)),
            ),
            child: TabBar(
              controller: _tab,
              labelColor:          _kAccent,
              unselectedLabelColor: t.sub,
              labelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(fontFamily: 'Poppins',
                  fontSize: 13, fontWeight: FontWeight.w500),
              indicatorColor:  _kAccent,
              indicatorWeight: 2.5,
              indicatorSize:   TabBarIndicatorSize.tab,
              dividerColor:    Colors.transparent,
              tabs: [
                Tab(child: _LogTab(
                  icon: Icons.login_rounded,
                  label: 'Login Logs',
                  count: loginFiltered,
                  color: const Color(0xFF0EA5E9),
                )),
                Tab(child: _LogTab(
                  icon: Icons.event_note_rounded,
                  label: 'Event Logs',
                  count: eventFiltered,
                  color: const Color(0xFF7C3AED),
                )),
              ],
            ),
          ),
        ]),
      ),

      // ── Tab content ───────────────────────────────────────────────────────
      Expanded(
        child: TabBarView(
          controller: _tab,
          children: [
            _buildLoginTab(loginFiltered, loginTotal),
            _buildEventTab(eventFiltered, eventTotal),
          ],
        ),
      ),
    ]);
  }

  // ── Login tab ─────────────────────────────────────────────────────────────

  Widget _buildLoginTab(int filtered, int total) {
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
    const roles = ['All', 'Admin', 'Organizer', 'Student'];
    const plats = ['All', 'Web', 'Mobile'];

    if (_loginLoading) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    if (_loginError) {
      return _ErrorState(message: '', onRetry: _loadLogin);
    }

    // KPI stats for the filtered set
    final uniqueUsers = _loginFiltered
        .map((r) => r['identifier'] as String? ?? '')
        .where((s) => s.isNotEmpty).toSet().length;
    final webCount    = _loginFiltered.where((r) => r['platform'] == 'web').length;
    final mobileCount = _loginFiltered.where((r) => r['platform'] == 'mobile').length;
    final loginPeriodLabel = switch (_dateRange) {
      'today' => 'Today',
      '7d'    => 'Last 7 days',
      '30d'   => 'Last 30 days',
      _       => null,
    };
    final loginFilterDesc = [
      if (loginPeriodLabel != null) loginPeriodLabel,
      if (_loginRole != 'All')      _loginRole,
      if (_loginPlat != 'All')      _loginPlat,
      if (_search.isNotEmpty)       '"$_search"',
    ].join(' · ');
    final loginEmptySubtitle = loginFilterDesc.isEmpty
        ? 'Login activity will appear here once users log in.'
        : 'No login entries match $loginFilterDesc.';

    return Column(children: [
      // Filter bar
      Container(
        padding: const EdgeInsets.fromLTRB(kWebPad, 8, kWebPad, 8),
        decoration: BoxDecoration(
          color: t.bg,
          border: Border(bottom: BorderSide(color: t.border)),
        ),
        child: Row(children: [
          Text('Role:',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                fontWeight: FontWeight.w600, color: t.text)),
          const SizedBox(width: 8),
          for (final r in roles) ...[
            WebFilterChip(
              label: r, selected: _loginRole == r,
              onTap: () { setState(() => _loginRole = r); _applyLogin(); },
              count: r == 'All'
                  ? _loginAll.length
                  : _loginAll.where((x) => x['user_role'] == r.toLowerCase()).length,
              selectedColor: switch (r) {
                'Admin'     => _kAccent,
                'Organizer' => const Color(0xFF7C3AED),
                'Student'   => const Color(0xFF0EA5E9),
                _           => kGold,
              },
            ),
            const SizedBox(width: 6),
          ],
          const SizedBox(width: 12),
          Container(width: 1, height: 18, color: t.border),
          const SizedBox(width: 12),
          Text('Platform:',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                fontWeight: FontWeight.w600, color: t.text)),
          const SizedBox(width: 8),
          for (final p in plats) ...[
            WebFilterChip(
              label: p, selected: _loginPlat == p,
              onTap: () { setState(() => _loginPlat = p); _applyLogin(); },
              count: p == 'All'
                  ? _loginAll.length
                  : _loginAll.where((x) => x['platform'] == p.toLowerCase()).length,
              selectedColor: p == 'Web'
                  ? const Color(0xFF4F46E5)
                  : const Color(0xFF0D9488),
            ),
            const SizedBox(width: 6),
          ],
          if (_loginRole != 'All' || _loginPlat != 'All') ...[
            const Spacer(),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  setState(() { _loginRole = 'All'; _loginPlat = 'All'; });
                  _applyLogin();
                },
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.close_rounded, size: 13, color: t.muted),
                  const SizedBox(width: 4),
                  Text('Clear', style: TextStyle(fontFamily: 'Poppins',
                      fontSize: 11.5, fontWeight: FontWeight.w600, color: t.muted)),
                ]),
              ),
            ),
          ],
        ]),
      ),
      // KPI insight strip
      if (_loginFiltered.isNotEmpty)
        Container(
          padding: const EdgeInsets.fromLTRB(kWebPad, 8, kWebPad, 8),
          decoration: BoxDecoration(
            color: t.inputBg,
            border: Border(bottom: BorderSide(color: t.border)),
          ),
          child: Row(children: [
            _LogKpiChip(
              icon: Icons.people_alt_rounded,
              label: '$uniqueUsers Unique User${uniqueUsers == 1 ? "" : "s"}',
              color: const Color(0xFF0EA5E9),
            ),
            const SizedBox(width: 8),
            _LogKpiChip(
              icon: Icons.desktop_mac_rounded,
              label: '$webCount Web',
              color: const Color(0xFF4F46E5),
            ),
            const SizedBox(width: 8),
            _LogKpiChip(
              icon: Icons.smartphone_rounded,
              label: '$mobileCount Mobile',
              color: const Color(0xFF0D9488),
            ),
            const SizedBox(width: 16),
            Container(width: 1, height: 14, color: t.border),
            const SizedBox(width: 16),
            _LogKpiChip(
              icon: Icons.admin_panel_settings_rounded,
              label: '${_loginFiltered.where((r) => r['user_role'] == 'admin').length} Admin',
              color: _kAccent,
            ),
            const SizedBox(width: 8),
            _LogKpiChip(
              icon: Icons.badge_rounded,
              label: '${_loginFiltered.where((r) => r['user_role'] == 'organizer').length} Organizer',
              color: const Color(0xFF7C3AED),
            ),
            const SizedBox(width: 8),
            _LogKpiChip(
              icon: Icons.school_rounded,
              label: '${_loginFiltered.where((r) => r['user_role'] == 'student').length} Student',
              color: const Color(0xFF10B981),
            ),
          ]),
        ),
      // Body
      if (_loginFiltered.isEmpty)
        Expanded(child: Center(child: WebEmptyState(
          icon: Icons.login_outlined,
          title: 'No login events found',
          subtitle: loginEmptySubtitle,
        )))
      else
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(kWebPad),
              child: WebCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  // Table header
                  Container(
                    padding: const EdgeInsets.only(
                        left: 23, right: 20, top: 10, bottom: 10),
                    decoration: BoxDecoration(
                      color: t.bg,
                      border: Border(bottom: BorderSide(color: t.border)),
                    ),
                    child: const Row(children: [
                      SizedBox(width: 52),
                      Expanded(flex: 4, child: _LogColLabel('USER')),
                      Expanded(flex: 2, child: _LogColLabel('ROLE')),
                      Expanded(flex: 2, child: _LogColLabel('PLATFORM')),
                      Expanded(flex: 2, child: _LogColLabel('LOGGED IN AT')),
                    ]),
                  ),
                  // Rows
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _loginFiltered.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: t.border),
                    itemBuilder: (_, i) =>
                        _LoginLogRow(log: _loginFiltered[i]),
                  ),
                  // Footer
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: t.border))),
                    child: Row(children: [
                      Text(
                        filtered == total
                            ? '$total login events'
                            : 'Showing $filtered of $total login events',
                        style: TextStyle(fontFamily: 'Poppins',
                            fontSize: 11.5, color: t.sub)),
                      if (total >= 500) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: kGold.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: kGold.withValues(alpha: 0.28)),
                          ),
                          child: const Text('Showing latest 500',
                            style: TextStyle(fontFamily: 'Poppins',
                                fontSize: 10, fontWeight: FontWeight.w600,
                                color: kGold)),
                        ),
                      ],
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  // ── Event tab ─────────────────────────────────────────────────────────────

  Widget _buildEventTab(int filtered, int total) {
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
    const actions = ['All', 'Created', 'Updated', 'Deleted'];

    if (_eventLoading) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    if (_eventError) {
      return _ErrorState(message: '', onRetry: _loadEvent);
    }

    // Unique organizer names from all event logs (for the organizer filter chips)
    final orgNames = _eventAll
        .map((r) => r['organizer_name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    // KPI counts from the filtered set
    final createdCount = _eventFiltered.where((r) => r['action'] == 'created').length;
    final updatedCount = _eventFiltered.where((r) => r['action'] == 'updated').length;
    final deletedCount = _eventFiltered.where((r) => r['action'] == 'deleted').length;
    final activeOrgs   = _eventFiltered
        .map((r) => r['organizer_name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toSet()
        .length;
    final eventPeriodLabel = switch (_dateRange) {
      'today' => 'Today',
      '7d'    => 'Last 7 days',
      '30d'   => 'Last 30 days',
      _       => null,
    };
    final eventFilterDesc = [
      if (eventPeriodLabel != null) eventPeriodLabel,
      if (_eventAction != 'All')    _eventAction,
      if (_eventOrg    != 'All')    _eventOrg,
      if (_search.isNotEmpty)       '"$_search"',
    ].join(' · ');
    final eventEmptySubtitle = eventFilterDesc.isEmpty
        ? 'Event actions will be logged here as organizers create or manage events.'
        : 'No event log entries match $eventFilterDesc.';

    return Column(children: [
      // Action filter bar
      Container(
        padding: const EdgeInsets.fromLTRB(kWebPad, 8, kWebPad, 8),
        decoration: BoxDecoration(
          color: t.bg,
          border: Border(bottom: BorderSide(color: t.border)),
        ),
        child: Row(children: [
          Text('Action:',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                fontWeight: FontWeight.w600, color: t.text)),
          const SizedBox(width: 8),
          for (final a in actions) ...[
            WebFilterChip(
              label: a, selected: _eventAction == a,
              onTap: () { setState(() => _eventAction = a); _applyEvent(); },
              count: a == 'All'
                  ? _eventAll.length
                  : _eventAll.where((x) => x['action'] == a.toLowerCase()).length,
              selectedColor: switch (a) {
                'Created' => const Color(0xFF10B981),
                'Updated' => const Color(0xFF3B82F6),
                'Deleted' => const Color(0xFFEF4444),
                _         => kGold,
              },
            ),
            const SizedBox(width: 6),
          ],
          if (_eventAction != 'All' || _eventOrg != 'All') ...[
            const Spacer(),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  setState(() { _eventAction = 'All'; _eventOrg = 'All'; });
                  _applyEvent();
                },
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.close_rounded, size: 13, color: t.muted),
                  const SizedBox(width: 4),
                  Text('Clear', style: TextStyle(fontFamily: 'Poppins',
                      fontSize: 11.5, fontWeight: FontWeight.w600, color: t.muted)),
                ]),
              ),
            ),
          ],
        ]),
      ),
      // Organizer filter bar (only shown when there are multiple organizers)
      if (orgNames.length > 1)
        Container(
          padding: const EdgeInsets.fromLTRB(kWebPad, 6, kWebPad, 6),
          decoration: BoxDecoration(
            color: t.bg,
            border: Border(bottom: BorderSide(color: t.border)),
          ),
          child: Row(children: [
            Text('Organizer:',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  fontWeight: FontWeight.w600, color: t.text)),
            const SizedBox(width: 8),
            Container(
              height: 28,
              padding: const EdgeInsets.only(left: 10, right: 6),
              decoration: BoxDecoration(
                color: _eventOrg != 'All'
                    ? const Color(0xFF7C3AED).withValues(alpha: 0.07)
                    : t.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _eventOrg != 'All'
                      ? const Color(0xFF7C3AED).withValues(alpha: 0.45)
                      : t.border,
                  width: _eventOrg != 'All' ? 1.5 : 1.0,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: ['All', ...orgNames].contains(_eventOrg)
                      ? _eventOrg : 'All',
                  isDense: true,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                      fontWeight: FontWeight.w600, color: t.text),
                  selectedItemBuilder: (_) =>
                      ['All', ...orgNames].map((nm) => Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          nm == 'All' ? 'All Organizers' : nm,
                          style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _eventOrg != 'All'
                                ? const Color(0xFF7C3AED) : t.text,
                          ),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      )).toList(),
                  items: ['All', ...orgNames].map((nm) {
                    final lbl = nm == 'All' ? 'All Organizers' : nm;
                    final cnt = nm == 'All'
                        ? _eventAll.length
                        : _eventAll.where((r) =>
                            r['organizer_name'] == nm).length;
                    return DropdownMenuItem<String>(
                      value: nm,
                      child: Text('$lbl  ($cnt)',
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 11)),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() { _eventOrg = v; _applyEvent(); });
                    }
                  },
                ),
              ),
            ),
          ]),
        ),
      // KPI insight strip
      if (_eventFiltered.isNotEmpty)
        Container(
          padding: const EdgeInsets.fromLTRB(kWebPad, 8, kWebPad, 8),
          decoration: BoxDecoration(
            color: t.inputBg,
            border: Border(bottom: BorderSide(color: t.border)),
          ),
          child: Row(children: [
            _LogKpiChip(
              icon: Icons.add_circle_rounded,
              label: '$createdCount Created',
              color: const Color(0xFF10B981),
            ),
            const SizedBox(width: 8),
            _LogKpiChip(
              icon: Icons.edit_rounded,
              label: '$updatedCount Updated',
              color: const Color(0xFF3B82F6),
            ),
            const SizedBox(width: 8),
            _LogKpiChip(
              icon: Icons.delete_rounded,
              label: '$deletedCount Deleted',
              color: const Color(0xFFEF4444),
            ),
            const SizedBox(width: 16),
            Container(width: 1, height: 14, color: t.border),
            const SizedBox(width: 16),
            _LogKpiChip(
              icon: Icons.badge_rounded,
              label: '$activeOrgs Active Organizer${activeOrgs == 1 ? "" : "s"}',
              color: const Color(0xFF7C3AED),
            ),
          ]),
        ),
      // Body
      if (_eventFiltered.isEmpty)
        Expanded(child: Center(child: WebEmptyState(
          icon: Icons.event_note_outlined,
          title: 'No event log entries found',
          subtitle: eventEmptySubtitle,
        )))
      else
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(kWebPad),
              child: WebCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  // Table header
                  Container(
                    padding: const EdgeInsets.only(
                        left: 23, right: 20, top: 10, bottom: 10),
                    decoration: BoxDecoration(
                      color: t.bg,
                      border: Border(bottom: BorderSide(color: t.border)),
                    ),
                    child: const Row(children: [
                      SizedBox(width: 52),
                      Expanded(flex: 4, child: _LogColLabel('EVENT')),
                      Expanded(flex: 3, child: _LogColLabel('ORGANIZER')),
                      Expanded(flex: 2, child: _LogColLabel('ACTION')),
                      Expanded(flex: 3, child: _LogColLabel('DETAILS')),
                      Expanded(flex: 2, child: _LogColLabel('TIME')),
                    ]),
                  ),
                  // Rows
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _eventFiltered.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: t.border),
                    itemBuilder: (_, i) =>
                        _EventLogRow(log: _eventFiltered[i]),
                  ),
                  // Footer
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: t.border))),
                    child: Row(children: [
                      Text(
                        filtered == total
                            ? '$total event log entries'
                            : 'Showing $filtered of $total event log entries',
                        style: TextStyle(fontFamily: 'Poppins',
                            fontSize: 11.5, color: t.sub)),
                      if (total >= 500) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: kGold.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: kGold.withValues(alpha: 0.28)),
                          ),
                          child: const Text('Showing latest 500',
                            style: TextStyle(fontFamily: 'Poppins',
                                fontSize: 10, fontWeight: FontWeight.w600,
                                color: kGold)),
                        ),
                      ],
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }
}

// ── Small widgets ──────────────────────────────────────────────────────────────

class _LogTab extends StatelessWidget {
  final IconData icon; final String label; final int count; final Color color;
  const _LogTab({required this.icon, required this.label,
      required this.count, required this.color});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 15),
    const SizedBox(width: 7),
    Text(label),
    const SizedBox(width: 7),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('$count',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
            fontWeight: FontWeight.w700, color: color)),
    ),
  ]);
}

class _LogStatChip extends StatelessWidget {
  final IconData icon; final String label; final int count; final Color color;
  const _LogStatChip({required this.icon, required this.label,
      required this.count, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.20)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 7),
      Text('$count',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
            fontWeight: FontWeight.w700, color: color)),
      const SizedBox(width: 4),
      Text(label,
        style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
            fontWeight: FontWeight.w500,
            color: color.withValues(alpha: 0.75))),
    ]),
  );
}

class _LogColLabel extends StatelessWidget {
  final String text;
  const _LogColLabel(this.text);
  @override
  Widget build(BuildContext context) {
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
    return Text(text,
      style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5,
          fontWeight: FontWeight.w700, color: t.sub, letterSpacing: 0.8));
  }
}

class _LogKpiChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  const _LogKpiChip({required this.icon, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color:        color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(6),
      border:       Border.all(color: color.withValues(alpha: 0.18)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 5),
      Text(label,
        style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
            fontWeight: FontWeight.w600, color: color)),
    ]),
  );
}

// ── Login log row ──────────────────────────────────────────────────────────────

class _LoginLogRow extends StatefulWidget {
  final Map<String, dynamic> log;
  const _LoginLogRow({required this.log});
  @override State<_LoginLogRow> createState() => _LoginLogRowState();
}
class _LoginLogRowState extends State<_LoginLogRow> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final t        = AdminTk(Theme.of(context).brightness == Brightness.dark);
    final r        = widget.log;
    final role     = r['user_role']  as String? ?? '';
    final name     = r['full_name']  as String? ?? '—';
    final ident    = r['identifier'] as String? ?? '—';
    final platform = r['platform']   as String? ?? '';
    final ts       = r['created_at'] as String?;
    final color    = _logRoleColor(role);
    final initials = name == '—' ? '?' : name.trim().split(' ')
        .where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).take(2).join();

    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _h ? _kAccent.withValues(alpha: 0.028) : Colors.transparent,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 3, color: color.withValues(alpha: 0.35)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  // Role-colored avatar
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withValues(alpha: 0.18)),
                    ),
                    child: Center(child: Text(initials,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                          fontWeight: FontWeight.w700, color: color))),
                  ),
                  const SizedBox(width: 12),
                  // Name + identifier
                  Expanded(flex: 4, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(name,
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                            fontWeight: FontWeight.w600, color: t.text),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(ident,
                        style: TextStyle(fontFamily: 'Poppins',
                            fontSize: 11, color: t.sub),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  )),
                  // Role badge
                  Expanded(flex: 2, child: _LogRoleBadge(role: role)),
                  // Platform badge
                  Expanded(flex: 2, child: _LogPlatformBadge(platform: platform)),
                  // Time with tooltip
                  Expanded(flex: 2, child: Tooltip(
                    message: _logFullTime(ts),
                    preferBelow: false,
                    waitDuration: const Duration(milliseconds: 400),
                    child: Row(children: [
                      Icon(Icons.access_time_rounded,
                          size: 12, color: t.muted),
                      const SizedBox(width: 5),
                      Flexible(child: Text(_logRelTime(ts),
                        style: TextStyle(fontFamily: 'Poppins',
                            fontSize: 12, color: t.sub),
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ]),
                  )),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Event log row ──────────────────────────────────────────────────────────────

class _EventLogRow extends StatefulWidget {
  final Map<String, dynamic> log;
  const _EventLogRow({required this.log});
  @override State<_EventLogRow> createState() => _EventLogRowState();
}
class _EventLogRowState extends State<_EventLogRow> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final t      = AdminTk(Theme.of(context).brightness == Brightness.dark);
    final r      = widget.log;
    final title  = r['event_title']    as String? ?? '—';
    final orgId  = r['organizer_id']   as String? ?? '';
    final orgNm  = r['organizer_name'] as String? ?? '';
    final action = r['action']         as String? ?? '';
    final detail = r['details']        as String? ?? '—';
    final ts     = r['created_at']     as String?;
    final color  = _logActionColor(action);

    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _h ? const Color(0xFF7C3AED).withValues(alpha: 0.025)
            : Colors.transparent,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 3, color: color.withValues(alpha: 0.40)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  // Action icon container
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withValues(alpha: 0.18)),
                    ),
                    child: Icon(_logActionIcon(action), size: 18, color: color),
                  ),
                  const SizedBox(width: 12),
                  // Event title
                  Expanded(flex: 4, child: Text(title,
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                        fontWeight: FontWeight.w600, color: t.text),
                    maxLines: 2, overflow: TextOverflow.ellipsis)),
                  // Organizer
                  Expanded(flex: 3, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (orgNm.isNotEmpty)
                        Text(orgNm,
                          style: TextStyle(fontFamily: 'Poppins',
                              fontSize: 12.5, fontWeight: FontWeight.w500,
                              color: t.text),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (orgId.isNotEmpty)
                        Text(orgId,
                          style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 11,
                            color: orgNm.isEmpty ? t.text : t.sub),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  )),
                  // Action badge
                  Expanded(flex: 2, child: _LogActionBadge(action: action)),
                  // Details
                  Expanded(flex: 3, child: Text(detail,
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                        color: t.sub, height: 1.4),
                    maxLines: 2, overflow: TextOverflow.ellipsis)),
                  // Time with tooltip
                  Expanded(flex: 2, child: Tooltip(
                    message: _logFullTime(ts),
                    preferBelow: false,
                    waitDuration: const Duration(milliseconds: 400),
                    child: Row(children: [
                      Icon(Icons.access_time_rounded,
                          size: 12, color: t.muted),
                      const SizedBox(width: 5),
                      Flexible(child: Text(_logRelTime(ts),
                        style: TextStyle(fontFamily: 'Poppins',
                            fontSize: 12, color: t.sub),
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ]),
                  )),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Badge widgets ──────────────────────────────────────────────────────────────

class _LogRoleBadge extends StatelessWidget {
  final String? role;
  const _LogRoleBadge({this.role});
  @override
  Widget build(BuildContext context) {
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
    final isKnown = const ['admin', 'organizer', 'student'].contains(role);
    final color = isKnown ? _logRoleColor(role) : t.muted;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_logRoleIcon(role), size: 11, color: color),
          const SizedBox(width: 4),
          Text(_logRoleLabel(role),
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    ]);
  }
}

class _LogPlatformBadge extends StatelessWidget {
  final String? platform;
  const _LogPlatformBadge({this.platform});
  @override
  Widget build(BuildContext context) {
    final isWeb = (platform ?? '') == 'web';
    final color = isWeb ? const Color(0xFF4F46E5) : const Color(0xFF0D9488);
    final icon  = isWeb ? Icons.language_rounded : Icons.smartphone_rounded;
    final label = isWeb ? 'Web' : 'Mobile';
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    ]);
  }
}

class _LogActionBadge extends StatelessWidget {
  final String? action;
  const _LogActionBadge({this.action});
  @override
  Widget build(BuildContext context) {
    final t = AdminTk(Theme.of(context).brightness == Brightness.dark);
    final isKnown = const ['created', 'updated', 'deleted'].contains(action);
    final color = isKnown ? _logActionColor(action) : t.muted;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_logActionIcon(action), size: 11, color: color),
          const SizedBox(width: 4),
          Text(_logActionLabel(action),
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    ]);
  }
}

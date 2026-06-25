import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/services/supabase_service.dart';
import '../organizer/web/web_shared.dart';
import '../../shared/widgets/event_phase_pill.dart';

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Admin palette Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
const _kAccent     = Color(0xFFEA580C); // orange
const _kSideTop    = Color(0xFF4A2894);
const _kSideMid    = Color(0xFF3B1F7A);
const _kSideBot    = Color(0xFF2D1660);
const _kSideBorder = Color(0xFF5A35A8);
const _kNavText    = Color(0xFFF1F5F9);
const _kNavIcon    = Color(0xFFCBD5E1);

const _kSideGrad = LinearGradient(
  colors: [_kSideTop, _kSideMid, _kSideBot],
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
);

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Navigation Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
enum AdminPage { overview, students, organizers, events, registrations }

const _kNavItems = [
  (AdminPage.overview,      Icons.dashboard_rounded,      'Dashboard'),
  (AdminPage.students,      Icons.people_rounded,         'Students'),
  (AdminPage.organizers,    Icons.badge_rounded,          'Organizers'),
  (AdminPage.events,        Icons.event_rounded,          'Events'),
  (AdminPage.registrations, Icons.how_to_reg_rounded,     'Registrations'),
];

// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
// Shell
// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â

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
    if (_loading) {
      return const Scaffold(
        backgroundColor: kWebBg,
        body: Center(child: CircularProgressIndicator(color: _kAccent)),
      );
    }
    if (_error) {
      return Scaffold(
        backgroundColor: kWebBg,
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
            const Text('Could not load admin profile',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 17,
                  fontWeight: FontWeight.w800, color: kText)),
            const SizedBox(height: 8),
            const Text('Check your connection and try again.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: kSubText)),
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
      backgroundColor: kWebBg,
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
    AdminPage.overview      => _AdminOverviewPage(onNavigate: _navigate),
    AdminPage.students      => const _AdminStudentsPage(),
    AdminPage.organizers    => const _AdminOrganizersPage(),
    AdminPage.events        => const _AdminEventsPage(),
    AdminPage.registrations => const _AdminRegistrationsPage(),
  };
}

// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
// Sidebar
// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â

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
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      gradient: _kSideGrad,
      border: Border(right: BorderSide(color: _kSideBorder, width: 1)),
    ),
    child: Column(children: [
      _cascade(_buildHeader(), 0),
      const SizedBox(height: 4),
      _cascade(_buildNavLabel(), 1),
      Expanded(child: _buildNavItems()),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Divider(color: _kSideBorder.withValues(alpha: 0.35), height: 1),
      ),
      _cascade(_buildUserSection(), widget.collapsed ? 6 : 7),
    ]),
  );

  Widget _buildHeader() {
    const bDeco = BoxDecoration(
      border: Border(bottom: BorderSide(color: _kSideBorder, width: 1)),
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
              const Text('J-Jireh',
                style: TextStyle(
                  fontFamily: 'Playball', fontSize: 21,
                  color: _kNavText, fontWeight: FontWeight.w700, height: 1.1,
                )),
              const SizedBox(height: 3),
              Row(children: [
                Container(
                  width: 16, height: 2,
                  decoration: BoxDecoration(
                    color: _kAccent,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                const SizedBox(width: 8),
                Text('EVENTHUB',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: _kNavText.withValues(alpha: 0.70),
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

  Widget _buildNavLabel() {
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
        const Text('NAVIGATION',
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w700,
            color: _kNavIcon, letterSpacing: 1.8,
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

  Widget _buildUserSection() {
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
          _SignOutIconBtn(onTap: widget.onSignOut, borderColor: _kSideBorder),
          const SizedBox(height: 2),
        ]),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kSideBorder.withValues(alpha: 0.50)),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
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
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                                fontWeight: FontWeight.w700, color: _kNavText),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 1),
                          const Text('System Admin',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 9.5, color: _kNavIcon)),
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

// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
// Nav item
// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â

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
    final active = widget.isActive;
    final Color itemBg     = active ? _kAccent.withValues(alpha: 0.13)
        : _hovered ? Colors.white.withValues(alpha: 0.46) : Colors.transparent;
    final Color itemBorder = active ? _kAccent.withValues(alpha: 0.24)
        : _hovered ? _kSideBorder.withValues(alpha: 0.26) : Colors.transparent;
    final Color iconColor  = active ? _kAccent : _hovered ? _kNavText : _kNavIcon;
    final Color labelColor = active ? Colors.white : _hovered ? _kNavText : _kNavIcon;

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

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Sign-out buttons Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

class _SignOutIconBtn extends StatefulWidget {
  final VoidCallback onTap; final Color borderColor;
  const _SignOutIconBtn({required this.onTap, required this.borderColor});
  @override State<_SignOutIconBtn> createState() => _SignOutIconBtnState();
}
class _SignOutIconBtnState extends State<_SignOutIconBtn> {
  bool _h = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _h = true),
    onExit:  (_) => setState(() => _h = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: _h ? const Color(0xFFFEF2F2) : Colors.white.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: _h ? const Color(0xFFFCA5A5) : widget.borderColor.withValues(alpha: 0.45)),
        ),
        child: Icon(Icons.logout_rounded, size: 15,
            color: _h ? const Color(0xFFEF4444) : _kNavIcon),
      ),
    ),
  );
}

class _InlineSignOutBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _InlineSignOutBtn({required this.onTap});
  @override State<_InlineSignOutBtn> createState() => _InlineSignOutBtnState();
}
class _InlineSignOutBtnState extends State<_InlineSignOutBtn> {
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
        width: 30, height: 30,
        decoration: BoxDecoration(
          color: _h ? const Color(0xFFFEF2F2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _h ? const Color(0xFFFCA5A5) : Colors.transparent),
        ),
        child: Icon(Icons.logout_rounded, size: 14,
            color: _h ? const Color(0xFFEF4444) : _kNavIcon),
      ),
    ),
  );
}

// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
// Top bar
// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â

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
    AdminPage.overview      => 'Dashboard',
    AdminPage.students      => 'Students',
    AdminPage.organizers    => 'Organizers',
    AdminPage.events        => 'Events',
    AdminPage.registrations => 'Registrations',
  };

  @override
  Widget build(BuildContext context) => Container(
    height: kWebTopH,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: kCardBorder)),
      boxShadow: [BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2))],
    ),
    child: Row(children: [
      _TopIconBtn(
        icon: collapsed ? Icons.menu_open_rounded : Icons.menu_rounded,
        onTap: onMenuTap,
      ),
      const SizedBox(width: 14),
      const Text('Admin',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: kMuted, fontWeight: FontWeight.w500)),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: Icon(Icons.chevron_right_rounded, size: 16, color: kMuted),
      ),
      Text(_label(),
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
            fontWeight: FontWeight.w700, color: kText)),
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

// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
// Overview page
// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â

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
  bool      _refreshing = false;
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
  Map<String, int>           _statusCounts   = {};
  List<_TopEvent>            _topEvents      = [];
  List<Map<String, dynamic>> _recentRegs     = [];
  List<Map<String, dynamic>> _upcomingEvents = [];

  @override
  void initState() { super.initState(); _load(); }

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
      // 1. Stat counts â€” 3 columns, all rows (much less data than full rows)
      // 2. Recent 10 â€” full display columns, limited (for activity feed)
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

      // Ã¢â€â‚¬Ã¢â€â‚¬ Event stats Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
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

      // Ã¢â€â‚¬Ã¢â€â‚¬ Registration stats Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
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

      // Ã¢â€â‚¬Ã¢â€â‚¬ Top 5 events by registration count Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
      // Top 5 events by current_participants â€” already in events query, no extra reg fetch needed
      final topEvents = (events
          .where((e) => (e['current_participants'] as int? ?? 0) > 0)
          .toList()
            ..sort((a, b) => (b['current_participants'] as int? ?? 0)
                .compareTo(a['current_participants'] as int? ?? 0)))
          .take(5)
          .map((e) => _TopEvent(
              title:    e['title'] as String? ?? 'â€”',
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

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await _load(silent: true);
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _kAccent));
    if (_dashError) return _buildDashError();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(kWebPad),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildHeader(),
        const SizedBox(height: 20),
        _buildKpiRow(),
        const SizedBox(height: 20),
        _buildRecentRegs(),
        const SizedBox(height: 20),
        _buildChartsRow(),
        const SizedBox(height: 20),
        _buildBottomRow(),
        const SizedBox(height: 16),
      ]),
    );
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Photo review alert Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬


  // Ã¢â€â‚¬Ã¢â€â‚¬ Header Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  Widget _buildHeader() {
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Dashboard Overview',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 22,
              fontWeight: FontWeight.w800, color: kText)),
        const SizedBox(height: 2),
        const Text('J-Jireh EventHub  Â·  Administration',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: kMuted)),
      ])),
      if (_regNeedsReview > 0) ...[
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => widget.onNavigate(AdminPage.registrations),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.30)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.photo_camera_outlined, size: 14, color: Color(0xFF8B5CF6)),
                const SizedBox(width: 6),
                Text('$_regNeedsReview pending review${_regNeedsReview == 1 ? '' : 's'}',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                      fontWeight: FontWeight.w700, color: Color(0xFF8B5CF6))),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 12),
      ],
      WebBtn(label: 'Refresh', icon: Icons.refresh_rounded,
          onTap: _refreshing ? () {} : _refresh, outlined: true, color: _kAccent),
    ]);
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ KPI row Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  Widget _buildKpiRow() => Row(children: [
    Expanded(child: _KpiCard(
      icon: Icons.people_rounded, color: _kAccent,
      label: 'Total Students', value: '$_studentTotal',
      sub1: '$_studentActive Active', sub2: '${_studentTotal - _studentActive} Inactive',
      sub1Color: const Color(0xFF10B981), sub2Color: kMuted,
      onTap: () => widget.onNavigate(AdminPage.students),
    )),
    const SizedBox(width: 14),
    Expanded(child: _KpiCard(
      icon: Icons.badge_rounded, color: kGold,
      label: 'Organizers', value: '$_orgTotal',
      sub1: '$_orgActive Active', sub2: '${_orgTotal - _orgActive} Inactive',
      sub1Color: const Color(0xFF10B981), sub2Color: kMuted,
      onTap: () => widget.onNavigate(AdminPage.organizers),
    )),
    const SizedBox(width: 14),
    Expanded(child: _KpiCard(
      icon: Icons.event_rounded, color: const Color(0xFF10B981),
      label: 'Total Events', value: '$_eventTotal',
      sub1: '$_eventUpcoming Upcoming / Ongoing',
      sub2: '${_statusCounts['completed'] ?? 0} Completed',
      sub1Color: _kAccent, sub2Color: kMuted,
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
      sub2Color: _regNeedsReview > 0 ? const Color(0xFF8B5CF6) : kMuted,
      onTap: () => widget.onNavigate(AdminPage.registrations),
    )),
  ]);

  // Ã¢â€â‚¬Ã¢â€â‚¬ Today snapshot row Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬


  // Ã¢â€â‚¬Ã¢â€â‚¬ Charts row Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  Widget _buildChartsRow() => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Expanded(
      flex: 3,
      child: WebCard(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(children: [
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Registration Trend',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                      fontWeight: FontWeight.w700, color: kText)),
                SizedBox(height: 2),
                Text('Daily sign-ups over the selected period',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: kSubText)),
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
          const Text('Event Status Breakdown',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                fontWeight: FontWeight.w700, color: kText)),
          const SizedBox(height: 3),
          const Text('Distribution of all events',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: kSubText)),
          const SizedBox(height: 20),
          _EventStatusDonut(statusCounts: _statusCounts, total: _eventTotal),
        ]),
      ),
    ),
  ]);

  // Ã¢â€â‚¬Ã¢â€â‚¬ Bottom row Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  Widget _buildBottomRow() => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Expanded(
      flex: 3,
      child: WebCard(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Top Events by Registrations',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                    fontWeight: FontWeight.w700, color: kText)),
              const SizedBox(height: 3),
              const Text('Most registered events across all organizers',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: kSubText)),
            ])),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => widget.onNavigate(AdminPage.events),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('View events', style: TextStyle(fontFamily: 'Poppins',
                      fontSize: 12, fontWeight: FontWeight.w600, color: _kAccent)),
                  Icon(Icons.chevron_right_rounded, size: 14, color: _kAccent),
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
              const Expanded(child: Text('Upcoming Events',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                    fontWeight: FontWeight.w700, color: kText))),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => widget.onNavigate(AdminPage.events),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('All events', style: TextStyle(fontFamily: 'Poppins',
                        fontSize: 12, fontWeight: FontWeight.w600, color: _kAccent)),
                    Icon(Icons.chevron_right_rounded, size: 14, color: _kAccent),
                  ]),
                ),
              ),
            ]),
          ),
          const Divider(height: 1, color: kCardBorder),
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

  // Ã¢â€â‚¬Ã¢â€â‚¬ Recent registrations Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  Widget _buildRecentRegs() => WebCard(
    padding: EdgeInsets.zero,
    child: Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: Row(children: [
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Recent Registrations',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                  fontWeight: FontWeight.w700, color: kText)),
            SizedBox(height: 2),
            Text('Latest sign-ups across all events',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: kSubText)),
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
      const Divider(height: 1, color: kCardBorder),
      if (_recentRegs.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.how_to_reg_rounded, size: 36, color: kCardBorder),
            SizedBox(height: 12),
            Text('No registrations yet',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  fontWeight: FontWeight.w600, color: kText)),
            SizedBox(height: 4),
            Text('Sign-ups will appear here as students register for events.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: kSubText)),
          ])),
        )
      else
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _recentRegs.length,
          separatorBuilder: (_, _) => const Divider(height: 1, color: kCardBorder),
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
                    Text(r['student_name'] as String? ?? 'â€”',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                          fontWeight: FontWeight.w600, color: kText),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(r['event_title'] as String? ?? 'â€”',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: kSubText),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ])),
                  const SizedBox(width: 12),
                  WebStatusBadge(label: webStatusLabel(status), color: sc),
                  const SizedBox(width: 16),
                  Text(webTimeAgo(r['registered_at'] as String?),
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: kMuted)),
                ]),
              ),
            );
          },
        ),
    ]),
  );

  Widget _buildDashError() => Center(
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
      const Text('Could not load dashboard data',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 16,
            fontWeight: FontWeight.w800, color: kText)),
      const SizedBox(height: 8),
      const Text('Check your connection and try again.',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: kSubText)),
      const SizedBox(height: 24),
      WebBtn(label: 'Retry', icon: Icons.refresh_rounded, onTap: () {
        setState(() => _dashError = false);
        _load();
      }),
    ]),
  );

}

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ KPI card Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

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
  Widget build(BuildContext context) => MouseRegion(
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
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12, offset: const Offset(0, 2),
            )],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: kCardBorder),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(height: 3, color: widget.color),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 15, 18, 18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: Text(widget.label,
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                            color: kMuted, fontWeight: FontWeight.w500))),
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
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 30,
                          fontWeight: FontWeight.w800, color: kText, height: 1.0)),
                    const SizedBox(height: 14),
                    const Divider(height: 1, color: kCardBorder),
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

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Registration trend line chart Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

class _RegTrendChart extends StatelessWidget {
  final List<double> dailyRegs;
  final DateTime     windowStart;
  const _RegTrendChart({required this.dailyRegs, required this.windowStart});

  @override
  Widget build(BuildContext context) {
    final n      = dailyRegs.length;
    final rawMax = dailyRegs.reduce((a, b) => a > b ? a : b);
    if (rawMax < 1) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.show_chart_rounded, size: 32, color: kCardBorder),
          SizedBox(height: 10),
          Text('No registrations in this period',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: kMuted)),
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
              color: Colors.grey.withValues(alpha: 0.10),
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
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 9, color: kMuted)),
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
                        color: isToday ? _kAccent : kMuted,
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

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Chart window toggle (7D / 30D) Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

class _ChartWindowToggle extends StatelessWidget {
  final int                selected;
  final ValueChanged<int>  onSelect;
  const _ChartWindowToggle({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: kCardBorder.withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _tab(7,  '7D'),
        _tab(30, '30D'),
      ]),
    );
  }

  Widget _tab(int days, String label) {
    final active = selected == days;
    return GestureDetector(
      onTap: () => onSelect(days),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color:        active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          boxShadow: active
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
                           blurRadius: 4, offset: const Offset(0, 1))]
              : null,
        ),
        child: Text(label,
          style: TextStyle(
            fontFamily:  'Poppins',
            fontSize:    11,
            fontWeight:  active ? FontWeight.w700 : FontWeight.w500,
            color:       active ? _kAccent : kMuted,
          )),
      ),
    );
  }
}

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Event status donut chart Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

class _EventStatusDonut extends StatefulWidget {
  final Map<String, int> statusCounts;
  final int              total;
  const _EventStatusDonut({required this.statusCounts, required this.total});
  @override State<_EventStatusDonut> createState() => _EventStatusDonutState();
}

class _EventStatusDonutState extends State<_EventStatusDonut> {
  int _touched = -1;

  static const _statuses = [
    ('upcoming',  'Upcoming',  Color(0xFF3B82F6)),
    ('ongoing',   'Ongoing',   Color(0xFF10B981)),
    ('completed', 'Completed', Color(0xFF8B5CF6)),
    ('cancelled', 'Cancelled', Color(0xFFEF4444)),
  ];

  @override
  Widget build(BuildContext context) {
    final active = <(String, String, Color, int)>[];
    for (final s in _statuses) {
      final c = widget.statusCounts[s.$1] ?? 0;
      if (c > 0) active.add((s.$1, s.$2, s.$3, c));
    }

    final sections = active.isEmpty
        ? [PieChartSectionData(value: 1, color: kCardBorder, radius: 40, showTitle: false)]
        : active.asMap().entries.map((entry) {
            final isTouched = _touched == entry.key;
            final s = entry.value;
            return PieChartSectionData(
              value: s.$4.toDouble(),
              color: s.$3,
              radius: isTouched ? 50 : 40,
              showTitle: false,
            );
          }).toList();

    return Column(children: [
      SizedBox(
        height: 130,
        child: Stack(alignment: Alignment.center, children: [
          PieChart(
            PieChartData(
              sections: sections,
              centerSpaceRadius: 38,
              sectionsSpace: 3,
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  if (!event.isInterestedForInteractions ||
                      response?.touchedSection == null) {
                    if (mounted) setState(() => _touched = -1);
                    return;
                  }
                  if (mounted) {
                    setState(() =>
                        _touched = response!.touchedSection!.touchedSectionIndex);
                  }
                },
              ),
            ),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${widget.total}',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 22,
                  fontWeight: FontWeight.w800, color: kText, height: 1.0)),
            const Text('events',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: kMuted)),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12, runSpacing: 6, alignment: WrapAlignment.center,
        children: _statuses
            .where((s) => (widget.statusCounts[s.$1] ?? 0) > 0)
            .map((s) => Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8,
                  decoration: BoxDecoration(color: s.$3, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text('${s.$2} (${widget.statusCounts[s.$1] ?? 0})',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 10.5, color: kSubText)),
              ]))
            .toList(),
      ),
    ]);
  }
}

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Top events progress bars Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

class _TopEventsChart extends StatelessWidget {
  final List<_TopEvent> events;
  const _TopEventsChart({required this.events});

  @override
  Widget build(BuildContext context) {
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
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                    fontWeight: FontWeight.w600, color: kText),
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
                    color: kCardBorder, borderRadius: BorderRadius.circular(6)),
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

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Today snapshot stat cell Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬


// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Upcoming event tile Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

class _UpcomingEventTile extends StatelessWidget {
  final Map<String, dynamic> event;
  final bool                  isLast;
  const _UpcomingEventTile({required this.event, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final title   = event['title']         as String? ?? 'â€”';
    final dStr    = event['event_date']    as String?;
    final status  = (event['event_status'] as String? ?? '').toLowerCase();
    final orgName = (event['organizers']   as Map<String, dynamic>?)?['full_name'] as String? ?? 'â€”';
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
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                  fontWeight: FontWeight.w600, color: kText),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(
              timeLabel.isNotEmpty ? '$timeLabel  Â·  by $orgName' : 'by $orgName',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: kMuted),
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
      if (!isLast) const Divider(height: 1, color: kCardBorder),
    ]);
  }
}

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Placeholder note Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

class _PlaceholderNote extends StatelessWidget {
  final String text;
  const _PlaceholderNote({required this.text});
  @override
  Widget build(BuildContext context) => Center(
    child: Text(text,
      style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: kMuted)),
  );
}

// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
// Students page
// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â

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

  List<String> get _yearOptions {
    final years = _all
        .map((s) => s['year_level'])
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();
    return ['All', ...years.map((y) => 'Year $y')];
  }

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = false; });
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
        final yr = int.tryParse(_yearFilter.replaceAll('Year ', ''));
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
    final result = await showDialog<Map<String, dynamic>?>(
      context: context, builder: (_) => const _StudentDialog(student: null));
    if (result == null) return;
    try {
      await SupabaseService.client.from('students').insert(result);
      _load();
      if (mounted) WebAlert.success(context: context, title: 'Added', message: 'New student record created.');
    } catch (e) { if (mounted) _snack('Failed: $e'); }
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
    final totalCount        = _all.length;
    final activeCount       = _all.where((s) => s['is_active'] == true).length;
    final inactiveCount     = totalCount - activeCount;
    final noAuthCount       = _all.where((s) => s['user_id'] == null).length;
    final unregisteredCount = _all.where((s) =>
        (_regCounts[s['lrn'] as String? ?? ''] ?? 0) == 0).length;
    final hasFilter         = _search.isNotEmpty || _statusFilter != 'All' || _yearFilter != 'All';
    final yearOpts          = _yearOptions;

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    if (_error) {
      return _ErrorState(message: _errorMsg, onRetry: _load);
    }

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Ã¢â€â‚¬Ã¢â€â‚¬ Page header Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
      Container(
        padding: const EdgeInsets.fromLTRB(kWebPad, 18, kWebPad, 14),
        color: Colors.white,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Manage Students',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 18,
                    fontWeight: FontWeight.w800, color: kText)),
              const SizedBox(height: 2),
              Text('$totalCount students enrolled',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: kSubText)),
            ])),
            WebSearchField(
              controller: _searchCtrl, hint: 'Search name or LRNÃ¢â‚¬Â¦',
              onChanged: (v) { _search = v; _applyFilter(); }, width: 240),
            const SizedBox(width: 12),
            WebBtn(label: 'Refresh', icon: Icons.refresh_rounded,
                onTap: _load, outlined: true, color: _kAccent),
            const SizedBox(width: 10),
            WebBtn(label: 'Add Student', icon: Icons.add_rounded, onTap: _addStudent),
          ]),
          const SizedBox(height: 16),
          // Ã¢â€â‚¬Ã¢â€â‚¬ Stat tiles Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
          Row(children: [
            _StudentStatCard(label: 'Total Enrolled', value: '$totalCount',
                color: _kAccent, icon: Icons.people_rounded),
            const SizedBox(width: 10),
            _StudentStatCard(label: 'Active', value: '$activeCount',
                color: const Color(0xFF10B981), icon: Icons.check_circle_rounded),
            const SizedBox(width: 10),
            _StudentStatCard(
              label: inactiveCount > 0 ? 'Inactive' : 'All Active',
              value: '$inactiveCount',
              color: inactiveCount > 0 ? kMuted : const Color(0xFF10B981),
              icon:  inactiveCount > 0 ? Icons.person_off_outlined : Icons.verified_rounded,
            ),
            const SizedBox(width: 10),
            _StudentStatCard(
              label: noAuthCount > 0 ? 'No Auth Account' : 'All Linked',
              value: '$noAuthCount',
              color: noAuthCount > 0 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
              icon:  noAuthCount > 0 ? Icons.warning_amber_rounded : Icons.link_rounded,
            ),
            const SizedBox(width: 10),
            _StudentStatCard(
              label: unregisteredCount > 0 ? 'Never Registered' : 'All Participated',
              value: '$unregisteredCount',
              color: unregisteredCount > 0 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
              icon:  unregisteredCount > 0 ? Icons.event_busy_rounded : Icons.event_available_rounded,
            ),
          ]),
        ]),
      ),
      // Ã¢â€â‚¬Ã¢â€â‚¬ Filter bar Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
      Container(
        padding: const EdgeInsets.fromLTRB(kWebPad, 8, kWebPad, 8),
        decoration: const BoxDecoration(
          color: Color(0xFFFAFBFC),
          border: Border(bottom: BorderSide(color: kCardBorder)),
        ),
        child: Row(children: [
          const Text('Status:',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                fontWeight: FontWeight.w600, color: kText)),
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
            Container(width: 1, height: 18, color: kCardBorder),
            const SizedBox(width: 12),
            const Text('Year:',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  fontWeight: FontWeight.w600, color: kText)),
            const SizedBox(width: 8),
            for (final y in yearOpts) ...[
              WebFilterChip(
                label: y, selected: _yearFilter == y,
                onTap: () { _yearFilter = y; _applyFilter(); },
                count: y == 'All'
                    ? totalCount
                    : _all.where((s) {
                        final yr = int.tryParse(y.replaceAll('Year ', ''));
                        return (s['year_level'] as int?) == yr;
                      }).length,
              ),
              const SizedBox(width: 6),
            ],
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
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.close_rounded, size: 13, color: kMuted),
                  SizedBox(width: 4),
                  Text('Clear filters', style: TextStyle(fontFamily: 'Poppins',
                      fontSize: 11.5, fontWeight: FontWeight.w600, color: kMuted)),
                ]),
              ),
            ),
          ],
        ]),
      ),
      // Ã¢â€â‚¬Ã¢â€â‚¬ Body Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
        if (_filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(kWebPad),
            child: WebEmptyState(
              icon: Icons.people_outline_rounded,
              title: 'No students found',
              subtitle: hasFilter
                  ? 'No students match the current filters.'
                  : 'Add your first student to get started.',
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
                  separatorBuilder: (_, _) => const Divider(height: 1, color: kCardBorder),
                  itemBuilder: (_, i) => _StudentRow(
                    student:  _filtered[i],
                    regCount: _regCounts[_filtered[i]['lrn'] as String? ?? ''] ?? 0,
                    onEdit:   () => _editStudent(_filtered[i]),
                    onToggle: () => _toggleActive(
                      _filtered[i]['lrn'] as String,
                      _filtered[i]['is_active'] == true),
                    onDelete: () => _deleteStudent(
                      _filtered[i]['lrn'] as String,
                      _filtered[i]['full_name'] as String? ?? 'â€”'),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: kCardBorder))),
                  child: Text(
                    hasFilter
                        ? 'Showing ${_filtered.length} of $totalCount students'
                        : '${_filtered.length} students total',
                    style: const TextStyle(fontFamily: 'Poppins',
                        fontSize: 11.5, color: kMuted)),
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
    final s           = widget.student;
    final active      = s['is_active'] == true;
    final linked      = s['user_id'] != null;
    final yr          = s['year_level'] as int?;
    final initials    = (s['full_name'] as String? ?? '?').trim().split(' ')
        .where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).take(2).join();
    final avatarColor = active ? _kAccent : kMuted;

    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _h ? _kAccent.withValues(alpha: 0.03) : Colors.transparent,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 3, color: active ? Colors.transparent : kMuted.withValues(alpha: 0.30)),
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
            Text(s['full_name'] as String? ?? 'Ã¢â‚¬â€',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? kText : kMuted),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            if (!linked)
              const Text('No auth account',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                    color: Color(0xFFF59E0B), fontWeight: FontWeight.w600)),
          ])),
          // LRN
          Expanded(flex: 2, child: Text(s['lrn'] as String? ?? 'Ã¢â‚¬â€',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: kSubText),
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
                child: Text('Yr $yr',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                      fontWeight: FontWeight.w700, color: Color(0xFF6D28D9))))
            : const Text('â€”', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: kMuted))),
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
                    color: kMuted.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('0',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                        fontWeight: FontWeight.w500, color: kMuted)))),
          // Status badge
          Expanded(child: WebStatusBadge(
            label: active ? 'Active' : 'Inactive',
            color: active ? const Color(0xFF10B981) : kMuted)),
          // Account link status Ã¢â‚¬â€ amber when unlinked
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
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: kMuted))),
          // Actions Ã¢â‚¬â€ always rendered at fixed width; _ActBtn provides its own hover color
          SizedBox(
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
            ]),          // closes actions Row
          ),             // closes SizedBox(108)
                ]),      // closes inner Row (Padding child)
              ),         // closes Padding
            ),           // closes Expanded
          ]),            // closes outer Row (IntrinsicHeight child)
        ),               // closes IntrinsicHeight
      ),                 // closes AnimatedContainer
    );                   // closes MouseRegion
  }
}

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Mini stat tile Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

class _MiniStat extends StatelessWidget {
  final String   label, value;
  final Color    color;
  final IconData icon;
  const _MiniStat({
    required this.label, required this.value,
    required this.color, required this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
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
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 9.5, color: kSubText)),
      ]),
    ]),
  );
}

// â”€â”€â”€ Student stat card (Students tab â€” full-width Expanded KPI style) â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _StudentStatCard extends StatelessWidget {
  final String   label, value;
  final Color    color;
  final IconData icon;
  const _StudentStatCard({
    required this.label, required this.value,
    required this.color, required this.icon,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8, offset: const Offset(0, 1))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: kCardBorder),
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
                            fontWeight: FontWeight.w800, color: kText, height: 1.0)),
                      const SizedBox(height: 2),
                      Text(label,
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 9.5,
                            color: kSubText)),
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

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Sortable table header for Students Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

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

  Widget _staticCol(String label, {int flex = 1}) => Expanded(
    flex: flex,
    child: Text(label, style: const TextStyle(fontFamily: 'Poppins',
        fontSize: 10.5, fontWeight: FontWeight.w700, color: kSubText, letterSpacing: 0.8)),
  );

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.only(left: 23, right: 20, top: 10, bottom: 10),
    decoration: const BoxDecoration(
      color: Color(0xFFF0F3F7),
      border: Border(bottom: BorderSide(color: kCardBorder)),
    ),
    child: Row(children: [
      const SizedBox(width: 52),
      _sortCol('FULL NAME',  'full_name',  flex: 3),
      _sortCol('LRN',        'lrn',        flex: 2),
      _sortCol('YEAR',       'year_level'),
      _sortCol('REGS',       'reg_count'),
      _sortCol('STATUS',     'is_active'),
      _staticCol('ACCOUNT'),
      _sortCol('CREATED',    'created_at', flex: 2),
      const SizedBox(width: 108),
    ]),
  );
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
  Widget build(BuildContext context) => MouseRegion(
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
            color: widget.active ? _kAccent : _h ? kText : kSubText,
          )),
        const SizedBox(width: 3),
        Icon(
          widget.active
              ? (widget.asc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded)
              : Icons.unfold_more_rounded,
          size: 11,
          color: widget.active ? _kAccent : _h ? kSubText : kCardBorder,
        ),
      ]),
    ),
  );
}

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Student dialog Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

class _StudentDialog extends StatefulWidget {
  final Map<String, dynamic>? student;
  const _StudentDialog({required this.student});
  @override State<_StudentDialog> createState() => _StudentDialogState();
}
class _StudentDialogState extends State<_StudentDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _scale, _fade;
  final _lrnCtrl  = TextEditingController();
  final _nameCtrl = TextEditingController();
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
    _lrnCtrl.dispose(); _nameCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final lrn  = _lrnCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (!_isEdit && !RegExp(r'^\d{12}$').hasMatch(lrn)) {
      _snack('LRN must be exactly 12 digits'); return;
    }
    if (name.isEmpty) { _snack('Full name is required'); return; }
    final data = <String, dynamic>{'full_name': name, 'year_level': _selectedYear};
    if (!_isEdit) { data['lrn'] = lrn; data['is_active'] = true; }
    Navigator.of(context).pop(data);
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: Colors.red));

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child: ScaleTransition(
      scale: _scale,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: _dialogShell(
            icon: Icons.people_rounded, iconColor: _kAccent,
            title: _isEdit ? 'Edit Student' : 'Add Student',
            body: Column(children: [
              if (!_isEdit) ...[
                TextField(
                  controller: _lrnCtrl,
                  decoration: webInputDeco('LRN (e.g. 123456789012)', icon: Icons.badge_outlined),
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: kText)),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _nameCtrl,
                decoration: webInputDeco('Full Name', icon: Icons.person_outline_rounded),
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: kText)),
              const SizedBox(height: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Year Level',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                      fontWeight: FontWeight.w600, color: kSubText)),
                const SizedBox(height: 8),
                Row(children: [
                  for (final y in [1, 2, 3, 4]) ...[
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(
                            () => _selectedYear = _selectedYear == y ? null : y),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: BoxDecoration(
                            color: _selectedYear == y
                                ? _kAccent.withValues(alpha: 0.10)
                                : const Color(0xFFF8F9FC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _selectedYear == y ? _kAccent : kCardBorder,
                              width: _selectedYear == y ? 1.5 : 1.0,
                            ),
                          ),
                          child: Text('Year $y',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 12.5,
                              fontWeight: _selectedYear == y
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: _selectedYear == y ? _kAccent : kSubText,
                            )),
                        ),
                      ),
                    ),
                    if (y < 4) const SizedBox(width: 8),
                  ],
                ]),
              ]),
              if (!_isEdit) ...[
                const SizedBox(height: 12),
                _InfoNote(
                  'Login credentials are provisioned separately via SQL. This creates the profile record only.'),
              ],
            ]),
            confirmLabel: _isEdit ? 'Save Changes' : 'Add Student',
            confirmColor: _kAccent,
            onConfirm: _save,
          ),
        ),
      ),
    ),
  );
}

// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
// Organizers page
// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â

class _AdminOrganizersPage extends StatefulWidget {
  const _AdminOrganizersPage();
  @override State<_AdminOrganizersPage> createState() => _AdminOrganizersPageState();
}

class _AdminOrganizersPageState extends State<_AdminOrganizersPage> {
  bool   _loading = true, _error = false, _refreshing = false;
  String _errorMsg = '';
  List<Map<String, dynamic>> _all = [], _filtered = [];
  Map<String, int> _eventCounts = {};
  String _search       = '';
  String _statusFilter = 'All';
  String _sortField    = 'created_at';
  bool   _sortAsc      = false;
  final _searchCtrl = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

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

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await _load(silent: true);
    if (mounted) setState(() => _refreshing = false);
  }

  void _applyFilter() {
    final q = _search.toLowerCase();
    var list = _all.where((o) {
      if (_statusFilter == 'Active'    && o['is_active'] != true) return false;
      if (_statusFilter == 'Inactive'  && o['is_active'] == true) return false;
      if (_statusFilter == 'No Auth'   && o['user_id']  != null)  return false;
      if (_statusFilter == 'No Events' &&
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
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (_) => _OrganizerDialog(organizer: null, suggestedId: nextId));
    if (result == null) return;
    try {
      await SupabaseService.client.from('organizers').insert(result);
      _load();
      if (mounted) WebAlert.success(context: context, title: 'Added', message: 'Organizer record created.');
    } catch (e) { if (mounted) _snack('Failed: $e'); }
  }

  Future<String> _nextOrgId() async {
    try {
      final rows = await SupabaseService.client.from('organizers')
          .select('organizer_id').order('organizer_id', ascending: false).limit(1);
      final list = rows as List;
      if (list.isEmpty) return 'JJ0001';
      final last = list.first['organizer_id'] as String? ?? 'JJ0000';
      final num  = int.tryParse(last.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return 'JJ${(num + 1).toString().padLeft(4, '0')}';
    } catch (_) { return 'JJ0001'; }
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
    final totalCount    = _all.length;
    final activeCount   = _all.where((o) => o['is_active'] == true).length;
    final inactiveCount = totalCount - activeCount;
    final noAuthCount   = _all.where((o) => o['user_id'] == null).length;
    final noEventsCount = _all.where((o) =>
        (_eventCounts[o['organizer_id'] as String? ?? ''] ?? 0) == 0).length;
    final hasFilter     = _search.isNotEmpty || _statusFilter != 'All';

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    if (_error) {
      return _ErrorState(message: _errorMsg, onRetry: _load);
    }

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Ã¢â€â‚¬Ã¢â€â‚¬ Page header Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
      Container(
        padding: const EdgeInsets.fromLTRB(kWebPad, 18, kWebPad, 14),
        color: Colors.white,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Manage Organizers',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 18,
                    fontWeight: FontWeight.w800, color: kText)),
              const SizedBox(height: 2),
              Text('$totalCount organizers registered',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: kSubText)),
            ])),
            WebSearchField(
              controller: _searchCtrl, hint: 'Search name, ID, or orgÃ¢â‚¬Â¦',
              onChanged: (v) { _search = v; _applyFilter(); }, width: 240),
            const SizedBox(width: 12),
            WebBtn(label: 'Refresh', icon: Icons.refresh_rounded,
                onTap: _refreshing ? () {} : _refresh, outlined: true, color: _kAccent),
            const SizedBox(width: 10),
            WebBtn(label: 'Add Organizer', icon: Icons.add_rounded, onTap: _addOrganizer),
          ]),
          const SizedBox(height: 16),
          // Ã¢â€â‚¬Ã¢â€â‚¬ Stat tiles Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
          Row(children: [
            _StudentStatCard(label: 'Total Organizers', value: '$totalCount',
                color: kGold, icon: Icons.badge_rounded),
            const SizedBox(width: 10),
            _StudentStatCard(label: 'Active', value: '$activeCount',
                color: const Color(0xFF10B981), icon: Icons.check_circle_rounded),
            const SizedBox(width: 10),
            _StudentStatCard(
              label: inactiveCount > 0 ? 'Inactive' : 'All Active',
              value: '$inactiveCount',
              color: inactiveCount > 0 ? kMuted : const Color(0xFF10B981),
              icon:  inactiveCount > 0 ? Icons.person_off_outlined : Icons.verified_rounded,
            ),
            const SizedBox(width: 10),
            _StudentStatCard(
              label: noAuthCount > 0 ? 'No Auth Account' : 'All Linked',
              value: '$noAuthCount',
              color: noAuthCount > 0 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
              icon:  noAuthCount > 0 ? Icons.warning_amber_rounded : Icons.link_rounded,
            ),
            const SizedBox(width: 10),
            _StudentStatCard(
              label: noEventsCount > 0 ? 'No Events' : 'All Creating',
              value: '$noEventsCount',
              color: noEventsCount > 0 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
              icon:  noEventsCount > 0 ? Icons.event_busy_rounded : Icons.event_available_rounded,
            ),
          ]),
        ]),
      ),
      // Ã¢â€â‚¬Ã¢â€â‚¬ Filter bar Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
      Container(
        padding: const EdgeInsets.fromLTRB(kWebPad, 8, kWebPad, 8),
        decoration: const BoxDecoration(
          color: Color(0xFFFAFBFC),
          border: Border(bottom: BorderSide(color: kCardBorder)),
        ),
        child: Row(children: [
          const Text('Status:',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                fontWeight: FontWeight.w600, color: kText)),
          const SizedBox(width: 8),
          for (final f in ['All', 'Active', 'Inactive', 'No Auth', 'No Events']) ...[
            WebFilterChip(
              label: f, selected: _statusFilter == f,
              onTap: () { _statusFilter = f; _applyFilter(); },
              count: f == 'All'       ? totalCount
                   : f == 'Active'    ? activeCount
                   : f == 'Inactive'  ? inactiveCount
                   : f == 'No Auth'   ? noAuthCount
                   :                    noEventsCount,
              selectedColor: f == 'No Auth'   ? const Color(0xFFF59E0B)
                           : f == 'No Events' ? _kAccent
                           : f == 'Inactive'  ? kMuted
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
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.close_rounded, size: 13, color: kMuted),
                  SizedBox(width: 4),
                  Text('Clear filters', style: TextStyle(fontFamily: 'Poppins',
                      fontSize: 11.5, fontWeight: FontWeight.w600, color: kMuted)),
                ]),
              ),
            ),
          ],
        ]),
      ),
      // Ã¢â€â‚¬Ã¢â€â‚¬ Body Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
        if (_filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(kWebPad),
            child: WebEmptyState(
              icon: Icons.badge_outlined,
              title: 'No organizers found',
              subtitle: hasFilter
                  ? 'No organizers match the current filters.'
                  : 'Add your first organizer to get started.',
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
                  separatorBuilder: (_, _) => const Divider(height: 1, color: kCardBorder),
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
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: kCardBorder))),
                  child: Text(
                    hasFilter
                        ? 'Showing ${_filtered.length} of $totalCount organizers'
                        : '${_filtered.length} organizers total',
                    style: const TextStyle(fontFamily: 'Poppins',
                        fontSize: 11.5, color: kMuted)),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Sortable table header for Organizers Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

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

  Widget _staticCol(String label, {int flex = 1}) => Expanded(
    flex: flex,
    child: Text(label, style: const TextStyle(fontFamily: 'Poppins',
        fontSize: 10.5, fontWeight: FontWeight.w700, color: kSubText, letterSpacing: 0.8)),
  );

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.only(left: 23, right: 20, top: 10, bottom: 10),
    decoration: const BoxDecoration(
      color: Color(0xFFF0F3F7),
      border: Border(bottom: BorderSide(color: kCardBorder)),
    ),
    child: Row(children: [
      const SizedBox(width: 52),
      _sortCol('FULL NAME',  'full_name',    flex: 3),
      _sortCol('ORG ID',     'organizer_id'),
      _sortCol('EVENTS',     'event_count'),
      _sortCol('STATUS',     'is_active'),
      _staticCol('ACCOUNT'),
      _sortCol('CREATED',    'created_at',   flex: 2),
      const SizedBox(width: 108),
    ]),
  );
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
    final o           = widget.org;
    final active      = o['is_active'] == true;
    final linked      = o['user_id'] != null;
    final orgName     = o['organization'] as String?;
    final orgId       = o['organizer_id'] as String? ?? 'â€”';
    final initials    = (o['full_name'] as String? ?? '?').trim().split(' ')
        .where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).take(2).join();
    final avatarColor = active ? kGold : kMuted;

    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _h ? kGold.withValues(alpha: 0.04) : Colors.transparent,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 3, color: active ? Colors.transparent : kMuted.withValues(alpha: 0.30)),
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
                      Text(o['full_name'] as String? ?? 'â€”',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                            fontWeight: FontWeight.w600, color: active ? kText : kMuted),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (orgName != null && orgName.isNotEmpty)
                        Text(orgName,
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 10.5,
                              color: kSubText),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (!linked)
                        const Text('No auth account',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                              color: Color(0xFFF59E0B), fontWeight: FontWeight.w600)),
                    ],
                  )),
                  // Org ID â€” gold-tinted badge
                  Expanded(child: Container(
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
                          color: kMuted.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('0', style: TextStyle(fontFamily: 'Poppins',
                            fontSize: 11, fontWeight: FontWeight.w500, color: kMuted)))),
                  // Status badge
                  Expanded(child: WebStatusBadge(
                    label: active ? 'Active' : 'Inactive',
                    color: active ? const Color(0xFF10B981) : kMuted)),
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
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: kMuted))),
                  // Actions
                  SizedBox(
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
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Organizer dialog Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

class _OrganizerDialog extends StatefulWidget {
  final Map<String, dynamic>? organizer;
  final String?               suggestedId;
  final int                   eventCount;
  const _OrganizerDialog({required this.organizer, this.suggestedId, this.eventCount = 0});
  @override State<_OrganizerDialog> createState() => _OrganizerDialogState();
}
class _OrganizerDialogState extends State<_OrganizerDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _scale, _fade;
  final _idCtrl   = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _orgCtrl  = TextEditingController();

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
    super.dispose();
  }

  void _save() {
    final id   = _idCtrl.text.trim().toUpperCase();
    final name = _nameCtrl.text.trim();
    final org  = _orgCtrl.text.trim();
    if (!_isEdit && !RegExp(r'^[A-Z]{2}\d{4}$').hasMatch(id)) {
      _snack('ID must be 2 letters + 4 digits (e.g. JJ0001)'); return;
    }
    if (name.isEmpty) { _snack('Full name is required'); return; }
    Navigator.of(context).pop(<String, dynamic>{
      'full_name':    name,
      'organization': org.isEmpty ? null : org,
      if (!_isEdit) 'organizer_id': id,
      if (!_isEdit) 'is_active': true,
    });
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: Colors.red));

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child: ScaleTransition(
      scale: _scale,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: _dialogShell(
            icon: Icons.badge_rounded, iconColor: kGold,
            title: _isEdit ? 'Edit Organizer' : 'Add Organizer',
            body: Column(children: [
              if (_isEdit) ...[
                _InfoNote(widget.eventCount > 0
                    ? 'This organizer has ${widget.eventCount} event${widget.eventCount == 1 ? '' : 's'}. Name and organization changes apply immediately.'
                    : 'This organizer has no events yet.'),
                const SizedBox(height: 12),
              ],
              if (!_isEdit) ...[
                TextField(
                  controller: _idCtrl,
                  decoration: webInputDeco('Organizer ID (e.g. JJ0001)', icon: Icons.tag_rounded),
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: kText)),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _nameCtrl,
                decoration: webInputDeco('Full Name', icon: Icons.person_outline_rounded),
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: kText)),
              const SizedBox(height: 12),
              TextField(
                controller: _orgCtrl,
                decoration: webInputDeco('Organization / Department (optional)', icon: Icons.business_outlined),
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: kText)),
              if (!_isEdit) ...[
                const SizedBox(height: 12),
                _InfoNote('Login credentials are provisioned via SQL after creating this profile record.'),
              ],
            ]),
            confirmLabel: _isEdit ? 'Save Changes' : 'Add Organizer',
            confirmColor: kGold,
            onConfirm: _save,
          ),
        ),
      ),
    ),
  );
}

// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
// Events page (read-only)
// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â

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
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = false; });
    try {
      final rows = await SupabaseService.client.from('events')
          .select('event_id, title, event_type, event_date, start_time, event_status, current_participants, max_participants, organizer_id, organizers(full_name, organization)')
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
      if (_statusFilter != 'All' && e['event_status'] != _statusFilter) return false;
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
        const order = {'ongoing': 0, 'upcoming': 1, 'completed': 2, 'cancelled': 3};
        final ao = order[a['event_status'] as String? ?? ''] ?? 4;
        final bo = order[b['event_status'] as String? ?? ''] ?? 4;
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
    final totalCount     = _all.length;
    final upcomingCount  = _all.where((e) => e['event_status'] == 'upcoming').length;
    final ongoingCount   = _all.where((e) => e['event_status'] == 'ongoing').length;
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

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    if (_error) {
      return _ErrorState(message: _errorMsg, onRetry: _load);
    }

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Ã¢â€â‚¬Ã¢â€â‚¬ Page header Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
      Container(
        padding: const EdgeInsets.fromLTRB(kWebPad, 18, kWebPad, 14),
        color: Colors.white,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('All Events',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 18,
                    fontWeight: FontWeight.w800, color: kText)),
              const SizedBox(height: 2),
              Text('$totalCount events Ã‚Â· system-wide view',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: kSubText)),
            ])),
            WebSearchField(
              controller: _searchCtrl, hint: 'Search title, organizer, or typeÃ¢â‚¬Â¦',
              onChanged: (v) { _search = v; _applyFilter(); }, width: 260),
            const SizedBox(width: 12),
            WebBtn(label: 'Refresh', icon: Icons.refresh_rounded,
                onTap: _load, outlined: true, color: _kAccent),
          ]),
          const SizedBox(height: 16),
          // Ã¢â€â‚¬Ã¢â€â‚¬ Stat tiles Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
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
            _StudentStatCard(label: 'Completed', value: '$completedCount',
                color: const Color(0xFF8B5CF6), icon: Icons.check_circle_rounded),
            const SizedBox(width: 10),
            _StudentStatCard(
              label: cancelledCount > 0 ? 'Cancelled' : 'No Cancellations',
              value: '$cancelledCount',
              color: cancelledCount > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
              icon:  cancelledCount > 0 ? Icons.cancel_rounded : Icons.check_circle_outline_rounded,
            ),
          ]),
        ]),
      ),
      // Ã¢â€â‚¬Ã¢â€â‚¬ Filter bar Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
      Container(
        padding: const EdgeInsets.fromLTRB(kWebPad, 10, kWebPad, 10),
        decoration: const BoxDecoration(
          color: Color(0xFFFAFBFC),
          border: Border(bottom: BorderSide(color: kCardBorder)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Status filter row
          Row(children: [
            const Text('Status:',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  fontWeight: FontWeight.w600, color: kText)),
            const SizedBox(width: 8),
            WebFilterChip(
              label: 'All', selected: _statusFilter == 'All',
              onTap: () { _statusFilter = 'All'; _applyFilter(); },
              count: totalCount),
            const SizedBox(width: 6),
            for (final s in ['upcoming', 'ongoing', 'completed', 'cancelled']) ...[
              WebFilterChip(
                label: webEventStatusLabel(s),
                selected: _statusFilter == s,
                onTap: () { _statusFilter = s; _applyFilter(); },
                count: _all.where((e) => e['event_status'] == s).length,
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
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.close_rounded, size: 13, color: kMuted),
                    SizedBox(width: 4),
                    Text('Clear filters', style: TextStyle(fontFamily: 'Poppins',
                        fontSize: 11.5, fontWeight: FontWeight.w600, color: kMuted)),
                  ]),
                ),
              ),
            ],
          ]),
          // Capacity filter row â€” shown only when at least one event is at capacity
          if (atCapacityCount > 0) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Text('Capacity:',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w600, color: kText)),
              const SizedBox(width: 8),
              WebFilterChip(
                label: 'All', selected: _fillFilter == 'All',
                onTap: () { _fillFilter = 'All'; _applyFilter(); },
                count: totalCount, selectedColor: kGold),
              const SizedBox(width: 6),
              WebFilterChip(
                label: 'At Capacity', selected: _fillFilter == 'At Capacity',
                onTap: () { _fillFilter = 'At Capacity'; _applyFilter(); },
                count: atCapacityCount,
                selectedColor: const Color(0xFFEF4444)),
            ]),
          ],
          // Type filter row â€” shown only when data has event types
          if (typeOpts.length > 1) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Text('Type:',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w600, color: kText)),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 6, runSpacing: 6,
                  children: typeOpts.map((t) {
                    final cap = t == 'All' || t.isEmpty ? t
                        : '${t[0].toUpperCase()}${t.substring(1)}';
                    return WebFilterChip(
                      label: cap, selected: _typeFilter == t,
                      onTap: () { _typeFilter = t; _applyFilter(); },
                      selectedColor: t == 'All' ? null : _eventTypeColor(t),
                      count: t == 'All'
                          ? totalCount
                          : _all.where((e) =>
                              (e['event_type'] as String? ?? '') == t).length,
                    );
                  }).toList(),
                ),
              ),
            ]),
          ],
        ]),
      ),
      // Ã¢â€â‚¬Ã¢â€â‚¬ Body Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
        if (_filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(kWebPad),
            child: WebEmptyState(
              icon: Icons.event_outlined,
              title: 'No events found',
              subtitle: hasFilter
                  ? 'No events match the current filters.'
                  : 'No events have been created yet.',
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
                  separatorBuilder: (_, _) => const Divider(height: 1, color: kCardBorder),
                  itemBuilder: (_, i) {
                    final e      = _filtered[i];
                    final status = e['event_status'] as String? ?? '';
                    return _EventRow(
                      event: e,
                      onCancel: (status == 'upcoming' || status == 'ongoing')
                          ? () => _cancelEvent(
                              e['event_id'] as String? ?? '',
                              e['title']    as String? ?? 'this event')
                          : null,
                    );
                  },
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: kCardBorder))),
                  child: Text(
                    hasFilter
                        ? 'Showing ${_filtered.length} of $totalCount events'
                        : '${_filtered.length} events total',
                    style: const TextStyle(fontFamily: 'Poppins',
                        fontSize: 11.5, color: kMuted)),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Event type color helper Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

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

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Sortable table header for Events Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.only(left: 23, right: 20, top: 10, bottom: 10),
    decoration: const BoxDecoration(
      color: Color(0xFFF0F3F7),
      border: Border(bottom: BorderSide(color: kCardBorder)),
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
    final status       = e['event_status'] as String? ?? '';
    final type         = e['event_type']   as String? ?? '';
    final orgMap       = e['organizers']   as Map<String, dynamic>?;
    final orgName      = orgMap?['full_name']    as String? ?? 'â€”';
    final orgSub       = orgMap?['organization'] as String?;
    final cur          = e['current_participants'] as int? ?? 0;
    final max          = e['max_participants']     as int? ?? 0;
    final pct          = max > 0 ? (cur / max).clamp(0.0, 1.0) : 0.0;
    final isFull       = max > 0 && cur >= max;
    final isAlmostFull = !isFull && pct >= 0.8;
    final isCancelled  = status == 'cancelled';
    final typeColor    = type.isEmpty ? kMuted : _eventTypeColor(type);
    final timeStr      = _fmtEventTime(e['start_time'] as String?);
    final barColor     = isCancelled  ? kMuted
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
                      Text(e['title'] as String? ?? 'â€”',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isCancelled ? kMuted : kText),
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
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 9.5,
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
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                            fontWeight: FontWeight.w500, color: kSubText),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (orgSub != null && orgSub.isNotEmpty)
                        Text(orgSub,
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 10.5,
                              color: kMuted),
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
                            color: isCancelled ? kMuted : kSubText)),
                      if (timeStr.isNotEmpty)
                        Text(timeStr, style: const TextStyle(fontFamily: 'Poppins',
                            fontSize: 10.5, color: kMuted)),
                    ],
                  )),
                  // Status badge
                  Expanded(child: WebStatusBadge(
                    label: webEventStatusLabel(status),
                    color: webEventStatusColor(status))),
                  // Fill rate: count + capacity badge + gradient bar
                  Expanded(flex: 2, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(children: [
                        Text('$cur / $max',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isCancelled ? kMuted : kText)),
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
                          color: kCardBorder,
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
                  // Cancel action â€” placeholder keeps layout stable when no action
                  SizedBox(
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
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
// Registrations page (read-only)
// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â

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
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = false; });
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

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kAccent));
    }
    if (_error) {
      return _ErrorState(message: _errorMsg, onRetry: _load);
    }

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Ã¢â€â‚¬Ã¢â€â‚¬ Page header Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
      Container(
        padding: const EdgeInsets.fromLTRB(kWebPad, 18, kWebPad, 14),
        color: Colors.white,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('All Registrations',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 18,
                    fontWeight: FontWeight.w800, color: kText)),
              const SizedBox(height: 2),
              Text('$totalCount registrations Ã‚Â· $checkInRate% check-in rate Ã‚Â· system-wide view',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: kSubText)),
            ])),
            WebSearchField(
              controller: _searchCtrl, hint: 'Search student, LRN, or eventÃ¢â‚¬Â¦',
              onChanged: (v) { _search = v; _applyFilter(); }, width: 260),
            const SizedBox(width: 12),
            WebBtn(label: 'Refresh', icon: Icons.refresh_rounded,
                onTap: _load, outlined: true, color: _kAccent),
          ]),
          const SizedBox(height: 16),
          // Ã¢â€â‚¬Ã¢â€â‚¬ Stat tiles Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
          Row(children: [
            _StudentStatCard(label: 'Total', value: '$totalCount',
                color: _kAccent, icon: Icons.how_to_reg_rounded),
            const SizedBox(width: 10),
            _StudentStatCard(
              label: pendingCount > 0 ? 'Pending' : 'Queue Clear',
              value: '$pendingCount',
              color: pendingCount > 0 ? const Color(0xFF3B82F6) : const Color(0xFF10B981),
              icon:  pendingCount > 0 ? Icons.hourglass_top_rounded : Icons.check_circle_outline_rounded,
            ),
            const SizedBox(width: 10),
            _StudentStatCard(label: 'Checked In', value: '$checkedInCount',
                color: const Color(0xFF10B981), icon: Icons.verified_rounded),
            const SizedBox(width: 10),
            _StudentStatCard(
              label: needsReview > 0 ? 'Needs Review' : 'All Reviewed',
              value: '$needsReview',
              color: needsReview > 0 ? const Color(0xFF8B5CF6) : const Color(0xFF10B981),
              icon:  needsReview > 0 ? Icons.photo_camera_outlined : Icons.check_circle_outline_rounded,
            ),
            const SizedBox(width: 10),
            _StudentStatCard(
              label: rejectedCount > 0 ? 'Rejected' : 'No Rejections',
              value: '$rejectedCount',
              color: rejectedCount > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
              icon:  rejectedCount > 0 ? Icons.cancel_outlined : Icons.check_circle_outline_rounded,
            ),
          ]),
          // â”€â”€ Check-in pipeline bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
                    child: Container(color: kCardBorder),
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
          // â”€â”€ Needs-review urgent banner â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
                      const Text('Tap to filter and review submitted selfies',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5, color: kSubText)),
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
      // Ã¢â€â‚¬Ã¢â€â‚¬ Filter bar Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
      Container(
        padding: const EdgeInsets.fromLTRB(kWebPad, 8, kWebPad, 8),
        decoration: const BoxDecoration(
          color: Color(0xFFFAFBFC),
          border: Border(bottom: BorderSide(color: kCardBorder)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Status filter row
          Row(children: [
            const Text('Status:',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  fontWeight: FontWeight.w600, color: kText)),
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
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.close_rounded, size: 13, color: kMuted),
                    SizedBox(width: 4),
                    Text('Clear filters', style: TextStyle(fontFamily: 'Poppins',
                        fontSize: 11.5, fontWeight: FontWeight.w600, color: kMuted)),
                  ]),
                ),
              ),
            ],
          ]),
          // Event filter row â€” shown only when there are multiple distinct events
          if (eventOpts.length > 1) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Text('Event:',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w600, color: kText)),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final t in eventOpts) ...[
                      WebFilterChip(
                        label: t == 'All' ? 'All Events' : t,
                        selected: _eventFilter == t,
                        onTap: () { _eventFilter = t; _applyFilter(); },
                        count: t == 'All'
                            ? totalCount
                            : _all.where((r) =>
                                (r['event_title'] as String? ?? '') == t).length,
                        selectedColor: t == 'All' ? kGold : _kAccent,
                      ),
                      const SizedBox(width: 6),
                    ],
                  ]),
                ),
              ),
            ]),
          ],
        ]),
      ),
      // Ã¢â€â‚¬Ã¢â€â‚¬ Body Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
        if (_filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(kWebPad),
            child: WebEmptyState(
              icon: Icons.how_to_reg_outlined,
              title: 'No registrations found',
              subtitle: hasFilter
                  ? 'No registrations match the current filters.'
                  : 'No registrations have been recorded yet.',
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
                  separatorBuilder: (_, _) => const Divider(height: 1, color: kCardBorder),
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
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: kCardBorder))),
                  child: Text(
                    hasFilter
                        ? 'Showing ${_filtered.length} of $totalCount registrations'
                        : '${_filtered.length} of up to 300 most recent registrations',
                    style: const TextStyle(fontFamily: 'Poppins',
                        fontSize: 11.5, color: kMuted)),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

// Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Sortable table header for Registrations Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

class _RegLegend extends StatelessWidget {
  final Color  color;
  final String label;
  const _RegLegend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 7, height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 10, color: kSubText)),
  ]);
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.only(left: 23, right: 20, top: 10, bottom: 10),
    decoration: const BoxDecoration(
      color: Color(0xFFF0F3F7),
      border: Border(bottom: BorderSide(color: kCardBorder)),
    ),
    child: Row(children: [
      const SizedBox(width: 52), // 3(rail strip) + 20(padding) + 40(avatar) + 12(gap) - 23(left inset) = 52
      _sortCol('STUDENT',    'student_name',  flex: 4),
      _sortCol('EVENT',      'event_title',   flex: 3),
      _sortCol('STATUS',     'status',        flex: 2),
      _sortCol('REGISTERED', 'registered_at', flex: 2),
      _sortCol('CHECKED IN', 'checked_in_at', flex: 2),
      SizedBox(width: 76, child: Text('ACTION',
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
            fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.5),
        textAlign: TextAlign.center)),
    ]),
  );
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
    final lrn         = r['student_school_id'] as String? ?? 'â€”';
    final initials    = name.trim().split(' ')
        .where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).take(2).join();

    final avatarColor = switch (status) {
      'checked_in'      => const Color(0xFF10B981),
      'photo_submitted' => const Color(0xFF8B5CF6),
      'rejected'        => const Color(0xFFEF4444),
      'pending'         => const Color(0xFF3B82F6),
      'qr_scanned'      => const Color(0xFFF59E0B),
      'photo_required'  => const Color(0xFFF59E0B),
      _                 => kMuted,
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
                            color: isRejected ? kMuted : kText),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: kMuted.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('LRN',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 9,
                                fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.5)),
                        ),
                        const SizedBox(width: 5),
                        Flexible(child: Text(lrn,
                          style: const TextStyle(fontFamily: 'Poppins', fontSize: 10.5, color: kSubText),
                          overflow: TextOverflow.ellipsis)),
                      ]),
                    ],
                  )),
                  // Event title
                  Expanded(flex: 3, child: Row(children: [
                    Icon(Icons.calendar_today_rounded, size: 11,
                        color: isRejected ? kMuted.withValues(alpha: 0.4) : kMuted.withValues(alpha: 0.55)),
                    const SizedBox(width: 5),
                    Flexible(child: Text(r['event_title'] as String? ?? 'â€”',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                          color: isRejected ? kMuted : kSubText),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ])),
                  // Status badge
                  Expanded(flex: 2, child: WebStatusBadge(
                    label: webStatusLabel(status), color: webStatusColor(status))),
                  // Registered date
                  Expanded(flex: 2, child: Text(webFmtDate(r['registered_at'] as String?),
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: kMuted))),
                  // Check-in date â€” green with time if checked in
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
                            style: const TextStyle(fontFamily: 'Poppins', fontSize: 10, color: kMuted)),
                        ],
                      )
                    : const Text('â€”', style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 11.5, color: kMuted))),
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

// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
// Shared helper widgets
// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â

// Row action button
class _ActBtn extends StatefulWidget {
  final IconData icon; final Color color; final String tip; final VoidCallback onTap;
  const _ActBtn({required this.icon, required this.color, required this.tip, required this.onTap});
  @override State<_ActBtn> createState() => _ActBtnState();
}
class _ActBtnState extends State<_ActBtn> {
  bool _h = false;
  @override
  Widget build(BuildContext context) => Tooltip(
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
              color: _h ? widget.color : kMuted.withValues(alpha: 0.70)),
        ),
      ),
    ),
  );
}

// Error state
class _ErrorState extends StatelessWidget {
  final String message; final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
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
        const Text('Permission Required',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 15,
              fontWeight: FontWeight.w700, color: kText)),
        const SizedBox(height: 8),
        const Text(
          'Run the admin RLS policies SQL in Supabase to grant\nthe admin account read access to this table.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
              color: kSubText, height: 1.6),
          textAlign: TextAlign.center),
        const SizedBox(height: 20),
        WebBtn(label: 'Retry', icon: Icons.refresh_rounded, onTap: onRetry),
      ]),
    ),
  );
}

// Info note box used inside dialogs
class _InfoNote extends StatelessWidget {
  final String text;
  const _InfoNote(this.text);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF0F9FF),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFF0EA5E9).withValues(alpha: 0.25)),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.info_outline_rounded, size: 15, color: Color(0xFF0EA5E9)),
      const SizedBox(width: 8),
      Expanded(child: Text(text,
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
            color: Color(0xFF0369A1), height: 1.5))),
    ]),
  );
}

// Shared dialog chrome (header + form body + buttons)
Widget _dialogShell({
  required IconData  icon,
  required Color     iconColor,
  required String    title,
  required Widget    body,
  required String    confirmLabel,
  required Color     confirmColor,
  required VoidCallback onConfirm,
}) {
  return Container(
    decoration: BoxDecoration(
      color: Colors.white,
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
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: kCardBorder))),
        child: _DialogHeader(icon: icon, iconColor: iconColor, title: title),
      ),
      // Body
      Padding(padding: const EdgeInsets.all(24), child: body),
      // Buttons
      const Divider(height: 1, color: kCardBorder),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        child: Row(children: [
          Expanded(
            child: Builder(builder: (ctx) => OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: kCardBorder),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: const Text('Cancel',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: kSubText)),
            )),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: onConfirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: confirmColor, foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: Text(confirmLabel,
                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    ]),
  );
}

// Dialog header row
class _DialogHeader extends StatelessWidget {
  final IconData icon; final Color iconColor; final String title;
  const _DialogHeader({required this.icon, required this.iconColor, required this.title});

  @override
  Widget build(BuildContext context) => Row(children: [
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
      style: const TextStyle(fontFamily: 'Poppins', fontSize: 16,
          fontWeight: FontWeight.w800, color: kText))),
    Builder(builder: (ctx) => GestureDetector(
      onTap: () => Navigator.of(ctx).pop(),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
            color: Colors.transparent, borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.close_rounded, size: 18, color: kMuted),
        ),
      ),
    )),
  ]);
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// Photo review dialog â€” shown when admin clicks "Review Photo" on a
// photo_submitted registration. Generates a signed URL for the private selfie
// and presents approve / reject choices in one step (no double-confirm).
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

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
    final reg         = widget.reg;
    final studentName = reg['student_name']      as String? ?? 'â€”';
    final lrn         = reg['student_school_id'] as String? ?? 'â€”';
    final eventTitle  = reg['event_title']        as String? ?? 'â€”';
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
                color: Colors.white,
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
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: kCardBorder))),
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
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 15,
                            fontWeight: FontWeight.w700, color: kText)),
                      const SizedBox(height: 3),
                      Row(children: [
                        const Text('LRN ',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                              fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.5)),
                        Text(lrn,
                          style: const TextStyle(fontFamily: 'Poppins',
                              fontSize: 11.5, color: kSubText)),
                      ]),
                      const SizedBox(height: 4),
                      Text(eventTitle,
                        style: const TextStyle(fontFamily: 'Poppins',
                            fontSize: 12, color: kSubText),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('Registered $regDate',
                        style: const TextStyle(fontFamily: 'Poppins',
                            fontSize: 11, color: kMuted)),
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
                      color: const Color(0xFFF8F9FC),
                      child: _urlLoading
                          ? const SizedBox(
                              height: 200,
                              child: Center(
                                child: CircularProgressIndicator(
                                    color: Color(0xFF8B5CF6), strokeWidth: 2.5)))
                          : _urlError || _imageUrl == null
                              ? const SizedBox(
                                  height: 160,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.broken_image_rounded,
                                          size: 44, color: kMuted),
                                      SizedBox(height: 10),
                                      Text('Photo unavailable',
                                        style: TextStyle(fontFamily: 'Poppins',
                                            fontSize: 13, color: kMuted)),
                                    ],
                                  ))
                              : Image.network(
                                  _imageUrl!,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => const SizedBox(
                                    height: 160,
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.broken_image_rounded,
                                            size: 44, color: kMuted),
                                        SizedBox(height: 10),
                                        Text('Failed to load image',
                                          style: TextStyle(fontFamily: 'Poppins',
                                              fontSize: 13, color: kMuted)),
                                      ],
                                    )),
                                ),
                    ),
                  ),
                ),
                // Action buttons
                const Divider(height: 1, color: kCardBorder),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                  child: Row(children: [
                    // Dismiss
                    Builder(builder: (ctx) => OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: kCardBorder),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                      ),
                      child: const Text('Cancel',
                        style: TextStyle(fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600, color: kSubText)),
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

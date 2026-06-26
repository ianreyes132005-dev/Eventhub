import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/app_colors.dart';
import '../../../core/services/supabase_service.dart';
import 'web_shared.dart';
import 'dashboard_page.dart';
import 'events_page.dart';
import 'registrations_page.dart';
import 'announcements_page.dart';
import 'settings_page.dart';
import 'ai_chatbot.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shell
// ─────────────────────────────────────────────────────────────────────────────

class OrganizerWebDashboard extends StatefulWidget {
  const OrganizerWebDashboard({super.key});

  @override
  State<OrganizerWebDashboard> createState() => _OrganizerWebDashboardState();
}

class _OrganizerWebDashboardState extends State<OrganizerWebDashboard>
    with SingleTickerProviderStateMixin {
  OrganizerPage _page         = OrganizerPage.dashboard;
  bool          _collapsed    = false;
  AppTheme      _theme        = const AppTheme();
  // GlobalKey preserves WebSettingsPage state (active tab) when _theme.variant
  // changes, which restructures the widget tree and would otherwise reset state.
  final         _settingsKey  = GlobalKey();
  String?       _orgId;
  String?       _name;
  String?       _email;
  String?       _organization;
  bool          _loading      = true;
  bool          _profileError = false;

  // ── Shell entrance animations (run once when profile finishes loading) ─────
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
    _sidebarSlide = Tween<Offset>(
            begin: const Offset(-0.04, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryCt,
            curve: const Interval(0.00, 0.65, curve: Curves.easeOutCubic)));
    _topbarFade   = CurvedAnimation(parent: _entryCt,
        curve: const Interval(0.00, 0.60, curve: Curves.easeOut));
    _topbarSlide  = Tween<Offset>(
            begin: const Offset(0, -0.65), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryCt,
            curve: const Interval(0.00, 0.60, curve: Curves.easeOutCubic)));
    _contentFade  = CurvedAnimation(parent: _entryCt,
        curve: const Interval(0.12, 0.78, curve: Curves.easeOut));
    _loadTheme();
    _loadProfile();
  }

  @override
  void dispose() {
    _entryCt.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) { _goLogin(); return; }
      _email = user.email;
      final row = await SupabaseService.client
          .from('organizers')
          .select('organizer_id, full_name, organization')
          .eq('user_id', user.id)
          .maybeSingle();
      if (!mounted) return;
      if (row == null) { _goLogin(); return; }
      setState(() {
        _orgId        = row['organizer_id'] as String?;
        _name         = row['full_name']    as String?;
        _organization = row['organization'] as String?;
        _loading      = false;
      });
      _entryCt.forward();
    } catch (_) {
      if (mounted) setState(() { _loading = false; _profileError = true; });
    }
  }

  // ── Theme persistence ─────────────────────────────────────────────────────

  Future<void> _loadTheme() async {
    final prefs      = await SharedPreferences.getInstance();
    final primary    = prefs.getInt('org_theme_primary_v2');
    final secondary  = prefs.getInt('org_theme_secondary_v2');
    final variantIdx = prefs.getInt('org_theme_variant_v2');
    if (primary == null && secondary == null && variantIdx == null) return;
    if (!mounted) return;
    setState(() {
      _theme = _theme.copyWith(
        primaryColor:   primary    != null ? Color(primary)   : null,
        secondaryColor: secondary  != null ? Color(secondary)  : null,
        variant:        variantIdx != null
            ? SidebarVariant.values[variantIdx.clamp(0, SidebarVariant.values.length - 1)]
            : null,
      );
    });
  }

  Future<void> _saveTheme(AppTheme t) async {
    final prefs = await SharedPreferences.getInstance();
    // ignore: deprecated_member_use
    await prefs.setInt('org_theme_primary_v2',   t.primaryColor.value);
    // ignore: deprecated_member_use
    await prefs.setInt('org_theme_secondary_v2', t.secondaryColor.value);
    await prefs.setInt('org_theme_variant_v2',   t.variant.index);
  }

  void _goLogin() => Navigator.of(context).pushReplacementNamed('/');

  Future<void> _signOut() async {
    final ok = await WebAlert.confirm(
      context:      context,
      title:        'Sign Out?',
      message:      'You will be returned to the login screen.',
      confirmLabel: 'Sign Out',
    );
    if (ok != true) return;
    await SupabaseService.signOut();
    if (mounted) _goLogin();
  }

  void _onThemeChanged(AppTheme t) {
    setState(() => _theme = t);
    _saveTheme(t); // fire-and-forget; persists across sessions
  }

  // Hamburger: in minimal mode, expand to inset; otherwise toggle collapse
  void _onMenuTap() {
    if (_theme.variant == SidebarVariant.minimal) {
      setState(() => _theme = _theme.copyWith(variant: SidebarVariant.inset));
    } else {
      setState(() => _collapsed = !_collapsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: kWebBg,
        body: Center(child: CircularProgressIndicator(color: kGold)),
      );
    }
    if (_profileError) {
      return Scaffold(
        backgroundColor: kWebBg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFFCA5A5), width: 1.5),
                ),
                child: const Icon(
                  Icons.cloud_off_rounded,
                  color: Color(0xFFEF4444),
                  size: 34,
                ),
              ),
              const SizedBox(height: 20),
              const Text('Could not load your profile',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 17,
                  fontWeight: FontWeight.w800, color: kText,
                )),
              const SizedBox(height: 8),
              const Text('Check your connection and try again.',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 13, color: kSubText,
                )),
              const SizedBox(height: 28),
              WebBtn(
                label: 'Retry',
                icon:  Icons.refresh_rounded,
                onTap: () {
                  setState(() { _profileError = false; _loading = true; });
                  _loadProfile();
                },
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: kWebBg,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_theme.variant) {
      case SidebarVariant.inset:
        return Stack(children: [
          Row(children: [
            // Sidebar: fade + subtle left slide
            FadeTransition(
              opacity: _sidebarFade,
              child: SlideTransition(
                position: _sidebarSlide,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  width: _collapsed ? kWebSideWc : kWebSideW,
                  child: _Sidebar(
                    theme:        _theme,
                    collapsed:    _collapsed,
                    minimal:      false,
                    currentPage:  _page,
                    name:         _name,
                    organization: _organization,
                    onPageChanged: (p) => setState(() => _page = p),
                    onToggle:  () => setState(() => _collapsed = !_collapsed),
                    onSignOut: _signOut,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Column(children: [
                // Top bar: clips overflow, slides down from above
                ClipRect(
                  child: SlideTransition(
                    position: _topbarSlide,
                    child: FadeTransition(
                      opacity: _topbarFade,
                      child: _TopBar(
                        theme:       _theme,
                        name:        _name,
                        email:       _email,
                        orgId:       _orgId,
                        leftPad:     0,
                        onMenuTap:   _onMenuTap,
                        onSignOut:   _signOut,
                        currentPage: _page,
                      ),
                    ),
                  ),
                ),
                // Content: fade in with slight delay
                Expanded(
                  child: FadeTransition(
                    opacity: _contentFade,
                    child: _buildPage(),
                  ),
                ),
              ]),
            ),
          ]),
          WebAiChatbot(orgId: _orgId),
        ]);

      case SidebarVariant.floating:
        final sideW = _collapsed ? kWebSideWc : kWebSideW;
        final pad   = sideW + 24.0;
        return Stack(children: [
          Column(children: [
            ClipRect(
              child: SlideTransition(
                position: _topbarSlide,
                child: FadeTransition(
                  opacity: _topbarFade,
                  child: _TopBar(
                    theme:       _theme,
                    name:        _name,
                    email:       _email,
                    orgId:       _orgId,
                    leftPad:     pad,
                    onMenuTap:   _onMenuTap,
                    onSignOut:   _signOut,
                    currentPage: _page,
                  ),
                ),
              ),
            ),
            Expanded(
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 220),
                curve:    Curves.easeInOut,
                padding:  EdgeInsets.only(left: pad),
                child:    FadeTransition(
                  opacity: _contentFade,
                  child:   _buildPage(),
                ),
              ),
            ),
          ]),
          // Floating sidebar panel: fade + left slide
          Positioned(
            left: 10, top: 10, bottom: 10,
            child: FadeTransition(
              opacity: _sidebarFade,
              child: SlideTransition(
                position: _sidebarSlide,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  width: sideW,
                  child: Material(
                    elevation: 14,
                    shadowColor: Colors.black.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: _Sidebar(
                        theme:        _theme,
                        collapsed:    _collapsed,
                        minimal:      false,
                        currentPage:  _page,
                        name:         _name,
                        organization: _organization,
                        onPageChanged: (p) => setState(() => _page = p),
                        onToggle:  () => setState(() => _collapsed = !_collapsed),
                        onSignOut: _signOut,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          WebAiChatbot(orgId: _orgId),
        ]);

      case SidebarVariant.minimal:
        return Stack(children: [
          Row(children: [
            FadeTransition(
              opacity: _sidebarFade,
              child: SizedBox(
                width: 56,
                child: _Sidebar(
                  theme:        _theme,
                  collapsed:    true,
                  minimal:      true,
                  currentPage:  _page,
                  name:         _name,
                  organization: _organization,
                  onPageChanged: (p) => setState(() => _page = p),
                  onToggle:  _onMenuTap,
                  onSignOut: _signOut,
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
                      child: _TopBar(
                        theme:       _theme,
                        name:        _name,
                        email:       _email,
                        orgId:       _orgId,
                        leftPad:     0,
                        onMenuTap:   _onMenuTap,
                        onSignOut:   _signOut,
                        currentPage: _page,
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
          WebAiChatbot(orgId: _orgId),
        ]);
    }
  }

  Widget _buildPage() {
    return switch (_page) {
      OrganizerPage.dashboard     => WebDashboardPage(orgId: _orgId, name: _name),
      OrganizerPage.events        => WebEventsPage(orgId: _orgId),
      OrganizerPage.registrations => WebRegistrationsPage(orgId: _orgId),
      OrganizerPage.announcements => const WebAnnouncementsPage(),
      OrganizerPage.settings      => WebSettingsPage(
          key:          _settingsKey,
          orgId:        _orgId,
          name:         _name,
          email:        _email,
          organization: _organization,
          theme:        _theme,
          onThemeChanged:   _onThemeChanged,
          onProfileUpdated: (name, org) => setState(() {
            _name         = name;
            _organization = org;
          }),
        ),
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Nav items list
// ─────────────────────────────────────────────────────────────────────────────

const _kNavItems = [
  (OrganizerPage.dashboard,     Icons.dashboard_rounded,       'Dashboard'),
  (OrganizerPage.events,        Icons.event_rounded,           'Events'),
  (OrganizerPage.registrations, Icons.how_to_reg_rounded,      'Registrations'),
  (OrganizerPage.announcements, Icons.campaign_rounded,        'Announcements'),
  (OrganizerPage.settings,      Icons.settings_rounded,        'Settings'),
];

// ─────────────────────────────────────────────────────────────────────────────
// Sidebar
// ─────────────────────────────────────────────────────────────────────────────

class _Sidebar extends StatefulWidget {
  final AppTheme      theme;
  final bool          collapsed;
  final bool          minimal;
  final OrganizerPage currentPage;
  final String?       name;
  final String?       organization;
  final ValueChanged<OrganizerPage> onPageChanged;
  final VoidCallback  onToggle;
  final VoidCallback  onSignOut;

  const _Sidebar({
    required this.theme,
    required this.collapsed,
    required this.minimal,
    required this.currentPage,
    required this.name,
    required this.organization,
    required this.onPageChanged,
    required this.onToggle,
    required this.onSignOut,
  });

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sc;

  bool get _isCollapsed => widget.collapsed || widget.minimal;

  @override
  void initState() {
    super.initState();
    // 900 ms covers: header (0 ms) → nav label (60 ms) →
    // 5 nav items (120–360 ms) → user section (420 ms end ≈ 770 ms).
    _sc = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _sc.forward();
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

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
          child: Transform.translate(
            offset: Offset(0, 10.0 * (1 - ts)),
            child: c,
          ),
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: widget.theme.sideGradient,
        border: widget.theme.variant == SidebarVariant.floating
          ? null
          : Border(right: BorderSide(color: widget.theme.sideBorder, width: 1)),
      ),
      child: Column(
        children: [
          _cascade(_buildHeader(), 0),
          SizedBox(height: widget.minimal ? 8 : 4),
          if (!widget.minimal) _cascade(_buildNavSection(), 1),
          Expanded(child: _buildNavItems()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Divider(
              color: widget.theme.sideBorder.withValues(alpha: 0.35), height: 1),
          ),
          _cascade(_buildUserSection(), _isCollapsed ? 6 : 7),
        ],
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final borderDeco = BoxDecoration(
      border: Border(
        bottom: BorderSide(
          color: widget.theme.sideBorder.withValues(alpha: 0.40), width: 1),
      ),
    );

    // ── Minimal mode: centered logo only ─────────────────────────────────
    if (widget.minimal) {
      return Container(
        height: kWebTopH,
        decoration: borderDeco,
        alignment: Alignment.center,
        child: _logoCircle(34),
      );
    }

    // ── Collapsed: centered logo, no arrow ───────────────────────────────
    if (widget.collapsed) {
      return Container(
        height: kWebTopH,
        decoration: borderDeco,
        alignment: Alignment.center,
        child: _logoCircle(34),
      );
    }

    // ── Expanded: full brand lockup, no collapse arrow ───────────────────
    return Container(
      height: kWebTopH,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: borderDeco,
      child: Row(
        children: [
          _logoCircle(40),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('J-Jireh',
                  style: TextStyle(
                    fontFamily: 'Playball',
                    fontSize: 21,
                    color: widget.theme.logoText,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    height: 1.1,
                  )),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 16, height: 1.5,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: widget.theme.primaryColor.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                    Text('EVENTHUB',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 9.5,
                        color: widget.theme.primaryColor.withValues(alpha: 0.70),
                        letterSpacing: 2.0,
                        fontWeight: FontWeight.w700,
                      )),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Logo circle (shared, resizable) ──────────────────────────────────────

  Widget _logoCircle(double size) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: widget.theme.primaryColor.withValues(alpha: 0.45),
        width: 2.0),
      boxShadow: [
        BoxShadow(
          color: widget.theme.primaryColor.withValues(alpha: 0.25),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: Image.asset(
        'assets/logo.jpg',
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          decoration: BoxDecoration(
            gradient: widget.theme.avatarGradient,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.celebration_rounded,
            color: Colors.white, size: size * 0.44),
        ),
      ),
    ),
  );

  // ── Section label ────────────────────────────────────────────────────────────

  Widget _buildNavSection() {
    if (_isCollapsed) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 2),
      child: Row(
        children: [
          Container(
            width: 5, height: 5,
            decoration: BoxDecoration(
              color: widget.theme.primaryColor.withValues(alpha: 0.50),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text('NAVIGATION',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: widget.theme.navLabel,
              letterSpacing: 1.8,
            )),
        ],
      ),
    );
  }

  // ── Nav items — each item cascades in with a 60 ms sequential delay ──────────

  Widget _buildNavItems() {
    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: widget.minimal ? 6 : 8, vertical: 4),
      children: _kNavItems.asMap().entries.map((entry) {
        final i               = entry.key;
        final (page, icon, label) = entry.value;
        // Collapsed/minimal has no nav-label row, so items start at idx 1;
        // expanded sidebar has nav-label at idx 1, so items start at idx 2.
        final cIdx = _isCollapsed ? i + 1 : i + 2;
        return _cascade(
          _NavItem(
            icon:      icon,
            label:     label,
            isActive:  widget.currentPage == page,
            collapsed: _isCollapsed,
            theme:     widget.theme,
            onTap:     () => widget.onPageChanged(page),
          ),
          cIdx,
        );
      }).toList(),
    );
  }

  // ── User section ─────────────────────────────────────────────────────────────

  Widget _buildUserSection() {
    final initials = (widget.name ?? '?').trim().split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase())
        .take(2)
        .join();

    if (_isCollapsed) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          widget.minimal ? 9 : 10, 8, widget.minimal ? 9 : 10, 12),
        child: Column(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              gradient: widget.theme.avatarGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: widget.theme.primaryColor.withValues(alpha: 0.26),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(initials,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                )),
            ),
          ),
          const SizedBox(height: 6),
          _SignOutIconBtn(
            onTap:      widget.onSignOut,
            sideBorder: widget.theme.sideBorder,
          ),
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
          border: Border.all(
            color: widget.theme.sideBorder.withValues(alpha: 0.50)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Gold left accent bar
                Container(
                  width: 3,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        widget.theme.primaryColor,
                        widget.theme.primaryColor.withValues(alpha: 0.42),
                      ],
                    ),
                  ),
                ),
                // Card content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
                    child: Row(children: [
                      // Avatar
                      Container(
                        width: 34, height: 34,
                        decoration: BoxDecoration(
                          gradient: widget.theme.avatarGradient,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: widget.theme.primaryColor.withValues(alpha: 0.28),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(initials,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            )),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(widget.name ?? 'Organizer',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: widget.theme.navText,
                              ),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 1),
                            Text(widget.organization ?? 'EventHub',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 9.5,
                                color: widget.theme.navIcon,
                              ),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      _InlineSignOutBtn(onTap: widget.onSignOut),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Nav item
// ─────────────────────────────────────────────────────────────────────────────

class _NavItem extends StatefulWidget {
  final IconData     icon;
  final String       label;
  final bool         isActive;
  final bool         collapsed;
  final AppTheme     theme;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.collapsed,
    required this.theme,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isActive;
    final t      = widget.theme;

    final Color itemBg     = active
        ? t.primaryColor.withValues(alpha: 0.13)
        : _hovered
            ? Colors.white.withValues(alpha: 0.46)
            : Colors.transparent;
    final Color itemBorder = active
        ? t.primaryColor.withValues(alpha: 0.24)
        : _hovered
            ? t.sideBorder.withValues(alpha: 0.26)
            : Colors.transparent;
    final Color iconColor  = active
        ? t.primaryColor
        : _hovered ? t.navText : t.navIcon;
    final Color labelColor = active
        ? kText
        : _hovered ? t.navText : t.navIcon;

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit:  (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Tooltip(
            message:      widget.collapsed ? widget.label : '',
            preferBelow:  false,
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
                          color: active
                              ? t.primaryColor.withValues(alpha: 0.16)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Center(
                          child: Icon(widget.icon, size: 19, color: iconColor),
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 170),
                            width: 30, height: 30,
                            decoration: BoxDecoration(
                              color: active
                                  ? t.primaryColor.withValues(alpha: 0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Icon(widget.icon, size: 18, color: iconColor),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 150),
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 13,
                                fontWeight: active
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: labelColor,
                              ),
                              child: Text(widget.label),
                            ),
                          ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width:  active ? 6.0 : 0.0,
                            height: active ? 6.0 : 0.0,
                            decoration: BoxDecoration(
                              color: t.primaryColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sign-out buttons
// ─────────────────────────────────────────────────────────────────────────────

class _SignOutIconBtn extends StatefulWidget {
  final VoidCallback onTap;
  final Color        sideBorder;
  const _SignOutIconBtn({required this.onTap, required this.sideBorder});

  @override
  State<_SignOutIconBtn> createState() => _SignOutIconBtnState();
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
        width: 38,
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: _h
            ? const Color(0xFFFEE2E2)
            : const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _h
              ? const Color(0xFFFCA5A5)
              : const Color(0xFFFECACA),
            width: 0.8,
          ),
        ),
        child: const Icon(Icons.logout_rounded, size: 14, color: Color(0xFFEF4444)),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Inline sign-out button (used in expanded user card)
// ─────────────────────────────────────────────────────────────────────────────

class _InlineSignOutBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _InlineSignOutBtn({required this.onTap});

  @override
  State<_InlineSignOutBtn> createState() => _InlineSignOutBtnState();
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
      child: Tooltip(
        message: 'Sign out',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 30, height: 30,
          decoration: BoxDecoration(
            color: _h
              ? const Color(0xFFFEE2E2)
              : const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _h
                ? const Color(0xFFFCA5A5)
                : const Color(0xFFFECACA),
              width: 0.8,
            ),
          ),
          child: const Icon(Icons.logout_rounded,
            size: 14, color: Color(0xFFEF4444)),
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Top bar
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatefulWidget {
  final AppTheme     theme;
  final String?      name;
  final String?      email;
  final String?      orgId;
  final double       leftPad;
  final VoidCallback onMenuTap;
  final VoidCallback onSignOut;
  final OrganizerPage currentPage;

  const _TopBar({
    required this.theme,
    required this.name,
    required this.email,
    this.orgId,
    required this.leftPad,
    required this.onMenuTap,
    required this.onSignOut,
    required this.currentPage,
  });

  @override
  State<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<_TopBar> {
  @override
  Widget build(BuildContext context) {
    final initials = (widget.name ?? '?').trim().split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase())
        .take(2)
        .join();

    return Container(
      height: kWebTopH,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: kCardBorder)),
        boxShadow: [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: kWebPad),
      child: Row(
        children: [
          // Animated spacer for floating sidebar
          if (widget.leftPad > 0)
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve:    Curves.easeInOut,
              width:    widget.leftPad,
            ),

          // Hamburger
          _MenuBtn(onTap: widget.onMenuTap),
          const SizedBox(width: 16),

          // Page context indicator
          _PageContext(page: widget.currentPage, theme: widget.theme),

          const Spacer(),

          // Notification bell
          _NotificationBell(orgId: widget.orgId),
          const SizedBox(width: 4),
          Container(height: 28, width: 1, color: kCardBorder),
          const SizedBox(width: 16),

          // User info + sign-out
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(widget.name ?? 'Organizer',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: kText,
                    )),
                  if (widget.email != null)
                    Text(widget.email!,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10.5,
                        color: kMuted,
                      )),
                ],
              ),
              const SizedBox(width: 10),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: widget.theme.avatarGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: widget.theme.primaryColor.withValues(alpha: 0.30),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(initials,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    )),
                ),
              ),
              const SizedBox(width: 16),
              Container(height: 28, width: 1, color: kCardBorder),
              const SizedBox(width: 16),
              _TopBarSignOutBtn(onTap: widget.onSignOut),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page context indicator (replaces dead search bar)
// ─────────────────────────────────────────────────────────────────────────────

class _PageContext extends StatelessWidget {
  final OrganizerPage page;
  final AppTheme      theme;
  const _PageContext({required this.page, required this.theme});

  static const _labels = <OrganizerPage, String>{
    OrganizerPage.dashboard:     'Dashboard',
    OrganizerPage.events:        'Events',
    OrganizerPage.registrations: 'Registrations',
    OrganizerPage.announcements: 'Announcements',
    OrganizerPage.settings:      'Settings',
  };

  @override
  Widget build(BuildContext context) {
    final label = _labels[page] ?? '';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Organizer',
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 13,
            fontWeight: FontWeight.w500, color: kMuted)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Icon(Icons.chevron_right_rounded, size: 16, color: kMuted),
        ),
        Text(label,
          style: const TextStyle(
            fontFamily: 'Poppins', fontSize: 13,
            fontWeight: FontWeight.w700, color: kText)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hamburger button (top bar)
// ─────────────────────────────────────────────────────────────────────────────

class _MenuBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _MenuBtn({required this.onTap});

  @override
  State<_MenuBtn> createState() => _MenuBtnState();
}

class _MenuBtnState extends State<_MenuBtn> {
  bool _h = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _h = true),
    onExit:  (_) => setState(() => _h = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: _h ? const Color(0xFFF1F5F9) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _h ? kCardBorder : Colors.transparent),
        ),
        child: const Icon(Icons.menu_rounded, size: 18, color: kSubText),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sign-out button (top bar)
// ─────────────────────────────────────────────────────────────────────────────

class _TopBarSignOutBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _TopBarSignOutBtn({required this.onTap});

  @override
  State<_TopBarSignOutBtn> createState() => _TopBarSignOutBtnState();
}

class _TopBarSignOutBtnState extends State<_TopBarSignOutBtn> {
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _h ? const Color(0xFFFEF2F2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _h ? const Color(0xFFFCA5A5) : kCardBorder),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.logout_rounded, size: 14, color: Color(0xFFEF4444)),
            SizedBox(width: 6),
            Text('Sign out',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFFEF4444),
              )),
          ],
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Notification data model
// ─────────────────────────────────────────────────────────────────────────────

class _AppNotif {
  final String   title;
  final String   subtitle;
  final IconData icon;
  final Color    color;
  const _AppNotif({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Notification bell + dropdown panel (top bar)
// ─────────────────────────────────────────────────────────────────────────────

class _NotificationBell extends StatefulWidget {
  final String? orgId;
  const _NotificationBell({this.orgId});

  @override
  State<_NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<_NotificationBell> {
  // Survives widget remounts — tracks the hash of the last batch of
  // notifications the user actually opened the panel to read.
  static int _lastSeenHash = 0;

  final _layerLink = LayerLink();
  OverlayEntry?   _entry;
  bool            _open   = false;
  bool            _loaded = false;
  bool            _read   = false;
  List<_AppNotif> _notifs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _entry?.remove();
    super.dispose();
  }

  // ── Data fetch ─────────────────────────────────────────────────────────────

  Future<void> _load() async {
    if (widget.orgId == null) {
      if (mounted) setState(() => _loaded = true);
      return;
    }
    final orgId = widget.orgId!;
    final now   = DateTime.now();

    String fmtDate(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final todayStr    = fmtDate(now);
    final tomorrowStr = fmtDate(now.add(const Duration(days: 1)));
    final todayStart  = '${todayStr}T00:00:00';
    final result      = <_AppNotif>[];

    try {
      final client = SupabaseService.client;

      // Query 1 — all org events (id + display fields, capped at 200)
      final evtRows = await client
          .from('events')
          .select('event_id, title, event_date, start_time, event_status')
          .eq('organizer_id', orgId)
          .order('event_date', ascending: true)
          .limit(200);

      final evts   = List<Map<String, dynamic>>.from(evtRows as List);
      final evtIds = evts.map((e) => e['event_id'] as String).toList();

      // Query 2 — today's new registrations across all org events
      if (evtIds.isNotEmpty) {
        final regRows = await client
            .from('registrations')
            .select('id')
            .in_('event_id', evtIds)
            .gte('registered_at', todayStart);
        final count = (regRows as List).length;
        if (count > 0) {
          result.add(_AppNotif(
            title:    '$count new sign-up${count == 1 ? '' : 's'} today',
            subtitle: 'Students registered for your events',
            icon:     Icons.how_to_reg_rounded,
            color:    const Color(0xFF8B5CF6),
          ));
        }
      }

      // Ongoing (live) events
      for (final e in evts
          .where((e) => e['event_status'] == 'ongoing')
          .take(3)) {
        result.add(_AppNotif(
          title:    e['title'] as String? ?? '—',
          subtitle: 'Event is live · check in students now',
          icon:     Icons.radio_button_checked_rounded,
          color:    const Color(0xFF10B981),
        ));
      }

      // Upcoming events starting today
      for (final e in evts
          .where((e) =>
              e['event_status'] == 'upcoming' &&
              (e['event_date'] as String?) == todayStr)
          .take(3)) {
        final t = webFmtTime(e['start_time'] as String?);
        result.add(_AppNotif(
          title:    e['title'] as String? ?? '—',
          subtitle: 'Starting today${t.isNotEmpty ? ' at $t' : ''}',
          icon:     Icons.today_rounded,
          color:    const Color(0xFF3B82F6),
        ));
      }

      // Upcoming events starting tomorrow
      for (final e in evts
          .where((e) =>
              e['event_status'] == 'upcoming' &&
              (e['event_date'] as String?) == tomorrowStr)
          .take(2)) {
        final t = webFmtTime(e['start_time'] as String?);
        result.add(_AppNotif(
          title:    e['title'] as String? ?? '—',
          subtitle: 'Starting tomorrow${t.isNotEmpty ? ' at $t' : ''}',
          icon:     Icons.calendar_month_rounded,
          color:    const Color(0xFFF59E0B),
        ));
      }
    } catch (_) {}

    if (mounted) {
      final hash = Object.hashAll(result.map((n) => n.title));
      setState(() {
        _notifs = result;
        _loaded = true;
        // Don't flash the dot if nothing changed since the user last read.
        _read   = result.isEmpty || hash == _lastSeenHash;
      });
      _entry?.markNeedsBuild();
    }
  }

  // ── Panel lifecycle ────────────────────────────────────────────────────────

  void _toggle() {
    if (!_loaded) return;
    _open ? _close() : _openPanel();
  }

  void _openPanel() {
    _lastSeenHash = Object.hashAll(_notifs.map((n) => n.title));
    setState(() { _open = true; _read = true; });
    _entry = OverlayEntry(builder: (_) => _buildOverlay());
    Overlay.of(context).insert(_entry!);
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() => _open = false);
  }

  // ── Overlay ────────────────────────────────────────────────────────────────

  Widget _buildOverlay() {
    return GestureDetector(
      onTap:    _close,
      behavior: HitTestBehavior.opaque,
      child: SizedBox.expand(
        child: Stack(
          children: [
            CompositedTransformFollower(
              link:             _layerLink,
              showWhenUnlinked: false,
              targetAnchor:     Alignment.bottomRight,
              followerAnchor:   Alignment.topRight,
              offset:           const Offset(0, 8),
              child: GestureDetector(
                onTap: () {},
                child: _buildPanel(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel() {
    return Material(
      elevation: 0,
      color: Colors.transparent,
      child: Container(
        width: 320,
        constraints: const BoxConstraints(maxHeight: 440),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kCardBorder),
          boxShadow: [
            BoxShadow(
              color:      Colors.black.withValues(alpha: 0.10),
              blurRadius: 20,
              offset:     const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 12, 11),
              child: Row(children: [
                const Icon(Icons.notifications_rounded, size: 15, color: kText),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Notifications',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                      fontWeight: FontWeight.w700, color: kText)),
                ),
                Text(
                  'Today · ${webTodayLabel().split(',').last.trim()}',
                  style: const TextStyle(fontFamily: 'Poppins',
                    fontSize: 10, color: kMuted),
                ),
                const SizedBox(width: 8),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: _close,
                    child: const Icon(Icons.close_rounded,
                      size: 15, color: kMuted),
                  ),
                ),
              ]),
            ),
            const Divider(height: 1, color: kCardBorder),

            // ── Body ─────────────────────────────────────────────────
            if (_notifs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_circle_outline_rounded,
                        size: 24, color: Color(0xFF10B981)),
                    ),
                    const SizedBox(height: 12),
                    const Text("You're all caught up!",
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                        fontWeight: FontWeight.w600, color: kText),
                      textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    const Text('No new events or sign-ups today.',
                      style: TextStyle(fontFamily: 'Poppins',
                        fontSize: 11, color: kMuted),
                      textAlign: TextAlign.center),
                  ],
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shrinkWrap: true,
                  itemCount: _notifs.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: kCardBorder),
                  itemBuilder: (_, i) => _buildItem(_notifs[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(_AppNotif n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: n.color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(n.icon, size: 17, color: n.color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(n.title,
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12,
                  fontWeight: FontWeight.w600, color: kText),
                maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(n.subtitle,
                style: const TextStyle(fontFamily: 'Poppins',
                  fontSize: 10.5, color: kMuted),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ]),
    );
  }

  // ── Bell button ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final count = _loaded ? _notifs.length : 0;
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _toggle,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: _open
                  ? const Color(0xFFF1F5F9)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _open ? kCardBorder : Colors.transparent),
            ),
            child: Stack(
              children: [
                const Center(
                  child: Icon(Icons.notifications_rounded,
                    size: 18, color: kSubText),
                ),
                if (count > 0 && !_read)
                  Positioned(
                    top: 7, right: 7,
                    child: Container(
                      width: 7, height: 7,
                      decoration: const BoxDecoration(
                        color:  Color(0xFFEF4444),
                        shape:  BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

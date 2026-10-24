import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/app_colors.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/org_notif_prefs.dart';
import '../../../core/services/organizer_notices.dart';
import '../../../core/services/account_session_guard.dart';
import '../../../shared/utils/realtime_utils.dart';
import 'web_shared.dart';
import 'dashboard_page.dart';
import 'events_page.dart';
import 'registrations_page.dart';
import 'announcements_page.dart';
import 'profile_page.dart';
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
  String?       _orgId;
  String?       _name;
  String?       _email;
  String?       _organization;
  String?       _photoUrl;
  RealtimeChannel? _accountChannel;

  // Selfies waiting for this organizer's review — the badge on Registrations,
  // like the admin's count of events to review.
  int              _reviewCount = 0;
  bool             _reviewFirst = false; // open Registrations on those selfies
  Set<String>      _myEventIds  = {};
  RealtimeChannel? _reviewChannel;
  Timer?           _reviewDebounce;
  Timer?           _reviewClock;
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
    final userId = SupabaseService.currentUser?.id;
    if (userId != null) {
      _accountChannel = AccountSessionGuard.watch(
        context,
        table: 'organizers',
        userId: userId,
        // The admin renamed the organizer (or changed the organization or
        // photo): the header and pages follow without a page refresh.
        onUpdate: (row) {
          if (!mounted) return;
          setState(() {
            if (row.containsKey('full_name')) _name = row['full_name'] as String?;
            if (row.containsKey('organization')) {
              _organization = row['organization'] as String?;
            }
            if (row.containsKey('profile_image_url')) {
              _photoUrl = row['profile_image_url'] as String?;
            }
          });
        },
      );
    }
    _loadTheme();
    _loadProfile();
  }

  @override
  void dispose() {
    if (_accountChannel != null) {
      SupabaseService.client.removeChannel(_accountChannel!);
    }
    _reviewDebounce?.cancel();
    _reviewClock?.cancel();
    if (_reviewChannel != null) {
      SupabaseService.client.removeChannel(_reviewChannel!);
    }
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
          .select('organizer_id, full_name, organization, profile_image_url')
          .eq('user_id', user.id)
          .maybeSingle();
      if (!mounted) return;
      if (row == null) { _goLogin(); return; }
      setState(() {
        _orgId        = row['organizer_id']     as String?;
        _name         = row['full_name']        as String?;
        _organization = row['organization']     as String?;
        _photoUrl     = row['profile_image_url'] as String?;
        _loading      = false;
      });
      _entryCt.forward();
      _loadReviewCount();
      if (_reviewChannel == null) _watchReviewCount();
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

  // Hamburger: in minimal mode, expand to inset; otherwise toggle collapse
  void _onMenuTap() {
    if (_theme.variant == SidebarVariant.minimal) {
      setState(() => _theme = _theme.copyWith(variant: SidebarVariant.inset));
    } else {
      setState(() => _collapsed = !_collapsed);
    }
  }

  // ── Registrations badge ──────────────────────────────────────────────────

  /// Selfies submitted for this organizer's events while check-in is open —
  /// the ones that can still be approved. A selfie left after check-in
  /// closed can't be approved any more, so it doesn't keep the badge on.
  Future<void> _loadReviewCount() async {
    final orgId = _orgId;
    if (orgId == null) return;
    try {
      final eventsRaw = await SupabaseService.client
          .from('events')
          .select()
          .eq('organizer_id', orgId);
      final events = List<Map<String, dynamic>>.from(eventsRaw as List);
      _myEventIds = events.map((e) => e['event_id'] as String).toSet();
      final open = events
          .where(checkInIsOpen)
          .map((e) => e['event_id'] as String)
          .toList();
      var count = 0;
      if (open.isNotEmpty) {
        final rows = await SupabaseService.client
            .from('registrations')
            .select('id')
            .eq('status', 'photo_submitted')
            .in_('event_id', open);
        count = (rows as List).length;
      }
      if (mounted && count != _reviewCount) setState(() => _reviewCount = count);
    } catch (_) {
      // A shortcut, not the source of truth: the Registrations page reports
      // a failed load itself, so the badge just keeps its last number.
    }
  }

  void _watchReviewCount() {
    final channel =
        SupabaseService.client.channel('organizer-shell-review-$_orgId');
    for (final table in ['registrations', 'events']) {
      channel.on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(event: '*', schema: 'public', table: table),
        (payload, [_]) {
          if (!_touchesMyEvents(table, realtimeRow(payload))) return;
          _reviewDebounce?.cancel();
          _reviewDebounce = Timer(const Duration(milliseconds: 600), () {
            if (mounted) _loadReviewCount();
          });
        },
      );
    }
    _reviewChannel = channel..subscribe();
    // Check-in opens and closes with the clock, not with a database change.
    _reviewClock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) _loadReviewCount();
    });
  }

  // Skips other organizers' changes. A row without the column (a delete
  // carries only its key) counts as a maybe.
  bool _touchesMyEvents(String table, Map<String, dynamic>? row) {
    if (row == null) return true;
    if (table == 'events') {
      final owner = row['organizer_id'];
      return owner == null || owner == _orgId;
    }
    final eventId = row['event_id'];
    return eventId == null || _myEventIds.contains(eventId);
  }

  // While selfies are waiting, Registrations opens on them (the Photo
  // Submitted filter); every other time it opens as usual.
  void _openPage(OrganizerPage p) => setState(() {
        _reviewFirst = p == OrganizerPage.registrations && _reviewCount > 0;
        _page = p;
      });

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    if (_loading) {
      return Scaffold(
        backgroundColor: t.bg,
        body: const Center(child: CircularProgressIndicator(color: kGold)),
      );
    }
    if (_profileError) {
      return Scaffold(
        backgroundColor: t.bg,
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
              Text('Could not load your profile',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 17,
                  fontWeight: FontWeight.w800, color: t.text,
                )),
              const SizedBox(height: 8),
              Text('Check your connection and try again.',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 13, color: t.sub,
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
      backgroundColor: t.bg,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // Sidebar-only override: hard-switches the sidebar to the shared graphite
    // dark palette when the app is in dark mode, regardless of the
    // organizer's chosen (light-mode-only) accent/secondary color.
    final sidebarTheme = _theme.copyWith(
      dark: Theme.of(context).brightness == Brightness.dark,
    );
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
                    theme:        sidebarTheme,
                    collapsed:    _collapsed,
                    minimal:      false,
                    currentPage:  _page,
                    onPageChanged: _openPage,
                    reviewCount:  _reviewCount,
                    onToggle:  () => setState(() => _collapsed = !_collapsed),
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
                        photoUrl:    _photoUrl,
                        leftPad:     0,
                        onMenuTap:   _onMenuTap,
                        onSignOut:   _signOut,
                        onProfileTap: () =>
                            setState(() => _page = OrganizerPage.profile),
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
                    photoUrl:    _photoUrl,
                    leftPad:     pad,
                    onMenuTap:   _onMenuTap,
                    onSignOut:   _signOut,
                    onProfileTap: () =>
                        setState(() => _page = OrganizerPage.profile),
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
                        theme:        sidebarTheme,
                        collapsed:    _collapsed,
                        minimal:      false,
                        currentPage:  _page,
                        onPageChanged: _openPage,
                        reviewCount:  _reviewCount,
                        onToggle:  () => setState(() => _collapsed = !_collapsed),
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
                  theme:        sidebarTheme,
                  collapsed:    true,
                  minimal:      true,
                  currentPage:  _page,
                  onPageChanged: _openPage,
                  reviewCount:  _reviewCount,
                  onToggle:  _onMenuTap,
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
                        photoUrl:    _photoUrl,
                        leftPad:     0,
                        onMenuTap:   _onMenuTap,
                        onSignOut:   _signOut,
                        onProfileTap: () =>
                            setState(() => _page = OrganizerPage.profile),
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
      OrganizerPage.dashboard     => WebDashboardPage(
          orgId:      _orgId,
          name:       _name,
          onNavigate: _openPage,
        ),
      OrganizerPage.events        => WebEventsPage(orgId: _orgId),
      OrganizerPage.registrations => WebRegistrationsPage(
          orgId:         _orgId,
          initialStatus: _reviewFirst ? 'Photo Submitted' : null,
        ),
      OrganizerPage.announcements => WebAnnouncementsPage(orgId: _orgId),
      OrganizerPage.profile       => WebProfilePage(
          orgId:        _orgId,
          name:         _name,
          email:        _email,
          organization: _organization,
          onPhotoUpdated: (url) => setState(() => _photoUrl = url),
          onNavigate:     _openPage,
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
  (OrganizerPage.profile,       Icons.person_rounded,          'Profile'),
];

// ─────────────────────────────────────────────────────────────────────────────
// Sidebar
// ─────────────────────────────────────────────────────────────────────────────

class _Sidebar extends StatefulWidget {
  final AppTheme      theme;
  final bool          collapsed;
  final bool          minimal;
  final OrganizerPage currentPage;
  final ValueChanged<OrganizerPage> onPageChanged;
  final VoidCallback  onToggle;
  /// Selfies waiting for review — the badge on Registrations.
  final int           reviewCount;

  const _Sidebar({
    required this.theme,
    required this.collapsed,
    required this.minimal,
    required this.currentPage,
    required this.onPageChanged,
    required this.onToggle,
    this.reviewCount = 0,
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
          // Name, photo and Sign out are in the top bar — not repeated here.
          const SizedBox(height: 12),
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
        final badge = page == OrganizerPage.registrations ? widget.reviewCount : 0;
        return _cascade(
          _NavItem(
            icon:       icon,
            label:      label,
            isActive:   widget.currentPage == page,
            collapsed:  _isCollapsed,
            theme:      widget.theme,
            badgeCount: badge,
            badgeTip:   '$badge selfie${badge == 1 ? '' : 's'} waiting for your review',
            onTap:      () => widget.onPageChanged(page),
          ),
          cIdx,
        );
      }).toList(),
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
  final int          badgeCount;
  /// What the badge counts, for its hover text.
  final String?      badgeTip;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.collapsed,
    required this.theme,
    this.badgeCount = 0,
    this.badgeTip,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  // Collapsed, the label — and what the badge counts — move into the tooltip.
  String get _collapsedTip => widget.badgeCount > 0 && widget.badgeTip != null
      ? '${widget.label} · ${widget.badgeTip}'
      : widget.label;

  @override
  Widget build(BuildContext context) {
    final active = widget.isActive;
    final t      = widget.theme;

    final Color itemBg     = active
        ? t.primaryColor.withValues(alpha: 0.13)
        : _hovered
            ? t.navHoverColor
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
        ? (t.dark ? Colors.white : kText)
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
            message:      widget.collapsed ? _collapsedTip : '',
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
                      child: Stack(clipBehavior: Clip.none, children: [
                        AnimatedContainer(
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
                        if (widget.badgeCount > 0)
                          Positioned(
                            top: -4, right: -6,
                            child: WebNavBadge(count: widget.badgeCount),
                          ),
                      ]),
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
                          if (widget.badgeCount > 0)
                            WebNavBadge(
                              count:   widget.badgeCount,
                              tooltip: widget.badgeTip,
                            )
                          else
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
// Top bar
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatefulWidget {
  final AppTheme     theme;
  final String?      name;
  final String?      email;
  final String?      orgId;
  final String?      photoUrl;
  final double       leftPad;
  final VoidCallback onMenuTap;
  final VoidCallback onSignOut;
  final VoidCallback onProfileTap;
  final OrganizerPage currentPage;

  const _TopBar({
    required this.theme,
    required this.name,
    required this.email,
    this.orgId,
    this.photoUrl,
    required this.leftPad,
    required this.onMenuTap,
    required this.onSignOut,
    required this.onProfileTap,
    required this.currentPage,
  });

  @override
  State<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<_TopBar> {
  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final initials = (widget.name ?? '?').trim().split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase())
        .take(2)
        .join();

    return Container(
      height: kWebTopH,
      decoration: BoxDecoration(
        color: t.card,
        border: Border(bottom: BorderSide(color: t.border)),
        boxShadow: [
          BoxShadow(
            color: t.shadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
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
          Container(height: 28, width: 1, color: t.border),
          const SizedBox(width: 16),

          // User info + sign-out
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: widget.onProfileTap,
                  child: Tooltip(
                    message: 'Profile',
                    waitDuration: const Duration(milliseconds: 600),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(widget.name ?? 'Organizer',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: t.text,
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
                          clipBehavior: Clip.antiAliasWithSaveLayer,
                          child: (widget.photoUrl != null && widget.photoUrl!.isNotEmpty)
                              ? Image.network(widget.photoUrl!, fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Center(
                                    child: Text(initials,
                                      style: const TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      )),
                                  ))
                              : Center(
                                  child: Text(initials,
                                    style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    )),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Container(height: 28, width: 1, color: t.border),
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
    OrganizerPage.profile:       'Profile',
  };

  @override
  Widget build(BuildContext context) {
    final t     = WebTk(Theme.of(context).brightness == Brightness.dark);
    final label = _labels[page] ?? '';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Organizer',
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 13,
            fontWeight: FontWeight.w500, color: t.muted)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Icon(Icons.chevron_right_rounded, size: 16, color: t.muted),
        ),
        Text(label,
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 13,
            fontWeight: FontWeight.w700, color: t.text)),
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
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return MouseRegion(
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
            color: _h ? t.divider : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _h ? t.border : Colors.transparent),
          ),
          child: Icon(Icons.menu_rounded, size: 18, color: t.sub),
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return MouseRegion(
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
            color: _h ? const Color(0xFFFCA5A5) : t.border),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Notification data model
// ─────────────────────────────────────────────────────────────────────────────

class _AppNotif {
  final String    id;
  final String    title;
  final String    subtitle;
  final IconData  icon;
  final Color     color;
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
  final _layerLink = LayerLink();
  OverlayEntry?    _entry;
  Timer?           _refreshTimer;
  Timer?           _debounce;
  RealtimeChannel? _channel;
  bool             _open     = false;
  bool             _loaded   = false;
  bool             _fetching = false;
  bool             _again    = false;
  List<_AppNotif>  _notifs   = [];
  /// Not read yet: gold in the panel and counted on the bell. A row is read
  /// once the pointer rests on it or it's clicked, or with "Mark all as
  /// read" — opening the panel doesn't read anything by itself.
  Set<String>      _unreadIds = {};
  /// Read ids for [_readUser], kept in memory so quick hovers can't undo
  /// each other's saves.
  Set<String>      _read = {};
  String?          _readUser;
  final Map<String, Timer> _hoverTimers = {};
  /// How long the pointer rests on a row before it counts as read, so
  /// sweeping across the list on the way to something else doesn't.
  static const _readAfterHover = Duration(milliseconds: 500);

  String? get _uid => SupabaseService.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
    // The bell lives in the shell for the whole session, so it needs its own
    // refresh — unlike a per-page widget it never gets rebuilt on navigation.
    // Realtime brings event decisions at once; this also catches change-
    // request decisions and announcement removals.
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!_open) _load();
    });
  }

  @override
  void didUpdateWidget(_NotificationBell old) {
    super.didUpdateWidget(old);
    if (old.orgId != widget.orgId) {
      _unsubscribe();
      _subscribe();
      _load();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _debounce?.cancel();
    for (final t in _hoverTimers.values) {
      t.cancel();
    }
    _unsubscribe();
    _entry?.remove();
    super.dispose();
  }

  // ── Live updates ───────────────────────────────────────────────────────────
  // The admin's decisions reach the bell at once: approving or rejecting one
  // of this organizer's events (or applying a change request) updates the
  // event row, rejecting a change request updates event_revisions, and
  // removing an announcement adds a notification.

  void _subscribe() {
    final orgId = widget.orgId;
    if (orgId == null) return;
    void soon() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 800), _load);
    }

    _channel = SupabaseService.client.channel('org-notif-bell-$orgId');
    for (final (table, column) in const [
      ('events', 'organizer_id'),
      ('event_revisions', 'organizer_id'),
      ('notifications', 'user_id'),
    ]) {
      _channel!.on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(
          event: '*',
          schema: 'public',
          table: table,
          filter: '$column=eq.$orgId',
        ),
        (_, [_]) => soon(),
      );
    }
    _channel!.subscribe();
  }

  void _unsubscribe() {
    if (_channel != null) SupabaseService.client.removeChannel(_channel!);
    _channel = null;
  }

  // ── Read-state persistence (per-user, per-notification-ID) ────────────────

  static String _prefKey(String userId) => 'web_notif_read_ids_$userId';

  Future<Set<String>> _readIds(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return Set<String>.from(prefs.getStringList(_prefKey(userId)) ?? []);
  }

  Future<void> _saveRead() async {
    final userId = _readUser;
    if (userId == null) return;
    final list    = _read.toList();
    final trimmed = list.length > 200 ? list.sublist(list.length - 200) : list;
    final prefs   = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefKey(userId), trimmed);
  }

  /// Marks [ids] read: their gold fades and the bell's number drops.
  void _markRead(Iterable<String> ids) {
    final fresh = ids.where(_unreadIds.contains).toList();
    if (fresh.isEmpty || !mounted) return;
    for (final id in fresh) {
      _hoverTimers.remove(id)?.cancel();
    }
    setState(() {
      _unreadIds = {..._unreadIds}..removeAll(fresh);
      _read.addAll(fresh);
    });
    _entry?.markNeedsBuild();
    _saveRead(); // fire-and-forget — survives reload/logout
  }

  void _hoverStart(String id) {
    if (!_unreadIds.contains(id) || _hoverTimers.containsKey(id)) return;
    _hoverTimers[id] = Timer(_readAfterHover, () {
      _hoverTimers.remove(id);
      _markRead([id]);
    });
  }

  void _hoverEnd(String id) => _hoverTimers.remove(id)?.cancel();

  // ── Data fetch ─────────────────────────────────────────────────────────────

  // One fetch at a time; a request that arrives meanwhile runs once after.
  Future<void> _load() async {
    if (_fetching) {
      _again = true;
      return;
    }
    _fetching = true;
    try {
      await _fetch();
    } finally {
      _fetching = false;
      if (_again && mounted) {
        _again = false;
        _load();
      }
    }
  }

  Future<void> _fetch() async {
    if (widget.orgId == null) {
      if (mounted) setState(() => _loaded = true);
      return;
    }
    final orgId  = widget.orgId!;
    final userId = _uid;
    final now    = DateTime.now();

    String fmtDate(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final todayStr    = fmtDate(now);
    final tomorrowStr = fmtDate(now.add(const Duration(days: 1)));
    final todayStart  = '${todayStr}T00:00:00';
    final decisions   = <_AppNotif>[];
    final reminders   = <_AppNotif>[];

    try {
      final client = SupabaseService.client;

      // Query 1 — all org events (id + display fields, capped at 200)
      final evtRows = await client
          .from('events')
          .select('event_id, title, event_date, end_date, start_time, end_time, '
              'event_status, approval_status, rejection_reason, reviewed_at')
          .eq('organizer_id', orgId)
          .order('event_date', ascending: true)
          .limit(200);

      final evts   = List<Map<String, dynamic>>.from(evtRows as List);
      final evtIds = evts.map((e) => e['event_id'] as String).toList();

      // Admin decisions (approved / rejected events and change requests,
      // removed announcements) — first, newest first. Deliberately NOT gated
      // by OrgNotifPrefs: what happened to your own submission isn't
      // something to silence. Same items as the mobile app.
      for (final n in await OrganizerNotices.load(organizerId: orgId, events: evts)) {
        decisions.add(_AppNotif.notice(n));
      }

      // Query 2 — today's new registrations across all org events
      if (evtIds.isNotEmpty) {
        final regRows = await client
            .from('registrations')
            .select('id')
            .in_('event_id', evtIds)
            .gte('registered_at', todayStart);
        final count = (regRows as List).length;
        if (count > 0) {
          reminders.add(_AppNotif(
            id:       'signups_today_$todayStr',
            title:    '$count new sign-up${count == 1 ? '' : 's'} today',
            subtitle: 'Students registered for your events',
            icon:     Icons.how_to_reg_rounded,
            color:    const Color(0xFF8B5CF6),
          ));
        }
      }

      // Ongoing (live) events — status from the clock, like mobile.
      for (final e in evts
          .where((e) => eventIsApproved(e) && eventStatusValue(e) == 'ongoing')
          .take(3)) {
        reminders.add(_AppNotif(
          id:       'event_live_${e['event_id']}',
          title:    e['title'] as String? ?? '—',
          subtitle: 'Event is live · check in students now',
          icon:     Icons.radio_button_checked_rounded,
          color:    const Color(0xFF10B981),
        ));
      }

      // Upcoming events starting today
      for (final e in evts
          .where((e) =>
              eventIsApproved(e) &&
              eventStatusValue(e) == 'upcoming' &&
              (e['event_date'] as String?) == todayStr)
          .take(3)) {
        final t = webFmtTime(e['start_time'] as String?);
        reminders.add(_AppNotif(
          id:       'event_today_${e['event_id']}',
          title:    e['title'] as String? ?? '—',
          subtitle: 'Starting today${t.isNotEmpty ? ' at $t' : ''}',
          icon:     Icons.today_rounded,
          color:    const Color(0xFF3B82F6),
        ));
      }

      // Upcoming events starting tomorrow
      for (final e in evts
          .where((e) =>
              eventIsApproved(e) &&
              eventStatusValue(e) == 'upcoming' &&
              (e['event_date'] as String?) == tomorrowStr)
          .take(2)) {
        final t = webFmtTime(e['start_time'] as String?);
        reminders.add(_AppNotif(
          id:       'event_tomorrow_${e['event_id']}',
          title:    e['title'] as String? ?? '—',
          subtitle: 'Starting tomorrow${t.isNotEmpty ? ' at $t' : ''}',
          icon:     Icons.calendar_month_rounded,
          color:    const Color(0xFFF59E0B),
        ));
      }

      // Respect per-user preferences (Profile → Notifications) — same
      // categories the mobile app already filters on.
      if (userId != null) {
        final disabledCats = await OrgNotifPrefs.disabled(userId);
        if (disabledCats.isNotEmpty) {
          reminders.removeWhere((n) =>
              (disabledCats.contains(OrgNotifPrefs.signups) &&
                  n.id.startsWith('signups_today_')) ||
              (disabledCats.contains(OrgNotifPrefs.live) &&
                  n.id.startsWith('event_live_')) ||
              (disabledCats.contains(OrgNotifPrefs.today) &&
                  n.id.startsWith('event_today_')) ||
              (disabledCats.contains(OrgNotifPrefs.tomorrow) &&
                  n.id.startsWith('event_tomorrow_')));
        }
      }
    } catch (e) {
      debugPrint('Organizer notifications failed to load: $e');
    }

    final result = [...decisions, ...reminders];
    if (userId != _readUser) {
      _readUser = userId;
      _read = {};
    }
    // What's saved, plus any marks made since (their save may still be on
    // its way).
    if (userId != null) _read.addAll(await _readIds(userId));
    if (!mounted) return;
    setState(() {
      _notifs = result;
      _loaded = true;
      // New arrivals stay unread (gold) even while the panel is open.
      _unreadIds = {for (final n in result) if (!_read.contains(n.id)) n.id};
    });
    _entry?.markNeedsBuild();
  }

  // ── Panel lifecycle ────────────────────────────────────────────────────────

  void _toggle() {
    if (!_loaded) return;
    _open ? _close() : _openPanel();
  }

  void _openPanel() {
    setState(() => _open = true);
    _entry = OverlayEntry(builder: (_) => _buildOverlay());
    Overlay.of(context).insert(_entry!);
    _load(); // refresh in the background; overlay repaints via markNeedsBuild
  }

  void _close() {
    for (final t in _hoverTimers.values) {
      t.cancel();
    }
    _hoverTimers.clear();
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
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final newCount = _unreadIds.length;
    return Material(
      elevation: 0,
      color: Colors.transparent,
      child: Container(
        width: 360,
        constraints: const BoxConstraints(maxHeight: 480),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.border),
          boxShadow: [
            BoxShadow(
              color:      t.shadow,
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
                Icon(Icons.notifications_rounded, size: 15, color: t.text),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Notifications',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                      fontWeight: FontWeight.w700, color: t.text)),
                ),
                Text(
                  newCount > 0 ? '$newCount new' : 'Recent activity',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10.5,
                    fontWeight: newCount > 0 ? FontWeight.w600 : FontWeight.w400,
                    color: t.sub,
                  ),
                ),
                if (newCount > 0) ...[
                  const SizedBox(width: 10),
                  Semantics(
                    button: true,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => _markRead([..._unreadIds]),
                        child: Text('Mark all as read',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            // Darker gold on light cards for contrast.
                            color: t.dark ? kGold : kSwalGold,
                          )),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: _close,
                    child: Icon(Icons.close_rounded,
                      size: 15, color: t.sub),
                  ),
                ),
              ]),
            ),
            Divider(height: 1, color: t.border),

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
                    Text("You're all caught up!",
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                        fontWeight: FontWeight.w600, color: t.text),
                      textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    Text('Admin approvals, sign-ups and event reminders show up here.',
                      style: TextStyle(fontFamily: 'Poppins',
                        fontSize: 11, color: t.sub),
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
                      Divider(height: 1, color: t.border),
                  itemBuilder: (_, i) => _buildItem(_notifs[i], t),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(_AppNotif n, WebTk t) {
    final isNew = _unreadIds.contains(n.id);
    final gold  = kGold.withValues(alpha: t.dark ? 0.10 : 0.07);
    // Resting the pointer on an unread row (or clicking it) reads it.
    return MouseRegion(
      onEnter: (_) => _hoverStart(n.id),
      onExit:  (_) => _hoverEnd(n.id),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _markRead([n.id]),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          color: isNew ? gold : gold.withValues(alpha: 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                    Row(children: [
                      Expanded(
                        child: Text(n.title,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                            fontWeight: FontWeight.w600, color: t.text),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      if (n.at != null) ...[
                        const SizedBox(width: 8),
                        Text(noticeTimeAgo(n.at!),
                          style: TextStyle(fontFamily: 'Poppins',
                            fontSize: 10, color: t.sub)),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    // Admin decisions carry the reason — show it in full.
                    Text(n.subtitle,
                      style: TextStyle(fontFamily: 'Poppins',
                        fontSize: 11, height: 1.45, color: t.sub),
                      maxLines: n.at != null ? 5 : 1,
                      overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              // Kept in place once read (just faded) so the text doesn't shift.
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: ExcludeSemantics(
                  excluding: !isNew,
                  child: Semantics(
                    label: 'New',
                    child: AnimatedOpacity(
                      opacity: isNew ? 1 : 0,
                      duration: const Duration(milliseconds: 350),
                      child: Container(
                        width: 7, height: 7,
                        decoration: const BoxDecoration(color: kGold, shape: BoxShape.circle),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Bell button ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t     = WebTk(Theme.of(context).brightness == Brightness.dark);
    final count = _loaded ? _unreadIds.length : 0;
    final label = count == 0
        ? 'Notifications'
        : '$count new notification${count == 1 ? '' : 's'}';
    return CompositedTransformTarget(
      link: _layerLink,
      child: Tooltip(
        message: label,
        child: Semantics(
          button: true,
          label: label,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _toggle,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: _open ? t.divider : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _open ? t.border : Colors.transparent),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Center(
                      child: Icon(
                        count > 0
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_rounded,
                        size: 18,
                        color: count > 0 ? kGold : t.sub),
                    ),
                    if (count > 0)
                      Positioned(
                        top: 2, right: 1,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 16),
                          height: 16,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            // #DC2626 keeps the white count at 4.8:1.
                            color: const Color(0xFFDC2626),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: t.card, width: 1.5),
                          ),
                          child: Text(
                            count > 9 ? '9+' : '$count',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 9,
                              height: 1,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
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

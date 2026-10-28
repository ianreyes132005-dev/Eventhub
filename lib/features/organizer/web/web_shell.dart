import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/app_colors.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/org_notif_prefs.dart';
import '../../../core/services/organizer_notices.dart';
import '../../../core/services/account_session_guard.dart';
import '../../../core/theme_store.dart';
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
  final         _scaffoldKey = GlobalKey<ScaffoldState>();
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
  String?          _openEventId;         // open Events on this event's details
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
      icon:         Icons.logout_rounded,
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

  // Dark mode from the account menu (also on the Profile page).
  Future<void> _toggleTheme() async {
    try {
      await ThemeStore.toggle();
    } catch (e) {
      if (mounted) showErrorAlert(context, e, title: 'Couldn’t save theme preference');
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
        _openEventId = null;
        _page = p;
      });

  // The dashboard's Next event card opens that event on the Events tab.
  void _openEvent(String eventId) => setState(() {
        _reviewFirst = false;
        _openEventId = eventId;
        _page = OrganizerPage.events;
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
    final drawer = webNavUsesDrawer(MediaQuery.sizeOf(context).width);
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: t.bg,
      // Narrow windows: the sidebar slides in from the menu button.
      drawer: drawer
          ? Drawer(
              width: 288,
              backgroundColor: Colors.transparent,
              shape: const RoundedRectangleBorder(),
              child: _sideNav(
                onClose: () => _scaffoldKey.currentState?.closeDrawer(),
              ),
            )
          : null,
      body: _buildBody(drawer),
    );
  }

  // Wide: the sidebar; narrow ([drawer]): no sidebar, a menu button in the
  // top bar opens it as a drawer.
  Widget _buildBody(bool drawer) {
    return Stack(children: [
      Row(children: [
        if (!drawer)
          // Sidebar: fade + subtle left slide
          FadeTransition(
            opacity: _sidebarFade,
            child: SlideTransition(
              position: _sidebarSlide,
              child: SizedBox(width: kWebSideW, child: _sideNav()),
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
                    theme:         _theme,
                    name:          _name,
                    orgId:         _orgId,
                    photoUrl:      _photoUrl,
                    title:         _pageTitles[_page] ?? '',
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
  }

  static const _pageTitles = <OrganizerPage, String>{
    OrganizerPage.dashboard:     'Dashboard',
    OrganizerPage.events:        'Events',
    OrganizerPage.registrations: 'Registrations',
    OrganizerPage.announcements: 'Announcements',
    OrganizerPage.profile:       'Profile',
  };

  // Dashboard, then MANAGE and ACCOUNT — the layout the user chose.
  List<WebNavGroup<OrganizerPage>> get _navGroups => [
    const WebNavGroup(entries: [
      WebNavEntry(
        page: OrganizerPage.dashboard,
        icon: Icons.dashboard_rounded,
        label: 'Dashboard',
      ),
    ]),
    WebNavGroup(title: 'Manage', entries: [
      const WebNavEntry(
        page: OrganizerPage.events,
        icon: Icons.event_rounded,
        label: 'Events',
      ),
      WebNavEntry(
        page: OrganizerPage.registrations,
        icon: Icons.how_to_reg_rounded,
        label: 'Registrations',
        badge: _reviewCount,
        badgeTip: '$_reviewCount selfie${_reviewCount == 1 ? '' : 's'} '
            'waiting for your review',
      ),
      const WebNavEntry(
        page: OrganizerPage.announcements,
        icon: Icons.campaign_rounded,
        label: 'Announcements',
      ),
    ]),
    const WebNavGroup(title: 'Account', entries: [
      WebNavEntry(
        page: OrganizerPage.profile,
        icon: Icons.person_rounded,
        label: 'Profile',
      ),
    ]),
  ];

  // [onClose]: the drawer — choosing a page closes it.
  Widget _sideNav({VoidCallback? onClose}) {
    // The sidebar follows dark mode, whatever accent the organizer chose.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final s    = _theme.copyWith(dark: dark);
    final hsl  = HSLColor.fromColor(s.primaryColor);
    return WebSideNav<OrganizerPage>(
      portalLabel:  'Organizer portal',
      groups:       _navGroups,
      current:      _page,
      headerHeight: kWebTopH,
      onClose:      onClose,
      onSelect: (page) {
        onClose?.call();
        _openPage(page);
      },
      palette: WebNavPalette(
        background:   s.sideGradient,
        border:       s.sideBorder,
        text:         s.navText,
        activeText:   dark ? Colors.white : kText,
        icon:         s.navIcon,
        // Group titles readable on the dark sidebar too (4.5:1).
        label:        dark ? const Color(0xFF8E97A5) : s.navLabel,
        hover:        s.navHoverColor,
        accent:       s.primaryColor,
        accentStrong: dark
            ? s.primaryColor
            : hsl.withLightness((hsl.lightness - 0.22).clamp(0.0, 1.0)).toColor(),
        focus:        dark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
      ),
    );
  }

  Widget _buildPage() {
    return switch (_page) {
      OrganizerPage.dashboard     => WebDashboardPage(
          orgId:      _orgId,
          name:       _name,
          onNavigate: _openPage,
          onOpenEvent: _openEvent,
        ),
      OrganizerPage.events        => WebEventsPage(orgId: _orgId, openEventId: _openEventId),
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
// Top bar
// ─────────────────────────────────────────────────────────────────────────────

// Page title, the notification bell and the account menu (Dark mode, Sign
// out — the same as the admin's; Profile is in the sidebar). On a narrow
// window a menu button opens the sidebar as a drawer.
class _TopBar extends StatelessWidget {
  final AppTheme      theme;
  final String?       name;
  final String?       orgId;
  final String?       photoUrl;
  final String        title;
  /// Narrow window: the account button shows only the photo.
  final bool          compact;
  /// Set on narrow windows: opens the sidebar drawer.
  final VoidCallback? onMenuTap;
  final VoidCallback  onToggleTheme;
  final VoidCallback  onSignOut;

  const _TopBar({
    required this.theme,
    required this.name,
    this.orgId,
    this.photoUrl,
    required this.title,
    required this.compact,
    this.onMenuTap,
    required this.onToggleTheme,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final initials = (name ?? '?').trim().split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase())
        .take(2)
        .join();
    final initialsText = Center(
      child: Text(initials,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        )),
    );
    final avatar = Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        gradient: theme.avatarGradient,
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: (photoUrl != null && photoUrl!.isNotEmpty)
          ? Image.network(photoUrl!, fit: BoxFit.cover,
              errorBuilder: (_, _, _) => initialsText)
          : initialsText,
    );

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
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : kWebPad),
      child: Row(
        children: [
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
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: t.text,
                )),
            ),
          ),
          _NotificationBell(orgId: orgId),
          const SizedBox(width: 10),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: ThemeStore.notifier,
            builder: (_, mode, _) => WebAccountMenu(
              name:    name ?? 'Organizer',
              role:    'Organizer',
              avatar:  avatar,
              accent:  theme.primaryColor,
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
        ],
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

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../events/student_all_events.dart';
import '../events/event_details_page.dart';
import '../events/my_registered_events_page.dart';
import '../profile/student_profile.dart' hide kSubText;
import '../notifications/notifications_screen.dart';
import '../check_in/selfie_screen.dart';
import 'package:eventhub/core/services/supabase_service.dart';
import 'package:eventhub/core/services/registration_service.dart';
import 'package:eventhub/core/services/notif_read_store.dart';
import 'package:eventhub/shared/widgets/ai_chat_fab.dart';
import 'package:eventhub/shared/widgets/app_loader.dart';
import 'package:eventhub/shared/widgets/event_phase_pill.dart';
import 'package:eventhub/shared/widgets/qr_code_dialog.dart';
import 'package:eventhub/models/event_registration.dart';
import 'package:eventhub/core/app_colors.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

String _greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

String _todayFormatted() {
  final now    = DateTime.now();
  const days   = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
  const months = ['Jan','Feb','Mar','Apr','May','Jun',
                  'Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
}

String _fmtTime(String? ts) {
  if (ts == null || ts.isEmpty) return 'Just now';
  try {
    final d = DateTime.parse(ts);
    final diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60)  return 'Just now';
    if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
    if (diff.inHours   < 24)  return '${diff.inHours}h ago';
    if (diff.inDays    < 7)   return '${diff.inDays}d ago';
    return '${diff.inDays ~/ 7}w ago';
  } catch (_) { return 'Recently'; }
}


// ── Screen ────────────────────────────────────────────────────────────────────

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard>
    with SingleTickerProviderStateMixin {
  int _selectedIndex     = 0;
  int _notificationCount = 0;

  late final AnimationController _staggerCtrl;

  // Home tab state
  bool    _homeLoading      = true;
  bool    _homeRefreshing   = false;
  String? _studentName;
  int     _totalRegistrations = 0;
  int     _attendedCount      = 0;
  int     _upcomingCount      = 0;

  List<Map<String, dynamic>> _announcements        = [];
  List<Map<String, dynamic>> _registrations          = [];
  List<Map<String, dynamic>> _upcomingRegistrations  = [];

  RealtimeChannel? _regChannel;
  RealtimeChannel? _annChannel;
  Timer?           _annDebounce;
  final Set<String> _selfiePrompted = {};

  // ── Init / dispose ────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _loadHomeData();
    SupabaseService.announcementsVersion.addListener(_onAnnouncementUpdate);
    _subscribeToCheckInRequests();
    _subscribeAnnouncements();
    NotifReadStore.unreadNotifier.addListener(_onNotifCountChanged);
  }

  void _onNotifCountChanged() {
    if (mounted) setState(() => _notificationCount = NotifReadStore.unreadNotifier.value);
  }

  void _onAnnouncementUpdate() => _loadHomeData(silent: true);

  @override
  void dispose() {
    _annDebounce?.cancel();
    _staggerCtrl.dispose();
    SupabaseService.announcementsVersion.removeListener(_onAnnouncementUpdate);
    NotifReadStore.unreadNotifier.removeListener(_onNotifCountChanged);
    if (_regChannel != null) Supabase.instance.client.removeChannel(_regChannel!);
    if (_annChannel != null) Supabase.instance.client.removeChannel(_annChannel!);
    super.dispose();
  }

  void _subscribeAnnouncements() {
    _annChannel = Supabase.instance.client.channel('student-announcements');
    _annChannel!.on(
      RealtimeListenTypes.postgresChanges,
      ChannelFilter(event: '*', schema: 'public', table: 'announcements'),
      (_, [a]) {
        _annDebounce?.cancel();
        _annDebounce = Timer(const Duration(milliseconds: 600), () {
          if (mounted) _loadHomeData(silent: true);
        });
      },
    );
    _annChannel!.subscribe();
  }

  // ── Data ─────────────────────────────────────────────────────────────────

  Future<void> _loadHomeData({bool silent = false}) async {
    if (silent && _homeRefreshing) return;
    if (silent) {
      if (mounted) setState(() => _homeRefreshing = true);
    } else {
      setState(() => _homeLoading = true);
    }

    try {
      final client = Supabase.instance.client;
      final user   = client.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() { _homeLoading = false; _homeRefreshing = false; });
        if (!silent) _staggerCtrl.forward(from: 0);
        return;
      }

      // Parallel fetch: profile + announcements
      final results = await Future.wait([
        client.from('students').select('full_name').eq('user_id', user.id).maybeSingle(),
        client.from('announcements')
            .select('id, title, message, created_at')
            .order('created_at', ascending: false)
            .limit(10),
      ]);

      // Registrations fetched separately (needs user.id, not parallelizable cleanly)
      final regRows = await client
          .from('registrations')
          .select('*, events(event_id, title, event_date, start_time, end_time, '
                  'location, event_image_url, description, event_status, '
                  'max_participants, event_type)')
          .eq('student_user_id', user.id)
          .order('registered_at', ascending: false);
      final regList = List<Map<String, dynamic>>.from(regRows as List);

      if (!mounted) return;

      final profile  = results[0] as Map<String, dynamic>?;
      final annList  = List<Map<String, dynamic>>.from(results[1] as List);
      final today    = DateTime.now();
      final todayMid = DateTime(today.year, today.month, today.day);

      final upcomingCount = regList.where((r) {
        if ((r['status'] as String?) == 'checked_in') return false;
        final evMap = r['events'] as Map?;
        final dStr  = evMap?['event_date'] as String?;
        if (dStr == null) return false;
        try {
          final d = DateTime.parse(dStr);
          return !DateTime(d.year, d.month, d.day).isBefore(todayMid);
        } catch (_) { return false; }
      }).length;

      final sortedUpcoming = regList.where((r) {
        final evMap = r['events'] as Map?;
        final dStr  = evMap?['event_date'] as String?;
        if (dStr == null) return false;
        try {
          final d        = DateTime.parse(dStr);
          final eTimeStr = evMap?['end_time'] as String?;
          if (eTimeStr != null) {
            // Keep until 1 hour after event ends so "Completed" can display
            final ep       = eTimeStr.split(':');
            final eh       = int.tryParse(ep[0]) ?? 23;
            final em       = ep.length > 1 ? (int.tryParse(ep[1]) ?? 59) : 59;
            final endTime  = DateTime(d.year, d.month, d.day, eh, em);
            return endTime.isAfter(today.subtract(const Duration(hours: 1)));
          } else {
            // No end_time: show for the whole event day
            final eventMid = DateTime(d.year, d.month, d.day);
            final todayMid = DateTime(today.year, today.month, today.day);
            return !eventMid.isBefore(todayMid);
          }
        } catch (_) { return false; }
      }).toList()
        ..sort((a, b) {
          final da = DateTime.tryParse(((a['events'] as Map?) ?? {})['event_date'] as String? ?? '') ?? DateTime(9999);
          final db = DateTime.tryParse(((b['events'] as Map?) ?? {})['event_date'] as String? ?? '') ?? DateTime(9999);
          return da.compareTo(db);
        });

      final notifIds = [
        ...annList.map((a) => 'ann_${a['id']}'),
        ...regList
            .where((r) => const {'checked_in', 'photo_required', 'photo_submitted'}
                .contains(r['status']))
            .map((r) => 'reg_${r['id']}_${r['status']}'),
      ];
      NotifReadStore.setAll(notifIds);

      if (mounted) {
        setState(() {
          _studentName           = profile?['full_name'] as String? ?? 'Student';
          _totalRegistrations    = regList.length;
          _attendedCount         = regList.where((r) => r['status'] == 'checked_in').length;
          _upcomingCount         = upcomingCount;
          _announcements         = annList.take(3).toList();
          _registrations         = regList;
          _upcomingRegistrations = sortedUpcoming;
          _notificationCount     = NotifReadStore.unreadNotifier.value;
          _homeLoading           = false;
          _homeRefreshing        = false;
        });
        if (!silent) _staggerCtrl.forward(from: 0);
      }
    } catch (e) {
      debugPrint('StudentDashboard load error: $e');
      if (mounted) {
        setState(() { _homeLoading = false; _homeRefreshing = false; });
        if (!silent) _staggerCtrl.forward(from: 0);
      }
    }
  }

  // ── Realtime ─────────────────────────────────────────────────────────────

  void _subscribeToCheckInRequests() {
    _regChannel = RegistrationService.subscribeToMyRegistrations((record) {
      if (!mounted) return;
      final status = record['status'] as String?;
      final regId  = record['id']     as String?;
      if (status == 'photo_required' && regId != null && !_selfiePrompted.contains(regId)) {
        _selfiePrompted.add(regId);
        _openSelfieScreen(regId);
      }
    });
  }

  void _openSelfieScreen(String registrationId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SelfieScreen(registrationId: registrationId),
        fullscreenDialog: true,
      ),
    ).then((submitted) {
      if (submitted != true) _selfiePrompted.remove(registrationId);
    });
  }

  void _showAnnouncementDetail(Map<String, dynamic> ann) {
    final title     = ann['title']   as String? ?? '—';
    final message   = ann['message'] as String? ?? '';
    final createdAt = ann['created_at'] as String?;

    NotifReadStore.mark('ann_${ann['id']}');

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (_, scrollCtrl) {
          final t = AppTk(Theme.of(context).brightness == Brightness.dark);
          return Container(
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: t.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: kGold.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.campaign_rounded, color: kGold, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700, color: t.text)),
                            if (createdAt != null)
                              Text(_fmtTime(createdAt), style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: t.sub, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                Divider(height: 24, indent: 20, endIndent: 20, color: t.divider),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    children: [
                      Text(
                        message.isNotEmpty ? message : 'No message content.',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: t.sub, height: 1.75),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ).then((_) { if (mounted) setState(() {}); });
  }

  void _showNextEventQR(Map<String, dynamic> reg) {
    final qrCode = reg['qr_code'] as String?;
    if (qrCode == null || qrCode.isEmpty) return;
    QRCodeDialog.show(
      context,
      EventRegistration(
        registrationId:   reg['id']               as String,
        eventId:          reg['event_id']          as String,
        eventTitle:       reg['event_title']       as String? ?? '',
        studentId:        reg['student_school_id'] as String? ?? '',
        studentName:      reg['student_name']      as String? ?? '',
        registrationDate: DateTime.tryParse(reg['registered_at'] as String? ?? '') ?? DateTime.now(),
        qrCodeData:       qrCode,
      ),
    );
  }

  void _navigateToEventDetail(Map<String, dynamic> reg) {
    final raw = reg['events'];
    if (raw == null) return;
    final evMap = Map<String, dynamic>.from(raw as Map);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventDetailsPage(event: evMap, registration: reg),
      ),
    ).then((_) { if (mounted) _loadHomeData(silent: true); });
  }

  // Returns true if any registration in [regs] has an event that is currently
  // ongoing (started but not yet ended), so the LIVE chip is only shown when
  // something is actually happening right now.
  bool _isAnyEventLive(List<Map<String, dynamic>> regs) {
    final now = DateTime.now();
    for (final reg in regs) {
      final evMap = reg['events'] as Map?;
      final dStr  = evMap?['event_date'] as String?;
      if (dStr == null) continue;
      try {
        final d = DateTime.parse(dStr);
        final sTime = evMap?['start_time'] as String?;
        DateTime startTime;
        if (sTime != null) {
          final p = sTime.split(':');
          startTime = DateTime(d.year, d.month, d.day,
              int.tryParse(p[0]) ?? 8,
              p.length > 1 ? (int.tryParse(p[1]) ?? 0) : 0);
        } else {
          startTime = DateTime(d.year, d.month, d.day, 8);
        }
        final eTime = evMap?['end_time'] as String?;
        DateTime? endTime;
        if (eTime != null) {
          final ep = eTime.split(':');
          endTime = DateTime(d.year, d.month, d.day,
              int.tryParse(ep[0]) ?? 23,
              ep.length > 1 ? (int.tryParse(ep[1]) ?? 59) : 59);
        }
        final started = !now.isBefore(startTime);
        final ended   = endTime != null && now.isAfter(endTime);
        if (started && !ended) return true;
      } catch (_) {}
    }
    return false;
  }

  void _onNavBarTapped(int index) {
    HapticFeedback.selectionClick();
    setState(() => _selectedIndex = index);
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
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            _buildHomeScreen(t),
            const StudentAllEventsPage(showAsEmbedded: true),
            const ProfileBody(showAsEmbedded: true),
          ],
        ),
      ),
      floatingActionButton: const AiChatFab(userRole: 'student'),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: _buildBottomNav(t),
    );
  }

  Widget _stagger(Widget child, {required double start, required double end}) {
    return AnimatedBuilder(
      animation: _staggerCtrl,
      builder: (_, c) {
        final raw = ((_staggerCtrl.value - start) / (end - start)).clamp(0.0, 1.0);
        final t  = Curves.easeOut.transform(raw);
        final ts = Curves.easeOutCubic.transform(raw);
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 16.0 * (1 - ts)), child: c),
        );
      },
      child: child,
    );
  }

  // ── Home screen ───────────────────────────────────────────────────────────

  Widget _buildHomeScreen(AppTk t) {
    if (_homeLoading) {
      return Container(
        color: t.bg,
        child: const AppFullScreenLoader(message: 'Loading your dashboard…'),
      );
    }

    return Column(
      children: [
        // Thin progress bar during silent refresh
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          height: _homeRefreshing ? 3 : 0,
          child: LinearProgressIndicator(
            color: kGold,
            backgroundColor: kGold.withValues(alpha: 0.15),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: kGold,
            backgroundColor: t.card,
            onRefresh: () => _loadHomeData(silent: true),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _stagger(_buildHeader(t),               start: 0.00, end: 0.34)),
                SliverToBoxAdapter(child: _stagger(_buildStatsCard(t),            start: 0.07, end: 0.44)),
                SliverToBoxAdapter(child: _stagger(_buildLiveBanner(t),           start: 0.16, end: 0.52)),
                SliverToBoxAdapter(child: _stagger(_buildAnnouncementsSection(t), start: 0.24, end: 0.65)),
                const SliverToBoxAdapter(child: SizedBox(height: 36)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader(AppTk t) {
    final firstName = (_studentName ?? 'Student').split(' ').first;

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
                    _DateChip(t: t),
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
          _buildNotificationBell(t),
        ],
      ),
    );
  }

  Widget _buildNotificationBell(AppTk t) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const NotificationsScreen(markAllRead: true),
          ),
        );
      },
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
                color: _notificationCount > 0
                    ? kGold.withValues(alpha: 0.35)
                    : t.border,
              ),
              boxShadow: [
                BoxShadow(color: t.shadow, blurRadius: 10, offset: const Offset(0, 3)),
              ],
            ),
            child: Center(
              child: Icon(
                _notificationCount > 0
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
                color: _notificationCount > 0 ? kGold : t.sub,
                size: 22,
              ),
            ),
          ),
          if (_notificationCount > 0)
            Positioned(
              top: -2, right: -2,
              child: Container(
                width: 18, height: 18,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  shape: BoxShape.circle,
                  border: Border.all(color: t.bg, width: 2),
                ),
                child: Center(
                  child: Text(
                    _notificationCount > 9 ? '9+' : '$_notificationCount',
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
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LIVE BANNER — registered upcoming events
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildLiveBanner(AppTk t) {
    final regs = _upcomingRegistrations;
    if (regs.isEmpty) return _buildExploreCard(t);

    final hasLive = _isAnyEventLive(regs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(
            children: [
              _SectionLabel(label: 'MY UPCOMING EVENTS', t: t),
              if (hasLive) ...[
                const SizedBox(width: 10),
                const _LivePulseDot(),
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.25)),
                  ),
                  child: const Text(
                    'LIVE',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ),
              ],
              if (regs.length > 1) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: kGold.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: kGold.withValues(alpha: 0.22)),
                  ),
                  child: Text(
                    '${regs.length} events',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: kGold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _buildMainEventBannerCard(regs.first, t),
        ),
        if (regs.length > 1) _buildMoreRegisteredStrip(regs.sublist(1), t),
      ],
    );
  }

  Widget _buildExploreCard(AppTk t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kGold.withValues(alpha: 0.22)),
          boxShadow: [BoxShadow(color: t.shadow, blurRadius: 14, offset: const Offset(0, 4))],
        ),
        child: Column(
          children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: kGold.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kGold.withValues(alpha: 0.22)),
              ),
              child: const Icon(Icons.event_available_rounded, size: 26, color: kGold),
            ),
            const SizedBox(height: 14),
            Text(
              'No Upcoming Events',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "You haven't registered for any events yet.\nExplore what's happening around you.",
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11.5,
                color: t.muted,
                height: 1.55,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                _onNavBarTapped(1);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFC49230), kGold, Color(0xFFEAB866)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: kGold.withValues(alpha: 0.32),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Browse Events',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, size: 15, color: Colors.white),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainEventBannerCard(Map<String, dynamic> reg, AppTk t) {
    final evMap   = reg['events'] as Map?;
    final title   = reg['event_title'] as String? ?? '—';
    final dStr    = evMap?['event_date'] as String?;
    if (dStr == null) return const SizedBox.shrink();

    DateTime  startTime;
    DateTime? endTime;
    try {
      final d     = DateTime.parse(dStr);
      final sTime = evMap?['start_time'] as String?;
      if (sTime != null) {
        final p = sTime.split(':');
        final h = int.tryParse(p[0]) ?? 8;
        final m = p.length > 1 ? (int.tryParse(p[1]) ?? 0) : 0;
        startTime = DateTime(d.year, d.month, d.day, h, m);
      } else {
        startTime = DateTime(d.year, d.month, d.day, 8);
      }
      final eTime = evMap?['end_time'] as String?;
      if (eTime != null) {
        final ep = eTime.split(':');
        final eh = int.tryParse(ep[0]) ?? 23;
        final em = ep.length > 1 ? (int.tryParse(ep[1]) ?? 59) : 59;
        endTime = DateTime(d.year, d.month, d.day, eh, em);
      }
    } catch (_) { return const SizedBox.shrink(); }

    final EventPhase initPhase = resolveEventPhase(startTime, endTime);
    final target = startTime;

    final location = evMap?['location'] as String? ?? '';
    final imageUrl = evMap?['event_image_url'] as String?;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    const months   = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final fmtDate  = '${months[target.month - 1]} ${target.day}';

    return GestureDetector(
      onTap: () => _navigateToEventDetail(reg),
      child: Container(
        height: 196,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: kGold.withValues(alpha: 0.28),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background
            hasImage
                ? Image.network(imageUrl, fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _goldGradientBg())
                : _goldGradientBg(),
            // Scrim
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: hasImage ? 0.08 : 0.0),
                    Colors.black.withValues(alpha: 0.76),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.2, 1.0],
                ),
              ),
            ),
            // Top-left phase pill
            Positioned(
              top: 14, left: 14,
              child: EventPhasePill(phase: initPhase),
            ),
            // Top-right QR chip — independent tap target to show the QR dialog
            // directly without navigating to the event detail page.
            Positioned(
              top: 14, right: 14,
              child: GestureDetector(
                onTap: () => _showNextEventQR(reg),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.40), width: 1.2),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.qr_code_2_rounded, size: 13, color: Colors.white),
                      SizedBox(width: 5),
                      Text('My QR', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
            // Bottom content
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.calendar_today_rounded, size: 11, color: Colors.white70),
                              const SizedBox(width: 4),
                              Text(fmtDate, style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white70)),
                              if (location.isNotEmpty) ...[
                                const Text(' · ', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white38)),
                                const Icon(Icons.location_on_outlined, size: 11, color: Colors.white70),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    location,
                                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white70),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    EventStatusTimer(start: startTime, end: endTime),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoreRegisteredStrip(List<Map<String, dynamic>> regs, AppTk t) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Also coming up',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: t.muted,
              ),
            ),
          ),
          SizedBox(
            height: 82,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 20, right: 8),
              itemCount: regs.length,
              itemBuilder: (_, i) => _buildCompactRegCard(regs[i], t),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactRegCard(Map<String, dynamic> reg, AppTk t) {
    final evMap    = reg['events'] as Map?;
    final title    = reg['event_title'] as String? ?? '—';
    final dStr     = evMap?['event_date'] as String?;
    final imageUrl = evMap?['event_image_url'] as String?;

    String dateLabel = '';
    if (dStr != null) {
      try {
        final d = DateTime.parse(dStr);
        const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
        dateLabel = '${m[d.month - 1]} ${d.day}';
      } catch (_) {}
    }

    return GestureDetector(
      onTap: () => _navigateToEventDetail(reg),
      child: Container(
        width: 210,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.border),
          boxShadow: [BoxShadow(color: t.shadow, blurRadius: 8, offset: const Offset(0, 3))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            SizedBox(
              width: 72,
              height: 82,
              child: imageUrl != null && imageUrl.isNotEmpty
                  ? Image.network(imageUrl, fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _imagePlaceholder())
                  : _imagePlaceholder(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, fontWeight: FontWeight.w700, color: t.text, height: 1.3),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (dateLabel.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 9, color: kGold),
                          const SizedBox(width: 4),
                          Text(dateLabel, style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: t.sub)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
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
  // STATS CARD — unified horizontal card
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildStatsCard(AppTk t) {
    final hasData = _totalRegistrations > 0;
    final rate    = hasData ? _attendedCount / _totalRegistrations : 0.0;

    void goToMyEvents() => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MyRegisteredEventsPage()),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(label: 'YOUR OVERVIEW', t: t),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: t.border),
              boxShadow: [BoxShadow(color: t.shadow, blurRadius: 16, offset: const Offset(0, 4))],
            ),
            child: Column(
              children: [
                IntrinsicHeight(
                  child: Row(
                    children: [
                      _statCell('$_totalRegistrations', 'Registered',
                          Icons.how_to_reg_rounded, kGold, t,
                          onTap: goToMyEvents),
                      _VertDivider(t: t),
                      _statCell('$_attendedCount', 'Attended',
                          Icons.check_circle_rounded, const Color(0xFF16A34A), t,
                          onTap: goToMyEvents),
                      _VertDivider(t: t),
                      _statCell('$_upcomingCount', 'Upcoming',
                          Icons.event_rounded, const Color(0xFF3B82F6), t,
                          onTap: () => _onNavBarTapped(1)),
                    ],
                  ),
                ),
                if (hasData) _buildAttendanceRate(rate, t),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceRate(double rate, AppTk t) {
    final pct   = (rate * 100).round();
    final color = rate >= 0.7
        ? const Color(0xFF16A34A)
        : rate >= 0.4 ? kGold : const Color(0xFFEF4444);
    return Column(
      children: [
        Divider(height: 1, color: t.divider),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    'Attendance rate',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: t.muted,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$pct%  ·  $_attendedCount of $_totalRegistrations attended',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: rate),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOut,
                  builder: (_, v, child) => LinearProgressIndicator(
                    value: v,
                    minHeight: 5,
                    backgroundColor: t.shimmer1,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statCell(String value, String label, IconData icon, Color color, AppTk t,
      {VoidCallback? onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap == null ? null : () {
          HapticFeedback.selectionClick();
          onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: t.text,
                      height: 1.0,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(icon, color: color, size: 15),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: t.muted,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: 22,
                height: 2.5,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ANNOUNCEMENTS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildAnnouncementsSection(AppTk t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SectionLabel(label: 'ANNOUNCEMENTS', t: t),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                ),
                child: Row(
                  children: [
                    Text('See all', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700, color: kGold)),
                    const SizedBox(width: 2),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 11, color: kGold),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _announcements.isEmpty
              ? _emptyState(
                  icon: Icons.campaign_outlined,
                  title: 'No announcements yet',
                  subtitle: 'Updates from organizers will appear here.',
                  t: t,
                )
              : Container(
                  decoration: BoxDecoration(
                    color: t.card,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: t.border),
                    boxShadow: [BoxShadow(color: t.shadow, blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: _announcements.asMap().entries.map((entry) {
                      return _announcementItem(
                        entry.value,
                        showDivider: entry.key < _announcements.length - 1,
                        t: t,
                      );
                    }).toList(),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _announcementItem(Map<String, dynamic> ann, {required bool showDivider, required AppTk t}) {
    final title     = ann['title']      as String? ?? '—';
    final createdAt = ann['created_at'] as String?;
    final annId     = ann['id']?.toString() ?? '';
    final isRead    = NotifReadStore.isRead('ann_$annId');

    return GestureDetector(
      onTap: () => _showAnnouncementDetail(ann),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: isRead ? t.divider : kGold,
                  width: 3,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: isRead
                          ? t.shimmer1
                          : kGold.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.campaign_rounded,
                      size: 17,
                      color: isRead ? t.muted : kGold,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                            color: isRead ? t.sub : t.text,
                            height: 1.35,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _fmtTime(createdAt),
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5, color: t.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right_rounded, size: 18, color: t.muted),
                ],
              ),
            ),
          ),
          if (showDivider)
            Divider(height: 1, color: t.divider, indent: 16, endIndent: 0),
        ],
      ),
    );
  }



  // ── Shared helpers ────────────────────────────────────────────────────────

  Widget _imagePlaceholder() {
    return Container(
      color: kGold.withValues(alpha: 0.07),
      child: Center(child: Icon(Icons.image_outlined, size: 26, color: kGold.withValues(alpha: 0.35))),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required AppTk t,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          Container(
            width: 54, height: 54,
            decoration: BoxDecoration(
              color: kGold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kGold.withValues(alpha: 0.18)),
            ),
            child: Icon(icon, size: 26, color: kGold.withValues(alpha: 0.55)),
          ),
          const SizedBox(height: 14),
          Text(title, style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700, color: t.text), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: t.muted, height: 1.5), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BOTTOM NAVIGATION
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildBottomNav(AppTk t) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1C1814),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color:      Colors.black.withValues(alpha: 0.30),
              blurRadius: 16,
              offset:     const Offset(0, -2),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
        child: Row(
            children: [
              _NavItem(
                activeIcon:   Icons.home_rounded,
                inactiveIcon: Icons.home_outlined,
                label:        'Home',
                active:       _selectedIndex == 0,
                onTap:        () => _onNavBarTapped(0),
              ),
              _NavItem(
                activeIcon:   Icons.event_rounded,
                inactiveIcon: Icons.event_outlined,
                label:        'Events',
                active:       _selectedIndex == 1,
                onTap:        () => _onNavBarTapped(1),
              ),
              _NavItem(
                activeIcon:   Icons.person_rounded,
                inactiveIcon: Icons.person_outline_rounded,
                label:        'Profile',
                active:       _selectedIndex == 2,
                onTap:        () => _onNavBarTapped(2),
              ),
            ],
          ),
        ),
    );
  }
}


// ══════════════════════════════════════════════════════════════════════════════
// Sub-widgets
// ══════════════════════════════════════════════════════════════════════════════

class _NavItem extends StatefulWidget {
  final IconData     activeIcon;
  final IconData     inactiveIcon;
  final String       label;
  final bool         active;
  final VoidCallback onTap;

  const _NavItem({
    required this.activeIcon,
    required this.inactiveIcon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap:       widget.onTap,
        onTapDown:   (_) => setState(() => _pressed = true),
        onTapUp:     (_) => setState(() => _pressed = false),
        onTapCancel: ()  => setState(() => _pressed = false),
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale:    _pressed ? 0.90 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve:    Curves.easeOut,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve:    Curves.easeOut,
                padding:  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: widget.active
                      ? kGold.withValues(alpha: 0.18)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  widget.active ? widget.activeIcon : widget.inactiveIcon,
                  size:  22,
                  color: widget.active
                      ? kGold
                      : Colors.white.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                widget.label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize:   10,
                  fontWeight: widget.active ? FontWeight.w700 : FontWeight.w400,
                  color: widget.active
                      ? kGold
                      : Colors.white.withValues(alpha: 0.45),
                ),
                maxLines:  1,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final AppTk    t;

  const _SectionLabel({required this.label, required this.t});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 3, height: 13,
          decoration: BoxDecoration(
            color: kGold,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: t.muted,
            letterSpacing: 1.4,
          ),
        ),
      ],
    );
  }
}

class _VertDivider extends StatelessWidget {
  final AppTk t;
  const _VertDivider({required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 16),
      color: t.divider,
    );
  }
}

class _DateChip extends StatelessWidget {
  final AppTk t;
  const _DateChip({required this.t});

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

class _LivePulseDot extends StatefulWidget {
  const _LivePulseDot();
  @override
  State<_LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<_LivePulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _fade = Tween<double>(begin: 0.25, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Container(
        width: 7, height: 7,
        decoration: const BoxDecoration(
          color: Color(0xFF10B981),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

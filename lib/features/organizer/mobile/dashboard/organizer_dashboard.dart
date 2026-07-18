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


// ── Notification data model ───────────────────────────────────────────────────

class _AppNotif {
  final String   id;
  final String   title;
  final String   subtitle;
  final IconData icon;
  final Color    color;
  const _AppNotif({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

String _fmtNotifTime(String? t) {
  if (t == null || t.isEmpty) return '';
  try {
    final parts  = t.split(':');
    final h      = int.parse(parts[0]);
    final m      = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    final period = h >= 12 ? 'PM' : 'AM';
    final h12    = h == 0 ? 12 : h > 12 ? h - 12 : h;
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
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;

  late final AnimationController _staggerCtrl;

  // Home tab state
  bool    _homeLoading  = true;
  bool    _dashError    = false;
  bool    _hasAnyEvents = false;
  String? _organizerName;

  // Analytics data
  List<double> _dailyRegistrations = List.filled(7, 0);
  int          _totalRegsThisWeek  = 0;
  List<Map<String, dynamic>> _eventAttendance = [];
  DateTime?    _lastUpdated;
  Map<String, dynamic>? _nextEvent;
  List<_AppNotif>       _notifs      = [];
  bool                  _notifsRead  = false;

  @override
  void initState() {
    super.initState();
    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _loadData();
  }

  @override
  void dispose() {
    _staggerCtrl.dispose();
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() { _homeLoading = true; _dashError = false; });
    try {
      final client = Supabase.instance.client;
      final user   = client.auth.currentUser;
      if (user == null) {
        setState(() => _homeLoading = false);
        _staggerCtrl.forward(from: 0);
        return;
      }

      final orgRow = await client
          .from('organizers')
          .select('organizer_id, full_name, organization')
          .eq('user_id', user.id)
          .maybeSingle();

      if (orgRow == null) {
        setState(() => _homeLoading = false);
        _staggerCtrl.forward(from: 0);
        return;
      }

      final organizerId = orgRow['organizer_id'] as String;

      final eventRows = await client
          .from('events')
          .select('event_id, title, event_date, start_time, end_time, event_status, event_image_url, max_participants')
          .eq('organizer_id', organizerId)
          .order('event_date', ascending: true);

      final allEvents = List<Map<String, dynamic>>.from(eventRows as List);
      final eventIds  = allEvents.map((e) => e['event_id'] as String).toList();

      List<Map<String, dynamic>> regList = [];
      if (eventIds.isNotEmpty) {
        final regRows = await client
            .from('registrations')
            .select('id, status, event_id, registered_at')
            .in_('event_id', eventIds);
        regList = List<Map<String, dynamic>>.from(regRows as List);
      }

      // Daily registrations this week (Mon=0 … Sun=6)
      final dailyRegs  = List<double>.filled(7, 0);
      final now        = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final weekStart  = todayStart.subtract(Duration(days: now.weekday - 1));

      for (final r in regList) {
        final dateStr = r['registered_at'] as String?;
        if (dateStr == null) continue;
        try {
          final date      = DateTime.parse(dateStr).toLocal();
          final dateStart = DateTime(date.year, date.month, date.day);
          if (!dateStart.isBefore(weekStart) &&
              !dateStart.isAfter(todayStart)) {
            final dayIdx = date.weekday - 1;
            if (dayIdx >= 0 && dayIdx < 7) dailyRegs[dayIdx]++;
          }
        } catch (_) {}
      }

      // Event attendance: last 5 events
      final last5 = allEvents.length > 5
          ? allEvents.sublist(allEvents.length - 5)
          : allEvents;

      final attendance = last5.map((e) {
        final eid       = e['event_id'] as String;
        final checkedIn = regList.where((r) =>
            r['event_id'] == eid && r['status'] == 'checked_in').length;
        final total     = regList.where((r) => r['event_id'] == eid).length;

        String label = '—';
        final dStr = e['event_date'] as String?;
        if (dStr != null) {
          try {
            final dt = DateTime.parse(dStr);
            const m  = ['Jan','Feb','Mar','Apr','May','Jun',
                        'Jul','Aug','Sep','Oct','Nov','Dec'];
            label = '${m[dt.month - 1]}\n${dt.day}';
          } catch (_) {}
        }

        return <String, dynamic>{
          'label':           label,
          'title':           (e['title'] as String?) ?? '—',
          'checkedIn':       checkedIn,
          'total':           total,
          'maxParticipants': (e['max_participants'] as int?) ?? 0,
        };
      }).toList();

      // Find the next upcoming event (allEvents sorted ascending by event_date)
      Map<String, dynamic>? nextEvt;
      for (final e in allEvents) {
        final status = (e['event_status'] as String? ?? '').toLowerCase();
        if (status == 'cancelled' || status == 'completed' || status == 'past') continue;
        final dStr = e['event_date'] as String?;
        if (dStr == null) continue;
        try {
          final d = DateTime.parse(dStr);
          if (!d.isBefore(todayStart)) { nextEvt = e; break; }
        } catch (_) {}
      }

      // Build notifications from already-loaded data (no extra queries needed)
      final notifTodayStr = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
      final notifTomDt    = now.add(const Duration(days: 1));
      final notifTomStr   = '${notifTomDt.year}-${notifTomDt.month.toString().padLeft(2,'0')}-${notifTomDt.day.toString().padLeft(2,'0')}';
      final notifResult   = <_AppNotif>[];

      final todayRegCount = regList.where((r) {
        final ds = r['registered_at'] as String?;
        if (ds == null) return false;
        try { return !DateTime.parse(ds).toLocal().isBefore(todayStart); }
        catch (_) { return false; }
      }).length;
      if (todayRegCount > 0) {
        notifResult.add(_AppNotif(
          id:       'signups_today_$notifTodayStr',
          title:    '$todayRegCount new sign-up${todayRegCount == 1 ? '' : 's'} today',
          subtitle: 'Students registered for your events',
          icon:     Icons.how_to_reg_rounded,
          color:    const Color(0xFF8B5CF6),
        ));
      }

      for (final e in allEvents.where((e) => e['event_status'] == 'ongoing').take(3)) {
        notifResult.add(_AppNotif(
          id:       'event_live_${e['event_id']}',
          title:    e['title'] as String? ?? '—',
          subtitle: 'Event is live · check in students now',
          icon:     Icons.radio_button_checked_rounded,
          color:    const Color(0xFF10B981),
        ));
      }

      for (final e in allEvents.where((e) =>
          e['event_status'] == 'upcoming' &&
          (e['event_date'] as String?) == notifTodayStr).take(3)) {
        final t = _fmtNotifTime(e['start_time'] as String?);
        notifResult.add(_AppNotif(
          id:       'event_today_${e['event_id']}',
          title:    e['title'] as String? ?? '—',
          subtitle: 'Starting today${t.isNotEmpty ? ' at $t' : ''}',
          icon:     Icons.today_rounded,
          color:    const Color(0xFF3B82F6),
        ));
      }

      for (final e in allEvents.where((e) =>
          e['event_status'] == 'upcoming' &&
          (e['event_date'] as String?) == notifTomStr).take(2)) {
        final t = _fmtNotifTime(e['start_time'] as String?);
        notifResult.add(_AppNotif(
          id:       'event_tomorrow_${e['event_id']}',
          title:    e['title'] as String? ?? '—',
          subtitle: 'Starting tomorrow${t.isNotEmpty ? ' at $t' : ''}',
          icon:     Icons.calendar_month_rounded,
          color:    const Color(0xFFF59E0B),
        ));
      }

      if (mounted) {
        final alreadyRead = await _wasAlreadyRead(user.id, notifResult);
        if (!mounted) return;
        setState(() {
          _organizerName      = orgRow['full_name']    as String? ?? 'Organizer';
          _dailyRegistrations = dailyRegs;
          _totalRegsThisWeek  = dailyRegs.fold(0, (s, v) => s + v.toInt());
          _eventAttendance    = attendance;
          _nextEvent          = nextEvt;
          _hasAnyEvents       = allEvents.isNotEmpty;
          _notifs             = notifResult;
          _notifsRead         = alreadyRead;
          _lastUpdated        = DateTime.now();
          _homeLoading        = false;
        });
        _staggerCtrl.forward(from: 0);
      }
    } catch (e) {
      debugPrint('OrganizerDashboard load error: $e');
      if (mounted) setState(() { _homeLoading = false; _dashError = true; });
    }
  }

  // ── Camera / QR ───────────────────────────────────────────────────────────

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60)  return 'Updated just now';
    if (diff.inMinutes < 60)  return 'Updated ${diff.inMinutes}m ago';
    if (diff.inHours < 24)    return 'Updated ${diff.inHours}h ago';
    return 'Updated ${diff.inDays}d ago';
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const QRScannerScreen()),
        );
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
    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        // IndexedStack keeps all tabs alive so they preserve scroll position
        // and don't re-fetch when the user switches tabs.
        // Indices: 0=Home, 1=Events, 2=Registrations, 3=Profile
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            _buildHomeContent(),
            const events.OrganizerEventsScreen(showAsEmbedded: true),
            const regs.RegistrationsScreen(showAsEmbedded: true),
            const OrganizerProfileScreen(showAsEmbedded: true),
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
        final raw = ((_staggerCtrl.value - start) / (end - start)).clamp(0.0, 1.0);
        final t  = Curves.easeOut.transform(raw);
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
    final prefs    = await SharedPreferences.getInstance();
    final existing = Set<String>.from(prefs.getStringList(_prefKey(userId)) ?? []);
    existing.addAll(_notifs.map((n) => n.id));
    final list    = existing.toList();
    final trimmed = list.length > 200 ? list.sublist(list.length - 200) : list;
    await prefs.setStringList(_prefKey(userId), trimmed);
  }

  Future<bool> _wasAlreadyRead(String userId, List<_AppNotif> notifs) async {
    if (notifs.isEmpty) return true;
    final prefs   = await SharedPreferences.getInstance();
    final readIds = Set<String>.from(prefs.getStringList(_prefKey(userId)) ?? []);
    return notifs.every((n) => readIds.contains(n.id));
  }

  Widget _buildHomeContent() {
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
                child: const Icon(Icons.cloud_off_rounded, size: 36, color: Color(0xFFEF4444)),
              ),
              const SizedBox(height: 20),
              const Text(
                'Could not load dashboard',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: kText,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Check your connection and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: kSubText,
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
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: kGold,
      onRefresh: _loadData,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _stagger(_buildHeader(),            start: 0.00, end: 0.38)),
          SliverToBoxAdapter(child: _stagger(_buildUpcomingCountdown(), start: 0.10, end: 0.48)),
          SliverToBoxAdapter(child: _stagger(_buildAnnouncementsCard(), start: 0.20, end: 0.58)),
          SliverToBoxAdapter(child: _stagger(
            _hasAnyEvents ? _buildAnalyticsSection() : _buildEmptyStateCTA(),
            start: 0.32, end: 0.72,
          )),
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
          _buildBellButton(t),
        ],
      ),
    );
  }

  // ── Notification bell button ──────────────────────────────────────────────

  Widget _buildBellButton(AppTk t) {
    final hasUnread = _notifs.isNotEmpty && !_notifsRead;
    return GestureDetector(
      onTap: _showNotificationSheet,
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
                BoxShadow(color: t.shadow, blurRadius: 10, offset: const Offset(0, 3)),
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
                  color: const Color(0xFFEF4444),
                  shape: BoxShape.circle,
                  border: Border.all(color: t.bg, width: 2),
                ),
                child: Center(
                  child: Text(
                    _notifs.length > 9 ? '9+' : '${_notifs.length}',
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

  void _showNotificationSheet() {
    setState(() => _notifsRead = true);
    _persistReadState(); // fire-and-forget — survives logout/login
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _NotifSheet(notifs: _notifs),
    );
  }

  // ── Announcements card ────────────────────────────────────────────────────

  Widget _buildAnnouncementsCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: kText,
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AnnouncementsScreen()),
              ),
              borderRadius: BorderRadius.circular(16),
              child: Ink(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: const Color(0xFFE87A00).withValues(alpha: 0.2)),
                  boxShadow: [
                    BoxShadow(
                      color: kText.withValues(alpha: 0.05),
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
                          color: const Color(0xFFE87A00)
                              .withValues(alpha: 0.1),
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
                            const Text(
                              'Announcements',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: kText,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Post updates and notices for students',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color: kSubText.withValues(alpha: 0.8),
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
                          color: const Color(0xFFE87A00)
                              .withValues(alpha: 0.08),
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

  Widget _buildAnalyticsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAnalyticsHeader(),
          const SizedBox(height: 16),
          _buildRegistrationsCard(),
          const SizedBox(height: 14),
          _buildAttendanceCard(),
        ],
      ),
    );
  }

  // ── Section header ────────────────────────────────────────────────────────

  Widget _buildAnalyticsHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 8, height: 8,
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
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Analytics',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 18,
                  fontWeight: FontWeight.w800, color: kText, height: 1.1,
                ),
              ),
              Text(
                'Live event performance data',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: kMuted),
              ),
            ],
          ),
        ),
        if (_lastUpdated != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6, offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.access_time_rounded, size: 11, color: kMuted),
                const SizedBox(width: 4),
                Text(
                  _timeAgo(_lastUpdated!),
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 10, color: kMuted),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── Registrations card (white + purple) ──────────────────────────────────

  Widget _buildRegistrationsCard() {
    const purple = Color(0xFF7C3AED);
    const indigo = Color(0xFF4F46E5);
    const green  = Color(0xFF059669);

    final todayIdx   = DateTime.now().weekday - 1;
    final todayCount = _dailyRegistrations[todayIdx].toInt();
    final peak       = _getPeakDay();

    final avgNum = _totalRegsThisWeek > 0 ? _totalRegsThisWeek / 7 : 0.0;
    final avgStr = avgNum == avgNum.toInt().toDouble()
        ? avgNum.toInt().toString()
        : avgNum.toStringAsFixed(1);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
          Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: purple.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.how_to_reg_rounded, color: purple, size: 19),
            ),
            const SizedBox(width: 11),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Weekly Registrations',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700, color: kText),
                  ),
                  Text(
                    'Sign-up activity · this week',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: kMuted),
                  ),
                ],
              ),
            ),
          ]),

          const SizedBox(height: 16),

          // ── KPI chips ────────────────────────────────────────────────
          Row(children: [
            _kpiChip(
              value: '$_totalRegsThisWeek',
              label: 'This Week',
              icon: Icons.how_to_reg_rounded,
              color: purple,
            ),
            const SizedBox(width: 10),
            _kpiChip(
              value: peak != null ? '${peak['count']}' : '—',
              label: peak != null ? 'Peak · ${peak['label']}' : 'Peak Day',
              icon: Icons.trending_up_rounded,
              color: indigo,
            ),
            const SizedBox(width: 10),
            _kpiChip(
              value: '$todayCount',
              label: 'Today',
              icon: Icons.today_rounded,
              color: green,
            ),
          ]),

          if (_totalRegsThisWeek > 0) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Daily average this week',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w500, color: kSubText),
                ),
                Text(
                  '$avgStr / day',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, color: purple),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: TweenAnimationBuilder<double>(
                tween: Tween(
                  begin: 0,
                  end: (todayCount / _totalRegsThisWeek).clamp(0.0, 1.0),
                ),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOut,
                builder: (_, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade100,
                  valueColor: const AlwaysStoppedAnimation<Color>(purple),
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // ── Bar chart ────────────────────────────────────────────────
          SizedBox(height: 185, child: _buildDailyBarChart()),

          if (_dailyRegistrations.any((v) => v > 0)) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendItem(color: purple, label: 'Registrations'),
                const SizedBox(width: 20),
                _legendItem(color: kGold, label: 'Today'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Map<String, dynamic>? _getPeakDay() {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    double maxVal = 0;
    int    maxIdx = -1;
    for (int i = 0; i < _dailyRegistrations.length; i++) {
      if (_dailyRegistrations[i] > maxVal) {
        maxVal = _dailyRegistrations[i];
        maxIdx = i;
      }
    }
    if (maxIdx == -1 || maxVal == 0) return null;
    return {'label': labels[maxIdx], 'count': maxVal.toInt()};
  }

  // ── Bar chart: daily registrations (light-card version) ─────────────────

  Widget _buildDailyBarChart() {
    const purple   = Color(0xFF7C3AED);
    const labels   = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final rawMax   = _dailyRegistrations.reduce(max);
    final barMaxY  = max(rawMax + 1.5, 5.0);
    final todayIdx = DateTime.now().weekday - 1;

    if (rawMax == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 62, height: 62,
              decoration: BoxDecoration(
                color: purple.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.bar_chart_rounded, size: 30, color: purple),
            ),
            const SizedBox(height: 14),
            const Text(
              'No registrations this week',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w600, color: kText),
            ),
            const SizedBox(height: 4),
            const Text(
              'Appears once students sign up',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: kMuted),
            ),
          ],
        ),
      );
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: barMaxY,
        minY: 0,
        barGroups: List.generate(7, (i) {
          final isToday = i == todayIdx;
          final value   = _dailyRegistrations[i];
          return BarChartGroupData(
            x: i,
            showingTooltipIndicators: value > 0 ? [0] : [],
            barRods: [
              BarChartRodData(
                toY: value > 0 ? value : 0.18,
                gradient: isToday
                    ? const LinearGradient(
                        colors: [Color(0xFFC49230), Color(0xFFEAB866)],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      )
                    : value > 0
                        ? LinearGradient(
                            colors: [
                              purple.withValues(alpha: 0.50),
                              purple.withValues(alpha: 0.85),
                            ],
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                          )
                        : LinearGradient(
                            colors: [
                              Colors.grey.withValues(alpha: 0.10),
                              Colors.grey.withValues(alpha: 0.18),
                            ],
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                          ),
                width: 26,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
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
                if (i < 0 || i >= labels.length) return const SizedBox();
                final isToday = i == todayIdx;
                return SideTitleWidget(
                  meta: meta,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 5, height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isToday ? kGold : Colors.transparent,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        labels[i],
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                          color: isToday ? kGold : kMuted.withValues(alpha: 0.70),
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
                      color: kMuted.withValues(alpha: 0.70),
                    ),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color:       Colors.grey.withValues(alpha: 0.09),
            strokeWidth: 1,
            dashArray:   [4, 4],
          ),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF1C1814),
            tooltipBorder:   const BorderSide(color: Color(0xFF2C2419)),
            tooltipPadding:  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final v = _dailyRegistrations[group.x];
              if (v <= 0) return null;
              final isToday = group.x == todayIdx;
              return BarTooltipItem(
                '${v.toInt()} reg${v.toInt() == 1 ? '' : 's'}',
                const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                children: [
                  TextSpan(
                    text: isToday ? '\nToday' : '\n${labels[group.x]}',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w400,
                      fontSize: 10,
                      color: Colors.white60,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      duration: const Duration(milliseconds: 400),
      curve:    Curves.easeOut,
    );
  }

  // ── Attendance card (white + blue) ────────────────────────────────────────

  Widget _buildAttendanceCard() {
    const blue = Color(0xFF2563EB);

    final totalCheckedIn       = _eventAttendance.fold<int>(0, (s, e) => s + (e['checkedIn']       as int));
    final totalMaxParticipants = _eventAttendance.fold<int>(0, (s, e) => s + (e['maxParticipants'] as int));
    final totalRegistered      = _eventAttendance.fold<int>(0, (s, e) => s + (e['total']           as int));
    final rate = totalMaxParticipants > 0
        ? (totalCheckedIn / totalMaxParticipants * 100).round()
        : totalRegistered > 0 ? (totalCheckedIn / totalRegistered * 100).round() : 0;
    final rateColor = rate >= 70
        ? const Color(0xFF16A34A)
        : rate >= 40
            ? kGold
            : const Color(0xFFDC2626);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14, offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card header ──────────────────────────────────────────────
          Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: blue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.people_alt_rounded, color: blue, size: 19),
            ),
            const SizedBox(width: 11),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Event Attendance',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700, color: kText)),
                  Text('Attendance per event · last 5 events',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: kMuted)),
                ],
              ),
            ),
          ]),

          const SizedBox(height: 16),

          // ── KPI chips ────────────────────────────────────────────────
          Row(children: [
            _kpiChip(value: '$totalCheckedIn', label: 'Checked In', icon: Icons.check_circle_rounded, color: blue),
            const SizedBox(width: 10),
            _kpiChip(value: '$rate%',          label: 'Avg Rate',   icon: Icons.trending_up_rounded,  color: rateColor),
          ]),

          if (_eventAttendance.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Overall capacity filled',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w500, color: kSubText)),
                Text('$rate%',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, color: rateColor)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: totalMaxParticipants > 0
                    ? totalCheckedIn / totalMaxParticipants
                    : totalRegistered > 0 ? totalCheckedIn / totalRegistered : 0.0),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOut,
                builder: (_, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade100,
                  valueColor: AlwaysStoppedAnimation<Color>(rateColor),
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),
          _buildAttendanceBreakdown(),
        ],
      ),
    );
  }

  Widget _kpiChip({
    required String   value,
    required String   label,
    required IconData icon,
    required Color    color,
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
                fontFamily: 'Poppins', fontSize: 20,
                fontWeight: FontWeight.w800, color: color, height: 1.0,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 9, color: kMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendItem({required Color color, required String label}) {
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
        Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 10, color: kMuted)),
      ],
    );
  }

  // ── Per-event attendance breakdown (horizontal progress rows) ───────────

  Widget _buildAttendanceBreakdown() {
    const blue  = Color(0xFF2563EB);
    const green = Color(0xFF16A34A);
    const red   = Color(0xFFDC2626);

    if (_eventAttendance.isEmpty) {
      return Column(
        children: [
          const SizedBox(height: 8),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: blue.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.people_alt_rounded, size: 26, color: blue),
                ),
                const SizedBox(height: 12),
                const Text('No attendance data yet',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                    fontWeight: FontWeight.w600, color: kText)),
                const SizedBox(height: 4),
                const Text('Appears after your first check-in',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: kMuted)),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      );
    }

    return Column(
      children: _eventAttendance.asMap().entries.map((entry) {
        final idx             = entry.key;
        final e               = entry.value;
        final total           = e['total']           as int;
        final checkedIn       = e['checkedIn']       as int;
        final maxParticipants = e['maxParticipants'] as int;
        final title           = e['title']           as String;
        final dateLabel       = (e['label'] as String).replaceAll('\n', ' ');
        final rate            = maxParticipants > 0
            ? (checkedIn / maxParticipants * 100).round()
            : total > 0 ? (checkedIn / total * 100).round() : 0;
        final rateColor       = rate >= 70 ? green : rate >= 40 ? kGold : red;
        final fraction        = maxParticipants > 0
            ? (checkedIn / maxParticipants).clamp(0.0, 1.0)
            : total > 0 ? (checkedIn / total).clamp(0.0, 1.0) : 0.0;

        return Padding(
          padding: EdgeInsets.only(
            bottom: idx < _eventAttendance.length - 1 ? 14 : 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: rateColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                          style: const TextStyle(fontFamily: 'Poppins',
                            fontSize: 12, fontWeight: FontWeight.w600, color: kText),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(dateLabel,
                          style: const TextStyle(fontFamily: 'Poppins',
                            fontSize: 10, color: kMuted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: rateColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: rateColor.withValues(alpha: 0.25)),
                        ),
                        child: Text('$rate%',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                            fontWeight: FontWeight.w700, color: rateColor)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        maxParticipants > 0 ? '$checkedIn / $maxParticipants' : '$checkedIn',
                        style: const TextStyle(fontFamily: 'Poppins',
                          fontSize: 10, fontWeight: FontWeight.w500, color: kMuted)),
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

  Widget _buildEmptyStateCTA() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: kGold.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 80, height: 80,
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
              child: const Icon(Icons.event_note_rounded, size: 38, color: Colors.white),
            ),
            const SizedBox(height: 20),
            const Text(
              'No events yet',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: kText,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Create your first event to start managing\nregistrations and tracking attendance.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: kSubText,
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
    final dStr  = e['event_date'] as String?;
    if (dStr == null) return const SizedBox.shrink();

    DateTime start;
    DateTime? end;
    try {
      final d     = DateTime.parse(dStr);
      final sTime = e['start_time'] as String?;
      if (sTime != null) {
        final p = sTime.split(':');
        final h = int.tryParse(p[0]) ?? 0;
        final m = p.length > 1 ? (int.tryParse(p[1]) ?? 0) : 0;
        start = DateTime(d.year, d.month, d.day, h, m);
      } else {
        start = DateTime(d.year, d.month, d.day, 8);
      }
      final eTime = e['end_time'] as String?;
      if (eTime != null && eTime.isNotEmpty) {
        final p = eTime.split(':');
        final h = int.tryParse(p[0]) ?? 0;
        final m = p.length > 1 ? (int.tryParse(p[1]) ?? 0) : 0;
        end = DateTime(d.year, d.month, d.day, h, m);
      }
    } catch (_) {
      return const SizedBox.shrink();
    }

    final imageUrl = e['event_image_url'] as String?;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final fmtDate = '${months[start.month - 1]} ${start.day}, ${start.year}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Container(
        height: 188,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: kGold.withValues(alpha: 0.30), blurRadius: 20, offset: const Offset(0, 7)),
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
              start:   start,
              end:     end,
              title:   title,
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

  const _OrganizerBottomNavItem({
    required this.activeIcon,
    required this.inactiveIcon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
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
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: active
                  ? activeColor.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              active ? activeIcon : inactiveIcon,
              size: 22,
              color: active
                  ? activeColor
                  : Colors.white.withValues(alpha: 0.45),
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
  const _NotifSheet({required this.notifs});

  @override
  Widget build(BuildContext context) {
    final now       = DateTime.now();
    const days      = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    const months    = ['Jan','Feb','Mar','Apr','May','Jun',
                       'Jul','Aug','Sep','Oct','Nov','Dec'];
    final dateLabel = '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                const Icon(Icons.notifications_rounded, size: 18, color: kText),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Notifications',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: kText,
                    )),
                ),
                Text(dateLabel,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: kMuted,
                  )),
              ]),
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: Colors.grey.shade100),
            // Content
            if (notifs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
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
                      child: const Icon(Icons.check_circle_outline_rounded,
                        size: 26, color: Color(0xFF10B981)),
                    ),
                    const SizedBox(height: 14),
                    const Text("You're all caught up!",
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: kText,
                      ),
                      textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    const Text('No new events or sign-ups today.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: kMuted,
                      ),
                      textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                  ],
                ),
              )
            else
              ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: notifs.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: Colors.grey.shade100),
                itemBuilder: (_, i) => _buildItem(notifs[i]),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(_AppNotif n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(children: [
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
              Text(n.title,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: kText,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text(n.subtitle,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: kMuted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ]),
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
  final DateTime  start;
  final DateTime? end;
  final String    title;
  final String    fmtDate;

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
    final now     = DateTime.now();
    final started = now.isAfter(widget.start);
    final ended   = widget.end != null && now.isAfter(widget.end!);

    // Badge chip
    final String badgeText;
    final Color  badgeColor;
    if (ended) {
      badgeText  = 'ENDED';
      badgeColor = const Color(0xFF6B7280);
    } else if (started) {
      badgeText  = 'LIVE NOW';
      badgeColor = const Color(0xFF10B981);
    } else {
      badgeText  = 'NEXT EVENT';
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
          fontFamily: 'Poppins', fontSize: 14,
          fontWeight: FontWeight.w700, color: Colors.white60,
        ),
      );
    } else if (started && widget.end != null) {
      final diff = widget.end!.difference(now);
      final h    = diff.inHours;
      final m    = diff.inMinutes.remainder(60).toString().padLeft(2, '0');
      final s    = diff.inSeconds.remainder(60).toString().padLeft(2, '0');
      bottomRight = Text(
        h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s',
        style: const TextStyle(
          fontFamily: 'Poppins', fontSize: 22,
          fontWeight: FontWeight.w800, color: Colors.white,
        ),
      );
    } else {
      bottomRight = LiveCountdown(target: widget.start, textColor: Colors.white);
    }

    return Positioned(
      bottom: 0, left: 0, right: 0,
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badgeText,
                      style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 8,
                        fontWeight: FontWeight.w800, letterSpacing: 0.8,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 15,
                      fontWeight: FontWeight.w700, color: Colors.white, height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, size: 11, color: Colors.white70),
                      const SizedBox(width: 4),
                      Text(
                        widget.fmtDate,
                        style: const TextStyle(
                          fontFamily: 'Poppins', fontSize: 11, color: Colors.white70,
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
                    fontFamily: 'Poppins', fontSize: 9,
                    fontWeight: FontWeight.w700, letterSpacing: 1.0,
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


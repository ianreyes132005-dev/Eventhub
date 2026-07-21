  import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/app_colors.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/notif_read_store.dart';
import '../../../core/services/student_notif_prefs.dart';
import '../../../shared/widgets/app_loader.dart';

// ── Notification type ─────────────────────────────────────────────────────────

// ── Notification type ─────────────────────────────────────────────────────────
enum _NotifType { announcement, checkIn, selfieRequired, photoSubmitted }
// ── Notification model ────────────────────────────────────────────────────────
class _NotifItem {
  final String     id;
  final _NotifType type;
  final String     title;
  final String     preview;   // truncated for list card
  final String     fullBody;  // full text for detail sheet
  final DateTime   time;
  final String?    orgName;

  const _NotifItem({
    required this.id,
    required this.type,
    required this.title,
    required this.preview,
    required this.fullBody,
    required this.time,
    this.orgName,
  });

  bool get isRead => NotifReadStore.isRead(id);
}

// ── Time helpers ──────────────────────────────────────────────────────────────
String _timeAgo(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) { final m = diff.inMinutes; return '$m min${m == 1 ? '' : 's'} ago'; }
  if (diff.inHours   < 24) { final h = diff.inHours;   return '$h hr${h == 1 ? '' : 's'} ago';  }
  if (diff.inDays    < 7)  { final d = diff.inDays;     return '$d day${d == 1 ? '' : 's'} ago'; }
  const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${mo[t.month - 1]} ${t.day}';
}

String _groupLabel(DateTime t) {
  final now   = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final dt    = DateTime(t.year, t.month, t.day);
  final diff  = today.difference(dt).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff < 7)  return 'This Week';
  return 'Earlier';
}

String _preview(String s) =>
    s.length > 110 ? '${s.substring(0, 110)}…' : s;

// ── Screen ────────────────────────────────────────────────────────────────────
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.markAllRead = false});

  /// When true (opened via bell tap) all items are immediately marked read.
  final bool markAllRead;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {

  List<_NotifItem> _all      = [];
  List<_NotifItem> _filtered = [];
  bool _loading  = true;
  int  _tabIndex = 0;

  late final TabController _tabCtrl;
  RealtimeChannel? _realtimeChannel;

  static const _tabs = ['All', 'Announcements', 'My Events'];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        setState(() { _tabIndex = _tabCtrl.index; _applyFilter(); });
      }
    });
    _load();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    if (_realtimeChannel != null) {
      Supabase.instance.client.removeChannel(_realtimeChannel!);
    }
    super.dispose();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;
      final user   = client.auth.currentUser;
      if (user == null) { if (mounted) setState(() => _loading = false); return; }

      // Fetch announcements and registrations in parallel
      final annFuture = SupabaseService.getAnnouncements(limit: 50);
      final regFuture = client
          .from('registrations')
          .select()
          .eq('student_user_id', user.id)
          .order('registered_at', ascending: false);

      final annRows = await annFuture;
      final regRows = await regFuture as List;

      // Resolve organizer names for announcements
      final annUids = annRows.map((a) => a['created_by'] as String?).whereType<String>().toSet().toList();
      final Map<String, String> orgNames = {};
      if (annUids.isNotEmpty) {
        final orgRows = List<Map<String, dynamic>>.from(
          await SupabaseService.client
              .from('organizers')
              .select('user_id, full_name')
              .filter('user_id', 'in', '(${annUids.join(',')})'),
        );
        for (final o in orgRows) {
          orgNames[o['user_id'] as String] = o['full_name'] as String? ?? '—';
        }
      }

      final items = <_NotifItem>[];

      // ── Announcements ─────────────────────────────────────────────────────
      for (final ann in annRows) {
        final id      = ann['id']?.toString() ?? '';
        final raw     = ann['created_at'] as String?;
        final message = ann['message'] as String? ?? '';
        items.add(_NotifItem(
          id:       'ann_$id',
          type:     _NotifType.announcement,
          title:    ann['title'] as String? ?? '—',
          preview:  _preview(message),
          fullBody: message,
          time:     raw != null
              ? (DateTime.tryParse(raw)?.toLocal() ?? DateTime.now())
              : DateTime.now(),
          orgName:  orgNames[ann['created_by'] as String? ?? ''],
        ));
      }

      // ── Registration status changes ───────────────────────────────────────
      for (final reg in regRows) {
        final rid     = reg['id']             as String? ?? '';
        final status  = reg['status']         as String? ?? '';
        final event   = reg['event_title']    as String? ?? 'an event';
        final rawCi   = reg['checked_in_at']  as String?;
        final rawReg  = reg['registered_at']  as String?;
        final timeRaw = rawCi ?? rawReg ?? '';

        _NotifType notifType;
        String title, body;

        if (status == 'checked_in') {
          notifType = _NotifType.checkIn;
          title     = 'Check-in confirmed! ✓';
          body      = 'You\'ve been successfully checked in to "$event". Enjoy the event!';
        } else if (status == 'photo_required') {
          notifType = _NotifType.selfieRequired;
          title     = 'Selfie required';
          body      = 'Your organizer needs a selfie to verify your attendance at "$event".';
        } else if (status == 'photo_submitted') {
          notifType = _NotifType.photoSubmitted;
          title     = 'Photo received';
          body      = 'Your selfie for "$event" was submitted — awaiting organizer confirmation.';
        } else {
          continue;
        }

        items.add(_NotifItem(
          id:       'reg_${rid}_$status',
          type:     notifType,
          title:    title,
          preview:  body,
          fullBody: body,
          time:     timeRaw.isNotEmpty
              ? (DateTime.tryParse(timeRaw)?.toLocal() ?? DateTime.now())
              : DateTime.now(),
        ));
      }

      // Sort newest first
      items.sort((a, b) => b.time.compareTo(a.time));

      // Respect per-user preferences (Profile → Notifications). Verification
      // items (selfie required / photo submitted) are never filtered.
      final disabledCats = await StudentNotifPrefs.disabled(user.id);
      if (disabledCats.isNotEmpty) {
        items.removeWhere((n) =>
            (disabledCats.contains(StudentNotifPrefs.announcements) &&
                n.type == _NotifType.announcement) ||
            (disabledCats.contains(StudentNotifPrefs.checkins) &&
                n.type == _NotifType.checkIn));
      }

      if (!mounted) return;

      if (widget.markAllRead) {
        NotifReadStore.markAll(items.map((e) => e.id));
      } else {
        NotifReadStore.setAll(items.map((e) => e.id));
      }

      setState(() {
        _all     = items;
        _loading = false;
        _applyFilter();
      });
    } catch (e) {
      debugPrint('NotificationsScreen load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    switch (_tabIndex) {
      case 1:
        _filtered = _all.where((n) => n.type == _NotifType.announcement).toList();
        break;
      case 2:
        _filtered = _all.where((n) => n.type != _NotifType.announcement).toList();
        break;
      default:
        _filtered = List.from(_all);
    }
  }

  void _subscribeRealtime() {
    final userId = SupabaseService.currentUser?.id ?? '';
    _realtimeChannel = SupabaseService.client.channel('notif-screen');
    _realtimeChannel!
        .on(
          RealtimeListenTypes.postgresChanges,
          ChannelFilter(event: '*', schema: 'public', table: 'announcements'),
          (_, [ref]) { if (mounted) _load(); },
        )
        .on(
          RealtimeListenTypes.postgresChanges,
          ChannelFilter(
            event: 'UPDATE',
            schema: 'public',
            table: 'registrations',
            filter: 'student_user_id=eq.$userId',
          ),
          (_, [ref]) { if (mounted) _load(); },
        )
        .subscribe();
  }

  void _markRead(String id) {
    if (NotifReadStore.isRead(id)) return;
    NotifReadStore.mark(id);
    setState(() {});
  }

  void _markAllRead() {
    NotifReadStore.markAll(_all.map((e) => e.id));
    setState(() {});
  }
  void _showAnnouncementDetail(_NotifItem item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final t = AppTk(Theme.of(sheetCtx).brightness == Brightness.dark);
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (_, scrollCtrl) => Container(
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: t.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE87A00).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.campaign_rounded,
                          color: Color(0xFFE87A00),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Announcement',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFE87A00),
                            ),
                          ),
                          if (item.orgName != null && item.orgName!.isNotEmpty)
                            Row(
                              children: [
                                Icon(Icons.person_outline_rounded, size: 10, color: t.muted),
                                const SizedBox(width: 3),
                                Text(
                                  'by ${item.orgName}',
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: t.muted),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        _timeAgo(item.time),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: t.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 24, indent: 20, endIndent: 20, color: t.divider),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    children: [
                      Text(
                        item.title,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: t.text,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        item.fullBody,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          color: t.sub,
                          height: 1.65,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t      = AppTk(Theme.of(context).brightness == Brightness.dark);
    final unread = _all.where((n) => !n.isRead).length;

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(unread, t),
            _buildTabBar(unread, t),
            Expanded(
              child: _loading
                  ? const AppShimmerList(itemCount: 6, hasAvatar: false)
                  : RefreshIndicator(
                      color: kGold,
                      onRefresh: _load,
                      child: _filtered.isEmpty
                          ? _buildEmptyState(t)
                          : _buildGroupedList(t),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(int unread, AppTk t) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: BoxDecoration(
        color: t.card,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: t.bg,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: t.border),
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded, size: 17, color: t.text),
            ),
          ),
          const SizedBox(width: 14),

          // Title + unread badge
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Notifications',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w800, color: t.text),
                ),
                if (unread > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$unread new',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Mark all read button
          if (unread > 0)
            GestureDetector(
              onTap: _markAllRead,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: kGold.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kGold.withValues(alpha: 0.25)),
                ),
                child: const Text(
                  'Mark all read',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: kGold),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF16A34A).withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, size: 13, color: Color(0xFF16A34A)),
                  SizedBox(width: 5),
                  Text('All read', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF16A34A))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Tab bar ───────────────────────────────────────────────────────────────

  Widget _buildTabBar(int totalUnread, AppTk t) {
    final annUnread = _all.where((n) => n.type == _NotifType.announcement && !n.isRead).length;
    final regUnread = _all.where((n) => n.type != _NotifType.announcement  && !n.isRead).length;
    final counts    = [totalUnread, annUnread, regUnread];

    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: t.card,
        border: Border(bottom: BorderSide(color: t.divider)),
      ),
      child: TabBar(
        controller: _tabCtrl,
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        tabs: List.generate(_tabs.length, (i) {
          final count = counts[i];
          return Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_tabs[i]),
                if (count > 0) ...[
                  const SizedBox(width: 5),
                  Container(
                    width: 17, height: 17,
                    decoration: const BoxDecoration(
                      color: Color(0xFFDC2626),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        count > 9 ? '9+' : '$count',
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }),
        labelStyle:           const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w500),
        labelColor:           kGold,
        unselectedLabelColor: t.muted,
        indicatorColor:       kGold,
        indicatorWeight:      2.5,
        indicatorSize:        TabBarIndicatorSize.label,
        dividerColor:         Colors.transparent,
      ),
    );
  }

  // ── Grouped list ──────────────────────────────────────────────────────────

  Widget _buildGroupedList(AppTk t) {
    const groupOrder = ['Today', 'Yesterday', 'This Week', 'Earlier'];
    final groups = <String, List<_NotifItem>>{};
    for (final item in _filtered) {
      groups.putIfAbsent(_groupLabel(item.time), () => []).add(item);
    }

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        for (final label in groupOrder)
          if (groups.containsKey(label)) ...[
            SliverToBoxAdapter(child: _buildGroupHeader(label, t)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _buildCard(groups[label]![i], t),
                  childCount: groups[label]!.length,
                ),
              ),
            ),
          ],
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  Widget _buildGroupHeader(String label, AppTk t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 10,
              fontWeight: FontWeight.w700, letterSpacing: 1.0, color: t.muted,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(height: 1, color: t.divider)),
        ],
      ),
    );
  }

  // ── Notification card ─────────────────────────────────────────────────────

  Widget _buildCard(_NotifItem item, AppTk t) {
    final isRead = item.isRead;

    // Type-specific styling
    late final Color   accentColor;
    late final IconData accentIcon;
    late final String  typeLabel;

    switch (item.type) {
      case _NotifType.announcement:
        accentColor = const Color(0xFFE87A00);
        accentIcon  = Icons.campaign_rounded;
        typeLabel   = 'Announcement';
      case _NotifType.checkIn:
        accentColor = const Color(0xFF16A34A);
        accentIcon  = Icons.check_circle_outline_rounded;
        typeLabel   = 'My Events';
      case _NotifType.selfieRequired:
        accentColor = const Color(0xFF9333EA);
        accentIcon  = Icons.camera_alt_outlined;
        typeLabel   = 'My Events';
      case _NotifType.photoSubmitted:
        accentColor = const Color(0xFF2979C8);
        accentIcon  = Icons.photo_camera_outlined;
        typeLabel   = 'My Events';
    }
    return Dismissible(
      key:       ValueKey(item.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        _markRead(item.id);
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding:   const EdgeInsets.only(right: 24),
        margin:    const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color:        kGold.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border:       Border.all(color: kGold.withValues(alpha: 0.22)),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mark_email_read_rounded, color: kGold, size: 22),
            SizedBox(height: 4),
            Text('Mark read', style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, color: kGold)),
          ],
        ),
      ),
      child: GestureDetector(
        onTap: () {
          _markRead(item.id);
          if (item.type == _NotifType.announcement) _showAnnouncementDetail(item);
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: isRead ? t.card : (t.dark ? const Color(0xFF2A1E0A) : const Color(0xFFFFF8E8)),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isRead
                  ? t.border
                  : kGold.withValues(alpha: 0.22),
              width: isRead ? 1 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isRead ? 0.03 : 0.06),
                blurRadius: isRead ? 6 : 14,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Left accent strip ──────────────────────────────────
                Container(
                  width: 4,
                  color: isRead ? Colors.transparent : accentColor,
                ),

                // ── Content ────────────────────────────────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Icon circle
                        Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: isRead ? 0.07 : 0.13),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Icon(accentIcon, color: accentColor, size: 22),
                        ),
                        const SizedBox(width: 12),

                        // Text content
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Title row
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.title,
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
                                  ),
                                  // Unread dot
                                  if (!isRead)
                                    Container(
                                      width: 8, height: 8,
                                      margin: const EdgeInsets.only(left: 8, top: 4),
                                      decoration: BoxDecoration(
                                        color: accentColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 5),

                              // Body preview
                              Text(
                                item.preview,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  color: isRead ? t.muted : t.sub,
                                  height: 1.55,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (item.type == _NotifType.announcement &&
                                  item.orgName != null &&
                                  item.orgName!.isNotEmpty) ...[
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    Icon(Icons.person_outline_rounded, size: 10, color: t.muted),
                                    const SizedBox(width: 3),
                                    Text(
                                      item.orgName!,
                                      style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: t.muted),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 9),

                              // Footer: type chip + time
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: accentColor.withValues(alpha: 0.09),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          typeLabel,
                                          style: TextStyle(
                                            fontFamily: 'Poppins', fontSize: 9,
                                            fontWeight: FontWeight.w700, color: accentColor,
                                          ),
                                        ),
                                        if (item.type == _NotifType.announcement) ...[
                                          const SizedBox(width: 2),
                                          Icon(Icons.chevron_right_rounded, size: 11, color: accentColor),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const Spacer(),
                                  Row(
                                    children: [
                                      Icon(Icons.access_time_rounded, size: 11, color: t.muted.withValues(alpha: 0.8)),
                                      const SizedBox(width: 3),
                                      Text(
                                        _timeAgo(item.time),
                                        style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: t.muted),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
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

  // ── Empty state ───────────────────────────────────────────────────────────

  Widget _buildEmptyState(AppTk t) {
    const messages = [
      ['No notifications yet', 'Check back later — updates from organizers will appear here.'],
      ['No announcements',     'Organizers haven\'t posted any announcements yet.'],
      ['No event updates',     'Registration and check-in updates will show up here.'],
    ];
    final msg = messages[_tabIndex];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 90, height: 90,
                decoration: BoxDecoration(
                  color: kGold.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Icon(
                  Icons.notifications_off_outlined,
                  size: 44,
                  color: kGold.withValues(alpha: 0.50),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                msg[0],
                style: TextStyle(fontFamily: 'Poppins', fontSize: 17, fontWeight: FontWeight.w700, color: t.text),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                msg[1],
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.sub, height: 1.6),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

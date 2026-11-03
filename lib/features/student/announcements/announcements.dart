import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/app_colors.dart';
import '../../../core/services/notif_read_store.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/app_loader.dart';
import '../../../shared/widgets/mark_all_read_button.dart';
import '../notifications/student_feed.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Announcements for students: Home shows the latest three, See all opens
// [AnnouncementsScreen] with the rest. They aren't under the bell — the bell
// is for the student's own events. An announcement is read once it's opened
// (or "Mark all as read"); Home and this page show the same read state.
// ─────────────────────────────────────────────────────────────────────────────

/// Read-state id of an announcement (NotifReadStore).
String announcementReadId(Map<String, dynamic> ann) => 'ann_${ann['id']}';

/// "Just now", "5m ago", "3h ago", "2d ago", "3w ago".
String announcementTimeAgo(String? ts) {
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

/// The full announcement in a sheet; opening it reads it.
Future<void> showAnnouncementSheet(BuildContext context, Map<String, dynamic> ann) {
  final title     = ann['title']   as String? ?? '—';
  final message   = ann['message'] as String? ?? '';
  final createdAt = ann['created_at'] as String?;

  NotifReadStore.mark(announcementReadId(ann));

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (_, scrollCtrl) {
        final t = AppTk(Theme.of(ctx).brightness == Brightness.dark);
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
                            Text(announcementTimeAgo(createdAt), style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted)),
                          if ((ann['_org'] as String?) != null && ann['_org'] != '—')
                            Row(
                              children: [
                                Icon(Icons.person_outline_rounded, size: 10, color: t.muted),
                                const SizedBox(width: 3),
                                Text('by ${ann['_org']}', style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5, color: t.muted)),
                              ],
                            ),
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
  );
}

/// One announcement in a list (Home and the See all page): gold edge and
/// bold title until it's read.
class AnnouncementTile extends StatelessWidget {
  final Map<String, dynamic> ann;
  final bool showDivider;
  /// Two lines of the message under the title (the See all page).
  final bool showPreview;
  final VoidCallback onTap;

  const AnnouncementTile({
    super.key,
    required this.ann,
    required this.showDivider,
    required this.onTap,
    this.showPreview = false,
  });

  @override
  Widget build(BuildContext context) {
    final t         = AppTk(Theme.of(context).brightness == Brightness.dark);
    final title     = ann['title']      as String? ?? '—';
    final message   = (ann['message']   as String? ?? '').trim();
    final createdAt = ann['created_at'] as String?;
    final isRead    = NotifReadStore.isRead(announcementReadId(ann));

    return GestureDetector(
      onTap: onTap,
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
                        if (showPreview && message.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            message,
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.sub, height: 1.5),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.person_outline_rounded, size: 10, color: t.muted),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                ann['_org'] as String? ?? '—',
                                style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: t.muted),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(' · ', style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: t.muted)),
                            Text(
                              announcementTimeAgo(createdAt),
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: t.muted),
                            ),
                          ],
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
}

// ── See all ───────────────────────────────────────────────────────────────────

/// Every recent announcement (Home shows the latest three), by day.
class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  bool _failed  = false;
  RealtimeChannel? _channel;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    // A new, edited or removed announcement shows up without a refresh.
    _channel = SupabaseService.client.channel('student-announcements-page');
    _channel!.on(
      RealtimeListenTypes.postgresChanges,
      ChannelFilter(event: '*', schema: 'public', table: 'announcements'),
      (_, [ref]) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 600), () {
          if (mounted) _load();
        });
      },
    );
    _channel!.subscribe();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_channel != null) SupabaseService.client.removeChannel(_channel!);
    super.dispose();
  }

  /// The list stays on screen while it reloads (pull down, live update).
  Future<void> _load() async {
    try {
      final rows = SupabaseService.client.auth.currentUser == null
          ? <Map<String, dynamic>>[]
          : await StudentNotifications.announcements();
      if (!mounted) return;
      setState(() { _all = rows; _loading = false; _failed = false; });
    } catch (e) {
      debugPrint('AnnouncementsScreen load error: $e');
      // A failed reload keeps what's already on screen.
      if (mounted) setState(() { _loading = false; _failed = _all.isEmpty; });
    }
  }

  void _open(Map<String, dynamic> ann) {
    showAnnouncementSheet(context, ann).then((_) { if (mounted) setState(() {}); });
  }

  void _markAllRead() {
    NotifReadStore.markAll(_all.map(announcementReadId));
    setState(() {});
  }

  static String _dayGroup(String? ts) {
    final t = DateTime.tryParse(ts ?? '')?.toLocal();
    if (t == null) return 'Earlier';
    final now  = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day)
        .difference(DateTime(t.year, t.month, t.day)).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7)  return 'This Week';
    return 'Earlier';
  }

  @override
  Widget build(BuildContext context) {
    final t      = AppTk(Theme.of(context).brightness == Brightness.dark);
    final unread = _all.where((a) => !NotifReadStore.isRead(announcementReadId(a))).length;

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(unread, t),
            Expanded(
              child: _loading
                  ? const AppShimmerList(itemCount: 6, hasAvatar: false)
                  : RefreshIndicator(
                      color: kGold,
                      onRefresh: _load,
                      child: _all.isEmpty ? _buildEmpty(t) : _buildList(t),
                    ),
            ),
          ],
        ),
      ),
    );
  }

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
          Semantics(
            button: true,
            label: 'Back',
            child: GestureDetector(
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
          ),
          const SizedBox(width: 14),
          // Title + unread badge (shrinks instead of overflowing on a narrow
          // phone or with large text)
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Announcements',
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
          ),
          const SizedBox(width: 8),
          MarkAllReadButton(unread: unread, onTap: _markAllRead),
        ],
      ),
    );
  }

  Widget _buildList(AppTk t) {
    const order = ['Today', 'Yesterday', 'This Week', 'Earlier'];
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final a in _all) {
      groups.putIfAbsent(_dayGroup(a['created_at'] as String?), () => []).add(a);
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      children: [
        for (final label in order)
          if (groups[label] case final items?) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
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
            ),
            Container(
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: t.border),
                boxShadow: [BoxShadow(color: t.shadow, blurRadius: 12, offset: const Offset(0, 4))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++)
                    AnnouncementTile(
                      ann: items[i],
                      showDivider: i < items.length - 1,
                      showPreview: true,
                      onTap: () => _open(items[i]),
                    ),
                ],
              ),
            ),
          ],
      ],
    );
  }

  Widget _buildEmpty(AppTk t) {
    final (title, hint) = _failed
        ? ('Couldn’t load announcements', 'Check your connection, then pull down to try again.')
        : ('No announcements yet', 'Updates from organizers will appear here.');
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 48),
          child: Column(
            children: [
              Container(
                width: 90, height: 90,
                decoration: BoxDecoration(
                  color: kGold.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Icon(
                  _failed ? Icons.cloud_off_rounded : Icons.campaign_outlined,
                  size: 44,
                  color: kGold.withValues(alpha: 0.50),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 17, fontWeight: FontWeight.w700, color: t.text),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                hint,
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

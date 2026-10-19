import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../../../shared/widgets/error_alert.dart';
import 'new_announcement.dart';
import 'announcement_view.dart';
import '../../../../core/app_colors.dart';

String _timeAgo(String? iso) {
  if (iso == null) return '';
  try {
    final d    = DateTime.parse(iso).toLocal();
    final diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60)  return 'Just now';
    if (diff.inMinutes < 60)  { final m = diff.inMinutes;  return '$m min${m == 1 ? '' : 's'} ago'; }
    if (diff.inHours   < 24)  { final h = diff.inHours;    return '$h hr${h == 1 ? '' : 's'} ago';  }
    if (diff.inDays    < 7)   { final dy = diff.inDays;    return '$dy day${dy == 1 ? '' : 's'} ago'; }
    const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${mo[d.month - 1]} ${d.day}';
  } catch (_) { return ''; }
}

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  List<Map<String, dynamic>> _all      = [];
  List<Map<String, dynamic>> _filtered = [];
  bool   _loading = true;
  String _search  = '';
  final  _searchCtrl = TextEditingController();
  RealtimeChannel? _channel;
  Timer?           _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    _channel = SupabaseService.client.channel('org-mobile-announcements');
    _channel!.on(
      RealtimeListenTypes.postgresChanges,
      ChannelFilter(event: '*', schema: 'public', table: 'announcements'),
      (_, [_]) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 600), () {
          if (mounted) _load(silent: true);
        });
      },
    );
    _channel!.subscribe();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _load({bool silent = false}) async {
    if (mounted && !silent) setState(() => _loading = true);
    try {
      final rows = await SupabaseService.getAnnouncements();
      if (!mounted) return;
      setState(() {
        _all     = rows;
        _loading = false;
        _applyFilter();
      });
    } catch (e) {
      debugPrint('AnnouncementsScreen load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    final q = _search.toLowerCase();
    _filtered = q.isEmpty
        ? List.from(_all)
        : _all.where((a) {
            final t = (a['title']   as String? ?? '').toLowerCase();
            final m = (a['message'] as String? ?? '').toLowerCase();
            return t.contains(q) || m.contains(q);
          }).toList();
  }

  Future<void> _delete(Map<String, dynamic> ann) async {
    final id    = ann['id'];
    final index = _all.indexWhere((a) => a['id'] == id);
    if (id == null) return;

    // Optimistic removal
    setState(() {
      _all.removeWhere((a) => a['id'] == id);
      _applyFilter();
    });

    try {
      await SupabaseService.deleteAnnouncement(id as int);
    } catch (e) {
      // Rollback
      setState(() {
        _all.insert(index < 0 ? 0 : index, ann);
        _applyFilter();
      });
      if (mounted) showErrorAlert(context, e, title: 'Couldn’t delete the announcement');
    }
  }

  void _confirmDelete(Map<String, dynamic> ann) {
    AppAlert.confirm(
      context,
      title: 'Delete Announcement?',
      message: '"${ann['title']}" will be permanently removed and students will no longer see it.',
      confirmText: 'Delete',
      cancelText: 'Cancel',
      onConfirm: () => _delete(ann),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = AppTk(Theme.of(context).brightness == Brightness.dark);
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(t),
            _buildStatsStrip(),
            _buildSearchBar(t),
            Expanded(
              child: _loading
                  ? const AppShimmerList(itemCount: 5, hasAvatar: false)
                  : RefreshIndicator(
                      color: kGold,
                      onRefresh: _load,
                      child: _filtered.isEmpty ? _buildEmptyState(t) : _buildList(t),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NewAnnouncementScreen()),
        ),
        backgroundColor: kGold,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.add_rounded, size: 22),
        label: const Text(
          'New',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(AppTk t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: t.shadow, blurRadius: 10, offset: const Offset(0, 3))],
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: t.text),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Announcements',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w800, color: t.text, height: 1.1),
                ),
                const SizedBox(height: 2),
                Text(
                  _loading
                      ? 'Loading…'
                      : '${_all.length} announcement${_all.length == 1 ? '' : 's'}',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.sub),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Stats strip ───────────────────────────────────────────────────────────

  Widget _buildStatsStrip() {
    if (_all.isEmpty && !_loading) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        decoration: BoxDecoration(
          gradient: kGoldGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: kGold.withValues(alpha: 0.30), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.campaign_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Total Announcements',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white70),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_all.length}',
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white, height: 1.1),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('Students notified', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: Colors.white70)),
                const SizedBox(height: 2),
                Row(
                  children: const [
                    Icon(Icons.groups_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text('All', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Search bar ────────────────────────────────────────────────────────────

  Widget _buildSearchBar(AppTk t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: t.shadow, blurRadius: 14, offset: const Offset(0, 4))],
        ),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() { _search = v; _applyFilter(); }),
          style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: t.text),
          decoration: InputDecoration(
            hintText: 'Search announcements…',
            hintStyle: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.sub.withValues(alpha: 0.55)),
            prefixIcon: const Icon(Icons.search_rounded, color: kGold, size: 22),
            suffixIcon: _search.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.cancel_rounded, color: t.sub.withValues(alpha: 0.45), size: 20),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() { _search = ''; _applyFilter(); });
                    },
                  )
                : null,
            border:        OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: kGold, width: 2)),
            filled: false,
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ),
    );
  }

  // ── List ──────────────────────────────────────────────────────────────────

  Widget _buildList(AppTk t) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: _filtered.length,
      itemBuilder: (_, i) {
        final ann = _filtered[i];
        return Dismissible(
          key: ValueKey(ann['id']),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) async {
            _confirmDelete(ann);
            return false;
          },
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 22),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.delete_outline_rounded, color: Colors.red.shade600, size: 26),
                const SizedBox(height: 4),
                Text('Delete', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.red.shade600)),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _buildCard(ann, t),
          ),
        );
      },
    );
  }

  // ── Announcement card ─────────────────────────────────────────────────────

  Widget _buildCard(Map<String, dynamic> ann, AppTk t) {
    final title     = ann['title']      as String? ?? '—';
    final message   = ann['message']    as String? ?? '';
    final createdAt = ann['created_at'] as String?;
    final preview   = message.length > 90 ? '${message.substring(0, 90)}…' : message;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AnnouncementViewScreen(
            id: ann['id']?.toString() ?? '',
            title: title,
            message: message,
            createdAt: createdAt,
          ),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: t.shadow, blurRadius: 12, offset: const Offset(0, 4))],
          border: Border.all(color: t.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left accent strip
              Container(
                width: 4,
                decoration: const BoxDecoration(gradient: kGoldGradient),
              ),

              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 42, height: 42,
                            decoration: BoxDecoration(
                              color: kGold.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.campaign_rounded, color: kGold, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700, color: t.text),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Icon(Icons.access_time_rounded, size: 11, color: t.muted),
                                    const SizedBox(width: 3),
                                    Text(
                                      _timeAgo(createdAt),
                                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Delete button
                          GestureDetector(
                            onTap: () => _confirmDelete(ann),
                            child: Container(
                              width: 32, height: 32,
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400, size: 16),
                            ),
                          ),
                        ],
                      ),

                      // Preview
                      if (preview.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          preview,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.sub, height: 1.5),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],

                      const SizedBox(height: 10),

                      // Footer
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF16A34A).withValues(alpha: 0.09),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.check_circle_rounded, size: 11, color: Color(0xFF16A34A)),
                                SizedBox(width: 4),
                                Text('Sent', style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF16A34A))),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: kGold.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.groups_rounded, size: 11, color: kGold),
                                SizedBox(width: 4),
                                Text('All Students', style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, color: kGold)),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Icon(Icons.chevron_right_rounded, size: 18, color: t.muted),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────

  Widget _buildEmptyState(AppTk t) {
    final isSearch = _search.isNotEmpty;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 90, height: 90,
                decoration: BoxDecoration(color: kGold.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(28)),
                child: Icon(
                  isSearch ? Icons.search_off_rounded : Icons.campaign_outlined,
                  size: 46,
                  color: kGold.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                isSearch ? 'No results found' : 'No announcements yet',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w700, color: t.text),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isSearch
                    ? 'Try a different search term'
                    : 'Tap + New to post your first announcement to all students.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.sub, height: 1.6),
              ),
              if (isSearch) ...[
                const SizedBox(height: 28),
                GestureDetector(
                  onTap: () {
                    _searchCtrl.clear();
                    setState(() { _search = ''; _applyFilter(); });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
                    decoration: BoxDecoration(
                      color: kGold,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: kGold.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: const Text('Clear search', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin — Announcements tab.
// Split out of admin_web_dashboard.dart so each sidebar tab has its own file.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/supabase_service.dart';
import '../organizer/web/web_shared.dart';
import 'admin_shared.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Announcements page
// ═════════════════════════════════════════════════════════════════════════════

class AdminAnnouncementsPage extends StatefulWidget {
  const AdminAnnouncementsPage({super.key});
  @override
  State<AdminAnnouncementsPage> createState() => _AdminAnnouncementsPageState();
}

class _AdminAnnouncementsPageState extends State<AdminAnnouncementsPage> {
  bool _loading = true;
  bool _error = false;
  String _search = '';
  String _orgFilter = 'All';
  bool _sortDesc = true;
  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _filtered = [];
  final _searchCtrl = TextEditingController();
  RealtimeChannel? _channel;
  Timer? _debounce;

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
    if (mounted)
      setState(() {
        if (!silent) _loading = true;
        _error = false;
      });
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

      final enriched = rows
          .map(
            (r) => <String, dynamic>{
              ...r,
              '_org': orgNames[r['created_by'] as String? ?? ''] ?? '—',
            },
          )
          .toList();

      if (!mounted) return;
      setState(() {
        _all = enriched;
        _filtered = _apply(enriched);
        _loading = false;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = true;
        });
    }
  }

  List<Map<String, dynamic>> _apply(List<Map<String, dynamic>> src) {
    final q = _search.trim().toLowerCase();
    var list = src.where((a) {
      if (_orgFilter != 'All' && a['_org'] != _orgFilter) return false;
      if (q.isEmpty) return true;
      final title = (a['title'] as String? ?? '').toLowerCase();
      final message = (a['message'] as String? ?? '').toLowerCase();
      final org = (a['_org'] as String? ?? '').toLowerCase();
      return title.contains(q) || message.contains(q) || org.contains(q);
    }).toList();
    return _sortDesc ? list : list.reversed.toList();
  }

  Future<void> _delete(Map<String, dynamic> ann) async {
    final ok = await WebAlert.confirm(
      context: context,
      title: 'Delete Announcement?',
      message:
          'This announcement will be permanently removed and will '
          'no longer be visible to students. You will be asked for '
          'a reason, which will be sent to the organizer.',
      confirmLabel: 'Delete',
    );
    if (ok != true || !mounted) return;

    final reason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AnnouncementRemovalReasonDialog(
        announcementTitle: ann['title'] as String? ?? '',
      ),
    );
    if (reason == null || !mounted) return;

    try {
      final deleted = await SupabaseService.client.rpc(
        'admin_delete_announcement',
        params: {'p_announcement_id': ann['id'] as int, 'p_reason': reason},
      );
      if (deleted != true) {
        throw StateError('The announcement was not deleted.');
      }
      SupabaseService.announcementsVersion.value++;
      await _load(silent: true);
      if (mounted) {
        WebAlert.success(
          context: context,
          title: 'Deleted',
          message:
              'Announcement removed. The organizer was notified with '
              'your reason.',
        );
      }
    } catch (e) {
      if (mounted) {
        adminErrorAlert(context, e, title: 'Couldn’t delete the announcement');
      }
    }
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 30) return '${diff.inDays}d ago';
      const mn = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${mn[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  void _clearFilters() {
    _searchCtrl.clear();
    setState(() {
      _search = '';
      _orgFilter = 'All';
      _filtered = _apply(_all);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: kAdminAccent),
      );
    }
    if (_error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 44,
              color: Color(0xFFEF4444),
            ),
            const SizedBox(height: 16),
            Text(
              'Couldn’t load announcements',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: t.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Check your internet connection and try again.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: t.sub),
            ),
            const SizedBox(height: 14),
            WebBtn(label: 'Retry', icon: Icons.refresh_rounded, onTap: _load),
          ],
        ),
      );
    }

    // ── Computed stats ─────────────────────────────────────────────────────
    final hasFilter = _search.isNotEmpty || _orgFilter != 'All';
    final orgOpts = <String>[
      'All',
      ..._all.map((a) => a['_org'] as String? ?? '—').toSet().toList()..sort(),
    ];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ══ Band 1: White header ════════════════════════════════════════════
          Container(
            color: t.card,
            padding: const EdgeInsets.fromLTRB(kWebPad, 20, kWebPad, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Announcements',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: t.text,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),

          // ══ Band 2: Filter bar ══════════════════════════════════════════════
          Container(
            padding: const EdgeInsets.fromLTRB(kWebPad, 8, kWebPad, 8),
            decoration: BoxDecoration(
              color: t.bg,
              border: Border(bottom: BorderSide(color: t.border)),
            ),
            child: Row(
              children: [
                // Search
                WebSearchField(
                  controller: _searchCtrl,
                  hint: 'Search title, message or organizer…',
                  onChanged: (v) => setState(() {
                    _search = v;
                    _filtered = _apply(_all);
                  }),
                  width: 240,
                ),
                const SizedBox(width: 14),
                Container(width: 1, height: 18, color: t.border),
                const SizedBox(width: 14),

                // Organizer filter
                Text(
                  'Organizer:',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 28,
                  padding: const EdgeInsets.only(left: 10, right: 6),
                  decoration: BoxDecoration(
                    color: _orgFilter != 'All'
                        ? kAdminAccent.withValues(alpha: 0.07)
                        : t.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _orgFilter != 'All'
                          ? kAdminAccent.withValues(alpha: 0.45)
                          : t.border,
                      width: _orgFilter != 'All' ? 1.5 : 1.0,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: orgOpts.contains(_orgFilter) ? _orgFilter : 'All',
                      isDense: true,
                      icon: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 14,
                        color: _orgFilter != 'All' ? kAdminAccent : t.muted,
                      ),
                      onChanged: (v) {
                        if (v != null)
                          setState(() {
                            _orgFilter = v;
                            _filtered = _apply(_all);
                          });
                      },
                      selectedItemBuilder: (ctx) => orgOpts
                          .map(
                            (n) => Center(
                              child: Text(
                                n == 'All' ? 'All Organizers' : n,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: _orgFilter != 'All'
                                      ? kAdminAccent
                                      : t.text,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      items: orgOpts
                          .map(
                            (n) => DropdownMenuItem<String>(
                              value: n,
                              child: Text(
                                n == 'All' ? 'All Organizers' : n,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  fontWeight: n == _orgFilter
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  color: n == _orgFilter
                                      ? kAdminAccent
                                      : t.text,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Container(width: 1, height: 18, color: t.border),
                const SizedBox(width: 14),

                // Sort toggle
                Text(
                  'Sort:',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                ),
                const SizedBox(width: 8),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _sortDesc = !_sortDesc;
                      _filtered = _apply(_all);
                    }),
                    child: Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: t.card,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: t.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _sortDesc
                                ? Icons.arrow_downward_rounded
                                : Icons.arrow_upward_rounded,
                            size: 12,
                            color: t.sub,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _sortDesc ? 'Newest first' : 'Oldest first',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: t.sub,
                            ),
                          ),
                        ],
                      ),
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.close_rounded, size: 13, color: t.muted),
                          const SizedBox(width: 4),
                          Text(
                            'Clear filters',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: t.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ══ Band 3: Body ════════════════════════════════════════════════════
          if (_filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.all(kWebPad),
              child: WebEmptyState(
                icon: Icons.campaign_outlined,
                title: hasFilter ? 'No results found' : 'No announcements yet',
                subtitle: hasFilter
                    ? 'Try adjusting your search or organizer filter.'
                    : 'Organizers have not posted any announcements yet.',
                action: hasFilter
                    ? TextButton(
                        onPressed: _clearFilters,
                        child: const Text(
                          'Clear all filters',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            color: kAdminAccent,
                          ),
                        ),
                      )
                    : null,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(kWebPad),
              child: WebCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    // Card section header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFFC2410C),
                                  kAdminAccent,
                                  Color(0xFFF97316),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: const Icon(
                              Icons.campaign_rounded,
                              size: 15,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'All Announcements',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: t.text,
                            ),
                          ),
                          if (hasFilter) ...[
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: t.divider,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${_filtered.length} of ${_all.length}',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: t.sub,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Divider(height: 1, color: t.border),

                    // Rows
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: t.border),
                      itemBuilder: (_, i) => _AdminAnnRow(
                        ann: _filtered[i],
                        timeAgo: _timeAgo(
                          _filtered[i]['created_at'] as String?,
                        ),
                        onDelete: () => _delete(_filtered[i]),
                      ),
                    ),

                    // Footer count row — matches Organizers/Registrations pattern
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: t.border)),
                      ),
                      child: Text(
                        hasFilter
                            ? 'Showing ${_filtered.length} of ${_all.length} announcements'
                            : '${_all.length} announcements total',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11.5,
                          color: t.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AnnouncementRemovalReasonDialog extends StatefulWidget {
  final String announcementTitle;
  const _AnnouncementRemovalReasonDialog({required this.announcementTitle});

  @override
  State<_AnnouncementRemovalReasonDialog> createState() =>
      _AnnouncementRemovalReasonDialogState();
}

class _AnnouncementRemovalReasonDialogState
    extends State<_AnnouncementRemovalReasonDialog> {
  static const _maxReasonLength = 500;
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final reason = _reasonController.text.trim();

    return Dialog(
      backgroundColor: t.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.campaign_outlined,
                      color: Color(0xFFEF4444),
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Reason for removal',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancel',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: t.muted, size: 19),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'This explanation will be sent to the organizer and shown in '
                'their notifications.',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  height: 1.5,
                  color: t.sub,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: t.inputBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: t.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ANNOUNCEMENT',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                        color: t.muted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.announcementTitle.isEmpty
                          ? 'Untitled announcement'
                          : widget.announcementTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: t.text,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _reasonController,
                autofocus: true,
                maxLength: _maxReasonLength,
                maxLines: 4,
                minLines: 4,
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: t.text,
                ),
                decoration: InputDecoration(
                  hintText: 'Explain why this announcement is being removed…',
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: t.muted,
                  ),
                  filled: true,
                  fillColor: t.inputBg,
                  counterText: '',
                  contentPadding: const EdgeInsets.all(13),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: t.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: t.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: kAdminAccent,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${_reasonController.text.length}/$_maxReasonLength',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    color: t.muted,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        color: t.sub,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: reason.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(reason),
                    icon: const Icon(
                      Icons.notifications_active_outlined,
                      size: 17,
                    ),
                    label: const Text(
                      'Delete & Notify',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(
                        0xFFEF4444,
                      ).withValues(alpha: 0.35),
                      disabledForegroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Announcement row ──────────────────────────────────────────────────────────

class _AdminAnnRow extends StatefulWidget {
  final Map<String, dynamic> ann;
  final String timeAgo;
  final VoidCallback onDelete;
  const _AdminAnnRow({
    required this.ann,
    required this.timeAgo,
    required this.onDelete,
  });
  @override
  State<_AdminAnnRow> createState() => _AdminAnnRowState();
}

class _AdminAnnRowState extends State<_AdminAnnRow> {
  bool _hover = false;
  bool _expanded = false;

  static const int _maxPreviewLength = 250;

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final title = widget.ann['title'] as String? ?? '';
    final message = widget.ann['message'] as String? ?? '';
    final org = widget.ann['_org'] as String? ?? '—';
    final isLong = message.length > _maxPreviewLength;
    final preview = isLong
        ? '${message.substring(0, _maxPreviewLength).trimRight()}…'
        : message;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: _hover
            ? kAdminAccent.withValues(alpha: 0.03)
            : Colors.transparent,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left accent bar
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 3,
                color: _hover
                    ? kAdminAccent
                    : kAdminAccent.withValues(alpha: 0.28),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Organizer initial avatar
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: kAdminAccent.withValues(alpha: 0.11),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: kAdminAccent.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            org.isNotEmpty ? org[0].toUpperCase() : '?',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: kAdminAccent,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: t.text,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              _expanded ? message : preview,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12.5,
                                color: t.sub,
                                height: 1.55,
                              ),
                            ),
                            if (isLong) ...[
                              const SizedBox(height: 4),
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _expanded = !_expanded),
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: Text(
                                    _expanded ? 'Show less' : 'Read more',
                                    style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: kAdminAccent,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            // Meta row
                            Row(
                              children: [
                                Icon(
                                  Icons.person_outline_rounded,
                                  size: 12,
                                  color: t.muted,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    org,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: t.sub,
                                    ),
                                  ),
                                ),
                                Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  width: 3,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: t.muted,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Icon(
                                  Icons.access_time_rounded,
                                  size: 11,
                                  color: t.muted,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  widget.timeAgo,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 11,
                                    color: t.muted,
                                  ),
                                ),
                                const Spacer(),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Delete button
                      const SizedBox(width: 12),
                      _AnnDeleteBtn(onTap: widget.onDelete),
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
}

class _AnnDeleteBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _AnnDeleteBtn({required this.onTap});
  @override
  State<_AnnDeleteBtn> createState() => _AnnDeleteBtnState();
}

class _AnnDeleteBtnState extends State<_AnnDeleteBtn> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _h ? const Color(0xFFFEF2F2) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _h ? const Color(0xFFFCA5A5) : Colors.transparent,
            ),
          ),
          child: Icon(
            Icons.delete_outline_rounded,
            size: 16,
            color: _h ? const Color(0xFFEF4444) : t.muted,
          ),
        ),
      ),
    );
  }
}

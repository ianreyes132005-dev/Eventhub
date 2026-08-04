// ─────────────────────────────────────────────────────────────────────────────
// Admin — Events tab.
// Purpose: the admin's only job here is approving or rejecting events
// organizers submit — a moderation gate before an event goes live and
// becomes visible/registerable to students (enforced server-side, see
// Section 18 of lib/supabase_schema.sql). There is no "manage/cancel a live
// event" affordance on this tab any more — Approved/Rejected are read-only
// history so this stays a queue, not a second cancel mechanism.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_colors.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/audit_service.dart';
import '../organizer/web/web_shared.dart';
import 'admin_shared.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Events page — approval queue
// ═════════════════════════════════════════════════════════════════════════════

class AdminEventsPage extends StatefulWidget {
  const AdminEventsPage({super.key});
  @override State<AdminEventsPage> createState() => _AdminEventsPageState();
}

class _AdminEventsPageState extends State<AdminEventsPage> {
  bool   _loading = true, _error = false;
  String _errorMsg = '';
  List<Map<String, dynamic>> _all = [], _filtered = [];
  String _search       = '';
  String _tab          = 'pending'; // pending | approved | rejected
  String _orgFilter    = 'All';
  String _sortField    = 'created_at';
  bool   _sortAsc      = false;
  final _searchCtrl = TextEditingController();

  RealtimeChannel? _channel;
  Timer?           _debounce;

  List<String> get _orgOptions {
    final names = _all
        .map((e) => (e['organizers'] as Map<String, dynamic>?)?['full_name'] as String?)
        .whereType<String>()
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['All', ...names];
  }

  @override
  void initState() { super.initState(); _load(); _subscribeRealtime(); }
  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    if (_channel != null) SupabaseService.client.removeChannel(_channel!);
    super.dispose();
  }

  void _subscribeRealtime() {
    _channel = SupabaseService.client.channel('admin-events');
    _channel!.on(
      RealtimeListenTypes.postgresChanges,
      ChannelFilter(event: '*', schema: 'public', table: 'events'),
      (_, [__]) => _debounceLoad(),
    );
    _channel!.subscribe();
  }

  void _debounceLoad() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted) _load(silent: true);
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (mounted) setState(() { if (!silent) _loading = true; _error = false; });
    try {
      final rows = await SupabaseService.client.from('events')
          .select('event_id, title, description, location, event_type, event_date, '
              'start_time, end_time, event_image_url, max_participants, '
              'current_participants, organizer_id, created_at, approval_status, '
              'rejection_reason, reviewed_at, organizers(full_name, organization)')
          .order('created_at', ascending: false);
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
      final approval = (e['approval_status'] as String? ?? 'approved');
      if (approval != _tab) return false;
      final orgName = (e['organizers'] as Map<String, dynamic>?)?['full_name'] as String? ?? '';
      if (_orgFilter != 'All' && orgName != _orgFilter) return false;
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
      } else if (_sortField == 'event_date') {
        cmp = ((a['event_date'] as String?) ?? '').compareTo((b['event_date'] as String?) ?? '');
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
      _sortAsc   = field == 'title' || field == 'organizer_name';
    }
    _applyFilter();
  }

  Future<void> _openReview(Map<String, dynamic> event) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _EventReviewDialog(event: event),
    );
    if (result == null) return;
    final action = result['action'] as String?;
    if (action == 'approve') {
      await _decide(event, approve: true);
    } else if (action == 'reject') {
      await _decide(event, approve: false, reason: result['reason'] as String?);
    }
  }

  Future<void> _decide(Map<String, dynamic> event, {required bool approve, String? reason}) async {
    final id      = event['event_id'] as String? ?? '';
    final title   = event['title']    as String? ?? 'this event';
    final orgId   = event['organizer_id'] as String?;
    final orgName = (event['organizers'] as Map<String, dynamic>?)?['full_name'] as String?;
    final user    = SupabaseService.currentUser;

    final payload = <String, dynamic>{
      'approval_status': approve ? 'approved' : 'rejected',
      'rejection_reason': approve ? null : reason,
      'reviewed_by': user?.id,
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      final updated = await SupabaseService.client.from('events')
          .update(payload).eq('event_id', id).select();
      if ((updated as List).isEmpty) {
        if (mounted) _snack('Failed: event not found or you do not have permission.');
        return;
      }
      AuditService.logEvent(
        action: approve ? 'approved' : 'rejected',
        eventTitle: title,
        eventId: id,
        organizerId: orgId,
        organizerName: orgName,
        details: approve
            ? 'Event approved by an administrator'
            : 'Event rejected — $reason',
      );
      final idx = _all.indexWhere((e) => e['event_id'] == id);
      if (idx != -1) { _all[idx] = {..._all[idx], ...payload}; _applyFilter(); }
      if (mounted) {
        WebAlert.success(
          context: context,
          title: approve ? 'Approved' : 'Rejected',
          message: approve
              ? 'Event is now live and visible to students.'
              : 'Event was rejected. The organizer will see the reason.',
        );
      }
    } catch (e) { if (mounted) _snack('Failed: $e'); }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: const Color(0xFFEF4444)));

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);

    int countFor(String status) => _all.where((e) =>
        (e['approval_status'] as String? ?? 'approved') == status).length;
    final pendingCount  = countFor('pending');
    final approvedCount = countFor('approved');
    final rejectedCount = countFor('rejected');
    final tabTotal      = countFor(_tab);

    final hasFilter = _search.isNotEmpty || _orgFilter != 'All';
    final orgOpts   = _orgOptions;
    final tabLabel = switch (_tab) {
      'pending'  => 'events pending review',
      'approved' => 'approved events',
      'rejected' => 'rejected events',
      _          => 'events',
    };
    final emptySubtitle = hasFilter
        ? 'No $tabLabel match your filters.'
        : _tab == 'pending'
            ? 'Nothing waiting for review right now.'
            : 'No $tabLabel yet.';

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kAdminAccent));
    }
    if (_error) {
      return AdminErrorState(message: _errorMsg, onRetry: _load);
    }

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Page header ───────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.fromLTRB(kWebPad, 20, kWebPad, 16),
        color: t.card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Events',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 22,
                    fontWeight: FontWeight.w800, color: t.text)),
              const SizedBox(height: 2),
              Text('Review and approve events submitted by organizers',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.sub)),
            ])),
          ]),
          const SizedBox(height: 16),
          // ── Stat tiles — Pending Review first: this is the number that
          // should drive admin attention, not an equal-weight afterthought.
          // No "Total Events" tile — every other card here maps to a real
          // decision state; a running historical total doesn't, and this
          // tab's job is the queue, not a lifetime counter.
          Row(children: [
            AdminStatCard(label: 'Pending Review', value: '$pendingCount',
                color: const Color(0xFFF59E0B), icon: Icons.pending_actions_rounded),
            const SizedBox(width: 10),
            AdminStatCard(label: 'Approved', value: '$approvedCount',
                color: const Color(0xFF10B981), icon: Icons.check_circle_rounded),
            const SizedBox(width: 10),
            AdminStatCard(label: 'Rejected', value: '$rejectedCount',
                color: const Color(0xFFEF4444), icon: Icons.cancel_rounded),
          ]),
        ]),
      ),
      // ── Filter bar ───────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.fromLTRB(kWebPad, 10, kWebPad, 10),
        decoration: BoxDecoration(
          color: t.inputBg,
          border: Border(bottom: BorderSide(color: t.border)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            WebSearchField(
              controller: _searchCtrl, hint: 'Search title, organizer, or type…',
              onChanged: (v) { _search = v; _applyFilter(); }, width: 200),
            const SizedBox(width: 14),
            Container(width: 1, height: 18, color: t.border),
            const SizedBox(width: 14),
            // No "All" tab — Pending/Approved/Rejected are the three real
            // outcomes; a combined view added a 4th state that mapped to
            // nothing actionable and let the tab drift from "queue" toward
            // "browse everything."
            WebFilterChip(
              label: 'Pending Review', selected: _tab == 'pending',
              onTap: () { _tab = 'pending'; _applyFilter(); },
              count: pendingCount, selectedColor: const Color(0xFFF59E0B)),
            const SizedBox(width: 6),
            WebFilterChip(
              label: 'Approved', selected: _tab == 'approved',
              onTap: () { _tab = 'approved'; _applyFilter(); },
              count: approvedCount, selectedColor: const Color(0xFF10B981)),
            const SizedBox(width: 6),
            WebFilterChip(
              label: 'Rejected', selected: _tab == 'rejected',
              onTap: () { _tab = 'rejected'; _applyFilter(); },
              count: rejectedCount, selectedColor: const Color(0xFFEF4444)),
            if (hasFilter) ...[
              const Spacer(),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    _search = ''; _orgFilter = 'All';
                    _searchCtrl.clear();
                    _applyFilter();
                  },
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.close_rounded, size: 13, color: t.muted),
                  const SizedBox(width: 4),
                  Text('Clear filters', style: TextStyle(fontFamily: 'Poppins',
                      fontSize: 11.5, fontWeight: FontWeight.w600, color: t.muted)),
                ]),
              ),
            ),
          ],
        ]),
        if (orgOpts.length > 1) ...[
          const SizedBox(height: 8),
          Row(children: [
            Text('Organizer:',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  fontWeight: FontWeight.w600, color: t.text)),
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
                  icon: Icon(Icons.keyboard_arrow_down_rounded, size: 14,
                      color: _orgFilter != 'All' ? kAdminAccent : t.muted),
                  onChanged: (v) {
                    if (v != null) { _orgFilter = v; _applyFilter(); }
                  },
                  selectedItemBuilder: (ctx) => orgOpts.map((name) => Center(
                    child: Text(
                      name == 'All' ? 'All Organizers' : name,
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: _orgFilter != 'All' ? kAdminAccent : t.text,
                      )),
                  )).toList(),
                  items: orgOpts.map((name) {
                    final cnt = name == 'All' ? _all.length
                        : _all.where((e) =>
                            ((e['organizers'] as Map<String, dynamic>?)?['full_name'] as String? ?? '') == name).length;
                    final lbl = name == 'All' ? 'All Organizers' : name;
                    return DropdownMenuItem<String>(
                      value: name,
                      child: Text('$lbl ($cnt)',
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 12,
                          fontWeight: name == _orgFilter
                              ? FontWeight.w700 : FontWeight.w400,
                          color: t.text,
                        )),
                    );
                  }).toList(),
                ),
              ),
            ),
          ]),
        ],
      ]),
      ),
      // ── Body ─────────────────────────────────────────────────────────
        if (_filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(kWebPad),
            child: WebEmptyState(
              icon: _tab == 'pending' ? Icons.task_alt_rounded : Icons.event_outlined,
              title: _tab == 'pending' ? 'All caught up' : 'No events found',
              subtitle: emptySubtitle,
              action: hasFilter
                  ? TextButton(
                      onPressed: () {
                        _search = ''; _orgFilter = 'All';
                        _searchCtrl.clear();
                        _applyFilter();
                      },
                      child: const Text('Clear all filters',
                        style: TextStyle(fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600, color: kAdminAccent)))
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
                  showAction: _tab == 'pending',
                ),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: t.border),
                  itemBuilder: (_, i) {
                    final e = _filtered[i];
                    final isPending = (e['approval_status'] as String? ?? 'approved') == 'pending';
                    return _EventRow(
                      event: e,
                      onReview: isPending ? () => _openReview(e) : null,
                    );
                  },
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: t.border))),
                  child: Text(
                    hasFilter
                        ? 'Showing ${_filtered.length} of $tabTotal $tabLabel'
                        : '${_filtered.length} $tabLabel',
                    style: TextStyle(fontFamily: 'Poppins',
                        fontSize: 11.5, color: t.muted)),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

// ─── Event type color helper ──────────────────────────────────────────────────

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

Color _eventTypeColor(String? type) => switch ((type ?? '').toLowerCase()) {
  'academic'  => const Color(0xFF6366F1),
  'cultural'  => const Color(0xFF9333EA),
  'sports'    => const Color(0xFF10B981),
  'seminar'   => const Color(0xFF0EA5E9),
  'workshop'  => const Color(0xFFF59E0B),
  'community' => const Color(0xFF14B8A6),
  _           => kMuted,
};

// ─── Sortable table header for Events ────────────────────────────────────────

class _EventTableHeader extends StatelessWidget {
  final String sortField;
  final bool   sortAsc;
  final bool   showAction;
  final void Function(String) onSort;
  const _EventTableHeader({
    required this.sortField, required this.sortAsc,
    required this.onSort, required this.showAction});

  Widget _sortCol(String label, String field, {int flex = 1}) => Expanded(
    flex: flex,
    child: AdminSortColBtn(
      label: label, field: field,
      active: sortField == field,
      asc:    sortAsc && sortField == field,
      onSort: onSort,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return Container(
      padding: const EdgeInsets.only(left: 23, right: 20, top: 10, bottom: 10),
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(children: [
        const SizedBox(width: 52),
        _sortCol('EVENT',     'title',          flex: 3),
        _sortCol('ORGANIZER', 'organizer_name', flex: 2),
        _sortCol('EVENT DATE','event_date',     flex: 2),
        Expanded(child: Text('STATUS',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5,
              fontWeight: FontWeight.w700, letterSpacing: 0.8, color: t.sub))),
        SizedBox(width: showAction ? 96 : 0),
      ]),
    );
  }
}

class _EventRow extends StatelessWidget {
  final Map<String, dynamic> event;
  final VoidCallback?         onReview;
  const _EventRow({required this.event, this.onReview});

  @override
  Widget build(BuildContext context) {
    final e            = event;
    final approval     = e['approval_status'] as String? ?? 'approved';
    final isRejected   = approval == 'rejected';
    final type         = e['event_type']   as String? ?? '';
    final orgMap       = e['organizers']   as Map<String, dynamic>?;
    final orgName      = orgMap?['full_name']    as String? ?? '—';
    final orgSub       = orgMap?['organization'] as String?;
    final t            = WebTk(Theme.of(context).brightness == Brightness.dark);
    final typeColor    = type.isEmpty ? t.muted : _eventTypeColor(type);
    final timeStr      = _fmtEventTime(e['start_time'] as String?);

    return Container(
      color: Colors.transparent,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            width: 3,
            color: approval == 'pending'
                ? const Color(0xFFF59E0B).withValues(alpha: 0.45)
                : Colors.transparent,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(children: [
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
                    color: typeColor.withValues(alpha: isRejected ? 0.45 : 1.0),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(flex: 3, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(e['title'] as String? ?? '—',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isRejected ? t.muted : t.text),
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
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                              fontWeight: FontWeight.w700, color: typeColor,
                              letterSpacing: 0.3)),
                      ),
                    ],
                  ],
                )),
                Expanded(flex: 2, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(orgName,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                          fontWeight: FontWeight.w500, color: t.sub),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (orgSub != null && orgSub.isNotEmpty)
                      Text(orgSub,
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5,
                            color: t.muted),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                )),
                Expanded(flex: 2, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(webFmtDate(e['event_date'] as String?),
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                          color: isRejected ? t.muted : t.sub)),
                    if (timeStr.isNotEmpty)
                      Text(timeStr, style: TextStyle(fontFamily: 'Poppins',
                          fontSize: 10.5, color: t.muted)),
                  ],
                )),
                Expanded(child: WebStatusBadge(
                  label: approvalStatusLabel(approval),
                  color: approvalStatusColor(approval))),
                if (onReview != null)
                  SizedBox(width: 96, child: Align(
                    alignment: Alignment.centerRight,
                    child: _EventReviewBtn(onTap: onReview!),
                  ))
                else
                  const SizedBox(width: 0),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Review action button — always visible (not hover-gated) on Pending rows;
// mirrors _ReviewBtn in admin_web_registrations.dart. Hover-only reveal on a
// consequential action was flagged as a discoverability/accessibility gap
// elsewhere in this dashboard — don't repeat it for the one action this tab
// exists to support.
class _EventReviewBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _EventReviewBtn({required this.onTap});
  @override State<_EventReviewBtn> createState() => _EventReviewBtnState();
}
class _EventReviewBtnState extends State<_EventReviewBtn> {
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
          color: _h ? const Color(0xFFF59E0B) : const Color(0xFFF59E0B).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: _h ? 0 : 0.28)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.rate_review_outlined, size: 12,
              color: _h ? Colors.white : const Color(0xFFF59E0B)),
          const SizedBox(width: 5),
          Text('Review', style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: _h ? Colors.white : const Color(0xFFF59E0B))),
        ]),
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Event review dialog — shown when admin clicks "Review" on a pending event.
// Structured like _PhotoReviewDialog (admin_web_registrations.dart): header,
// scrollable detail body, action row. Deliberately DIFFERENT from that dialog
// in one respect — Reject requires a reason and a second confirm step rather
// than popping immediately, because a same-shaped no-confirmation Reject was
// flagged as this dashboard's single highest-risk UX gap elsewhere; this is
// the more consequential of the two (it decides whether an event can exist
// at all), so it gets the extra step.
// ═══════════════════════════════════════════════════════════════════════════════

class _EventReviewDialog extends StatefulWidget {
  final Map<String, dynamic> event;
  const _EventReviewDialog({required this.event});
  @override State<_EventReviewDialog> createState() => _EventReviewDialogState();
}

class _EventReviewDialogState extends State<_EventReviewDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _scale, _fade;

  bool _rejecting = false;
  final _reasonCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    _scale = Tween<double>(begin: 0.88, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); _reasonCtrl.dispose(); super.dispose(); }

  Widget _infoTile(BuildContext context, IconData icon, String label, String value) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return Expanded(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 14, color: t.muted),
        const SizedBox(width: 6),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 9.5,
              fontWeight: FontWeight.w700, color: t.muted, letterSpacing: 0.4)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
              fontWeight: FontWeight.w600, color: t.text),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t          = WebTk(Theme.of(context).brightness == Brightness.dark);
    final e          = widget.event;
    final title      = e['title']       as String? ?? '—';
    final desc       = e['description'] as String? ?? '';
    final type       = e['event_type']  as String? ?? '';
    final location   = e['location']    as String? ?? '—';
    final bannerUrl  = e['event_image_url'] as String?;
    final orgMap     = e['organizers']  as Map<String, dynamic>?;
    final orgName    = orgMap?['full_name']    as String? ?? '—';
    final orgSub     = orgMap?['organization'] as String?;
    final max        = e['max_participants'] as int?;
    final dateStr    = webFmtDate(e['event_date'] as String?);
    final startStr   = _fmtEventTime(e['start_time'] as String?);
    final endStr     = _fmtEventTime(e['end_time']   as String?);
    final timeStr    = [startStr, endStr].where((s) => s.isNotEmpty).join(' – ');

    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
            child: Container(
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 40, offset: const Offset(0, 14)),
                ],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: t.border))),
                  child: AdminDialogHeader(
                    icon:      Icons.rate_review_outlined,
                    iconColor: const Color(0xFFF59E0B),
                    title:     'Review Event',
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // Banner — hero element; this is what the admin is
                      // actually here to look at first.
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: double.infinity,
                          height: 180,
                          color: t.inputBg,
                          child: (bannerUrl == null || bannerUrl.isEmpty)
                              ? Center(child: Icon(Icons.image_outlined, size: 40, color: t.muted))
                              : Image.network(
                                  bannerUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Center(
                                    child: Icon(Icons.broken_image_rounded, size: 36, color: t.muted)),
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: Text(title,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 17,
                              fontWeight: FontWeight.w800, color: t.text))),
                        if (type.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _eventTypeColor(type).withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text('${type[0].toUpperCase()}${type.substring(1)}',
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5,
                                  fontWeight: FontWeight.w700, color: _eventTypeColor(type))),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 4),
                      Text('$orgName${orgSub != null && orgSub.isNotEmpty ? ' · $orgSub' : ''}',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: t.sub)),
                      const SizedBox(height: 16),
                      Row(children: [
                        _infoTile(context, Icons.calendar_today_rounded, 'DATE', dateStr),
                        _infoTile(context, Icons.access_time_rounded, 'TIME',
                            timeStr.isEmpty ? '—' : timeStr),
                      ]),
                      const SizedBox(height: 14),
                      Row(children: [
                        _infoTile(context, Icons.location_on_outlined, 'VENUE', location),
                        _infoTile(context, Icons.groups_outlined, 'CAPACITY',
                            max != null && max > 0 ? '$max participants' : 'Unlimited'),
                      ]),
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text('DESCRIPTION',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 9.5,
                              fontWeight: FontWeight.w700, color: t.muted, letterSpacing: 0.4)),
                        const SizedBox(height: 6),
                        Text(desc,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                              color: t.sub, height: 1.5)),
                      ],
                      if (_rejecting) ...[
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.25)),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Reason for rejection',
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                                  fontWeight: FontWeight.w700, color: t.text)),
                            const SizedBox(height: 4),
                            Text('Shown to the organizer — be specific so they can fix and resubmit.',
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5, color: t.sub)),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _reasonCtrl,
                              autofocus: true,
                              maxLines: 3,
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: t.text),
                              decoration: webInputDeco('e.g. Venue conflicts with another approved event',
                                  dark: t.dark),
                              onChanged: (_) => setState(() {}),
                            ),
                          ]),
                        ),
                      ],
                    ]),
                  ),
                ),
                Divider(height: 1, color: t.border),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                  child: _rejecting
                      ? Row(children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => setState(() => _rejecting = false),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: t.border),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                              ),
                              child: Text('Back',
                                style: TextStyle(fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w600, color: t.sub)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _reasonCtrl.text.trim().isEmpty
                                  ? null
                                  : () => Navigator.of(context).pop({
                                      'action': 'reject',
                                      'reason': _reasonCtrl.text.trim(),
                                    }),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFEF4444),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.35),
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                              ),
                              child: const Text('Confirm Reject',
                                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ])
                      : Row(children: [
                          Builder(builder: (ctx) => OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: t.border),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                            ),
                            child: Text('Cancel',
                              style: TextStyle(fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w600, color: t.sub)),
                          )),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => setState(() => _rejecting = true),
                              icon: const Icon(Icons.cancel_outlined,
                                  size: 16, color: Color(0xFFEF4444)),
                              label: const Text('Reject',
                                style: TextStyle(fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w700, color: Color(0xFFEF4444))),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFEF4444)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => Navigator.of(context).pop({'action': 'approve'}),
                              icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                              label: const Text('Approve',
                                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

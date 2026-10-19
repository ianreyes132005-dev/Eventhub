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
import '../../core/friendly_error.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/audit_service.dart';
import '../../core/services/event_change_request_service.dart';
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
  int _page = 0;   // 0-based; kAdminPageSize rows per page
  String _search       = '';
  String _tab          = 'all'; // all | pending | changes | approved | rejected
  // Change requests: edits to live events waiting for review (oldest first).
  List<Map<String, dynamic>> _changeRequests = [];
  // Pending events that were rejected before — the organizer edited them and
  // sent them back. Keyed by event_id.
  Map<String, _Rejection> _lastRejection = {};
  String? _orgFilter;               // organizer_id; null = all organizers
  String _sortField    = 'created_at';
  bool   _sortAsc      = false;
  final _searchCtrl = TextEditingController();

  RealtimeChannel? _channel;
  Timer?           _debounce;

  // Every organizer that has at least one event, keyed by organizer_id (not
  // name — two organizers can share a name). Counts are scoped to the
  // current approval tab so they match the rows the table will show.
  List<_OrgOption> get _orgOptions {
    final byId = <String, _OrgOption>{};
    for (final e in _all) {
      final id = e['organizer_id'] as String?;
      if (id == null) continue;
      final org = e['organizers'] as Map<String, dynamic>?;
      final inTab = _tab == 'all' ||
          (e['approval_status'] as String? ?? 'approved') == _tab;
      final prev = byId[id];
      byId[id] = _OrgOption(
        id:           id,
        name:         (org?['full_name'] as String?)?.trim().isNotEmpty == true
                          ? org!['full_name'] as String : id,
        organization: org?['organization'] as String?,
        count:        (prev?.count ?? 0) + (inTab ? 1 : 0),
      );
    }
    return byId.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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
    for (final table in ['events', 'event_revisions']) {
      _channel!.on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(event: '*', schema: 'public', table: table),
        (_, [_]) => _debounceLoad(),
      );
    }
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
          // '*' (not a column list) so this keeps working whether or not the
          // archives migration (archived_at) has been run yet.
          .select('*, organizers(full_name, organization)')
          .order('created_at', ascending: false);
      final changeRequests = await EventChangeRequestService.pendingForAdmin();
      final pendingIds = [
        for (final e in rows as List)
          if ((e as Map)['approval_status'] == 'pending') e['event_id'] as String,
      ];
      final lastRejection = await _loadLastRejections(pendingIds);
      if (!mounted) return;
      // Archived events live in the Archives tab.
      _all     = [
        for (final e in rows)
          if (!eventIsArchived(e as Map<String, dynamic>)) e,
      ];
      _changeRequests = changeRequests;
      _lastRejection  = lastRejection;
      _loading = false;
      _applyFilter();
    } catch (e) {
      debugPrint('Admin events failed to load: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
          _errorMsg = friendlyError(e, fallback: 'The events couldn’t be loaded. Please try again.');
        });
      }
    }
  }

  // The latest rejection of each of these (pending) events, from the audit
  // log — resubmitting clears the event's own rejection_reason, so this is
  // where the admin can still see why it was sent back the first time.
  Future<Map<String, _Rejection>> _loadLastRejections(List<String> eventIds) async {
    if (eventIds.isEmpty) return {};
    try {
      final rows = await SupabaseService.client.from('event_logs')
          .select('event_id, details, created_at')
          .eq('action', 'rejected')
          .in_('event_id', eventIds)
          .order('created_at', ascending: false);
      final out = <String, _Rejection>{};
      for (final r in rows as List) {
        final id      = r['event_id'] as String?;
        final details = r['details'] as String? ?? '';
        // The event itself, not one of its change requests; newest first.
        if (id == null || !details.startsWith('Event rejected') || out.containsKey(id)) continue;
        out[id] = _Rejection(
          reason: details.replaceFirst(RegExp(r'^Event rejected\s*—?\s*'), '').trim(),
          at: DateTime.tryParse(r['created_at'] as String? ?? '')?.toLocal(),
        );
      }
      return out;
    } catch (e) {
      debugPrint('Admin events: rejection history unavailable: $e');
      return {};
    }
  }

  // resetPage: a new tab / search / filter / sort starts from page 1.
  // Reviews and live reloads keep the current page (clamped in build).
  void _applyFilter({bool resetPage = false}) {
    if (resetPage) _page = 0;
    final q = _search.toLowerCase();
    var list = _all.where((e) {
      final approval = (e['approval_status'] as String? ?? 'approved');
      if (_tab != 'all' && approval != _tab) return false;
      if (_orgFilter != null && e['organizer_id'] != _orgFilter) return false;
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

  void _clearFilters() {
    _search = ''; _orgFilter = null;
    _searchCtrl.clear();
    _applyFilter(resetPage: true);
  }

  Widget _barDivider(WebTk t) => Container(
    width: 1, height: 18, color: t.border,
    margin: const EdgeInsets.symmetric(horizontal: 6),
  );

  void _setSort(String field) {
    if (_sortField == field) {
      _sortAsc = !_sortAsc;
    } else {
      _sortField = field;
      _sortAsc   = field == 'title' || field == 'organizer_name';
    }
    _applyFilter(resetPage: true);
  }

  Future<void> _openReview(Map<String, dynamic> event) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _EventReviewDialog(
          event: event, rejection: _lastRejection[event['event_id']]),
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
        if (mounted) {
          adminErrorAlert(context,
              'This event couldn’t be updated — it may have been removed, or you '
              'don’t have permission to change it.',
              title: approve ? 'Couldn’t approve the event' : 'Couldn’t reject the event');
        }
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
    } catch (e) {
      // Rule messages (e.g. "already started, can no longer be approved")
      // show as written; database wording is translated.
      if (mounted) {
        adminErrorAlert(context, e,
            title: approve ? 'Couldn’t approve the event' : 'Couldn’t reject the event');
      }
    }
  }

  // ── Change requests (edits to live events) ─────────────────────────────────

  List<Map<String, dynamic>> get _visibleChangeRequests {
    final q = _search.toLowerCase();
    return _changeRequests.where((r) {
      final ev  = r['events'] as Map<String, dynamic>?;
      if (_orgFilter != null && ev?['organizer_id'] != _orgFilter) return false;
      if (q.isEmpty) return true;
      final title = (ev?['title'] as String? ?? '').toLowerCase();
      final org   = ((ev?['organizers'] as Map?)?['full_name'] as String? ?? '').toLowerCase();
      return title.contains(q) || org.contains(q);
    }).toList();
  }

  Future<void> _reviewChangeRequest(Map<String, dynamic> rev) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ChangeReviewDialog(request: rev),
    );
    if (result == null || !mounted) return;
    final id    = rev['id'] as String;
    final ev    = rev['events'] as Map<String, dynamic>? ?? const {};
    final title = ev['title'] as String? ?? 'event';
    try {
      if (result['action'] == 'approve') {
        await EventChangeRequestService.approve(id);
        AuditService.logEvent(
          action: 'updated', eventTitle: title, eventId: ev['event_id'] as String?,
          organizerId: ev['organizer_id'] as String?,
          organizerName: (ev['organizers'] as Map?)?['full_name'] as String?,
          details: 'Change request approved: '
              '${(rev['changes'] as Map? ?? const {}).keys.join(', ')}');
      } else {
        await EventChangeRequestService.reject(id, result['reason'] as String);
        AuditService.logEvent(
          action: 'rejected', eventTitle: title, eventId: ev['event_id'] as String?,
          organizerId: ev['organizer_id'] as String?,
          organizerName: (ev['organizers'] as Map?)?['full_name'] as String?,
          details: 'Change request rejected — ${result['reason']}');
      }
      await _load(silent: true);
      if (!mounted) return;
      final approved = result['action'] == 'approve';
      final notifies = EventChangeRequestService.touchesSchedule(
          Map<String, dynamic>.from(rev['changes'] as Map? ?? const {}));
      WebAlert.success(
        context: context,
        title: approved ? 'Changes Approved' : 'Changes Rejected',
        message: approved
            ? '"$title" now shows the new details.'
              '${notifies ? ' Registered students will see an "Event updated" notice.' : ''}'
            : 'The event keeps its current details. The organizer will see your reason.',
      );
    } catch (e) {
      if (mounted) {
        adminErrorAlert(context, e,
            title: result['action'] == 'approve'
                ? 'Couldn’t approve the changes'
                : 'Couldn’t reject the changes');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);

    int countFor(String status) => _all.where((e) =>
        (e['approval_status'] as String? ?? 'approved') == status).length;
    final pendingCount  = countFor('pending');
    final approvedCount = countFor('approved');
    final rejectedCount = countFor('rejected');
    final tabTotal      = _tab == 'all' ? _all.length : countFor(_tab);

    final hasFilter = _search.isNotEmpty || _orgFilter != null;
    final orgOpts   = _orgOptions;
    // Current page (clamped — a review or filter can shrink the list).
    final pageCount = _filtered.isEmpty
        ? 1 : (_filtered.length + kAdminPageSize - 1) ~/ kAdminPageSize;
    final page      = _page.clamp(0, pageCount - 1);
    final pageRows  = _filtered.skip(page * kAdminPageSize).take(kAdminPageSize).toList();
    // Review column: always on Pending; on All only when a pending row is
    // on this page. Every row reserves it so STATUS lines up in a mixed list.
    final showAction = _tab == 'pending' || (_tab == 'all' &&
        pageRows.any((e) => (e['approval_status'] as String? ?? 'approved') == 'pending'));
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
              Text('Archived events are in Archives.',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.muted)),
            ])),
          ]),
          const SizedBox(height: 8),
        ]),
      ),
      // ── Filter bar ───────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.fromLTRB(kWebPad, 10, kWebPad, 10),
        decoration: BoxDecoration(
          color: t.inputBg,
          border: Border(bottom: BorderSide(color: t.border)),
        ),
        // One row: search · approval tabs · organizer. Wraps instead of
        // overflowing on narrow windows; "Clear filters" stays pinned right.
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Wrap(
              spacing: 6, runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                WebSearchField(
                  controller: _searchCtrl, hint: 'Search title, organizer, or type…',
                  onChanged: (v) { _search = v; _applyFilter(resetPage: true); }, width: 200),
                _barDivider(t),
                // "All" first and selected by default: every event regardless
                // of approval state (pending rows still show Review).
                WebFilterChip(
                  label: 'All', selected: _tab == 'all',
                  onTap: () { _tab = 'all'; _applyFilter(resetPage: true); },
                  count: _all.length, selectedColor: kAdminAccent),
                WebFilterChip(
                  label: 'Pending Review', selected: _tab == 'pending',
                  onTap: () { _tab = 'pending'; _applyFilter(resetPage: true); },
                  count: pendingCount, selectedColor: const Color(0xFFF59E0B)),
                // Edits to live events waiting for review.
                WebFilterChip(
                  label: 'Change requests', selected: _tab == 'changes',
                  onTap: () { _tab = 'changes'; _applyFilter(resetPage: true); },
                  count: _changeRequests.length, selectedColor: const Color(0xFF3B82F6)),
                WebFilterChip(
                  label: 'Approved', selected: _tab == 'approved',
                  onTap: () { _tab = 'approved'; _applyFilter(resetPage: true); },
                  count: approvedCount, selectedColor: const Color(0xFF10B981)),
                WebFilterChip(
                  label: 'Rejected', selected: _tab == 'rejected',
                  onTap: () { _tab = 'rejected'; _applyFilter(resetPage: true); },
                  count: rejectedCount, selectedColor: const Color(0xFFEF4444)),
                _barDivider(t),
                _OrganizerFilterMenu(
                  options:    orgOpts,
                  selectedId: _orgFilter,
                  tabTotal:   tabTotal,
                  onSelect:   (id) { _orgFilter = id; _applyFilter(resetPage: true); },
                ),
              ],
            ),
          ),
          if (hasFilter) ...[
            const SizedBox(width: 12),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _clearFilters,
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
      ),
      // ── Body ─────────────────────────────────────────────────────────
        if (_tab == 'changes')
          Padding(
            padding: const EdgeInsets.all(kWebPad),
            child: _ChangeRequestList(
              requests: _visibleChangeRequests,
              onReview: _reviewChangeRequest,
            ),
          )
        else if (_filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(kWebPad),
            child: WebEmptyState(
              icon: _tab == 'pending' ? Icons.task_alt_rounded : Icons.event_outlined,
              title: _tab == 'pending' ? 'All caught up' : 'No events found',
              subtitle: emptySubtitle,
              action: hasFilter
                  ? TextButton(
                      onPressed: _clearFilters,
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
                  showAction: showAction,
                ),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: pageRows.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: t.border),
                  itemBuilder: (_, i) {
                    final e = pageRows[i];
                    final isPending = (e['approval_status'] as String? ?? 'approved') == 'pending';
                    return _EventRow(
                      event: e,
                      onReview: isPending ? () => _openReview(e) : null,
                      reserveAction: showAction,
                      resubmittedAfter: isPending ? _lastRejection[e['event_id']] : null,
                    );
                  },
                ),
                AdminPaginationBar(
                  page:       page,
                  total:      _filtered.length,
                  unfiltered: hasFilter ? tabTotal : null,
                  noun:       tabLabel,
                  onPage:     (p) => setState(() => _page = p),
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

/// The last time an event was rejected — shown when it comes back for review.
class _Rejection {
  final String    reason;
  final DateTime? at;
  const _Rejection({required this.reason, this.at});

  String get when => at == null ? '' : webFmtDate(at!.toIso8601String());

  /// "Rejected on Oct 18, 2026: Venue conflict" (parts left out when unknown).
  String get summary => 'Rejected${when.isEmpty ? '' : ' on $when'}'
      '${reason.isEmpty ? '' : ': $reason'}';
}

/// Blue that stays readable as small text in both themes.
Color _resubmitBlue(bool dark) => dark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB);

class _EventRow extends StatelessWidget {
  final Map<String, dynamic> event;
  final VoidCallback?         onReview;
  // Keep the Review column's width even when this row has no button, so the
  // STATUS column lines up with the header in a mixed (All) list.
  final bool                  reserveAction;
  // Set when this pending event was rejected before and sent back.
  final _Rejection?           resubmittedAfter;
  const _EventRow({required this.event, this.onReview, this.reserveAction = false,
      this.resubmittedAfter});

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
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    WebStatusBadge(
                      label: approvalLabelFor(e),
                      color: approvalColorFor(e)),
                    // Rejected before, edited and sent back by the organizer.
                    if (resubmittedAfter != null) ...[
                      const SizedBox(height: 4),
                      Tooltip(
                        message: '${resubmittedAfter!.summary}\n'
                            'The organizer edited it and sent it back for review.',
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.replay_rounded, size: 12, color: _resubmitBlue(t.dark)),
                          const SizedBox(width: 4),
                          Text('Resubmitted', style: TextStyle(fontFamily: 'Poppins',
                              fontSize: 10.5, fontWeight: FontWeight.w600,
                              color: _resubmitBlue(t.dark))),
                        ]),
                      ),
                    ],
                  ],
                )),
                if (onReview != null)
                  SizedBox(width: 96, child: Align(
                    alignment: Alignment.centerRight,
                    child: _EventReviewBtn(onTap: onReview!),
                  ))
                else
                  SizedBox(width: reserveAction ? 96 : 0),
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
  /// Set when the event was rejected before and the organizer resubmitted it.
  final _Rejection? rejection;
  const _EventReviewDialog({required this.event, this.rejection});
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
                      // Resubmitted: what was wrong last time, so the admin
                      // can check it's been fixed before approving.
                      if (widget.rejection != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _resubmitBlue(t.dark).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: _resubmitBlue(t.dark).withValues(alpha: 0.30)),
                          ),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Icon(Icons.replay_rounded, size: 18, color: _resubmitBlue(t.dark)),
                            const SizedBox(width: 10),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Resubmitted after rejection',
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                                      fontWeight: FontWeight.w700, color: t.text)),
                                const SizedBox(height: 3),
                                Text('${widget.rejection!.summary}. The organizer edited '
                                    'the event and sent it back — check that it’s been '
                                    'fixed before approving.',
                                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                                      color: t.sub, height: 1.5)),
                              ],
                            )),
                          ]),
                        ),
                        const SizedBox(height: 14),
                      ],
                      // Expired: the event started before it was reviewed —
                      // approving now would open registration mid-event.
                      if (approvalExpired(e)) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6B7280).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF6B7280).withValues(alpha: 0.30)),
                          ),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Icon(Icons.history_toggle_off_rounded, size: 18, color: t.sub),
                            const SizedBox(width: 10),
                            Expanded(child: Text(
                              'This event’s start time has already passed, so it can no longer '
                              'be approved. Reject it with a note asking the organizer to '
                              'reschedule and resubmit.',
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                                  color: t.sub, height: 1.5))),
                          ]),
                        ),
                        const SizedBox(height: 14),
                      ],
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
                        // Capacity is fixed: every active student can register.
                        _infoTile(context, Icons.groups_outlined, 'CAPACITY', 'All students'),
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
                              // Disabled once the start time has passed (server rejects it too).
                              onPressed: approvalExpired(e)
                                  ? null
                                  : () => Navigator.of(context).pop({'action': 'approve'}),
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

// ─── Organizer filter menu ───────────────────────────────────────────────────
// Trigger:  [ 👤 Organizer · All organizers ▾ ]   active: [ 👤 Organizer · Maria Santos ✕ ]
// Menu:
//   [ 🔍 Search organizers… ]            ← only when there are > 6 organizers
//   ✓ All organizers                  12
//   ──────────────────────────────────
//   (MS) Maria Santos                  3
//        Student Council
//   (JR) Jose Rizal                    0  ← dimmed: none in this tab
// Counts follow the active approval tab, so they match the table's rows.

class _OrgOption {
  final String  id, name;
  final String? organization;
  final int     count;
  const _OrgOption({
    required this.id, required this.name, required this.organization, required this.count});
}

const double _kOrgMenuWidth = 300;
const double _kOrgItemW     = 276;   // 300 − 8 panel padding − 16 item padding

class _OrganizerFilterMenu extends StatefulWidget {
  final List<_OrgOption> options;
  final String?          selectedId;   // null = all organizers
  final int              tabTotal;     // events in the current tab
  final ValueChanged<String?> onSelect;

  const _OrganizerFilterMenu({
    required this.options, required this.selectedId,
    required this.tabTotal, required this.onSelect,
  });

  @override
  State<_OrganizerFilterMenu> createState() => _OrganizerFilterMenuState();
}

class _OrganizerFilterMenuState extends State<_OrganizerFilterMenu> {
  final _menu   = MenuController();
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);

    _OrgOption? selected;
    for (final o in widget.options) {
      if (o.id == widget.selectedId) { selected = o; break; }
    }
    final showSearch = widget.options.length > 6;
    final q = _query.trim().toLowerCase();
    final visible = q.isEmpty
        ? widget.options
        : widget.options.where((o) =>
            o.name.toLowerCase().contains(q) ||
            (o.organization ?? '').toLowerCase().contains(q) ||
            o.id.toLowerCase().contains(q)).toList();

    Widget note(String text) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Text(text, textAlign: TextAlign.center,
        style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.muted)),
    );

    return MenuAnchor(
      controller: _menu,
      alignmentOffset: const Offset(0, 6),
      style: adminFilterMenuStyle(t, width: _kOrgMenuWidth, maxHeight: 440),
      onClose: () {
        if (_query.isNotEmpty) setState(() { _query = ''; _search.clear(); });
      },
      menuChildren: [
        if (showSearch)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
            child: SizedBox(
              width: _kOrgMenuWidth - 16,
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: t.text),
                decoration: webInputDeco('Search organizers…',
                    icon: Icons.search_rounded, dark: t.dark).copyWith(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
            ),
          ),
        _OrgMenuItem(
          name: 'All organizers', count: widget.tabTotal,
          selected: widget.selectedId == null,
          leading: _OrgAvatar.icon(Icons.groups_rounded, selected: widget.selectedId == null),
          onPressed: () => widget.onSelect(null),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
          child: Divider(height: 1, thickness: 1, color: t.border),
        ),
        if (widget.options.isEmpty)
          note('No organizers have submitted events yet.')
        else if (visible.isEmpty)
          note('No organizers match “${_query.trim()}”.')
        else
          for (final o in visible)
            _OrgMenuItem(
              name: o.name, subtitle: o.organization, count: o.count,
              selected: o.id == widget.selectedId,
              leading: _OrgAvatar.initials(o.name, selected: o.id == widget.selectedId),
              onPressed: () => widget.onSelect(o.id),
            ),
      ],
      builder: (context, controller, _) => AdminFilterTrigger(
        icon:   Icons.person_rounded,
        label:  'Organizer',
        value:  selected?.name ?? 'All organizers',
        active: widget.selectedId != null,
        open:   controller.isOpen,
        onTap:  () => controller.isOpen ? controller.close() : controller.open(),
        onClear: () { controller.close(); widget.onSelect(null); },
      ),
    );
  }
}

// Small round avatar: initials for an organizer, an icon for "All".
class _OrgAvatar extends StatelessWidget {
  final String?   initials;
  final IconData? icon;
  final bool      selected;
  const _OrgAvatar._({this.initials, this.icon, required this.selected});

  factory _OrgAvatar.initials(String name, {required bool selected}) {
    final parts = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final ini = parts.isEmpty
        ? '?'
        : parts.length == 1
            ? parts.first[0].toUpperCase()
            : '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return _OrgAvatar._(initials: ini, selected: selected);
  }

  factory _OrgAvatar.icon(IconData icon, {required bool selected}) =>
      _OrgAvatar._(icon: icon, selected: selected);

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final fg = selected ? kAdminAccent : t.sub;
    return Container(
      width: 26, height: 26,
      decoration: BoxDecoration(
        color: selected
            ? kAdminAccent.withValues(alpha: 0.14)
            : (t.dark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF1F5F9)),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: icon != null
          ? Icon(icon, size: 14, color: fg)
          : Text(initials!,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                  fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

// One organizer row: avatar · name (+ organization) · count · check.
// Built on MenuItemButton so arrow keys / Enter / Esc work out of the box.
class _OrgMenuItem extends StatelessWidget {
  final String  name;
  final String? subtitle;
  final int     count;
  final bool    selected;
  final Widget  leading;
  final VoidCallback onPressed;

  const _OrgMenuItem({
    required this.name, required this.count, required this.selected,
    required this.leading, required this.onPressed, this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final t       = WebTk(Theme.of(context).brightness == Brightness.dark);
    final empty   = count == 0;
    final hasSub  = subtitle != null && subtitle!.trim().isNotEmpty;

    return Semantics(
      selected: selected,
      label: '$name${hasSub ? ', $subtitle' : ''}, $count events',
      child: MenuItemButton(
        onPressed: onPressed,
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
          minimumSize: WidgetStatePropertyAll(Size(0, hasSub ? 44 : 36)),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (selected) return kAdminAccent.withValues(alpha: 0.10);
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return t.dark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9);
            }
            return Colors.transparent;
          }),
        ),
        child: SizedBox(
          width: _kOrgItemW,
          child: Row(children: [
            leading,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? kAdminAccent : (empty ? t.sub : t.text))),
                  if (hasSub)
                    Text(subtitle!,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 24,
              child: Text('$count',
                textAlign: TextAlign.right,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: selected ? kAdminAccent : t.muted)),
            ),
            SizedBox(
              width: 22,
              child: selected
                  ? const Align(alignment: Alignment.centerRight,
                      child: Icon(Icons.check_rounded, size: 14, color: kAdminAccent))
                  : null,
            ),
          ]),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Change requests — edits an organizer submitted for a LIVE event. The event
// keeps its current details until approved (see event_change_request_service).
// ═══════════════════════════════════════════════════════════════════════════════

const _kChangeBlue = Color(0xFF3B82F6);

const _kFieldLabels = <String, String>{
  'title':            'Title',
  'description':      'Description',
  'event_type':       'Category',
  'location':         'Venue',
  'event_date':       'Start date',
  'end_date':         'End date',
  'start_time':       'Start time',
  'end_time':         'End time',
  'max_participants': 'Capacity', // legacy — only in requests sent before capacity became "all students"
  'allow_walk_in':    'Walk-ins', // legacy — only in requests sent before walk-ins were removed
  'event_image_url':  'Banner',
};

String _fmtChangeValue(String key, Object? v) {
  final s = (v ?? '').toString().trim();
  switch (key) {
    case 'event_date':
    case 'end_date':
      return s.isEmpty ? '—' : webFmtDate(s);
    case 'start_time':
    case 'end_time':
      final f = _fmtEventTime(s);
      return f.isEmpty ? '—' : f;
    case 'max_participants':
      final n = v is int ? v : int.tryParse(s);
      return n == null || n <= 0 ? 'Unlimited' : '$n participants';
    case 'allow_walk_in':
      return v == true ? 'Allowed' : 'Not allowed';
    case 'event_type':
      return s.isEmpty ? '—' : '${s[0].toUpperCase()}${s.substring(1)}';
    default:
      return s.isEmpty ? '—' : s;
  }
}

String _timeAgo(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1)  return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24)   return '${diff.inHours}h ago';
  if (diff.inDays < 7)     return '${diff.inDays}d ago';
  return webFmtDate(d.toIso8601String());
}

String _submittedAt(Map<String, dynamic> r) =>
    _timeAgo((r['updated_at'] ?? r['created_at']) as String?);

class _ChangeRequestList extends StatelessWidget {
  final List<Map<String, dynamic>> requests;
  final void Function(Map<String, dynamic>) onReview;
  const _ChangeRequestList({required this.requests, required this.onReview});

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    if (requests.isEmpty) {
      return const WebEmptyState(
        icon: Icons.task_alt_rounded,
        title: 'No change requests',
        subtitle: 'When an organizer edits a live event, their changes wait here for review.',
      );
    }
    final n = requests.length;
    return WebCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: n,
          separatorBuilder: (_, _) => Divider(height: 1, color: t.border),
          itemBuilder: (_, i) => _ChangeRequestRow(
            request: requests[i], onReview: () => onReview(requests[i])),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: t.border))),
          child: Text(
            '$n change request${n == 1 ? '' : 's'} · '
            'each event keeps its current details until you approve',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: t.muted)),
        ),
      ]),
    );
  }
}

class _ChangeRequestRow extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback onReview;
  const _ChangeRequestRow({required this.request, required this.onReview});

  @override
  Widget build(BuildContext context) {
    final t        = WebTk(Theme.of(context).brightness == Brightness.dark);
    final ev       = request['events'] as Map<String, dynamic>? ?? const {};
    final changes  = Map<String, dynamic>.from(request['changes'] as Map? ?? const {});
    final orgMap   = ev['organizers'] as Map<String, dynamic>?;
    final orgName  = orgMap?['full_name']    as String? ?? '—';
    final orgSub   = orgMap?['organization'] as String?;
    final notifies = EventChangeRequestService.touchesSchedule(changes);
    final labels   = [
      for (final k in EventChangeRequestService.editableFields)
        if (changes.containsKey(k)) _kFieldLabels[k] ?? k,
    ];

    Widget chip(String text, Color c, {IconData? icon}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 11, color: c), const SizedBox(width: 3)],
        Text(text, style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
            fontWeight: FontWeight.w700, color: c)),
      ]),
    );

    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(width: 3, color: _kChangeBlue.withValues(alpha: 0.45)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: _kChangeBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kChangeBlue.withValues(alpha: 0.18)),
                ),
                child: const Icon(Icons.edit_calendar_rounded, size: 20, color: _kChangeBlue),
              ),
              const SizedBox(width: 12),
              Expanded(flex: 3, child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(ev['title'] as String? ?? '—',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                        fontWeight: FontWeight.w600, color: t.text),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Wrap(spacing: 4, runSpacing: 4, children: [
                    for (final l in labels) chip(l, t.sub),
                    if (notifies)
                      chip('Students notified', const Color(0xFFF59E0B),
                          icon: Icons.notifications_active_outlined),
                  ]),
                ],
              )),
              const SizedBox(width: 12),
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
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5, color: t.muted),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              )),
              Expanded(flex: 2, child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(webFmtDate(ev['event_date'] as String?),
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.sub)),
                  Text('Submitted ${_submittedAt(request)}',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5, color: t.muted)),
                ],
              )),
              SizedBox(width: 96, child: Align(
                alignment: Alignment.centerRight,
                child: _EventReviewBtn(onTap: onReview),
              )),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Current → Proposed comparison with Approve / Reject (reason required).
/// Pops {'action': 'approve'} or {'action': 'reject', 'reason': ...}.
class _ChangeReviewDialog extends StatefulWidget {
  final Map<String, dynamic> request;
  const _ChangeReviewDialog({required this.request});
  @override State<_ChangeReviewDialog> createState() => _ChangeReviewDialogState();
}

class _ChangeReviewDialogState extends State<_ChangeReviewDialog> {
  bool _rejecting = false;
  final _reasonCtrl = TextEditingController();
  int? _registered;

  Map<String, dynamic> get _event =>
      widget.request['events'] as Map<String, dynamic>? ?? const {};
  Map<String, dynamic> get _changes =>
      Map<String, dynamic>.from(widget.request['changes'] as Map? ?? const {});

  @override
  void initState() {
    super.initState();
    if (EventChangeRequestService.touchesSchedule(_changes)) _countRegistered();
  }

  Future<void> _countRegistered() async {
    final id = _event['event_id'] as String?;
    if (id == null) return;
    try {
      final rows = await SupabaseService.client.from('registrations')
          .select('event_id').eq('event_id', id);
      if (mounted) setState(() => _registered = (rows as List).length);
    } catch (_) {}
  }

  @override
  void dispose() { _reasonCtrl.dispose(); super.dispose(); }

  Widget _banner(WebTk t, Map<String, dynamic> m) {
    final url = m['event_image_url'] as String?;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 72, width: double.infinity, color: t.inputBg,
        child: (url == null || url.isEmpty)
            ? Center(child: Icon(Icons.image_outlined, size: 22, color: t.muted))
            : Image.network(url, fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Center(
                  child: Icon(Icons.broken_image_rounded, size: 20, color: t.muted))),
      ),
    );
  }

  Widget _diffRow(WebTk t, String key) {
    final isBanner = key == 'event_image_url';
    final cur = isBanner
        ? _banner(t, _event)
        : Text(_fmtChangeValue(key, _event[key]),
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: t.muted,
                decoration: TextDecoration.lineThrough, decorationColor: t.muted));
    final next = isBanner
        ? _banner(t, _changes)
        : Text(_fmtChangeValue(key, _changes[key]),
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                fontWeight: FontWeight.w600, color: t.text));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 96, child: Text(_kFieldLabels[key] ?? key,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
              fontWeight: FontWeight.w700, color: t.sub))),
        Expanded(child: cur),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.arrow_forward_rounded, size: 14, color: t.muted)),
        Expanded(child: next),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t        = WebTk(Theme.of(context).brightness == Brightness.dark);
    final ev       = _event;
    final changes  = _changes;
    final orgMap   = ev['organizers'] as Map<String, dynamic>?;
    final orgName  = orgMap?['full_name'] as String? ?? '—';
    final notifies = EventChangeRequestService.touchesSchedule(changes);
    final noteColor = notifies ? const Color(0xFFF59E0B) : _kChangeBlue;
    final who = _registered == null
        ? 'Registered students'
        : '$_registered registered student${_registered == 1 ? '' : 's'}';
    final keys = [
      for (final k in EventChangeRequestService.editableFields)
        if (changes.containsKey(k)) k,
    ];

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 680),
        child: Container(
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 40, offset: const Offset(0, 14))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.border))),
              child: const AdminDialogHeader(
                icon: Icons.edit_calendar_rounded,
                iconColor: _kChangeBlue,
                title: 'Review Changes',
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(ev['title'] as String? ?? '—',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 16,
                        fontWeight: FontWeight.w800, color: t.text)),
                  const SizedBox(height: 2),
                  Text('$orgName · submitted ${_submittedAt(widget.request)}',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.sub)),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: noteColor.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: noteColor.withValues(alpha: 0.28)),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(notifies ? Icons.notifications_active_outlined : Icons.info_outline_rounded,
                          size: 18, color: noteColor),
                      const SizedBox(width: 10),
                      Expanded(child: Text(
                        notifies
                            ? '$who will be notified that the date, time or venue changed.'
                            : 'This event is live. It keeps its current details until you approve.',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                            color: t.sub, height: 1.5))),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    const SizedBox(width: 96),
                    Expanded(child: Text('CURRENT', style: TextStyle(fontFamily: 'Poppins',
                        fontSize: 9.5, fontWeight: FontWeight.w700, color: t.muted,
                        letterSpacing: 0.6))),
                    const SizedBox(width: 30),
                    Expanded(child: Text('PROPOSED', style: TextStyle(fontFamily: 'Poppins',
                        fontSize: 9.5, fontWeight: FontWeight.w700, color: _kChangeBlue,
                        letterSpacing: 0.6))),
                  ]),
                  for (var i = 0; i < keys.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: t.border),
                    _diffRow(t, keys[i]),
                  ],
                  if (_rejecting) ...[
                    const SizedBox(height: 14),
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
                        Text('Shown to the organizer. The event keeps its current details.',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5, color: t.sub)),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _reasonCtrl,
                          autofocus: true,
                          maxLines: 3,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: t.text),
                          decoration: webInputDeco('e.g. The gymnasium is booked that afternoon',
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
                      Expanded(child: OutlinedButton(
                        onPressed: () => setState(() => _rejecting = false),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: t.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        child: Text('Back', style: TextStyle(fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600, color: t.sub)),
                      )),
                      const SizedBox(width: 10),
                      Expanded(child: ElevatedButton(
                        onPressed: _reasonCtrl.text.trim().isEmpty
                            ? null
                            : () => Navigator.of(context).pop({
                                'action': 'reject', 'reason': _reasonCtrl.text.trim()}),
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
                      )),
                    ])
                  : Row(children: [
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: t.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                        ),
                        child: Text('Cancel', style: TextStyle(fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600, color: t.sub)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: OutlinedButton.icon(
                        onPressed: () => setState(() => _rejecting = true),
                        icon: const Icon(Icons.cancel_outlined, size: 16, color: Color(0xFFEF4444)),
                        label: const Text('Reject', style: TextStyle(fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700, color: Color(0xFFEF4444))),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFEF4444)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: ElevatedButton.icon(
                        onPressed: () => Navigator.of(context).pop({'action': 'approve'}),
                        icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                        label: const Text('Approve', style: TextStyle(fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                      )),
                    ]),
            ),
          ]),
        ),
      ),
    );
  }
}

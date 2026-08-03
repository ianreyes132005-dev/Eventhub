// ─────────────────────────────────────────────────────────────────────────────
// Admin — Events tab.
// Split out of admin_web_dashboard.dart so each sidebar tab has its own file.
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
// Events page (read-only)
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
  String _statusFilter = 'All';
  String _typeFilter   = 'All';
  String _fillFilter   = 'All';
  String _sortField    = 'event_date';
  bool   _sortAsc      = false;
  final _searchCtrl = TextEditingController();

  RealtimeChannel? _channel;
  Timer?           _debounce;

  List<String> get _typeOptions {
    final types = _all
        .map((e) => e['event_type'] as String?)
        .whereType<String>()
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['All', ...types];
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
    for (final table in ['events', 'registrations']) {
      _channel!.on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(event: '*', schema: 'public', table: table),
        (_, [__]) => _debounceLoad(),
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
          .select('event_id, title, event_type, event_date, start_time, end_time, event_status, current_participants, max_participants, organizer_id, organizers(full_name, organization)')
          .order('event_date', ascending: false);
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
      if (_statusFilter != 'All') {
        if (_statusFilter == 'ended') {
          if (_resolveDisplayStatus(e) != 'ended') return false;
        } else {
          if (e['event_status'] != _statusFilter) return false;
        }
      }
      if (_typeFilter   != 'All' && (e['event_type'] as String? ?? '') != _typeFilter) return false;
      if (_fillFilter == 'At Capacity') {
        final cur = (e['current_participants'] as int?) ?? 0;
        final max = (e['max_participants']     as int?) ?? 0;
        if (max == 0 || cur < max) return false;
      }
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
      } else if (_sortField == 'fill_rate') {
        final maxA = (a['max_participants'] as int?) ?? 0;
        final maxB = (b['max_participants'] as int?) ?? 0;
        final rA   = maxA > 0 ? ((a['current_participants'] as int? ?? 0) / maxA) : 0.0;
        final rB   = maxB > 0 ? ((b['current_participants'] as int? ?? 0) / maxB) : 0.0;
        cmp = rA.compareTo(rB);
      } else if (_sortField == 'event_status') {
        const order = {'ongoing': 0, 'upcoming': 1, 'ended': 2, 'completed': 3, 'cancelled': 4};
        final ao = order[_resolveDisplayStatus(a)] ?? 5;
        final bo = order[_resolveDisplayStatus(b)] ?? 5;
        cmp = ao.compareTo(bo);
      } else {
        cmp = ((a['event_date'] as String?) ?? '').compareTo((b['event_date'] as String?) ?? '');
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
      _sortAsc   = field == 'title' || field == 'event_status' || field == 'organizer_name';
    }
    _applyFilter();
  }

  Future<void> _cancelEvent(String id, String title) async {
    final ok = await WebAlert.confirm(
      context:      context,
      title:        'Cancel Event?',
      message:      '"$title" will be marked as Cancelled. Registered students will be affected. This cannot be undone.',
      confirmLabel: 'Cancel Event',
      confirmColor: const Color(0xFFEF4444),
      iconColor:    const Color(0xFFEF4444),
      iconBg:       const Color(0xFFFEF2F2),
      icon:         Icons.cancel_rounded,
    );
    if (ok != true) return;
    try {
      final updated = await SupabaseService.client.from('events')
          .update({'event_status': 'cancelled'}).eq('event_id', id).select();
      if ((updated as List).isEmpty) {
        if (mounted) _snack('Failed: event not found or you do not have permission to cancel it.');
        return;
      }
      final idx    = _all.indexWhere((e) => e['event_id'] == id);
      final orgMap = idx != -1 ? _all[idx]['organizers'] as Map<String, dynamic>? : null;
      AuditService.logEvent(
        action: 'cancelled',
        eventTitle: title,
        eventId: id,
        organizerId: idx != -1 ? _all[idx]['organizer_id'] as String? : null,
        organizerName: orgMap?['full_name'] as String?,
        details: 'Event cancelled by an administrator',
      );
      if (idx != -1) { _all[idx] = {..._all[idx], 'event_status': 'cancelled'}; _applyFilter(); }
      if (mounted) WebAlert.success(context: context, title: 'Cancelled', message: 'Event has been cancelled.');
    } catch (e) { if (mounted) _snack('Failed: $e'); }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: const Color(0xFFEF4444)));

  @override
  Widget build(BuildContext context) {
    final t              = WebTk(Theme.of(context).brightness == Brightness.dark);
    final totalCount     = _all.length;
    final upcomingCount  = _all.where((e) => _resolveDisplayStatus(e) == 'upcoming').length;
    final ongoingCount   = _all.where((e) => _resolveDisplayStatus(e) == 'ongoing').length;
    final endedCount     = _all.where((e) => _resolveDisplayStatus(e) == 'ended').length;
    final completedCount = _all.where((e) => e['event_status'] == 'completed').length;
    final cancelledCount = _all.where((e) => e['event_status'] == 'cancelled').length;
    final atCapacityCount = _all.where((e) {
      final cur = (e['current_participants'] as int?) ?? 0;
      final max = (e['max_participants']     as int?) ?? 0;
      return max > 0 && cur >= max;
    }).length;
    final hasFilter = _search.isNotEmpty || _statusFilter != 'All' ||
                      _typeFilter != 'All'   || _fillFilter  != 'All';
    final typeOpts  = _typeOptions;
    final filterDesc = [
      if (_statusFilter != 'All') webEventStatusLabel(_statusFilter),
      if (_typeFilter   != 'All' && _typeFilter.isNotEmpty)
          '${_typeFilter[0].toUpperCase()}${_typeFilter.substring(1)}',
      if (_fillFilter   != 'All') _fillFilter,
      if (_search.isNotEmpty)     '"$_search"',
    ].join(' · ');
    final emptySubtitle = filterDesc.isEmpty
        ? 'No events have been created yet.'
        : 'No events match $filterDesc.';

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
              Text('$totalCount total · $upcomingCount upcoming · $ongoingCount ongoing',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.sub)),
            ])),
          ]),
          const SizedBox(height: 16),
          // ── Stat tiles ────────────────────────────────────────────────
          Row(children: [
            AdminStatCard(label: 'Total Events', value: '$totalCount',
                color: kAdminAccent, icon: Icons.event_rounded),
            const SizedBox(width: 10),
            AdminStatCard(label: 'Upcoming', value: '$upcomingCount',
                color: const Color(0xFF3B82F6), icon: Icons.schedule_rounded),
            const SizedBox(width: 10),
            AdminStatCard(label: 'Ongoing', value: '$ongoingCount',
                color: const Color(0xFF10B981), icon: Icons.play_circle_rounded),
            const SizedBox(width: 10),
            AdminStatCard(label: 'Ended', value: '${endedCount + completedCount}',
                color: const Color(0xFF6B7280), icon: Icons.check_circle_rounded),
            const SizedBox(width: 10),
            AdminStatCard(
              label: 'Cancelled',
              value: '$cancelledCount',
              color: cancelledCount > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
              icon: Icons.cancel_rounded,
            ),
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
          // Status filter row
          Row(children: [
            WebSearchField(
              controller: _searchCtrl, hint: 'Search title, organizer, or type…',
              onChanged: (v) { _search = v; _applyFilter(); }, width: 200),
            const SizedBox(width: 14),
            Container(width: 1, height: 18, color: t.border),
            const SizedBox(width: 14),
            Text('Status:',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  fontWeight: FontWeight.w600, color: t.text)),
            const SizedBox(width: 8),
            WebFilterChip(
              label: 'All', selected: _statusFilter == 'All',
              onTap: () { _statusFilter = 'All'; _applyFilter(); },
              count: totalCount),
            const SizedBox(width: 6),
            for (final s in ['upcoming', 'ongoing', 'ended', 'completed', 'cancelled']) ...[
              WebFilterChip(
                label: webEventStatusLabel(s),
                selected: _statusFilter == s,
                onTap: () { _statusFilter = s; _applyFilter(); },
                count: s == 'upcoming' || s == 'ongoing' || s == 'ended'
                    ? _all.where((e) => _resolveDisplayStatus(e) == s).length
                    : _all.where((e) => e['event_status'] == s).length,
                selectedColor: webEventStatusColor(s)),
              const SizedBox(width: 6),
            ],
            if (hasFilter) ...[
              const Spacer(),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    _search = ''; _statusFilter = 'All';
                    _typeFilter = 'All'; _fillFilter = 'All';
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
        // Type + Capacity — single compact row
        if (typeOpts.length > 1 || atCapacityCount > 0) ...[
          const SizedBox(height: 8),
          Row(children: [
            if (typeOpts.length > 1) ...[
              Text('Type:',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w600, color: t.text)),
              const SizedBox(width: 8),
              Container(
                height: 28,
                padding: const EdgeInsets.only(left: 10, right: 6),
                decoration: BoxDecoration(
                  color: _typeFilter != 'All'
                      ? _eventTypeColor(_typeFilter).withValues(alpha: 0.07)
                      : t.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _typeFilter != 'All'
                        ? _eventTypeColor(_typeFilter).withValues(alpha: 0.45)
                        : t.border,
                    width: _typeFilter != 'All' ? 1.5 : 1.0,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: typeOpts.contains(_typeFilter) ? _typeFilter : 'All',
                    isDense: true,
                    icon: Icon(Icons.keyboard_arrow_down_rounded, size: 14,
                        color: _typeFilter != 'All'
                            ? _eventTypeColor(_typeFilter) : t.muted),
                    onChanged: (v) {
                      if (v != null) { _typeFilter = v; _applyFilter(); }
                    },
                    selectedItemBuilder: (ctx) => typeOpts.map((typ) => Center(
                      child: Text(
                        typ == 'All' ? 'All Types'
                            : '${typ[0].toUpperCase()}${typ.substring(1)}',
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: _typeFilter != 'All'
                              ? _eventTypeColor(_typeFilter) : t.text,
                        )),
                    )).toList(),
                    items: typeOpts.map((typ) {
                      final cnt = typ == 'All' ? totalCount
                          : _all.where((e) =>
                              (e['event_type'] as String? ?? '') == typ).length;
                      final lbl = typ == 'All' ? 'All Types'
                          : '${typ[0].toUpperCase()}${typ.substring(1)}';
                      return DropdownMenuItem<String>(
                        value: typ,
                        child: Text('$lbl ($cnt)',
                          style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 12,
                            fontWeight: typ == _typeFilter
                                ? FontWeight.w700 : FontWeight.w400,
                            color: typ == 'All' ? t.text : _eventTypeColor(typ),
                          )),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
            if (typeOpts.length > 1 && atCapacityCount > 0) ...[
              const SizedBox(width: 12),
              Container(width: 1, height: 18, color: t.border),
              const SizedBox(width: 12),
            ],
            if (atCapacityCount > 0) ...[
              Text('Capacity:',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w600, color: t.text)),
                const SizedBox(width: 8),
                WebFilterChip(
                  label: 'At Capacity',
                  selected: _fillFilter == 'At Capacity',
                  onTap: () {
                    _fillFilter = _fillFilter == 'At Capacity' ? 'All' : 'At Capacity';
                    _applyFilter();
                  },
                  count: atCapacityCount,
                  selectedColor: const Color(0xFFEF4444)),
              ],
            ]),
          ],
        ]),
      ),
      // ── Body ─────────────────────────────────────────────────────────
        if (_filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(kWebPad),
            child: WebEmptyState(
              icon: Icons.event_outlined,
              title: 'No events found',
              subtitle: emptySubtitle,
              action: hasFilter
                  ? TextButton(
                      onPressed: () {
                        _search = ''; _statusFilter = 'All';
                        _typeFilter = 'All'; _fillFilter = 'All';
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
                ),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: t.border),
                  itemBuilder: (_, i) {
                    final e           = _filtered[i];
                    final dispStatus  = _resolveDisplayStatus(e);
                    return _EventRow(
                      event: e,
                      onCancel: (dispStatus == 'upcoming' || dispStatus == 'ongoing')
                          ? () => _cancelEvent(
                              e['event_id'] as String? ?? '',
                              e['title']    as String? ?? 'this event')
                          : null,
                    );
                  },
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: t.border))),
                  child: Text(
                    hasFilter
                        ? 'Showing ${_filtered.length} of $totalCount events'
                        : '${_filtered.length} events total',
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

// ─── Event display-status helper ─────────────────────────────────────────────
// Returns 'ended' when an 'upcoming'/'ongoing' event's date/time has passed,
// otherwise returns the raw DB status unchanged.

String _resolveDisplayStatus(Map<String, dynamic> event) {
  final db = (event['event_status'] as String? ?? '').toLowerCase();
  if (db != 'upcoming' && db != 'ongoing') return db;

  final dStr = event['event_date'] as String?;
  if (dStr == null) return db;
  try {
    final d    = DateTime.parse(dStr);
    final eDay = DateTime(d.year, d.month, d.day);
    final now  = DateTime.now();
    final nDay = DateTime(now.year, now.month, now.day);

    if (nDay.isAfter(eDay)) return 'ended';

    if (nDay == eDay) {
      final eStr = event['end_time'] as String?;
      if (eStr != null) {
        final p = eStr.split(':');
        final h = int.tryParse(p[0]) ?? 0;
        final m = p.length > 1 ? (int.tryParse(p[1]) ?? 0) : 0;
        if (now.isAfter(DateTime(d.year, d.month, d.day, h, m))) return 'ended';
      }
    }
  } catch (_) {}
  return db;
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
  final void Function(String) onSort;
  const _EventTableHeader({
    required this.sortField, required this.sortAsc, required this.onSort});

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
        _sortCol('DATE',      'event_date',     flex: 2),
        _sortCol('STATUS',    'event_status'),
        _sortCol('FILL RATE', 'fill_rate',      flex: 2),
        const SizedBox(width: 44),
      ]),
    );
  }
}

class _EventRow extends StatefulWidget {
  final Map<String, dynamic> event;
  final VoidCallback?         onCancel;
  const _EventRow({required this.event, this.onCancel});
  @override State<_EventRow> createState() => _EventRowState();
}
class _EventRowState extends State<_EventRow> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final e            = widget.event;
    final dbStatus     = e['event_status'] as String? ?? '';
    final dispStatus   = _resolveDisplayStatus(e);
    final type         = e['event_type']   as String? ?? '';
    final orgMap       = e['organizers']   as Map<String, dynamic>?;
    final orgName      = orgMap?['full_name']    as String? ?? '—';
    final orgSub       = orgMap?['organization'] as String?;
    final cur          = e['current_participants'] as int? ?? 0;
    final max          = e['max_participants']     as int? ?? 0;
    final pct          = max > 0 ? (cur / max).clamp(0.0, 1.0) : 0.0;
    final isFull       = max > 0 && cur >= max;
    final isAlmostFull = !isFull && pct >= 0.8;
    final isCancelled  = dbStatus == 'cancelled';
    final t            = WebTk(Theme.of(context).brightness == Brightness.dark);
    final typeColor    = type.isEmpty ? t.muted : _eventTypeColor(type);
    final timeStr      = _fmtEventTime(e['start_time'] as String?);
    final barColor     = isCancelled  ? t.muted
                       : isFull       ? const Color(0xFFEF4444)
                       : isAlmostFull ? const Color(0xFFF59E0B)
                       :                const Color(0xFF10B981);

    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _h ? kAdminAccent.withValues(alpha: 0.025) : Colors.transparent,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: 3,
              color: isCancelled
                  ? const Color(0xFFEF4444).withValues(alpha: 0.35)
                  : Colors.transparent,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(children: [
                  // Event type icon container
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
                      color: typeColor.withValues(alpha: isCancelled ? 0.45 : 1.0),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Event title + type badge
                  Expanded(flex: 3, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(e['title'] as String? ?? '—',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isCancelled ? t.muted : t.text),
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
                  // Organizer name + org subtitle
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
                  // Date + time
                  Expanded(flex: 2, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(webFmtDate(e['event_date'] as String?),
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                            color: isCancelled ? t.muted : t.sub)),
                      if (timeStr.isNotEmpty)
                        Text(timeStr, style: TextStyle(fontFamily: 'Poppins',
                            fontSize: 10.5, color: t.muted)),
                    ],
                  )),
                  // Status badge
                  Expanded(child: WebStatusBadge(
                    label: webEventStatusLabel(dispStatus),
                    color: webEventStatusColor(dispStatus))),
                  // Fill rate: count + capacity badge + gradient bar
                  Expanded(flex: 2, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(children: [
                        Text(max > 0 ? '$cur / $max' : '$cur / ∞',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isCancelled ? t.muted : t.text)),
                        const SizedBox(width: 6),
                        if (isFull)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('Full',
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFEF4444))),
                          )
                        else if (isAlmostFull)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('Almost Full',
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFF59E0B))),
                          ),
                      ]),
                      const SizedBox(height: 5),
                      Container(
                        height: 4,
                        clipBehavior: Clip.hardEdge,
                        decoration: BoxDecoration(
                          color: t.border,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: pct > 0
                          ? Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: pct,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [barColor.withValues(alpha: 0.60), barColor],
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : null,
                      ),
                    ],
                  )),
                  // Cancel action — fades in on hover; placeholder keeps layout stable
                  AnimatedOpacity(
                    opacity: _h && widget.onCancel != null ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: SizedBox(
                      width: 44,
                      child: widget.onCancel != null
                          ? AdminActBtn(
                              icon:  Icons.cancel_outlined,
                              color: const Color(0xFFEF4444),
                              tip:   'Cancel Event',
                              onTap: widget.onCancel!,
                            )
                          : null,
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

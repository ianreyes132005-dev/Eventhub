// ─────────────────────────────────────────────────────────────────────────────
// Admin — Organizers tab.
// Split out of admin_web_dashboard.dart so each sidebar tab has its own file.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_colors.dart';
import '../../core/services/supabase_service.dart';
import '../organizer/web/web_shared.dart';
import 'admin_shared.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Organizers page
// ═════════════════════════════════════════════════════════════════════════════

class AdminOrganizersPage extends StatefulWidget {
  const AdminOrganizersPage({super.key});
  @override State<AdminOrganizersPage> createState() => _AdminOrganizersPageState();
}

class _AdminOrganizersPageState extends State<AdminOrganizersPage> {
  bool   _loading = true, _error = false;
  String _errorMsg = '';
  List<Map<String, dynamic>> _all = [], _filtered = [];
  Map<String, int> _eventCounts = {};
  String _search       = '';
  String _statusFilter = 'All';
  String _sortField    = 'created_at';
  bool   _sortAsc      = false;
  final _searchCtrl = TextEditingController();

  RealtimeChannel? _channel;
  Timer?           _debounce;

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
    _channel = SupabaseService.client.channel('admin-organizers');
    for (final table in ['organizers', 'events']) {
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
      final results = await Future.wait([
        SupabaseService.client.from('organizers')
            .select('organizer_id, user_id, full_name, organization, is_active, created_at')
            .order('created_at', ascending: false),
        SupabaseService.client.from('events').select('organizer_id'),
      ]);
      if (!mounted) return;
      final organizers = List<Map<String, dynamic>>.from(results[0] as List);
      final eventRows  = results[1] as List;
      final counts = <String, int>{};
      for (final r in eventRows) {
        final id = (r as Map<String, dynamic>)['organizer_id'] as String?;
        if (id != null) counts[id] = (counts[id] ?? 0) + 1;
      }
      _all         = organizers;
      _eventCounts = counts;
      _loading     = false;
      _applyFilter();
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = true; _errorMsg = e.toString(); });
    }
  }

  void _applyFilter() {
    final q = _search.toLowerCase();
    var list = _all.where((o) {
      if (_statusFilter == 'Active'    && o['is_active'] != true) return false;
      if (_statusFilter == 'Inactive'  && o['is_active'] == true) return false;
      if (_statusFilter == 'No Auth'   && o['user_id']  != null)  return false;
      if (_statusFilter == '0 Events' &&
          (_eventCounts[o['organizer_id'] as String? ?? ''] ?? 0) > 0) { return false; }
      if (q.isNotEmpty) {
        final name = (o['full_name']    as String? ?? '').toLowerCase();
        final id   = (o['organizer_id'] as String? ?? '').toLowerCase();
        final org  = (o['organization'] as String? ?? '').toLowerCase();
        if (!name.contains(q) && !id.contains(q) && !org.contains(q)) return false;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      int cmp;
      if (_sortField == 'full_name') {
        cmp = (a['full_name'] as String? ?? '').compareTo(b['full_name'] as String? ?? '');
      } else if (_sortField == 'organizer_id') {
        cmp = (a['organizer_id'] as String? ?? '').compareTo(b['organizer_id'] as String? ?? '');
      } else if (_sortField == 'event_count') {
        final ac = _eventCounts[a['organizer_id'] as String? ?? ''] ?? 0;
        final bc = _eventCounts[b['organizer_id'] as String? ?? ''] ?? 0;
        cmp = ac.compareTo(bc);
      } else if (_sortField == 'is_active') {
        final ai = a['is_active'] == true ? 1 : 0;
        final bi = b['is_active'] == true ? 1 : 0;
        cmp = bi.compareTo(ai);
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
      _sortAsc   = field == 'full_name' || field == 'organizer_id' || field == 'is_active';
    }
    _applyFilter();
  }

  Future<void> _toggleActive(String id, bool cur) async {
    final ok = await WebAlert.confirm(
      context:      context,
      title:        cur ? 'Deactivate Organizer?' : 'Activate Organizer?',
      message:      cur
          ? 'This organizer will lose access and cannot manage events.'
          : 'This organizer will regain access to manage events.',
      confirmLabel: cur ? 'Deactivate' : 'Activate',
      confirmColor: cur ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
      iconColor:    cur ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
      iconBg:       cur ? const Color(0xFFFFFBEB) : const Color(0xFFECFDF5),
      icon:         cur ? Icons.person_off_outlined : Icons.person_add_outlined,
    );
    if (ok != true) return;
    try {
      final updated = await SupabaseService.client.from('organizers')
          .update({'is_active': !cur}).eq('organizer_id', id).select();
      if ((updated as List).isEmpty) {
        if (mounted) _snack('Failed: organizer not found or the update was not permitted.');
        return;
      }
      final idx = _all.indexWhere((o) => o['organizer_id'] == id);
      if (idx != -1) { _all[idx] = {..._all[idx], 'is_active': !cur}; _applyFilter(); }
    } catch (e) { if (mounted) _snack('Failed: $e'); }
  }

  Future<void> _editOrganizer(Map<String, dynamic> org) async {
    final result = await showDialog<Map<String, dynamic>?>(
      context: context, builder: (_) => _OrganizerDialog(
        organizer: org,
        eventCount: _eventCounts[org['organizer_id'] as String? ?? ''] ?? 0,
      ));
    if (result == null) return;
    try {
      final updated = await SupabaseService.client.from('organizers')
          .update(result).eq('organizer_id', org['organizer_id'] as String).select();
      if ((updated as List).isEmpty) {
        if (mounted) _snack('Failed: organizer not found or the update was not permitted.');
        return;
      }
      final idx = _all.indexWhere((o) => o['organizer_id'] == org['organizer_id']);
      if (idx != -1) { _all[idx] = {..._all[idx], ...result}; _applyFilter(); }
      if (mounted) WebAlert.success(context: context, title: 'Saved', message: 'Organizer profile updated.');
    } catch (e) { if (mounted) _snack('Failed: $e'); }
  }

  Future<void> _addOrganizer() async {
    final nextId = await _nextOrgId();
    if (!mounted) return;
    String? createdName;
    final ok = await showDialog<bool?>(
      context: context,
      builder: (_) => _OrganizerDialog(
        organizer: null,
        suggestedId: nextId,
        onCreate: (data) async {
          try {
            createdName = data['full_name'] as String?;
            final password     = data['password'] as String;
            final organizerData = Map<String, dynamic>.from(data)..remove('password');
            final res = await SupabaseService.client.functions.invoke(
              'create-organizer',
              body: {...organizerData, 'password': password},
            );
            final body = res.data is Map
                ? Map<String, dynamic>.from(res.data as Map)
                : null;
            if (res.status != 200) {
              return body?['message'] as String? ?? 'Failed to create account.';
            }
            return null; // success
          } catch (e) {
            return 'Failed: $e';
          }
        },
      ),
    );
    if (ok != true || !mounted) return;
    await _load();
    if (mounted) {
      WebAlert.success(
        context: context,
        title: 'Account Created',
        message: 'Organizer account for ${createdName ?? 'organizer'} has been created.',
      );
    }
  }

  Future<String> _nextOrgId() async {
    try {
      final rows = await SupabaseService.client.from('organizers')
          .select('organizer_id').order('organizer_id', ascending: false).limit(1);
      final list = rows as List;
      if (list.isEmpty) return 'Org0001';
      final last = list.first['organizer_id'] as String? ?? 'Org0000';
      final num  = int.tryParse(last.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return 'Org${(num + 1).toString().padLeft(4, '0')}';
    } catch (_) { return 'Org0001'; }
  }

  Future<void> _deleteOrganizer(String id, String name) async {
    final eventCount = _eventCounts[id] ?? 0;
    final message = eventCount > 0
        ? 'This will permanently delete $name\'s profile, their $eventCount event${eventCount == 1 ? '' : 's'}, and all student registrations for those events.'
        : 'This will permanently remove $name\'s profile and their account link.';
    final ok = await WebAlert.confirm(
      context: context, title: 'Delete Organizer?',
      message: message,
      confirmLabel: 'Delete',
    );
    if (ok != true) return;
    try {
      final res = await SupabaseService.client.functions.invoke(
        'delete-organizer',
        body: {'organizer_id': id},
      );
      final body = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : null;
      if (res.status != 200) {
        if (mounted) _snack(body?['message'] as String? ?? 'Failed to delete organizer.');
        return;
      }
      _all.removeWhere((o) => o['organizer_id'] == id);
      _eventCounts.remove(id);
      _applyFilter();
      if (mounted) WebAlert.success(context: context, title: 'Deleted',
          message: 'Organizer removed and login access revoked.');
    } catch (e) { if (mounted) _snack('Failed: $e'); }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: const Color(0xFFEF4444)));

  @override
  Widget build(BuildContext context) {
    final t             = WebTk(Theme.of(context).brightness == Brightness.dark);
    final totalCount    = _all.length;
    final activeCount   = _all.where((o) => o['is_active'] == true).length;
    final inactiveCount = totalCount - activeCount;
    final noAuthCount   = _all.where((o) => o['user_id'] == null).length;
    final noEventsCount = _all.where((o) =>
        (_eventCounts[o['organizer_id'] as String? ?? ''] ?? 0) == 0).length;
    final hasFilter     = _search.isNotEmpty || _statusFilter != 'All';
    final filterDesc    = [
      if (_statusFilter != 'All') _statusFilter,
      if (_search.isNotEmpty)     '"$_search"',
    ].join(' · ');
    final emptySubtitle = filterDesc.isEmpty
        ? 'Add your first organizer to get started.'
        : 'No organizers match $filterDesc.';

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
              Text('Organizers',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 22,
                    fontWeight: FontWeight.w800, color: t.text)),
              const SizedBox(height: 2),
              Text('$totalCount total · $activeCount active · $noAuthCount unlinked',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.sub)),
            ])),
            WebBtn(label: 'Add Organizer', icon: Icons.add_rounded, onTap: _addOrganizer),
          ]),
          const SizedBox(height: 16),
          // ── Stat tiles ────────────────────────────────────────────────
          Row(children: [
            AdminStatCard(label: 'Total Organizers', value: '$totalCount',
                color: kGold, icon: Icons.badge_rounded),
            const SizedBox(width: 10),
            AdminStatCard(label: 'Active', value: '$activeCount',
                color: const Color(0xFF10B981), icon: Icons.check_circle_rounded),
            const SizedBox(width: 10),
            AdminStatCard(
              label: 'Inactive',
              value: '$inactiveCount',
              color: inactiveCount > 0 ? t.muted : const Color(0xFF10B981),
              icon: Icons.person_off_outlined,
            ),
            const SizedBox(width: 10),
            AdminStatCard(
              label: 'No Auth',
              value: '$noAuthCount',
              color: noAuthCount > 0 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
              icon: Icons.warning_amber_rounded,
            ),
            const SizedBox(width: 10),
            AdminStatCard(
              label: 'No Events',
              value: '$noEventsCount',
              color: noEventsCount > 0 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
              icon: Icons.event_busy_rounded,
            ),
          ]),
        ]),
      ),
      // ── Filter bar ───────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.fromLTRB(kWebPad, 8, kWebPad, 8),
        decoration: BoxDecoration(
          color: t.inputBg,
          border: Border(bottom: BorderSide(color: t.border)),
        ),
        child: Row(children: [
          WebSearchField(
            controller: _searchCtrl, hint: 'Search name, ID, or org…',
            onChanged: (v) { _search = v; _applyFilter(); }, width: 200),
          const SizedBox(width: 14),
          Container(width: 1, height: 18, color: t.border),
          const SizedBox(width: 14),
          Text('Status:',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                fontWeight: FontWeight.w600, color: t.text)),
          const SizedBox(width: 8),
          for (final f in ['All', 'Active', 'Inactive', 'No Auth', '0 Events']) ...[
            WebFilterChip(
              label: f, selected: _statusFilter == f,
              onTap: () { _statusFilter = f; _applyFilter(); },
              count: f == 'All'       ? totalCount
                   : f == 'Active'    ? activeCount
                   : f == 'Inactive'  ? inactiveCount
                   : f == 'No Auth'   ? noAuthCount
                   :                    noEventsCount,
              selectedColor: f == 'No Auth'   ? const Color(0xFFF59E0B)
                           : f == '0 Events'  ? kAdminAccent
                           : f == 'Inactive'  ? t.muted
                           : f == 'Active'    ? const Color(0xFF10B981)
                           :                    kGold,
            ),
            const SizedBox(width: 6),
          ],
          if (hasFilter) ...[
            const Spacer(),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  _search = ''; _statusFilter = 'All';
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
      ),
      // ── Body ─────────────────────────────────────────────────────────
        if (_filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(kWebPad),
            child: WebEmptyState(
              icon: Icons.badge_outlined,
              title: 'No organizers found',
              subtitle: emptySubtitle,
              action: hasFilter
                  ? TextButton(
                      onPressed: () {
                        _search = ''; _statusFilter = 'All';
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
                _OrganizerTableHeader(
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
                    final o  = _filtered[i];
                    final id = o['organizer_id'] as String? ?? '';
                    return _OrganizerRow(
                      org:        o,
                      eventCount: _eventCounts[id] ?? 0,
                      onEdit:   () => _editOrganizer(o),
                      onToggle: () => _toggleActive(id, o['is_active'] == true),
                      onDelete: () => _deleteOrganizer(id, o['full_name'] as String? ?? ''),
                    );
                  },
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: t.border))),
                  child: Text(
                    hasFilter
                        ? 'Showing ${_filtered.length} of $totalCount organizers'
                        : '${_filtered.length} organizers total',
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

// ─── Sortable table header for Organizers ──────────────────────────────────

class _OrganizerTableHeader extends StatelessWidget {
  final String sortField;
  final bool   sortAsc;
  final void Function(String) onSort;
  const _OrganizerTableHeader({
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

  Widget _staticCol(String label, Color subColor, {int flex = 1}) => Expanded(
    flex: flex,
    child: Text(label, style: TextStyle(fontFamily: 'Poppins',
        fontSize: 10.5, fontWeight: FontWeight.w700, color: subColor, letterSpacing: 0.8)),
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
        _sortCol('FULL NAME',  'full_name',    flex: 3),
        _sortCol('ORG ID',     'organizer_id'),
        _sortCol('EVENTS',     'event_count'),
        _sortCol('STATUS',     'is_active'),
        _staticCol('AUTH', t.sub),
        _sortCol('CREATED',    'created_at',   flex: 2),
        const SizedBox(width: 108),
      ]),
    );
  }
}

class _OrganizerRow extends StatefulWidget {
  final Map<String, dynamic> org;
  final int          eventCount;
  final VoidCallback onEdit, onToggle, onDelete;
  const _OrganizerRow({
    required this.org, required this.eventCount,
    required this.onEdit, required this.onToggle, required this.onDelete});
  @override State<_OrganizerRow> createState() => _OrganizerRowState();
}
class _OrganizerRowState extends State<_OrganizerRow> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final t           = WebTk(Theme.of(context).brightness == Brightness.dark);
    final o           = widget.org;
    final active      = o['is_active'] == true;
    final linked      = o['user_id'] != null;
    final orgName     = o['organization'] as String?;
    final orgId       = o['organizer_id'] as String? ?? '—';
    final initials    = (o['full_name'] as String? ?? '?').trim().split(' ')
        .where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).take(2).join();
    final avatarColor = active ? kGold : t.muted;

    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _h ? kGold.withValues(alpha: 0.04) : Colors.transparent,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 3, color: active ? Colors.transparent : t.muted.withValues(alpha: 0.30)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(children: [
                  // Avatar
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: avatarColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: avatarColor.withValues(alpha: 0.22)),
                    ),
                    child: Center(child: Text(initials,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: avatarColor.withValues(alpha: active ? 1.0 : 0.55)))),
                  ),
                  const SizedBox(width: 12),
                  // Name + organization + auth warning
                  Expanded(flex: 3, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(o['full_name'] as String? ?? '—',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                            fontWeight: FontWeight.w600, color: active ? t.text : t.muted),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (orgName != null && orgName.isNotEmpty)
                        Text(orgName,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5,
                              color: t.sub),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (!linked)
                        const Text('No auth account',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                              color: Color(0xFFF59E0B), fontWeight: FontWeight.w600)),
                    ],
                  )),
                  // Org ID — gold-tinted badge, hugs content
                  Expanded(child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: kGold.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: kGold.withValues(alpha: 0.22)),
                      ),
                      child: Text(orgId,
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: kGold.withValues(alpha: 0.90), letterSpacing: 0.4),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  )),
                  // Events count
                  Expanded(child: widget.eventCount > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: kGold.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.event_rounded, size: 11,
                              color: kGold.withValues(alpha: 0.80)),
                          const SizedBox(width: 4),
                          Text('${widget.eventCount}',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: kGold.withValues(alpha: 0.90))),
                        ]))
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: t.muted.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('0', style: TextStyle(fontFamily: 'Poppins',
                            fontSize: 11, fontWeight: FontWeight.w500, color: t.muted)))),
                  // Status badge
                  Expanded(child: WebStatusBadge(
                    label: active ? 'Active' : 'Inactive',
                    color: active ? const Color(0xFF10B981) : t.muted)),
                  // Account link status
                  Expanded(child: Row(children: [
                    Container(width: 7, height: 7,
                        decoration: BoxDecoration(
                          color: linked ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                          shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(linked ? 'Linked' : 'No account',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                          fontWeight: linked ? FontWeight.w400 : FontWeight.w600,
                          color: linked ? const Color(0xFF10B981) : const Color(0xFFF59E0B))),
                  ])),
                  // Created date
                  Expanded(flex: 2, child: Text(webFmtDate(o['created_at'] as String?),
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: t.muted))),
                  // Actions — fade in on row hover
                  AnimatedOpacity(
                    opacity: _h ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: SizedBox(
                      width: 108,
                      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        AdminActBtn(icon: Icons.edit_outlined,
                            color: kAdminAccent, tip: 'Edit', onTap: widget.onEdit),
                        const SizedBox(width: 6),
                        AdminActBtn(
                          icon:  active ? Icons.person_off_outlined : Icons.person_add_outlined,
                          color: active ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                          tip:   active ? 'Deactivate' : 'Activate',
                          onTap: widget.onToggle),
                        const SizedBox(width: 6),
                        AdminActBtn(icon: Icons.delete_outline_rounded,
                            color: const Color(0xFFEF4444), tip: 'Delete', onTap: widget.onDelete),
                      ]),
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

// ─── Organizer dialog ──────────────────────────────────────────────────────

class _OrganizerDialog extends StatefulWidget {
  final Map<String, dynamic>? organizer;
  final String?               suggestedId;
  final int                   eventCount;
  // For add mode only: returns an error message on failure, null on success.
  final Future<String?> Function(Map<String, dynamic>)? onCreate;
  const _OrganizerDialog({
    required this.organizer,
    this.suggestedId,
    this.eventCount = 0,
    this.onCreate,
  });
  @override State<_OrganizerDialog> createState() => _OrganizerDialogState();
}
class _OrganizerDialogState extends State<_OrganizerDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _scale, _fade;
  final _idCtrl         = TextEditingController();
  final _nameCtrl       = TextEditingController();
  final _orgCtrl        = TextEditingController();
  final _pwCtrl         = TextEditingController();
  final _confirmPwCtrl  = TextEditingController();
  bool  _pwHidden        = true;
  bool  _confirmPwHidden = true;
  bool  _saving          = false;

  bool get _isEdit => widget.organizer != null;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    _scale = Tween<double>(begin: 0.87, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    if (_isEdit) {
      _idCtrl.text   = widget.organizer!['organizer_id'] as String? ?? '';
      _nameCtrl.text = widget.organizer!['full_name']    as String? ?? '';
      _orgCtrl.text  = widget.organizer!['organization'] as String? ?? '';
    } else if (widget.suggestedId != null) {
      _idCtrl.text = widget.suggestedId!;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _idCtrl.dispose(); _nameCtrl.dispose(); _orgCtrl.dispose();
    _pwCtrl.dispose(); _confirmPwCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final rawId = _idCtrl.text.trim();
    final name  = _nameCtrl.text.trim();
    final org   = _orgCtrl.text.trim();
    final pw    = _pwCtrl.text;
    if (!_isEdit && !RegExp(r'^Org\d{4}$', caseSensitive: false).hasMatch(rawId)) {
      _snack('ID must be Org followed by 4 digits (e.g. Org0001)'); return;
    }
    // Normalize to consistent Org#### casing regardless of what user typed
    final id = 'Org${rawId.substring(3)}';
    if (name.isEmpty) { _snack('Full name is required'); return; }
    if (!_isEdit && pw.length < 6) {
      _snack('Password must be at least 6 characters'); return;
    }
    if (!_isEdit && _confirmPwCtrl.text != pw) {
      _snack('Passwords do not match'); return;
    }

    if (_isEdit) {
      Navigator.of(context).pop(<String, dynamic>{
        'full_name':    name,
        'organization': org.isEmpty ? null : org,
      });
      return;
    }

    // Add mode: call onCreate inside the dialog so we can show a loading state.
    setState(() => _saving = true);
    final err = await widget.onCreate!(<String, dynamic>{
      'organizer_id': id,
      'full_name':    name,
      'organization': org.isEmpty ? null : org,
      'password':     pw,
      'is_active':    true,
    });
    if (!mounted) return;
    if (err != null) {
      setState(() => _saving = false);
      _snack(err);
      return;
    }
    Navigator.of(context).pop(true); // true = success
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: Colors.red));

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440, maxHeight: 680),
            child: adminDialogShell(
              icon: Icons.badge_rounded, iconColor: kGold,
              title: _isEdit ? 'Edit Organizer' : 'Add Organizer',
              loading: _saving,
              body: Column(children: [
                if (_isEdit) ...[
                  AdminInfoNote(widget.eventCount > 0
                      ? 'This organizer has ${widget.eventCount} event${widget.eventCount == 1 ? '' : 's'}. Name and organization changes apply immediately.'
                      : 'This organizer has no events yet.'),
                  const SizedBox(height: 12),
                ],
                if (!_isEdit) ...[
                  AdminInfoNote('Admin-provisioned account. The organizer will log in using their ID in lowercase (e.g. org0001) as their username.'),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _idCtrl,
                    enabled: !_saving,
                    decoration: webInputDeco('Organizer ID (e.g. Org0001)', icon: Icons.tag_rounded, dark: t.dark),
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.text)),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _nameCtrl,
                  enabled: !_saving,
                  decoration: webInputDeco('Full Name', icon: Icons.person_outline_rounded, dark: t.dark),
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.text)),
                const SizedBox(height: 12),
                TextField(
                  controller: _orgCtrl,
                  enabled: !_saving,
                  decoration: webInputDeco('Organization / Department (optional)', icon: Icons.business_outlined, dark: t.dark),
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.text)),
                if (!_isEdit) ...[
                  const SizedBox(height: 14),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _idCtrl,
                    builder: (_, v, __) {
                      final id = v.text.trim().toLowerCase();
                      return AdminCredentialPreview(
                        username: id.isEmpty ? '—' : id,
                        isReady:  RegExp(r'^org\d{4}$').hasMatch(id),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pwCtrl,
                    obscureText: _pwHidden,
                    enabled: !_saving,
                    decoration: webInputDeco('Password', icon: Icons.lock_outline_rounded, dark: t.dark).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          _pwHidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          size: 18, color: t.sub,
                        ),
                        onPressed: () => setState(() => _pwHidden = !_pwHidden),
                      ),
                    ),
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.text),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _pwCtrl,
                    builder: (_, v, __) => AdminPasswordStrengthBar(password: v.text),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmPwCtrl,
                    obscureText: _confirmPwHidden,
                    enabled: !_saving,
                    decoration: webInputDeco('Confirm Password', icon: Icons.lock_outline_rounded, dark: t.dark).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          _confirmPwHidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          size: 18, color: t.sub,
                        ),
                        onPressed: () => setState(() => _confirmPwHidden = !_confirmPwHidden),
                      ),
                    ),
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.text),
                  ),
                ],
              ]),
              confirmLabel: _isEdit ? 'Save Changes' : 'Add Organizer',
              confirmColor: kGold,
              onConfirm: _submit,
            ),
          ),
        ),
      ),
    );
  }
}

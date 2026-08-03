// ─────────────────────────────────────────────────────────────────────────────
// Admin — Students tab.
// Split out of admin_web_dashboard.dart so each sidebar tab has its own file.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_colors.dart';
import '../../core/services/supabase_service.dart';
import '../organizer/web/web_shared.dart';
import 'admin_shared.dart';

class AdminStudentsPage extends StatefulWidget {
  const AdminStudentsPage({super.key});
  @override State<AdminStudentsPage> createState() => _AdminStudentsPageState();
}

class _AdminStudentsPageState extends State<AdminStudentsPage> {
  bool   _loading = true, _error = false;
  String _errorMsg = '';
  List<Map<String, dynamic>> _all = [], _filtered = [];
  Map<String, int>           _regCounts = {};
  String _search       = '';
  String _statusFilter = 'All';
  String _yearFilter   = 'All';
  String _sortField    = 'created_at';
  bool   _sortAsc      = false;
  final _searchCtrl = TextEditingController();

  RealtimeChannel? _channel;
  Timer?           _debounce;

  List<String> get _yearOptions {
    final years = _all
        .map((s) => s['year_level'])
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();
    return ['All', ...years.map((y) => 'Grade $y')];
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
    _channel = SupabaseService.client.channel('admin-students');
    for (final table in ['students', 'registrations']) {
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
      final results = await Future.wait([
        SupabaseService.client
            .from('students')
            .select('lrn, user_id, full_name, year_level, is_active, created_at')
            .order('created_at', ascending: false),
        SupabaseService.client
            .from('registrations')
            .select('student_school_id'),
      ]);
      if (!mounted) return;
      _all = List<Map<String, dynamic>>.from(results[0] as List);
      final regRows = results[1] as List;
      final counts  = <String, int>{};
      for (final r in regRows) {
        final id = (r as Map<String, dynamic>)['student_school_id'] as String?;
        if (id != null) counts[id] = (counts[id] ?? 0) + 1;
      }
      _regCounts = counts;
      _loading   = false;
      _applyFilter();
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = true; _errorMsg = e.toString(); });
    }
  }

  void _applyFilter() {
    final q = _search.toLowerCase();
    var list = _all.where((s) {
      if (_statusFilter == 'Active'   && s['is_active'] != true) return false;
      if (_statusFilter == 'Inactive' && s['is_active'] == true) return false;
      if (_statusFilter == 'No Auth'  && s['user_id']  != null)  return false;
      if (_statusFilter == 'No Regs'  &&
          (_regCounts[s['lrn'] as String? ?? ''] ?? 0) > 0) { return false; }
      if (_yearFilter != 'All') {
        final yr = int.tryParse(_yearFilter.replaceAll('Grade ', ''));
        if ((s['year_level'] as int?) != yr) return false;
      }
      if (q.isNotEmpty) {
        final name = (s['full_name'] as String? ?? '').toLowerCase();
        final lrn  = (s['lrn']       as String? ?? '').toLowerCase();
        if (!name.contains(q) && !lrn.contains(q)) return false;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      int cmp;
      if (_sortField == 'full_name') {
        cmp = (a['full_name'] as String? ?? '').compareTo(b['full_name'] as String? ?? '');
      } else if (_sortField == 'lrn') {
        cmp = (a['lrn'] as String? ?? '').compareTo(b['lrn'] as String? ?? '');
      } else if (_sortField == 'year_level') {
        cmp = ((a['year_level'] as int?) ?? 0).compareTo((b['year_level'] as int?) ?? 0);
      } else if (_sortField == 'is_active') {
        final ai = a['is_active'] == true ? 1 : 0;
        final bi = b['is_active'] == true ? 1 : 0;
        cmp = bi.compareTo(ai);
      } else if (_sortField == 'reg_count') {
        final ac = _regCounts[a['lrn'] as String? ?? ''] ?? 0;
        final bc = _regCounts[b['lrn'] as String? ?? ''] ?? 0;
        cmp = ac.compareTo(bc);
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
      _sortAsc   = field == 'full_name' || field == 'lrn' ||
                   field == 'year_level' || field == 'is_active';
    }
    _applyFilter();
  }

  Future<void> _toggleActive(String lrn, bool cur) async {
    final ok = await WebAlert.confirm(
      context:      context,
      title:        cur ? 'Deactivate Student?' : 'Activate Student?',
      message:      cur
          ? 'This student will no longer be able to log in.'
          : 'This student will regain access to their account.',
      confirmLabel: cur ? 'Deactivate' : 'Activate',
      confirmColor: cur ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
      iconColor:    cur ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
      iconBg:       cur ? const Color(0xFFFFFBEB) : const Color(0xFFECFDF5),
      icon:         cur ? Icons.person_off_outlined : Icons.person_add_outlined,
    );
    if (ok != true) return;
    try {
      final updated = await SupabaseService.client.from('students')
          .update({'is_active': !cur}).eq('lrn', lrn).select();
      if ((updated as List).isEmpty) {
        if (mounted) _snack('Failed: student not found or the update was not permitted.');
        return;
      }
      final idx = _all.indexWhere((s) => s['lrn'] == lrn);
      if (idx != -1) { _all[idx] = {..._all[idx], 'is_active': !cur}; _applyFilter(); }
    } catch (e) {
      if (mounted) _snack('Failed: $e');
    }
  }

  Future<void> _editStudent(Map<String, dynamic> student) async {
    final result = await showDialog<Map<String, dynamic>?>(
      context: context, builder: (_) => _StudentDialog(student: student));
    if (result == null) return;
    try {
      final updated = await SupabaseService.client.from('students')
          .update(result).eq('lrn', student['lrn'] as String).select();
      if ((updated as List).isEmpty) {
        if (mounted) _snack('Failed: student not found or the update was not permitted.');
        return;
      }
      final idx = _all.indexWhere((s) => s['lrn'] == student['lrn']);
      if (idx != -1) { _all[idx] = {..._all[idx], ...result}; _applyFilter(); }
      if (mounted) WebAlert.success(context: context, title: 'Saved', message: 'Student profile updated.');
    } catch (e) { if (mounted) _snack('Failed: $e'); }
  }

  Future<void> _addStudent() async {
    String? createdName;
    final ok = await showDialog<bool?>(
      context: context,
      builder: (_) => _StudentDialog(
        student: null,
        onCreate: (data) async {
          try {
            createdName      = data['full_name'] as String?;
            final password   = data['password'] as String;
            final studentData = Map<String, dynamic>.from(data)..remove('password');
            final res = await SupabaseService.client.functions.invoke(
              'create-student',
              body: {...studentData, 'password': password},
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
        message: 'Student account for ${createdName ?? 'student'} has been created.',
      );
    }
  }

  Future<void> _deleteStudent(String lrn, String name) async {
    final ok = await WebAlert.confirm(
      context: context, title: 'Delete Student?',
      message: 'This will permanently remove $name\'s profile, revoke their login, '
          'and delete all their event registration history.',
      confirmLabel: 'Delete',
    );
    if (ok != true) return;
    try {
      final res = await SupabaseService.client.functions.invoke(
        'delete-student',
        body: {'lrn': lrn},
      );
      final body = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : null;
      if (res.status != 200) {
        if (mounted) _snack(body?['message'] as String? ?? 'Failed to delete student.');
        return;
      }
      _all.removeWhere((s) => s['lrn'] == lrn);
      _applyFilter();
      if (mounted) WebAlert.success(context: context, title: 'Deleted',
          message: 'Student record removed and login access revoked.');
    } catch (e) { if (mounted) _snack('Failed: $e'); }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: const Color(0xFFEF4444)));

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final totalCount        = _all.length;
    final activeCount       = _all.where((s) => s['is_active'] == true).length;
    final inactiveCount     = totalCount - activeCount;
    final noAuthCount       = _all.where((s) => s['user_id'] == null).length;
    final unregisteredCount = _all.where((s) =>
        (_regCounts[s['lrn'] as String? ?? ''] ?? 0) == 0).length;
    final hasFilter         = _search.isNotEmpty || _statusFilter != 'All' || _yearFilter != 'All';
    final yearOpts          = _yearOptions;
    final filterDesc = [
      if (_statusFilter != 'All') _statusFilter,
      if (_yearFilter   != 'All') _yearFilter,
      if (_search.isNotEmpty)     '"$_search"',
    ].join(' · ');
    final emptySubtitle = filterDesc.isEmpty
        ? 'Add your first student to get started.'
        : 'No students match $filterDesc.';

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
              Text('Students',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 22,
                    fontWeight: FontWeight.w800, color: t.text)),
              const SizedBox(height: 2),
              Text('$totalCount enrolled · $activeCount active · $noAuthCount unlinked',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.sub)),
            ])),
            WebBtn(label: 'Add Student', icon: Icons.add_rounded, onTap: _addStudent),
          ]),
          const SizedBox(height: 16),
          // ── Stat tiles ────────────────────────────────────────────────
          Row(children: [
            AdminStatCard(label: 'Total Enrolled', value: '$totalCount',
                color: kAdminAccent, icon: Icons.people_rounded),
            const SizedBox(width: 10),
            AdminStatCard(label: 'Active', value: '$activeCount',
                color: const Color(0xFF10B981), icon: Icons.check_circle_rounded),
            const SizedBox(width: 10),
            AdminStatCard(
              label: 'Inactive',
              value: '$inactiveCount',
              color: inactiveCount > 0 ? kMuted : const Color(0xFF10B981),
              icon:  Icons.person_off_outlined,
            ),
            const SizedBox(width: 10),
            AdminStatCard(
              label: 'No Auth',
              value: '$noAuthCount',
              color: noAuthCount > 0 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
              icon:  Icons.no_accounts_rounded,
            ),
            const SizedBox(width: 10),
            AdminStatCard(
              label: 'Never Registered',
              value: '$unregisteredCount',
              color: unregisteredCount > 0 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
              icon:  Icons.event_busy_rounded,
            ),
          ]),
          const SizedBox(height: 14),
          // ── Grade breakdown strip ──────────────────────────────────────
          // flex:4 JHS + flex:2 SHS → each chip gets equal width naturally
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 4,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('JHS',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 9.5,
                      fontWeight: FontWeight.w700, color: Color(0xFF6D28D9),
                      letterSpacing: 0.8)),
                const SizedBox(height: 5),
                Row(children: [
                  for (final g in [7, 8, 9, 10]) ...[
                    Expanded(child: _GradeChip(
                      grade: g,
                      count: _all.where((s) => (s['year_level'] as int?) == g).length,
                      isJhs: true,
                    )),
                    if (g < 10) const SizedBox(width: 8),
                  ],
                ]),
              ]),
            ),
            const SizedBox(width: 16),
            Container(width: 1, height: 58,
                margin: const EdgeInsets.only(top: 14), color: t.border),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('SHS',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 9.5,
                      fontWeight: FontWeight.w700, color: Color(0xFF0EA5E9),
                      letterSpacing: 0.8)),
                const SizedBox(height: 5),
                Row(children: [
                  for (final g in [11, 12]) ...[
                    Expanded(child: _GradeChip(
                      grade: g,
                      count: _all.where((s) => (s['year_level'] as int?) == g).length,
                      isJhs: false,
                    )),
                    if (g < 12) const SizedBox(width: 8),
                  ],
                ]),
              ]),
            ),
          ]),
        ]),
      ),
      // ── Filter bar ───────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.fromLTRB(kWebPad, 8, kWebPad, 8),
        decoration: BoxDecoration(
          color: t.bg,
          border: Border(bottom: BorderSide(color: t.border)),
        ),
        child: Row(children: [
          WebSearchField(
            controller: _searchCtrl, hint: 'Search name or LRN…',
            onChanged: (v) { _search = v; _applyFilter(); }, width: 200),
          const SizedBox(width: 14),
          Container(width: 1, height: 18, color: t.border),
          const SizedBox(width: 14),
          Text('Status:',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                fontWeight: FontWeight.w600, color: t.text)),
          const SizedBox(width: 8),
          for (final f in ['All', 'Active', 'Inactive', 'No Auth', 'No Regs']) ...[
            WebFilterChip(
              label: f, selected: _statusFilter == f,
              onTap: () { _statusFilter = f; _applyFilter(); },
              count: f == 'All'      ? totalCount
                   : f == 'Active'   ? activeCount
                   : f == 'Inactive' ? inactiveCount
                   : f == 'No Auth'  ? noAuthCount
                   :                   unregisteredCount,
              selectedColor: f == 'No Auth'  ? const Color(0xFFF59E0B)
                           : f == 'No Regs'  ? const Color(0xFFF59E0B)
                           : f == 'Inactive' ? kMuted
                           : f == 'Active'   ? const Color(0xFF10B981)
                           : null,
            ),
            const SizedBox(width: 6),
          ],
          if (yearOpts.length > 1) ...[
            const SizedBox(width: 12),
            Container(width: 1, height: 18, color: t.border),
            const SizedBox(width: 12),
            Text('Grade:',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  fontWeight: FontWeight.w600, color: t.text)),
            const SizedBox(width: 8),
            Container(
              height: 28,
              padding: const EdgeInsets.only(left: 10, right: 6),
              decoration: BoxDecoration(
                color: _yearFilter != 'All'
                    ? kAdminAccent.withValues(alpha: 0.07)
                    : t.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _yearFilter != 'All'
                      ? kAdminAccent.withValues(alpha: 0.45)
                      : t.border,
                  width: _yearFilter != 'All' ? 1.5 : 1.0,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: yearOpts.contains(_yearFilter) ? _yearFilter : 'All',
                  isDense: true,
                  icon: Icon(Icons.keyboard_arrow_down_rounded, size: 14,
                      color: _yearFilter != 'All' ? kAdminAccent : t.muted),
                  onChanged: (v) {
                    if (v != null) { _yearFilter = v; _applyFilter(); }
                  },
                  selectedItemBuilder: (ctx) => yearOpts.map((y) => Center(
                    child: Text(y,
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: _yearFilter != 'All' ? kAdminAccent : t.text,
                      )),
                  )).toList(),
                  items: yearOpts.map((y) {
                    final cnt = y == 'All'
                        ? totalCount
                        : _all.where((s) {
                            final yr = int.tryParse(y.replaceAll('Grade ', ''));
                            return (s['year_level'] as int?) == yr;
                          }).length;
                    return DropdownMenuItem<String>(
                      value: y,
                      child: Text('$y ($cnt)',
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 12,
                          fontWeight: y == _yearFilter ? FontWeight.w700 : FontWeight.w400,
                          color: y == _yearFilter ? kAdminAccent : t.text,
                        )),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
          if (hasFilter) ...[
            const Spacer(),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  _search = ''; _statusFilter = 'All'; _yearFilter = 'All';
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
              icon: Icons.people_outline_rounded,
              title: 'No students found',
              subtitle: emptySubtitle,
              action: hasFilter
                  ? TextButton(
                      onPressed: () {
                        _search = ''; _statusFilter = 'All'; _yearFilter = 'All';
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
                _StudentTableHeader(
                  sortField: _sortField,
                  sortAsc:   _sortAsc,
                  onSort:    _setSort,
                ),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: t.border),
                  itemBuilder: (_, i) => _StudentRow(
                    student:  _filtered[i],
                    regCount: _regCounts[_filtered[i]['lrn'] as String? ?? ''] ?? 0,
                    onEdit:   () => _editStudent(_filtered[i]),
                    onToggle: () => _toggleActive(
                      _filtered[i]['lrn'] as String,
                      _filtered[i]['is_active'] == true),
                    onDelete: () => _deleteStudent(
                      _filtered[i]['lrn'] as String,
                      _filtered[i]['full_name'] as String? ?? '—'),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: t.border))),
                  child: Text(
                    hasFilter
                        ? 'Showing ${_filtered.length} of $totalCount students'
                        : '${_filtered.length} students total',
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

class _StudentRow extends StatefulWidget {
  final Map<String, dynamic> student;
  final int          regCount;
  final VoidCallback onEdit, onToggle, onDelete;
  const _StudentRow({required this.student, required this.regCount, required this.onEdit, required this.onToggle, required this.onDelete});
  @override State<_StudentRow> createState() => _StudentRowState();
}
class _StudentRowState extends State<_StudentRow> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final t           = WebTk(Theme.of(context).brightness == Brightness.dark);
    final s           = widget.student;
    final active      = s['is_active'] == true;
    final linked      = s['user_id'] != null;
    final yr          = s['year_level'] as int?;
    final initials    = (s['full_name'] as String? ?? '?').trim().split(' ')
        .where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).take(2).join();
    final avatarColor = active ? kAdminAccent : t.muted;

    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _h ? kAdminAccent.withValues(alpha: 0.03) : Colors.transparent,
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
              border: Border.all(color: avatarColor.withValues(alpha: 0.18)),
            ),
            child: Center(child: Text(initials,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                  fontWeight: FontWeight.w700, color: avatarColor))),
          ),
          const SizedBox(width: 12),
          // Name + "no auth" warning
          Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s['full_name'] as String? ?? '—',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? t.text : t.muted),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            if (!linked)
              const Text('No auth account',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                    color: Color(0xFFF59E0B), fontWeight: FontWeight.w600)),
          ])),
          // LRN
          Expanded(flex: 2, child: Text(formatLrn(s['lrn'] as String? ?? '—'),
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.sub),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
          // Year level badge
          Expanded(child: yr != null
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF6D28D9).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF6D28D9).withValues(alpha: 0.18)),
                ),
                child: Text('G$yr',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 11,
                      fontWeight: FontWeight.w700, color: Color(0xFF6D28D9))))
            : Text('—', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.muted))),
          // Registration count
          Expanded(child: widget.regCount > 0
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.how_to_reg_rounded, size: 11,
                        color: const Color(0xFF10B981).withValues(alpha: 0.80)),
                    const SizedBox(width: 4),
                    Text('${widget.regCount}',
                      style: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                          fontWeight: FontWeight.w700, color: Color(0xFF10B981))),
                  ]),
                )
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: t.muted.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('0',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                        fontWeight: FontWeight.w500, color: t.muted)))),
          // Status badge
          Expanded(child: WebStatusBadge(
            label: active ? 'Active' : 'Inactive',
            color: active ? const Color(0xFF10B981) : t.muted)),
          // Account link status — amber when unlinked
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
          Expanded(flex: 2, child: Text(webFmtDate(s['created_at'] as String?),
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
                ]),      // closes inner Row (Padding child)
              ),         // closes Padding
            ),           // closes Expanded
          ]),            // closes outer Row (IntrinsicHeight child)
        ),               // closes IntrinsicHeight
      ),                 // closes AnimatedContainer
    );                   // closes MouseRegion
  }
}

// ─── Grade breakdown chip (used in the per-grade strip) ──────────────────────

class _GradeChip extends StatelessWidget {
  final int  grade, count;
  final bool isJhs;
  const _GradeChip({required this.grade, required this.count, required this.isJhs});

  @override
  Widget build(BuildContext context) {
    final color = isJhs ? const Color(0xFF6D28D9) : const Color(0xFF0EA5E9);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('$count',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 15,
              fontWeight: FontWeight.w800, color: color, height: 1.1)),
        const SizedBox(height: 2),
        Text('Grade $grade',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.70))),
      ]),
    );
  }
}

// ─── Sortable table header for Students ────────────────────────────────────

class _StudentTableHeader extends StatelessWidget {
  final String sortField;
  final bool   sortAsc;
  final void Function(String) onSort;
  const _StudentTableHeader({
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

  Widget _staticCol(String label, Color color, {int flex = 1}) => Expanded(
    flex: flex,
    child: Text(label, style: TextStyle(fontFamily: 'Poppins',
        fontSize: 10.5, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.8)),
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
        _sortCol('FULL NAME',  'full_name',  flex: 3),
        _sortCol('LRN',        'lrn',        flex: 2),
        _sortCol('GRADE',      'year_level'),
        _sortCol('REGS',       'reg_count'),
        _sortCol('STATUS',     'is_active'),
        _staticCol('AUTH',     t.sub),
        _sortCol('CREATED',    'created_at', flex: 2),
        const SizedBox(width: 108),
      ]),
    );
  }
}

// ─── Student dialog ────────────────────────────────────────────────────────

class _StudentDialog extends StatefulWidget {
  final Map<String, dynamic>? student;
  // For add mode only: called with the validated form data.
  // Returns an error message string on failure, or null on success.
  final Future<String?> Function(Map<String, dynamic>)? onCreate;
  const _StudentDialog({required this.student, this.onCreate});
  @override State<_StudentDialog> createState() => _StudentDialogState();
}
class _StudentDialogState extends State<_StudentDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _scale, _fade;
  final _lrnCtrl        = TextEditingController();
  final _nameCtrl       = TextEditingController();
  final _pwCtrl         = TextEditingController();
  final _confirmPwCtrl  = TextEditingController();
  bool  _pwHidden        = true;
  bool  _confirmPwHidden = true;
  bool  _saving          = false;
  int?  _selectedYear;

  bool get _isEdit => widget.student != null;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    _scale = Tween<double>(begin: 0.87, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    if (_isEdit) {
      _lrnCtrl.text  = widget.student!['lrn']       as String? ?? '';
      _nameCtrl.text = widget.student!['full_name']  as String? ?? '';
      _selectedYear  = widget.student!['year_level'] as int?;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _lrnCtrl.dispose();
    _nameCtrl.dispose();
    _pwCtrl.dispose();
    _confirmPwCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final lrn  = _lrnCtrl.text.replaceAll(RegExp(r'\D'), '');
    final name = _nameCtrl.text.trim();
    final pw   = _pwCtrl.text;
    if (!_isEdit && !RegExp(r'^\d{12}$').hasMatch(lrn)) {
      _snack('LRN must be exactly 12 digits'); return;
    }
    if (!_isEdit && !lrn.startsWith(kRequiredLrnPrefix)) {
      final prefixDisplay = '${kRequiredLrnPrefix.substring(0, 6)} - ${kRequiredLrnPrefix.substring(6, 8)}';
      _snack('LRN must start with $prefixDisplay '
          '— students log in with only the last 4 digits, which are rebuilt using this prefix.');
      return;
    }
    if (name.isEmpty) { _snack('Full name is required'); return; }
    if (!_isEdit && pw.length < 6) {
      _snack('Password must be at least 6 characters'); return;
    }
    if (!_isEdit && _confirmPwCtrl.text != pw) {
      _snack('Passwords do not match'); return;
    }
    final data = <String, dynamic>{'full_name': name, 'year_level': _selectedYear};
    if (!_isEdit) {
      data['lrn']       = lrn;
      data['password']  = pw;
      data['is_active'] = true;
    }

    if (_isEdit) {
      // Edit mode: pop immediately with data for the parent to save.
      Navigator.of(context).pop(data);
      return;
    }

    // Add mode: call onCreate inside the dialog so we can show a loading state.
    setState(() => _saving = true);
    final err = await widget.onCreate!(data);
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
            icon: Icons.people_rounded, iconColor: kAdminAccent,
            title: _isEdit ? 'Edit Student' : 'Add Student',
            loading: _saving,
            body: Column(children: [
              if (!_isEdit) ...[
                AdminInfoNote('Admin-provisioned account. The student will log in using the last 4 digits of their LRN as their username.'),
                const SizedBox(height: 14),
                TextField(
                  controller: _lrnCtrl,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_LrnFormatter()],
                  decoration: webInputDeco('e.g. 123456 - 26 - 1234', icon: Icons.badge_outlined, dark: t.dark),
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.text)),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _nameCtrl,
                enabled: !_saving,
                decoration: webInputDeco('Full Name', icon: Icons.person_outline_rounded, dark: t.dark),
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.text)),
              const SizedBox(height: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Grade Level',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                      fontWeight: FontWeight.w600, color: t.sub)),
                const SizedBox(height: 10),
                // Junior High School row
                Text('Junior High School',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                      fontWeight: FontWeight.w600, color: t.muted, letterSpacing: 0.4)),
                const SizedBox(height: 6),
                Row(children: [
                  for (final y in [7, 8, 9, 10]) ...[
                    Expanded(
                      child: GestureDetector(
                        onTap: _saving ? null : () => setState(
                            () => _selectedYear = _selectedYear == y ? null : y),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _selectedYear == y
                                ? kAdminAccent.withValues(alpha: 0.10)
                                : t.inputBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _selectedYear == y ? kAdminAccent : t.border,
                              width: _selectedYear == y ? 1.5 : 1.0,
                            ),
                          ),
                          child: Text('Grade $y',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 12,
                              fontWeight: _selectedYear == y
                                  ? FontWeight.w700 : FontWeight.w400,
                              color: _selectedYear == y ? kAdminAccent : t.sub,
                            )),
                        ),
                      ),
                    ),
                    if (y < 10) const SizedBox(width: 8),
                  ],
                ]),
                const SizedBox(height: 10),
                // Senior High School row
                Text('Senior High School',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                      fontWeight: FontWeight.w600, color: t.muted, letterSpacing: 0.4)),
                const SizedBox(height: 6),
                Row(children: [
                  for (final y in [11, 12]) ...[
                    Expanded(
                      child: GestureDetector(
                        onTap: _saving ? null : () => setState(
                            () => _selectedYear = _selectedYear == y ? null : y),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _selectedYear == y
                                ? kAdminAccent.withValues(alpha: 0.10)
                                : t.inputBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _selectedYear == y ? kAdminAccent : t.border,
                              width: _selectedYear == y ? 1.5 : 1.0,
                            ),
                          ),
                          child: Text('Grade $y',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 12,
                              fontWeight: _selectedYear == y
                                  ? FontWeight.w700 : FontWeight.w400,
                              color: _selectedYear == y ? kAdminAccent : t.sub,
                            )),
                        ),
                      ),
                    ),
                    if (y < 12) const SizedBox(width: 8),
                  ],
                  // Spacer to prevent Grade 11 / 12 from stretching across full width
                  const Expanded(flex: 2, child: SizedBox()),
                ]),
              ]),
              if (!_isEdit) ...[
                const SizedBox(height: 14),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _lrnCtrl,
                  builder: (_, v, _) {
                    final lrn   = v.text.replaceAll(RegExp(r'\D'), '');
                    final last4 = lrn.length >= 4
                        ? lrn.substring(lrn.length - 4)
                        : lrn.isEmpty ? '—' : lrn;
                    return AdminCredentialPreview(username: last4, isReady: lrn.length == 12);
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
                  builder: (_, v, _) => AdminPasswordStrengthBar(password: v.text),
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
            confirmLabel: _isEdit ? 'Save Changes' : 'Add Student',
            confirmColor: kAdminAccent,
            onConfirm: _submit,
          ),
        ),
      ),
    ),
  );
}
}

// ─── LRN auto-formatter ───────────────────────────────────────────────────────
// As admin types 12 digits, inserts " - " separators: XXXXXX - XX - XXXX.
class _LrnFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final capped = digits.length > 12 ? digits.substring(0, 12) : digits;
    final buf    = StringBuffer();
    for (var i = 0; i < capped.length; i++) {
      if (i == 6 || i == 8) buf.write(' - ');
      buf.write(capped[i]);
    }
    final out = buf.toString();
    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: out.length),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin — Logs tab.
// Split out of admin_web_dashboard.dart so each sidebar tab has its own file.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_colors.dart';
import '../../core/friendly_error.dart';
import '../../core/services/supabase_service.dart';
import '../organizer/web/web_shared.dart';
import 'admin_shared.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Logs page — helpers
// ═════════════════════════════════════════════════════════════════════════════

/// Log entries are kept at least this long: Clear only removes older ones.
/// The database refuses to delete newer ones (admin_delete_event_logs /
/// admin_delete_login_logs, migration 202610270001) — keep the two the same.
const Duration kLogRetention = Duration(days: 90);

/// How many of the newest entries each tab loads.
const int _kLoadedLogs = 500;

String _logRelTime(String? ts) {
  if (ts == null || ts.isEmpty) return '—';
  try {
    final d    = DateTime.parse(ts).toLocal();
    final diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60)  return 'Just now';
    if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
    if (diff.inHours   < 24)  return '${diff.inHours}h ago';
    if (diff.inDays    < 7)   return '${diff.inDays}d ago';
    const m = ['Jan','Feb','Mar','Apr','May','Jun',
                'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[d.month - 1]} ${d.day}';
  } catch (_) { return '—'; }
}

String _logFullTime(String? ts) {
  if (ts == null || ts.isEmpty) return '—';
  try {
    final d  = DateTime.parse(ts).toLocal();
    const m  = ['Jan','Feb','Mar','Apr','May','Jun',
                 'Jul','Aug','Sep','Oct','Nov','Dec'];
    final h  = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    final mi = d.minute.toString().padLeft(2, '0');
    final ap = d.hour >= 12 ? 'PM' : 'AM';
    return '${m[d.month - 1]} ${d.day}, ${d.year} · $h:$mi $ap';
  } catch (_) { return '—'; }
}

Color _logRoleColor(String? role) => switch (role) {
  'admin'     => kAdminAccent,
  'organizer' => const Color(0xFF7C3AED),
  'student'   => const Color(0xFF0EA5E9),
  _           => kMuted,
};

String _logRoleLabel(String? role) => switch (role) {
  'admin'     => 'Admin',
  'organizer' => 'Organizer',
  'student'   => 'Student',
  _           => role?.toUpperCase() ?? '—',
};

IconData _logRoleIcon(String? role) => switch (role) {
  'admin'     => Icons.admin_panel_settings_rounded,
  'organizer' => Icons.badge_rounded,
  'student'   => Icons.school_rounded,
  _           => Icons.person_rounded,
};

Color _logActionColor(String? action) => switch (action) {
  'created'             => const Color(0xFF10B981),
  'updated'             => const Color(0xFF3B82F6),
  'deleted'             => const Color(0xFFEF4444),
  'cancelled'           => const Color(0xFFEF4444),
  'approved'            => const Color(0xFF10B981),
  'rejected'            => const Color(0xFFF59E0B),
  'checked_in'          => const Color(0xFF10B981),
  'registration_rejected' => const Color(0xFFE11D48),
  'attendance_corrected' => const Color(0xFFC2410C),
  'archived'            => const Color(0xFF6366F1),
  'unarchived'          => const Color(0xFF0EA5E9),
  _                     => kMuted,
};

String _logActionLabel(String? action) => switch (action) {
  'created'             => 'Created',
  'updated'             => 'Updated',
  'deleted'             => 'Deleted',
  'cancelled'           => 'Cancelled',
  'approved'            => 'Approved',
  'rejected'            => 'Rejected',
  'checked_in'          => 'Checked In',
  'registration_rejected' => 'Registration Rejected',
  'attendance_corrected' => 'Attendance Corrected',
  'archived'            => 'Archived',
  'unarchived'          => 'Restored from Archive',
  _                     => action?.toUpperCase() ?? '—',
};

IconData _logActionIcon(String? action) => switch (action) {
  'created'             => Icons.add_circle_outline_rounded,
  'updated'             => Icons.edit_outlined,
  'deleted'             => Icons.delete_outline_rounded,
  'cancelled'           => Icons.cancel_outlined,
  'approved'            => Icons.check_circle_outline_rounded,
  'rejected'            => Icons.block_rounded,
  'checked_in'          => Icons.how_to_reg_rounded,
  'registration_rejected' => Icons.person_off_rounded,
  'attendance_corrected' => Icons.edit_note_rounded,
  _           => Icons.event_note_outlined,
};

// ═════════════════════════════════════════════════════════════════════════════
// Logs page
// ═════════════════════════════════════════════════════════════════════════════

class AdminLogsPage extends StatefulWidget {
  const AdminLogsPage({super.key});
  @override State<AdminLogsPage> createState() => _AdminLogsPageState();
}

class _AdminLogsPageState extends State<AdminLogsPage>
    with TickerProviderStateMixin {
  late final TabController       _tab;
  final _searchCtrl = TextEditingController();
  String _search    = '';
  String _dateRange = 'all';

  // ── Login logs ─────────────────────────────────────────────────────────────
  bool   _loginLoading = true;
  bool   _loginError   = false;
  String _loginRole    = 'All';
  String _loginPlat    = 'All';
  List<Map<String, dynamic>> _loginAll      = [];
  List<Map<String, dynamic>> _loginFiltered = [];

  // ── Event logs ─────────────────────────────────────────────────────────────
  bool   _eventLoading = true;
  bool   _eventError   = false;
  String _eventAction  = 'All';
  String _eventOrg     = 'All';
  List<Map<String, dynamic>> _eventAll      = [];
  List<Map<String, dynamic>> _eventFiltered = [];
  bool _clearingLogs = false;

  RealtimeChannel? _loginCh;
  RealtimeChannel? _eventCh;
  Timer?           _debounce;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this)
      ..addListener(() { if (mounted) setState(() {}); });
    _searchCtrl.addListener(_onSearch);
    _loadLogin();
    _loadEvent();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tab.dispose();
    _searchCtrl.dispose();
    if (_loginCh != null) SupabaseService.client.removeChannel(_loginCh!);
    if (_eventCh != null) SupabaseService.client.removeChannel(_eventCh!);
    super.dispose();
  }

  void _onSearch() {
    _search = _searchCtrl.text;
    _applyLogin();
    _applyEvent();
  }

      bool get _hasLoginFilters =>
        _loginRole != 'All' ||
        _loginPlat != 'All' ||
        _dateRange != 'all' ||
        _search.isNotEmpty;

      bool get _hasEventFilters =>
        _eventAction != 'All' ||
        _eventOrg != 'All' ||
        _dateRange != 'all' ||
        _search.isNotEmpty;

  DateTime? get _cutoff {
    final now = DateTime.now();
    return switch (_dateRange) {
      'today' => DateTime(now.year, now.month, now.day),
      '7d'    => now.subtract(const Duration(days: 7)),
      '30d'   => now.subtract(const Duration(days: 30)),
      _       => null,
    };
  }

  void _subscribeRealtime() {
    _loginCh = SupabaseService.client.channel('admin-login-logs')
      ..on(RealtimeListenTypes.postgresChanges,
          ChannelFilter(event: '*', schema: 'public', table: 'login_logs'),
          (_, [a]) => _debouncedLoad())
      ..subscribe();
    _eventCh = SupabaseService.client.channel('admin-event-logs')
      ..on(RealtimeListenTypes.postgresChanges,
          ChannelFilter(event: '*', schema: 'public', table: 'event_logs'),
          (_, [a]) => _debouncedLoad())
      ..subscribe();
  }

  void _debouncedLoad() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted) { _loadLogin(silent: true); _loadEvent(silent: true); }
    });
  }

  Future<void> _loadLogin({bool silent = false}) async {
    if (!silent && mounted) setState(() { _loginLoading = true; _loginError = false; });
    try {
      final rows = await SupabaseService.client
          .from('login_logs')
          .select('id, user_role, full_name, identifier, platform, created_at')
          .order('created_at', ascending: false)
          .limit(_kLoadedLogs);
      if (!mounted) return;
      _loginAll = List<Map<String, dynamic>>.from(rows as List);
      _applyLogin();
      if (mounted) setState(() => _loginLoading = false);
    } catch (_) {
      if (mounted) setState(() { _loginLoading = false; _loginError = true; });
    }
  }

  Future<void> _loadEvent({bool silent = false}) async {
    if (!silent && mounted) setState(() { _eventLoading = true; _eventError = false; });
    try {
      final rows = await SupabaseService.client
          .from('event_logs')
          .select('id, event_title, organizer_id, organizer_name, action, details, created_at')
          .order('created_at', ascending: false)
          .limit(_kLoadedLogs);
      if (!mounted) return;
      _eventAll = List<Map<String, dynamic>>.from(rows as List);
      _applyEvent();
      if (mounted) setState(() => _eventLoading = false);
    } catch (_) {
      if (mounted) setState(() { _eventLoading = false; _eventError = true; });
    }
  }

  void _applyLogin() {
    final cut = _cutoff;
    final q   = _search.toLowerCase();
    setState(() {
      _loginFiltered = _loginAll.where((r) {
        if (cut != null) {
          final d = DateTime.tryParse(r['created_at'] as String? ?? '')?.toLocal();
          if (d == null || d.isBefore(cut)) return false;
        }
        if (_loginRole != 'All' &&
            r['user_role'] != _loginRole.toLowerCase()) return false;
        if (_loginPlat != 'All' &&
            r['platform']  != _loginPlat.toLowerCase())  return false;
        if (q.isNotEmpty) {
          final name  = (r['full_name']  as String? ?? '').toLowerCase();
          final ident = (r['identifier'] as String? ?? '').toLowerCase();
          if (!name.contains(q) && !ident.contains(q)) return false;
        }
        return true;
      }).toList();
    });
  }

  void _applyEvent() {
    final cut = _cutoff;
    final q   = _search.toLowerCase();
    setState(() {
      _eventFiltered = _eventAll.where((r) {
        if (cut != null) {
          final d = DateTime.tryParse(r['created_at'] as String? ?? '')?.toLocal();
          if (d == null || d.isBefore(cut)) return false;
        }
        if (_eventAction != 'All' && r['action'] != _eventAction) return false;
        if (_eventOrg != 'All') {
          final nm = (r['organizer_name'] as String? ?? '');
          final id = (r['organizer_id']   as String? ?? '');
          if (nm != _eventOrg && id != _eventOrg) return false;
        }
        if (q.isNotEmpty) {
          final title  = (r['event_title']    as String? ?? '').toLowerCase();
          final org    = (r['organizer_name'] as String? ?? '').toLowerCase();
          final detail = (r['details']        as String? ?? '').toLowerCase();
          if (!title.contains(q) && !org.contains(q) && !detail.contains(q)) return false;
        }
        return true;
      }).toList();
    });
  }

  void _setDateRange(String v) {
    setState(() => _dateRange = v);
    _applyLogin();
    _applyEvent();
  }

  // Count entries in [list] that fall within [bucket] ("today"/"7d"/"30d"/"all").
  int _countFor(List<Map<String, dynamic>> list, String bucket) {
    final now = DateTime.now();
    final cut = switch (bucket) {
      'today' => DateTime(now.year, now.month, now.day),
      '7d'    => now.subtract(const Duration(days: 7)),
      '30d'   => now.subtract(const Duration(days: 30)),
      _       => null,
    };
    if (cut == null) return list.length;
    return list.where((r) {
      final d = DateTime.tryParse(r['created_at'] as String? ?? '')?.toLocal();
      return d != null && !d.isBefore(cut);
    }).length;
  }

  Future<void> _clearCurrentTabLogs() async {
    if (_clearingLogs) return;

    final isLoginTab = _tab.index == 0;
    final hasFilters = isLoginTab ? _hasLoginFilters : _hasEventFilters;
    final table = isLoginTab ? 'login_logs' : 'event_logs';
    final logType = isLoginTab ? 'login' : 'event';
    final tabLabel = isLoginTab ? 'Login' : 'Event';
    final loaded = isLoginTab ? _loginAll : _eventAll;
    // The last 90 days are kept (kLogRetention); the database won't delete
    // them. A day's margin keeps a computer clock that runs ahead from
    // picking entries the database still keeps.
    final cutoff = DateTime.now().subtract(kLogRetention + const Duration(days: 1));
    bool isOld(Map<String, dynamic> row) =>
        DateTime.tryParse(row['created_at'] as String? ?? '')?.isBefore(cutoff) ?? false;
    final oldIds = (hasFilters ? (isLoginTab ? _loginFiltered : _eventFiltered) : loaded)
        .where(isOld)
        .map((row) => row['id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    // Only the newest entries are loaded: without filters, older ones may
    // be waiting beyond them.
    final mayHaveMore = !hasFilters && loaded.length >= _kLoadedLogs;

    if (oldIds.isEmpty && !mayHaveMore) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(hasFilters
            ? 'None of the matching logs are older than 90 days. Logs from the last 90 days are always kept.'
            : 'Nothing to clear yet. Logs from the last 90 days are always kept.'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    final confirmed = await WebAlert.confirm(
      context: context,
      title: hasFilters ? 'Clear Matching $tabLabel Logs?' : 'Clear Old $tabLabel Logs?',
      message: hasFilters
          ? 'This permanently deletes ${oldIds.length} matching $logType log '
              '${oldIds.length == 1 ? 'entry' : 'entries'} older than 90 days. '
              'Logs from the last 90 days are kept. This action cannot be undone.'
          : 'This permanently deletes every $logType log entry older than 90 days. '
              'Logs from the last 90 days are kept. This action cannot be undone.',
      confirmLabel: hasFilters ? 'Clear Matching' : 'Clear Old Logs',
      icon: Icons.delete_sweep_rounded,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _clearingLogs = true);
    try {
      final deleted = hasFilters
          ? await SupabaseService.client
              .from(table)
              .delete()
              .in_('id', oldIds)
              .select('id')
          : await SupabaseService.client
              .from(table)
              .delete()
              .lt('created_at', cutoff.toUtc().toIso8601String())
              .select('id');
      final count = (deleted as List).length;
      if (count == 0 && oldIds.isNotEmpty) {
        _blockedDeletion(isLoginTab ? 'admin_delete_login_logs' : 'admin_delete_event_logs');
      }

      if (isLoginTab) {
        await _loadLogin(silent: true);
      } else {
        await _loadEvent(silent: true);
      }

      if (mounted) {
        await WebAlert.success(
          context: context,
          title: count == 0 ? 'Nothing to clear' : 'Logs cleared',
          message: count == 0
              ? 'No $logType log entries are older than 90 days yet.'
              : '$count $logType log ${count == 1 ? 'entry' : 'entries'} older than '
                  '90 days ${count == 1 ? 'was' : 'were'} deleted. Logs from the '
                  'last 90 days are kept.',
        );
      }
    } catch (e) {
      if (mounted) adminErrorAlert(context, e, title: 'Couldn’t clear the logs');
    } finally {
      if (mounted) setState(() => _clearingLogs = false);
    }
  }

  // Row-level security deletes nothing (without an error) when the admin
  // delete policy is missing — the technical hint goes to the debug log.
  Never _blockedDeletion(String policy) {
    debugPrint('Log deletion blocked by RLS — apply the $policy policy '
        'from supabase/migrations/202610270001_audit_log_integrity.sql.');
    throw const FriendlyException(
        'The logs couldn’t be deleted because this account isn’t allowed to '
        'delete them yet. Please contact the system administrator.');
  }

  @override
  Widget build(BuildContext context) {
    final t             = WebTk(Theme.of(context).brightness == Brightness.dark);
    final loginFiltered = _loginFiltered.length;
    final eventFiltered = _eventFiltered.length;
    final loginTotal    = _loginAll.length;
    final eventTotal    = _eventAll.length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Header ───────────────────────────────────────────────────────────
      Container(
        color: t.card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Title and activity counts
          Padding(
            padding: const EdgeInsets.fromLTRB(kWebPad, 20, kWebPad, 16),
            child: Row(children: [
              Text('Logs',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 22,
                    fontWeight: FontWeight.w800, color: t.text)),
              const Spacer(),
              _LogStatChip(
                icon: Icons.login_rounded, label: 'Logins',
                count: loginFiltered, color: const Color(0xFF0EA5E9)),
              const SizedBox(width: 8),
              _LogStatChip(
                icon: Icons.event_note_rounded, label: 'Event Actions',
                count: eventFiltered, color: const Color(0xFF7C3AED)),
            ]),
          ),
          // Filter bar — search first, period dropdown
          Padding(
            padding: const EdgeInsets.fromLTRB(kWebPad, 0, kWebPad, 12),
            child: Row(children: [
              WebSearchField(
                controller: _searchCtrl,
                hint: _tab.index == 0
                    ? 'Search name or identifier…'
                    : 'Search event or organizer…',
                onChanged: (_) {}, width: 220),
              const SizedBox(width: 14),
              Container(width: 1, height: 18, color: t.border),
              const SizedBox(width: 14),
              Text('Period:',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w600, color: t.text)),
              const SizedBox(width: 8),
              Container(
                height: 28,
                padding: const EdgeInsets.only(left: 10, right: 6),
                decoration: BoxDecoration(
                  color: _dateRange != 'all'
                      ? kAdminAccent.withValues(alpha: 0.07) : t.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _dateRange != 'all'
                        ? kAdminAccent.withValues(alpha: 0.45) : t.border,
                    width: _dateRange != 'all' ? 1.5 : 1.0,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _dateRange,
                    isDense: true,
                    icon: Icon(Icons.keyboard_arrow_down_rounded, size: 14,
                        color: _dateRange != 'all' ? kAdminAccent : t.muted),
                    selectedItemBuilder: (_) => [
                      for (final (label, _) in [
                        ('Today', 'today'), ('Last 7 days', '7d'),
                        ('Last 30 days', '30d'), ('All time', 'all'),
                      ])
                        Center(
                          child: Text(label,
                            style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: _dateRange != 'all' ? kAdminAccent : t.text,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    items: [
                      for (final (label, val) in [
                        ('Today', 'today'), ('Last 7 days', '7d'),
                        ('Last 30 days', '30d'), ('All time', 'all'),
                      ])
                        DropdownMenuItem<String>(
                          value: val,
                          child: Text(
                            '$label  (${_countFor(_tab.index == 0 ? _loginAll : _eventAll, val)})',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontWeight: val == _dateRange
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: val == _dateRange
                                  ? kAdminAccent
                                  : t.text,
                            ),
                          ),
                        ),
                    ],
                    onChanged: (v) { if (v != null) _setDateRange(v); },
                  ),
                ),
              ),
            ]),
          ),
          // Tab bar
          Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border)),
            ),
            child: TabBar(
              controller: _tab,
              labelColor:          kAdminAccent,
              unselectedLabelColor: t.sub,
              labelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(fontFamily: 'Poppins',
                  fontSize: 13, fontWeight: FontWeight.w500),
              indicatorColor:  kAdminAccent,
              indicatorWeight: 2.5,
              indicatorSize:   TabBarIndicatorSize.tab,
              dividerColor:    Colors.transparent,
              tabs: [
                Tab(child: _LogTab(
                  icon: Icons.login_rounded,
                  label: 'Login Logs',
                  count: loginFiltered,
                  color: const Color(0xFF0EA5E9),
                )),
                Tab(child: _LogTab(
                  icon: Icons.event_note_rounded,
                  label: 'Event Logs',
                  count: eventFiltered,
                  color: const Color(0xFF7C3AED),
                )),
              ],
            ),
          ),
        ]),
      ),

      // ── Tab content ───────────────────────────────────────────────────────
      Expanded(
        child: TabBarView(
          controller: _tab,
          children: [
            _buildLoginTab(loginFiltered, loginTotal),
            _buildEventTab(eventFiltered, eventTotal),
          ],
        ),
      ),
    ]);
  }

  // ── Login tab ─────────────────────────────────────────────────────────────

  Widget _buildLoginTab(int filtered, int total) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    const roles = ['All', 'Admin', 'Organizer', 'Student'];
    const plats = ['All', 'Web', 'Mobile'];

    if (_loginLoading) {
      return const Center(child: CircularProgressIndicator(color: kAdminAccent));
    }
    if (_loginError) {
      return AdminErrorState(message: '', onRetry: _loadLogin);
    }

    // KPI stats for the filtered set
    final uniqueUsers = _loginFiltered
        .map((r) => r['identifier'] as String? ?? '')
        .where((s) => s.isNotEmpty).toSet().length;
    final webCount    = _loginFiltered.where((r) => r['platform'] == 'web').length;
    final mobileCount = _loginFiltered.where((r) => r['platform'] == 'mobile').length;
    final loginPeriodLabel = switch (_dateRange) {
      'today' => 'Today',
      '7d'    => 'Last 7 days',
      '30d'   => 'Last 30 days',
      _       => null,
    };
    final loginFilterDesc = [
      if (loginPeriodLabel != null) loginPeriodLabel,
      if (_loginRole != 'All')      _loginRole,
      if (_loginPlat != 'All')      _loginPlat,
      if (_search.isNotEmpty)       '"$_search"',
    ].join(' · ');
    final loginEmptySubtitle = loginFilterDesc.isEmpty
        ? 'Login activity will appear here once users log in.'
        : 'No login entries match $loginFilterDesc.';

    return Column(children: [
      // Filter bar
      Container(
        padding: const EdgeInsets.fromLTRB(kWebPad, 8, kWebPad, 8),
        decoration: BoxDecoration(
          color: t.bg,
          border: Border(bottom: BorderSide(color: t.border)),
        ),
        child: Row(children: [
          Text('Role:',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                fontWeight: FontWeight.w600, color: t.text)),
          const SizedBox(width: 8),
          for (final r in roles) ...[
            WebFilterChip(
              label: r, selected: _loginRole == r,
              onTap: () { setState(() => _loginRole = r); _applyLogin(); },
              count: r == 'All'
                  ? _loginAll.length
                  : _loginAll.where((x) => x['user_role'] == r.toLowerCase()).length,
              selectedColor: switch (r) {
                'Admin'     => kAdminAccent,
                'Organizer' => const Color(0xFF7C3AED),
                'Student'   => const Color(0xFF0EA5E9),
                _           => kGold,
              },
            ),
            const SizedBox(width: 6),
          ],
          const SizedBox(width: 12),
          Container(width: 1, height: 18, color: t.border),
          const SizedBox(width: 12),
          Text('Platform:',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                fontWeight: FontWeight.w600, color: t.text)),
          const SizedBox(width: 8),
          for (final p in plats) ...[
            WebFilterChip(
              label: p, selected: _loginPlat == p,
              onTap: () { setState(() => _loginPlat = p); _applyLogin(); },
              count: p == 'All'
                  ? _loginAll.length
                  : _loginAll.where((x) => x['platform'] == p.toLowerCase()).length,
              selectedColor: p == 'Web'
                  ? const Color(0xFF4F46E5)
                  : const Color(0xFF0D9488),
            ),
            const SizedBox(width: 6),
          ],
            const Spacer(),
            Tooltip(
              message: _hasLoginFilters
                  ? 'Delete the matching login logs older than 90 days'
                  : 'Delete login logs older than 90 days (the last 90 days are kept)',
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _clearCurrentTabLogs,
                  child: Row(mainAxisSize: MainAxisSize.min, children: const [
                    Icon(Icons.delete_outline_rounded, size: 13, color: Color(0xFFEF4444)),
                    SizedBox(width: 4),
                    Text('Clear', style: TextStyle(fontFamily: 'Poppins',
                        fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFFEF4444))),
                  ]),
                ),
              ),
            ),
        ]),
      ),
      // KPI insight strip
      if (_loginFiltered.isNotEmpty)
        Container(
          padding: const EdgeInsets.fromLTRB(kWebPad, 8, kWebPad, 8),
          decoration: BoxDecoration(
            color: t.inputBg,
            border: Border(bottom: BorderSide(color: t.border)),
          ),
          child: Row(children: [
            _LogKpiChip(
              icon: Icons.people_alt_rounded,
              label: '$uniqueUsers Unique User${uniqueUsers == 1 ? "" : "s"}',
              color: const Color(0xFF0EA5E9),
            ),
            const SizedBox(width: 8),
            _LogKpiChip(
              icon: Icons.desktop_mac_rounded,
              label: '$webCount Web',
              color: const Color(0xFF4F46E5),
            ),
            const SizedBox(width: 8),
            _LogKpiChip(
              icon: Icons.smartphone_rounded,
              label: '$mobileCount Mobile',
              color: const Color(0xFF0D9488),
            ),
            const SizedBox(width: 16),
            Container(width: 1, height: 14, color: t.border),
            const SizedBox(width: 16),
            _LogKpiChip(
              icon: Icons.admin_panel_settings_rounded,
              label: '${_loginFiltered.where((r) => r['user_role'] == 'admin').length} Admin',
              color: kAdminAccent,
            ),
            const SizedBox(width: 8),
            _LogKpiChip(
              icon: Icons.badge_rounded,
              label: '${_loginFiltered.where((r) => r['user_role'] == 'organizer').length} Organizer',
              color: const Color(0xFF7C3AED),
            ),
            const SizedBox(width: 8),
            _LogKpiChip(
              icon: Icons.school_rounded,
              label: '${_loginFiltered.where((r) => r['user_role'] == 'student').length} Student',
              color: const Color(0xFF10B981),
            ),
          ]),
        ),
      // Body
      if (_loginFiltered.isEmpty)
        Expanded(child: Center(child: WebEmptyState(
          icon: Icons.login_outlined,
          title: 'No login events found',
          subtitle: loginEmptySubtitle,
        )))
      else
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(kWebPad),
              child: WebCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  // Table header
                  Container(
                    padding: const EdgeInsets.only(
                        left: 23, right: 20, top: 10, bottom: 10),
                    decoration: BoxDecoration(
                      color: t.bg,
                      border: Border(bottom: BorderSide(color: t.border)),
                    ),
                    child: const Row(children: [
                      SizedBox(width: 52),
                      Expanded(flex: 4, child: _LogColLabel('USER')),
                      Expanded(flex: 2, child: _LogColLabel('ROLE')),
                      Expanded(flex: 2, child: _LogColLabel('PLATFORM')),
                      Expanded(flex: 2, child: _LogColLabel('LOGGED IN AT')),
                    ]),
                  ),
                  // Rows
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _loginFiltered.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: t.border),
                    itemBuilder: (_, i) =>
                        _LoginLogRow(log: _loginFiltered[i]),
                  ),
                  // Footer
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: t.border))),
                    child: Row(children: [
                      Text(
                        filtered == total
                            ? '$total login events'
                            : 'Showing $filtered of $total login events',
                        style: TextStyle(fontFamily: 'Poppins',
                            fontSize: 11.5, color: t.sub)),
                      if (total >= 500) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: kGold.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: kGold.withValues(alpha: 0.28)),
                          ),
                          child: const Text('Showing latest 500',
                            style: TextStyle(fontFamily: 'Poppins',
                                fontSize: 10, fontWeight: FontWeight.w600,
                                color: kGold)),
                        ),
                      ],
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  // ── Event tab ─────────────────────────────────────────────────────────────

  Widget _buildEventTab(int filtered, int total) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    const actions = ['All', 'created', 'updated', 'deleted', 'cancelled', 'approved',
        'rejected', 'checked_in', 'registration_rejected', 'attendance_corrected'];

    if (_eventLoading) {
      return const Center(child: CircularProgressIndicator(color: kAdminAccent));
    }
    if (_eventError) {
      return AdminErrorState(message: '', onRetry: _loadEvent);
    }

    // Unique organizer names from all event logs (for the organizer filter chips)
    final orgNames = _eventAll
        .map((r) => r['organizer_name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    // KPI counts from the filtered set
    final createdCount   = _eventFiltered.where((r) => r['action'] == 'created').length;
    final updatedCount   = _eventFiltered.where((r) => r['action'] == 'updated').length;
    final deletedCount   = _eventFiltered.where((r) => r['action'] == 'deleted').length;
    final cancelledCount = _eventFiltered.where((r) => r['action'] == 'cancelled').length;
    final activeOrgs   = _eventFiltered
        .map((r) => r['organizer_name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toSet()
        .length;
    final eventPeriodLabel = switch (_dateRange) {
      'today' => 'Today',
      '7d'    => 'Last 7 days',
      '30d'   => 'Last 30 days',
      _       => null,
    };
    final eventFilterDesc = [
      if (eventPeriodLabel != null) eventPeriodLabel,
      if (_eventAction != 'All')    _logActionLabel(_eventAction),
      if (_eventOrg    != 'All')    _eventOrg,
      if (_search.isNotEmpty)       '"$_search"',
    ].join(' · ');
    final eventEmptySubtitle = eventFilterDesc.isEmpty
        ? 'Event actions will be logged here as organizers create or manage events.'
        : 'No event log entries match $eventFilterDesc.';

    return Column(children: [
      // Action filter bar
      Container(
        padding: const EdgeInsets.fromLTRB(kWebPad, 8, kWebPad, 8),
        decoration: BoxDecoration(
          color: t.bg,
          border: Border(bottom: BorderSide(color: t.border)),
        ),
        child: Row(children: [
          Expanded(
            child: Row(children: [
              Text('Action:',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                    fontWeight: FontWeight.w600, color: t.text)),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final a in actions) ...[
                      WebFilterChip(
                        label: a == 'All' ? 'All' : _logActionLabel(a),
                        selected: _eventAction == a,
                        onTap: () { setState(() => _eventAction = a); _applyEvent(); },
                        count: a == 'All'
                            ? _eventAll.length
                            : _eventAll.where((x) => x['action'] == a).length,
                        selectedColor: a == 'All' ? kGold : _logActionColor(a),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ]),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Tooltip(
            message: _hasEventFilters
                ? 'Delete the matching event logs older than 90 days'
                : 'Delete event logs older than 90 days (the last 90 days are kept)',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _clearCurrentTabLogs,
                child: Row(mainAxisSize: MainAxisSize.min, children: const [
                  Icon(Icons.delete_outline_rounded,
                      size: 13, color: Color(0xFFEF4444)),
                  SizedBox(width: 4),
                  Text(
                    'Clear',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
      // Organizer filter bar (only shown when there are multiple organizers)
      if (orgNames.length > 1)
        Container(
          padding: const EdgeInsets.fromLTRB(kWebPad, 6, kWebPad, 6),
          decoration: BoxDecoration(
            color: t.bg,
            border: Border(bottom: BorderSide(color: t.border)),
          ),
          child: Row(children: [
            Text('Organizer:',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  fontWeight: FontWeight.w600, color: t.text)),
            const SizedBox(width: 8),
            Container(
              height: 28,
              padding: const EdgeInsets.only(left: 10, right: 6),
              decoration: BoxDecoration(
                color: _eventOrg != 'All'
                    ? const Color(0xFF7C3AED).withValues(alpha: 0.07)
                    : t.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _eventOrg != 'All'
                      ? const Color(0xFF7C3AED).withValues(alpha: 0.45)
                      : t.border,
                  width: _eventOrg != 'All' ? 1.5 : 1.0,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: ['All', ...orgNames].contains(_eventOrg)
                      ? _eventOrg : 'All',
                  isDense: true,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                      fontWeight: FontWeight.w600, color: t.text),
                  selectedItemBuilder: (_) =>
                      ['All', ...orgNames].map((nm) => Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          nm == 'All' ? 'All Organizers' : nm,
                          style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _eventOrg != 'All'
                                ? const Color(0xFF7C3AED) : t.text,
                          ),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      )).toList(),
                  items: ['All', ...orgNames].map((nm) {
                    final lbl = nm == 'All' ? 'All Organizers' : nm;
                    final cnt = nm == 'All'
                        ? _eventAll.length
                        : _eventAll.where((r) =>
                            r['organizer_name'] == nm).length;
                    return DropdownMenuItem<String>(
                      value: nm,
                      child: Text('$lbl  ($cnt)',
                        style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 11)),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() { _eventOrg = v; _applyEvent(); });
                    }
                  },
                ),
              ),
            ),
          ]),
        ),
      // KPI insight strip
      if (_eventFiltered.isNotEmpty)
        Container(
          padding: const EdgeInsets.fromLTRB(kWebPad, 8, kWebPad, 8),
          decoration: BoxDecoration(
            color: t.inputBg,
            border: Border(bottom: BorderSide(color: t.border)),
          ),
          child: Row(children: [
            _LogKpiChip(
              icon: Icons.add_circle_rounded,
              label: '$createdCount Created',
              color: const Color(0xFF10B981),
            ),
            const SizedBox(width: 8),
            _LogKpiChip(
              icon: Icons.edit_rounded,
              label: '$updatedCount Updated',
              color: const Color(0xFF3B82F6),
            ),
            const SizedBox(width: 8),
            _LogKpiChip(
              icon: Icons.delete_rounded,
              label: '$deletedCount Deleted',
              color: const Color(0xFFEF4444),
            ),
            const SizedBox(width: 8),
            _LogKpiChip(
              icon: Icons.cancel_rounded,
              label: '$cancelledCount Cancelled',
              color: const Color(0xFFEF4444),
            ),
            const SizedBox(width: 16),
            Container(width: 1, height: 14, color: t.border),
            const SizedBox(width: 16),
            _LogKpiChip(
              icon: Icons.badge_rounded,
              label: '$activeOrgs Active Organizer${activeOrgs == 1 ? "" : "s"}',
              color: const Color(0xFF7C3AED),
            ),
          ]),
        ),
      // Body
      if (_eventFiltered.isEmpty)
        Expanded(child: Center(child: WebEmptyState(
          icon: Icons.event_note_outlined,
          title: 'No event log entries found',
          subtitle: eventEmptySubtitle,
        )))
      else
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(kWebPad),
              child: WebCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  // Table header
                  Container(
                    padding: const EdgeInsets.only(
                        left: 23, right: 20, top: 10, bottom: 10),
                    decoration: BoxDecoration(
                      color: t.bg,
                      border: Border(bottom: BorderSide(color: t.border)),
                    ),
                    child: const Row(children: [
                      SizedBox(width: 52),
                      Expanded(flex: 4, child: _LogColLabel('EVENT')),
                      Expanded(flex: 3, child: _LogColLabel('ORGANIZER')),
                      Expanded(flex: 2, child: _LogColLabel('ACTION')),
                      Expanded(flex: 3, child: _LogColLabel('DETAILS')),
                      Expanded(flex: 2, child: _LogColLabel('TIME')),
                    ]),
                  ),
                  // Rows
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _eventFiltered.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: t.border),
                    itemBuilder: (_, i) =>
                        _EventLogRow(log: _eventFiltered[i]),
                  ),
                  // Footer
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: t.border))),
                    child: Row(children: [
                      Text(
                        filtered == total
                            ? '$total event log entries'
                            : 'Showing $filtered of $total event log entries',
                        style: TextStyle(fontFamily: 'Poppins',
                            fontSize: 11.5, color: t.sub)),
                      if (total >= 500) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: kGold.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: kGold.withValues(alpha: 0.28)),
                          ),
                          child: const Text('Showing latest 500',
                            style: TextStyle(fontFamily: 'Poppins',
                                fontSize: 10, fontWeight: FontWeight.w600,
                                color: kGold)),
                        ),
                      ],
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }
}

// ── Small widgets ──────────────────────────────────────────────────────────────

class _LogTab extends StatelessWidget {
  final IconData icon; final String label; final int count; final Color color;
  const _LogTab({required this.icon, required this.label,
      required this.count, required this.color});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 15),
    const SizedBox(width: 7),
    Text(label),
    const SizedBox(width: 7),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('$count',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
            fontWeight: FontWeight.w700, color: color)),
    ),
  ]);
}

class _LogStatChip extends StatelessWidget {
  final IconData icon; final String label; final int count; final Color color;
  const _LogStatChip({required this.icon, required this.label,
      required this.count, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.20)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 7),
      Text('$count',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
            fontWeight: FontWeight.w700, color: color)),
      const SizedBox(width: 4),
      Text(label,
        style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
            fontWeight: FontWeight.w500,
            color: color.withValues(alpha: 0.75))),
    ]),
  );
}

class _LogColLabel extends StatelessWidget {
  final String text;
  const _LogColLabel(this.text);
  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return Text(text,
      style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5,
          fontWeight: FontWeight.w700, color: t.sub, letterSpacing: 0.8));
  }
}

class _LogKpiChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  const _LogKpiChip({required this.icon, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color:        color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(6),
      border:       Border.all(color: color.withValues(alpha: 0.18)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 5),
      Text(label,
        style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
            fontWeight: FontWeight.w600, color: color)),
    ]),
  );
}

// ── Login log row ──────────────────────────────────────────────────────────────

class _LoginLogRow extends StatefulWidget {
  final Map<String, dynamic> log;
  const _LoginLogRow({required this.log});
  @override State<_LoginLogRow> createState() => _LoginLogRowState();
}
class _LoginLogRowState extends State<_LoginLogRow> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final t        = WebTk(Theme.of(context).brightness == Brightness.dark);
    final r        = widget.log;
    final role     = r['user_role']  as String? ?? '';
    final name     = r['full_name']  as String? ?? '—';
    final ident    = r['identifier'] as String? ?? '—';
    final platform = r['platform']   as String? ?? '';
    final ts       = r['created_at'] as String?;
    final color    = _logRoleColor(role);
    final initials = name == '—' ? '?' : name.trim().split(' ')
        .where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).take(2).join();

    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _h ? kAdminAccent.withValues(alpha: 0.028) : Colors.transparent,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 3, color: color.withValues(alpha: 0.35)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  // Role-colored avatar
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withValues(alpha: 0.18)),
                    ),
                    child: Center(child: Text(initials,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                          fontWeight: FontWeight.w700, color: color))),
                  ),
                  const SizedBox(width: 12),
                  // Name + identifier
                  Expanded(flex: 4, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(name,
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                            fontWeight: FontWeight.w600, color: t.text),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(ident,
                        style: TextStyle(fontFamily: 'Poppins',
                            fontSize: 11, color: t.sub),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  )),
                  // Role badge
                  Expanded(flex: 2, child: _LogRoleBadge(role: role)),
                  // Platform badge
                  Expanded(flex: 2, child: _LogPlatformBadge(platform: platform)),
                  // Time with tooltip
                  Expanded(flex: 2, child: Tooltip(
                    message: _logFullTime(ts),
                    preferBelow: false,
                    waitDuration: const Duration(milliseconds: 400),
                    child: Row(children: [
                      Icon(Icons.access_time_rounded,
                          size: 12, color: t.muted),
                      const SizedBox(width: 5),
                      Flexible(child: Text(_logRelTime(ts),
                        style: TextStyle(fontFamily: 'Poppins',
                            fontSize: 12, color: t.sub),
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ]),
                  )),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Event log row ──────────────────────────────────────────────────────────────

class _EventLogRow extends StatefulWidget {
  final Map<String, dynamic> log;
  const _EventLogRow({required this.log});
  @override State<_EventLogRow> createState() => _EventLogRowState();
}
class _EventLogRowState extends State<_EventLogRow> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final t      = WebTk(Theme.of(context).brightness == Brightness.dark);
    final r      = widget.log;
    final title  = r['event_title']    as String? ?? '—';
    final orgId  = r['organizer_id']   as String? ?? '';
    final orgNm  = r['organizer_name'] as String? ?? '';
    final action = r['action']         as String? ?? '';
    final detail = r['details']        as String? ?? '—';
    final ts     = r['created_at']     as String?;
    final color  = _logActionColor(action);

    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _h ? const Color(0xFF7C3AED).withValues(alpha: 0.025)
            : Colors.transparent,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 3, color: color.withValues(alpha: 0.40)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  // Action icon container
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withValues(alpha: 0.18)),
                    ),
                    child: Icon(_logActionIcon(action), size: 18, color: color),
                  ),
                  const SizedBox(width: 12),
                  // Event title
                  Expanded(flex: 4, child: Text(title,
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                        fontWeight: FontWeight.w600, color: t.text),
                    maxLines: 2, overflow: TextOverflow.ellipsis)),
                  // Organizer
                  Expanded(flex: 3, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (orgNm.isNotEmpty)
                        Text(orgNm,
                          style: TextStyle(fontFamily: 'Poppins',
                              fontSize: 12.5, fontWeight: FontWeight.w500,
                              color: t.text),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (orgId.isNotEmpty)
                        Text(orgId,
                          style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 11,
                            color: orgNm.isEmpty ? t.text : t.sub),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  )),
                  // Action badge
                  Expanded(flex: 2, child: _LogActionBadge(action: action)),
                  // Details
                  Expanded(flex: 3, child: Text(detail,
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                        color: t.sub, height: 1.4),
                    maxLines: 2, overflow: TextOverflow.ellipsis)),
                  // Time with tooltip
                  Expanded(flex: 2, child: Tooltip(
                    message: _logFullTime(ts),
                    preferBelow: false,
                    waitDuration: const Duration(milliseconds: 400),
                    child: Row(children: [
                      Icon(Icons.access_time_rounded,
                          size: 12, color: t.muted),
                      const SizedBox(width: 5),
                      Flexible(child: Text(_logRelTime(ts),
                        style: TextStyle(fontFamily: 'Poppins',
                            fontSize: 12, color: t.sub),
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ]),
                  )),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Badge widgets ──────────────────────────────────────────────────────────────

class _LogRoleBadge extends StatelessWidget {
  final String? role;
  const _LogRoleBadge({this.role});
  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final isKnown = const ['admin', 'organizer', 'student'].contains(role);
    final color = isKnown ? _logRoleColor(role) : t.muted;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_logRoleIcon(role), size: 11, color: color),
          const SizedBox(width: 4),
          Text(_logRoleLabel(role),
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    ]);
  }
}

class _LogPlatformBadge extends StatelessWidget {
  final String? platform;
  const _LogPlatformBadge({this.platform});
  @override
  Widget build(BuildContext context) {
    final isWeb = (platform ?? '') == 'web';
    final color = isWeb ? const Color(0xFF4F46E5) : const Color(0xFF0D9488);
    final icon  = isWeb ? Icons.language_rounded : Icons.smartphone_rounded;
    final label = isWeb ? 'Web' : 'Mobile';
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    ]);
  }
}

class _LogActionBadge extends StatelessWidget {
  final String? action;
  const _LogActionBadge({this.action});
  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final isKnown = const ['created', 'updated', 'deleted', 'cancelled', 'approved', 'rejected',
        'checked_in', 'registration_rejected', 'attendance_corrected'].contains(action);
    final color = isKnown ? _logActionColor(action) : t.muted;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_logActionIcon(action), size: 11, color: color),
          const SizedBox(width: 4),
          Text(_logActionLabel(action),
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    ]);
  }
}

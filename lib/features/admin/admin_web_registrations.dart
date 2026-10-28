// ─────────────────────────────────────────────────────────────────────────────
// Admin — Registrations tab.
// View/audit — admin does NOT approve or reject check-in photos here.
// That's organizer's job: they're physically at the event and can compare
// the selfie to the person in front of them, which admin reviewing remotely
// never could. Admin can still open and inspect any submitted photo (audit
// needs visibility), but the decision itself belongs to organizer alone —
// see RegistrationService.updateStatus() for the reviewed_by trail and the
// Logs tab for the resulting audit entries. Same principle as the Events
// tab (Section 18/19 of lib/supabase_schema.sql): admin governs, organizer
// executes, neither duplicates the other's job.
//
// The one exception is after an event's check-in has closed: the attendance
// is final and the organizer can't change it any more, so only the admin can
// correct a record (Checked in ↔ Absent), with a reason that's saved with it
// and logged — RegistrationService.correctAttendance(), migration
// 202610280001.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_colors.dart';
import '../../core/friendly_error.dart';
import '../../core/services/registration_service.dart';
import '../../core/services/supabase_service.dart';
import '../organizer/web/web_shared.dart';
import 'admin_shared.dart';

// Swal confirm button: the admin orange, dark enough for white text.
const _kCorrectBtn = Color(0xFFC2410C);

// ═════════════════════════════════════════════════════════════════════════════
// Registrations page (read-only)
// ═════════════════════════════════════════════════════════════════════════════

class AdminRegistrationsPage extends StatefulWidget {
  const AdminRegistrationsPage({super.key});
  @override
  State<AdminRegistrationsPage> createState() => _AdminRegistrationsPageState();
}

class _AdminRegistrationsPageState extends State<AdminRegistrationsPage> {
  bool _loading = true, _error = false;
  String _errorMsg = '';
  List<Map<String, dynamic>> _all = [], _filtered = [];
  int _page = 0; // 0-based; kAdminPageSize rows per page
  String _search = '';
  String _statusFilter = 'All';
  String _eventFilter = 'All';
  String _sortField = 'registered_at';
  bool _sortAsc = false;
  final _searchCtrl = TextEditingController();

  RealtimeChannel? _channel;
  Timer? _debounce;

  static const _kStatuses = [
    'pending',
    'qr_scanned',
    'photo_required',
    'photo_submitted',
    'checked_in',
    'rejected',
  ];

  List<String> get _eventOptions {
    final titles =
        _all
            .map((r) => r['event_title'] as String?)
            .whereType<String>()
            .where((t) => t.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return ['All', ...titles];
  }

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
    _channel = SupabaseService.client.channel('admin-registrations')
      ..on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(event: '*', schema: 'public', table: 'registrations'),
        (_, [__]) => _debounceLoad(),
      )
      ..subscribe();
  }

  void _debounceLoad() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted) _load(silent: true);
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (mounted)
      setState(() {
        if (!silent) _loading = true;
        _error = false;
      });
    try {
      // Each with its event's schedule (whether check-in has closed, so the
      // attendance can be corrected) and organizer (for the Logs entry).
      final rows = await SupabaseService.client
          .from('registrations')
          .select(
            '*, events(event_date, end_date, start_time, end_time, event_status, '
            'archived_at, organizer_id, organizers(full_name))',
          )
          .order('registered_at', ascending: false)
          .limit(300);
      if (!mounted) return;
      _all = List<Map<String, dynamic>>.from(rows as List);
      _loading = false;
      _applyFilter();
    } catch (e) {
      debugPrint('Admin registrations failed to load: $e');
      if (mounted)
        setState(() {
          _loading = false;
          _error = true;
          _errorMsg = friendlyError(
            e,
            fallback: 'The registrations couldn’t be loaded. Please try again.',
          );
        });
    }
  }

  // resetPage: a new search / filter / sort starts from page 1. Live
  // reloads keep the current page (clamped in build).
  void _applyFilter({bool resetPage = false}) {
    if (resetPage) _page = 0;
    final q = _search.toLowerCase();
    var list = _all.where((r) {
      if (_statusFilter != 'All' && r['status'] != _statusFilter) return false;
      if (_eventFilter != 'All' &&
          (r['event_title'] as String? ?? '') != _eventFilter)
        return false;
      if (q.isNotEmpty) {
        final name = (r['student_name'] as String? ?? '').toLowerCase();
        final lrn = (r['student_school_id'] as String? ?? '').toLowerCase();
        final event = (r['event_title'] as String? ?? '').toLowerCase();
        if (!name.contains(q) && !lrn.contains(q) && !event.contains(q))
          return false;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      int cmp;
      if (_sortField == 'student_name') {
        cmp = (a['student_name'] as String? ?? '').compareTo(
          b['student_name'] as String? ?? '',
        );
      } else if (_sortField == 'event_title') {
        cmp = (a['event_title'] as String? ?? '').compareTo(
          b['event_title'] as String? ?? '',
        );
      } else if (_sortField == 'status') {
        const order = {
          'photo_submitted': 0,
          'pending': 1,
          'qr_scanned': 2,
          'photo_required': 3,
          'checked_in': 4,
          'rejected': 5,
        };
        final ao = order[a['status'] as String? ?? ''] ?? 6;
        final bo = order[b['status'] as String? ?? ''] ?? 6;
        cmp = ao.compareTo(bo);
      } else if (_sortField == 'checked_in_at') {
        final aDate = (a['checked_in_at'] as String?) ?? '';
        final bDate = (b['checked_in_at'] as String?) ?? '';
        if (aDate.isEmpty && bDate.isEmpty) {
          cmp = 0;
        } else if (aDate.isEmpty) {
          return 1;
        } else if (bDate.isEmpty) {
          return -1;
        } else {
          cmp = aDate.compareTo(bDate);
        }
      } else {
        cmp = ((a['registered_at'] as String?) ?? '').compareTo(
          (b['registered_at'] as String?) ?? '',
        );
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
      _sortAsc =
          field == 'student_name' ||
          field == 'event_title' ||
          field == 'status';
    }
    _applyFilter(resetPage: true);
  }

  // View-only — opens the submitted photo for inspection. No result to
  // handle: this dialog no longer writes anything, it only displays.
  void _viewPhoto(Map<String, dynamic> reg) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _PhotoViewDialog(reg: reg),
    );
  }

  // Only once the event's check-in has closed (before then it's the
  // organizer's to decide), and not for an archived or cancelled event.
  bool _canCorrect(Map<String, dynamic> reg) {
    final ev = reg['events'];
    if (ev is! Map) return false;
    final event = Map<String, dynamic>.from(ev);
    return attendanceFinal(event) &&
        !eventIsArchived(event) &&
        !eventIsCancelled(event);
  }

  // Checked in ↔ Absent, with a reason that's kept with the attendance and
  // logged. A Declined student who was there can be marked Checked in.
  Future<void> _correct(Map<String, dynamic> reg) async {
    final attended = reg['status'] != 'checked_in';
    final name = reg['student_name'] as String? ?? 'this student';
    final r = await Swal.fire(
      context,
      icon: SwalIcon.warning,
      title: attended ? 'Mark $name as checked in?' : 'Mark $name as absent?',
      text: attended
          ? 'Check-in for this event has closed, so the organizer can’t change '
              'it any more. Use this when the student was there but their '
              'check-in wasn’t finished in time. Your reason is saved with the '
              'attendance and in the Logs.'
          : 'Check-in for this event has closed, so the organizer can’t change '
              'it any more. Use this when the student was checked in by '
              'mistake. Your reason is saved with the attendance and in the Logs.',
      input: true,
      inputLabel: 'Reason',
      inputPlaceholder: attended
          ? 'e.g. Selfie was sent in time but not reviewed'
          : 'e.g. The wrong student was checked in',
      inputValidator: (v) =>
          v.trim().isEmpty ? 'Give a reason for the correction.' : null,
      showCancelButton: true,
      confirmButtonText: attended ? 'Mark Checked In' : 'Mark Absent',
      confirmButtonColor: _kCorrectBtn,
      preConfirm: (v) async {
        try {
          await RegistrationService.correctAttendance(
            reg,
            attended: attended,
            reason: v ?? '',
          );
          return null;
        } catch (e) {
          return friendlyError(
            e,
            fallback: 'The attendance couldn’t be corrected. Please try again.',
          );
        }
      },
    );
    if (!r.isConfirmed || !mounted) return;
    unawaited(_load(silent: true));
    await Swal.fire(
      context,
      icon: SwalIcon.success,
      title: 'Attendance corrected',
      text: '$name is now ${attended ? 'checked in' : 'absent'} for '
          '${reg['event_title'] ?? 'this event'}.',
      confirmButtonColor: _kCorrectBtn,
      timer: const Duration(seconds: 3),
      timerProgressBar: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final totalCount = _all.length;
    final eventOpts = _eventOptions;
    final hasFilter =
        _search.isNotEmpty || _statusFilter != 'All' || _eventFilter != 'All';
    // Current page (clamped — a filter or live reload can shrink the list).
    final pageCount = _filtered.isEmpty
        ? 1
        : (_filtered.length + kAdminPageSize - 1) ~/ kAdminPageSize;
    final page = _page.clamp(0, pageCount - 1);
    final pageRows = _filtered
        .skip(page * kAdminPageSize)
        .take(kAdminPageSize)
        .toList();
    final filterDesc = [
      if (_statusFilter != 'All') webStatusLabel(_statusFilter),
      if (_eventFilter != 'All') _eventFilter,
      if (_search.isNotEmpty) '"$_search"',
    ].join(' · ');
    final emptySubtitle = filterDesc.isEmpty
        ? 'No registrations have been recorded yet.'
        : 'No registrations match $filterDesc.';

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: kAdminAccent),
      );
    }
    if (_error) {
      return AdminErrorState(message: _errorMsg, onRetry: _load);
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Page header ───────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(kWebPad, 20, kWebPad, 16),
            color: t.card,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Registrations',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: t.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          // ── Filter bar ───────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(kWebPad, 8, kWebPad, 8),
            decoration: BoxDecoration(
              color: t.inputBg,
              border: Border(bottom: BorderSide(color: t.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status filter row
                Row(
                  children: [
                    WebSearchField(
                      controller: _searchCtrl,
                      hint: 'Search student, LRN, or event…',
                      onChanged: (v) {
                        _search = v;
                        _applyFilter(resetPage: true);
                      },
                      width: 200,
                    ),
                    const SizedBox(width: 14),
                    WebFilterMenu<String>(
                      icon: Icons.filter_list_rounded,
                      label: 'Status',
                      menuWidth: 260,
                      selected: _statusFilter,
                      options: [
                        WebFilterOption(
                          value: 'All',
                          label: 'All',
                          count: totalCount,
                        ),
                        for (final status in _kStatuses)
                          WebFilterOption(
                            value: status,
                            label: webStatusLabel(status),
                            count: _all
                                .where((r) => r['status'] == status)
                                .length,
                            color: webStatusColor(status),
                          ),
                      ],
                      onSelect: (status) {
                        _statusFilter = status;
                        _applyFilter(resetPage: true);
                      },
                    ),
                    const Spacer(),
                    if (hasFilter) ...[
                      const SizedBox(width: 8),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () {
                            _search = '';
                            _statusFilter = 'All';
                            _eventFilter = 'All';
                            _searchCtrl.clear();
                            _applyFilter(resetPage: true);
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.close_rounded,
                                size: 13,
                                color: t.muted,
                              ),
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
                // Event filter row — shown only when there are multiple distinct events
                if (eventOpts.length > 1) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'Event:',
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
                          color: _eventFilter != 'All'
                              ? kAdminAccent.withValues(alpha: 0.07)
                              : t.card,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _eventFilter != 'All'
                                ? kAdminAccent.withValues(alpha: 0.45)
                                : t.border,
                            width: _eventFilter != 'All' ? 1.5 : 1.0,
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: eventOpts.contains(_eventFilter)
                                ? _eventFilter
                                : 'All',
                            isDense: true,
                            selectedItemBuilder: (_) => eventOpts
                                .map(
                                  (opt) => Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      opt == 'All' ? 'All Events' : opt,
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: _eventFilter != 'All'
                                            ? kAdminAccent
                                            : t.text,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            items: eventOpts.map((opt) {
                              final lbl = opt == 'All' ? 'All Events' : opt;
                              final cnt = opt == 'All'
                                  ? totalCount
                                  : _all
                                        .where(
                                          (r) =>
                                              (r['event_title'] as String? ??
                                                  '') ==
                                              opt,
                                        )
                                        .length;
                              return DropdownMenuItem<String>(
                                value: opt,
                                child: Text(
                                  '$lbl  ($cnt)',
                                  style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 11,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setState(() {
                                  _eventFilter = v;
                                  _applyFilter(resetPage: true);
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // ── Body ─────────────────────────────────────────────────────────
          if (_filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.all(kWebPad),
              child: WebEmptyState(
                icon: Icons.how_to_reg_outlined,
                title: 'No registrations found',
                subtitle: emptySubtitle,
                action: hasFilter
                    ? TextButton(
                        onPressed: () {
                          _search = '';
                          _statusFilter = 'All';
                          _eventFilter = 'All';
                          _searchCtrl.clear();
                          _applyFilter(resetPage: true);
                        },
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
                    _RegTableHeader(
                      sortField: _sortField,
                      sortAsc: _sortAsc,
                      onSort: _setSort,
                    ),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: pageRows.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: t.border),
                      itemBuilder: (_, i) {
                        final r = pageRows[i];
                        final hasPhoto =
                            (r['selfie_url'] as String?)?.isNotEmpty == true;
                        return _RegistrationRow(
                          reg: r,
                          onView: hasPhoto ? () => _viewPhoto(r) : null,
                          onCorrect: _canCorrect(r) ? () => _correct(r) : null,
                        );
                      },
                    ),
                    AdminPaginationBar(
                      page: page,
                      total: _filtered.length,
                      unfiltered: hasFilter ? totalCount : null,
                      noun: 'registrations',
                      // Only the newest 300 are loaded — say so once the cap is hit.
                      note: _all.length >= 300 ? 'latest 300 loaded' : null,
                      onPage: (p) => setState(() => _page = p),
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

// ─── Sortable table header for Registrations ─────────────────────────────────

class _RegLegend extends StatelessWidget {
  final Color color;
  final String label;
  const _RegLegend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: t.sub),
        ),
      ],
    );
  }
}

// Passive inspection action, not a decision — deliberately neutral blue
// rather than the purple "needs your action" tone the old Review button
// used, and available on any row with a submitted photo (not just ones
// currently awaiting a decision), since audit means being able to look
// back at past decisions too, not just the current queue.
class _ViewPhotoBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _ViewPhotoBtn({required this.onTap});
  @override
  Widget build(BuildContext context) => _RowActionBtn(
    icon: Icons.visibility_outlined,
    label: 'View',
    color: const Color(0xFF3B82F6),
    onTap: onTap,
  );
}

// A correction is a decision, so it's in the admin orange — and only there
// once check-in has closed.
class _CorrectBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _CorrectBtn({required this.onTap});
  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Check-in has closed — correct this attendance',
    child: _RowActionBtn(
      icon: Icons.edit_note_rounded,
      label: 'Correct',
      color: _kCorrectBtn,
      onTap: onTap,
    ),
  );
}

class _RowActionBtn extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _RowActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  @override
  State<_RowActionBtn> createState() => _RowActionBtnState();
}

class _RowActionBtnState extends State<_RowActionBtn> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: _h ? c : c.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: c.withValues(alpha: _h ? 0 : 0.28)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 12, color: _h ? Colors.white : c),
              const SizedBox(width: 5),
              Text(
                widget.label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: _h ? Colors.white : c,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegTableHeader extends StatelessWidget {
  final String sortField;
  final bool sortAsc;
  final void Function(String) onSort;
  const _RegTableHeader({
    required this.sortField,
    required this.sortAsc,
    required this.onSort,
  });

  Widget _sortCol(String label, String field, {int flex = 1}) => Expanded(
    flex: flex,
    child: AdminSortColBtn(
      label: label,
      field: field,
      active: sortField == field,
      asc: sortAsc && sortField == field,
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
      child: Row(
        children: [
          const SizedBox(
            width: 52,
          ), // 3(rail strip) + 20(padding) + 40(avatar) + 12(gap) - 23(left inset) = 52
          _sortCol('STUDENT', 'student_name', flex: 4),
          _sortCol('EVENT', 'event_title', flex: 3),
          _sortCol('STATUS', 'status', flex: 2),
          _sortCol('REGISTERED', 'registered_at', flex: 2),
          _sortCol('CHECKED IN', 'checked_in_at', flex: 2),
          SizedBox(
            width: _kActionWidth,
            child: Text(
              'ACTION',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: t.sub,
                letterSpacing: 0.8,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// View + Correct side by side.
const double _kActionWidth = 156;

class _RegistrationRow extends StatefulWidget {
  final Map<String, dynamic> reg;
  final VoidCallback? onView;
  /// Set once the event's check-in has closed (see _canCorrect).
  final VoidCallback? onCorrect;
  const _RegistrationRow({required this.reg, this.onView, this.onCorrect});
  @override
  State<_RegistrationRow> createState() => _RegistrationRowState();
}

class _RegistrationRowState extends State<_RegistrationRow> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final r = widget.reg;
    final status = r['status'] as String? ?? '';
    final isCheckedIn = status == 'checked_in';
    final isRejected = status == 'rejected';
    final checkedInAt = r['checked_in_at'] as String?;
    final name = r['student_name'] as String? ?? '?';
    final lrn = r['student_school_id'] as String? ?? '—';
    final note = (r['attendance_note'] as String?)?.trim() ?? '';
    final initials = name
        .trim()
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase())
        .take(2)
        .join();

    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final avatarColor = switch (status) {
      'checked_in' => const Color(0xFF10B981),
      'photo_submitted' => const Color(0xFF8B5CF6),
      'rejected' => const Color(0xFFEF4444),
      'pending' => const Color(0xFF3B82F6),
      'qr_scanned' => const Color(0xFFF59E0B),
      'photo_required' => const Color(0xFFF59E0B),
      _ => t.muted,
    };
    final railColor = switch (status) {
      'photo_submitted' => const Color(0xFF8B5CF6).withValues(alpha: 0.45),
      'rejected' => const Color(0xFFEF4444).withValues(alpha: 0.35),
      'checked_in' => const Color(0xFF10B981).withValues(alpha: 0.30),
      _ => Colors.transparent,
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _h
            ? kAdminAccent.withValues(alpha: 0.030)
            : (status == 'photo_submitted'
                  ? const Color(0xFF8B5CF6).withValues(alpha: 0.035)
                  : Colors.transparent),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: railColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      // Status-colored avatar
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: avatarColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: avatarColor.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            initials,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: avatarColor.withValues(
                                alpha: isRejected ? 0.55 : 1.0,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Student name + LRN badge
                      Expanded(
                        flex: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isRejected ? t.muted : t.text,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: t.muted.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'LRN',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: t.muted,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    lrn,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 10.5,
                                      color: t.sub,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Event title
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today_rounded,
                              size: 11,
                              color: isRejected
                                  ? t.muted.withValues(alpha: 0.4)
                                  : t.muted.withValues(alpha: 0.55),
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                r['event_title'] as String? ?? '—',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  color: isRejected ? t.muted : t.sub,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Status badge — the hover says why when it didn't
                      // come from an approved selfie.
                      Expanded(
                        flex: 2,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Tooltip(
                            message: note.isEmpty
                                ? ''
                                : r['corrected_at'] != null
                                    ? 'Corrected by an administrator: $note'
                                    : 'Checked in by hand: $note',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                WebStatusBadge(
                                  label: webStatusLabel(status),
                                  color: webStatusColor(status),
                                ),
                                if (note.isNotEmpty) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.edit_note_rounded,
                                    size: 15,
                                    color: t.muted,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Registered date
                      Expanded(
                        flex: 2,
                        child: Text(
                          webFmtDate(r['registered_at'] as String?),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11.5,
                            color: t.muted,
                          ),
                        ),
                      ),
                      // Check-in date — green with time if checked in
                      Expanded(
                        flex: 2,
                        child: isCheckedIn && checkedInAt != null
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.check_circle_rounded,
                                        size: 13,
                                        color: Color(0xFF10B981),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        webFmtDate(checkedInAt),
                                        style: const TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 11.5,
                                          color: Color(0xFF10B981),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    adminFmtIsoTime(checkedInAt),
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 10,
                                      color: t.muted,
                                    ),
                                  ),
                                ],
                              )
                            : Text(
                                '—',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11.5,
                                  color: t.muted,
                                ),
                              ),
                      ),
                      // View Photo — inspection only, no decision made here.
                      // Correct — only once check-in has closed.
                      SizedBox(
                        width: _kActionWidth,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (widget.onView != null)
                              _ViewPhotoBtn(onTap: widget.onView!),
                            if (widget.onView != null &&
                                widget.onCorrect != null)
                              const SizedBox(width: 6),
                            if (widget.onCorrect != null)
                              _CorrectBtn(onTap: widget.onCorrect!),
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
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Photo VIEW dialog — shown when admin clicks "View" on any registration
// with a submitted selfie. Generates a signed URL for the private photo and
// displays it for inspection. No Approve/Reject here — that decision
// belongs to the organizer who was physically at the event (see
// RegistrationService.updateStatus() for where it actually happens, and the
// Logs tab for the resulting audit trail). This dialog is read-only by
// design, not a stripped-down version of one that used to decide anything.
// ═══════════════════════════════════════════════════════════════════════════════

class _PhotoViewDialog extends StatefulWidget {
  final Map<String, dynamic> reg;
  const _PhotoViewDialog({required this.reg});
  @override
  State<_PhotoViewDialog> createState() => _PhotoViewDialogState();
}

class _PhotoViewDialogState extends State<_PhotoViewDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale, _fade;

  String? _imageUrl;
  bool _urlLoading = true;
  bool _urlError = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _scale = Tween<double>(
      begin: 0.88,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    _loadSignedUrl();
  }

  Future<void> _loadSignedUrl() async {
    final path = widget.reg['selfie_url'] as String?;
    if (path == null || path.isEmpty) {
      if (mounted)
        setState(() {
          _urlLoading = false;
          _urlError = true;
        });
      return;
    }
    try {
      final url = await SupabaseService.client.storage
          .from('selfies')
          .createSignedUrl(path, 3600);
      if (mounted)
        setState(() {
          _imageUrl = url;
          _urlLoading = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _urlLoading = false;
          _urlError = true;
        });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final reg = widget.reg;
    final studentName = reg['student_name'] as String? ?? '—';
    final lrn = reg['student_school_id'] as String? ?? '—';
    final eventTitle = reg['event_title'] as String? ?? '—';
    final regDate = webFmtDate(reg['registered_at'] as String?);
    final status = reg['status'] as String? ?? '';
    final reason = reg['rejection_reason'] as String?;

    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 40,
            vertical: 40,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 40,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: t.border)),
                    ),
                    child: AdminDialogHeader(
                      icon: Icons.photo_camera_outlined,
                      iconColor: const Color(0xFF8B5CF6),
                      title: 'Submitted Photo',
                    ),
                  ),
                  // Student + event info
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                studentName,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: t.text,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Text(
                                    'LRN ',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: t.muted,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  Text(
                                    lrn,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 11.5,
                                      color: t.sub,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                eventTitle,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  color: t.sub,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Registered $regDate',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11,
                                  color: t.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        WebStatusBadge(
                          label: webStatusLabel(status),
                          color: webStatusColor(status),
                        ),
                      ],
                    ),
                  ),
                  if (status == 'rejected' &&
                      reason != null &&
                      reason.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFEF4444,
                          ).withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(
                              0xFFEF4444,
                            ).withValues(alpha: 0.22),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.block_rounded,
                              size: 14,
                              color: Color(0xFFEF4444),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Rejected by organizer',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: t.text,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    reason,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 11.5,
                                      color: t.sub,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Photo area
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxHeight: 340),
                        color: t.inputBg,
                        child: _urlLoading
                            ? const SizedBox(
                                height: 200,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: Color(0xFF8B5CF6),
                                    strokeWidth: 2.5,
                                  ),
                                ),
                              )
                            : _urlError || _imageUrl == null
                            ? SizedBox(
                                height: 160,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.broken_image_rounded,
                                      size: 44,
                                      color: t.muted,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Photo unavailable',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 13,
                                        color: t.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : Image.network(
                                _imageUrl!,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => SizedBox(
                                  height: 160,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.broken_image_rounded,
                                        size: 44,
                                        color: t.muted,
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        'Failed to load image',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: 13,
                                          color: t.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                  // View-only — no decision is made from this dialog.
                  Divider(height: 1, color: t.border),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                    child: Builder(
                      builder: (ctx) => SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: t.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          child: Text(
                            'Close',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              color: t.sub,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

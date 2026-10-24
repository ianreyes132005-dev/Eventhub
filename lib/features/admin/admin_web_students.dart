// ─────────────────────────────────────────────────────────────────────────────
// Admin — Students tab.
// Split out of admin_web_dashboard.dart so each sidebar tab has its own file.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_colors.dart';
import '../../core/friendly_error.dart';
import '../../core/services/event_archive_service.dart';
import '../../core/services/supabase_service.dart';
import '../organizer/web/web_shared.dart';
import 'admin_shared.dart';
import 'admin_web_student_import.dart';
import '../../shared/utils/lrn_input_formatter.dart';

class AdminStudentsPage extends StatefulWidget {
  const AdminStudentsPage({super.key});
  @override
  State<AdminStudentsPage> createState() => _AdminStudentsPageState();
}

class _AdminStudentsPageState extends State<AdminStudentsPage> {
  bool _loading = true, _error = false;
  String _errorMsg = '';
  List<Map<String, dynamic>> _all = [], _filtered = [];
  final Set<String> _selectedLrns = {};
  bool _bulkWorking = false;
  int _page = 0; // 0-based; kAdminPageSize rows per page
  Map<String, int> _regCounts = {};
  String _search = '';
  String _statusFilter = 'All';
  // Grade filter, three parts combined with AND:
  //   level  — 'all' | 'jhs' (7–10) | 'shs' (11–12)
  //   exact  — a single grade 7–12, or 0 = unassigned / outside 7–12
  //   strand — SHS strand ('HUMSS' | 'GAS' | 'STEM'), or 'none' = SHS with no strand
  // e.g. Grade 12 STEM = ('shs', 12, 'STEM').
  String _gradeLevel = 'all';
  int? _gradeExact;
  String? _gradeStrand;
  String _sortField = 'created_at';
  bool _sortAsc = false;
  final _searchCtrl = TextEditingController();

  RealtimeChannel? _channel;
  Timer? _debounce;

  static bool _isValidGrade(int? yr) => yr != null && yr >= 7 && yr <= 12;

  bool get _hasGradeFilter =>
      _gradeLevel != 'all' || _gradeExact != null || _gradeStrand != null;

  void _setGrade(String level, int? exact, String? strand) {
    _gradeLevel = level;
    _gradeExact = exact;
    _gradeStrand = strand;
    _applyFilter(resetPage: true);
  }

  void _clearFilters() {
    _search = '';
    _statusFilter = 'All';
    _gradeLevel = 'all';
    _gradeExact = null;
    _gradeStrand = null;
    _searchCtrl.clear();
    _applyFilter(resetPage: true);
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
    if (mounted)
      setState(() {
        if (!silent) _loading = true;
        _error = false;
      });
    try {
      final results = await Future.wait([
        SupabaseService.client
            .from('students')
            .select() // all columns — tolerant of not-yet-run optional migrations
            .order('created_at', ascending: false),
        SupabaseService.client
            .from('registrations')
            .select('student_school_id'),
      ]);
      if (!mounted) return;
      _all = List<Map<String, dynamic>>.from(results[0] as List);
      final regRows = results[1] as List;
      final counts = <String, int>{};
      for (final r in regRows) {
        final id = (r as Map<String, dynamic>)['student_school_id'] as String?;
        if (id != null) counts[id] = (counts[id] ?? 0) + 1;
      }
      _regCounts = counts;
      _loading = false;
      _applyFilter();
    } catch (e) {
      debugPrint('Admin students failed to load: $e');
      if (mounted)
        setState(() {
          _loading = false;
          _error = true;
          _errorMsg = friendlyError(e,
              fallback: 'The students couldn’t be loaded. Please try again.');
        });
    }
  }

  // resetPage: a new search / filter / sort starts from page 1. Edits,
  // deletes and live reloads keep the current page (clamped in build).
  void _applyFilter({bool resetPage = false}) {
    if (resetPage) _page = 0;
    final q = _search.toLowerCase();
    var list = _all.where((s) {
      if (_statusFilter == 'Active' && s['is_active'] != true) return false;
      if (_statusFilter == 'Inactive' && s['is_active'] == true) return false;
      if (_statusFilter == 'No Regs' &&
          (_regCounts[s['lrn'] as String? ?? ''] ?? 0) > 0) {
        return false;
      }
      final yr = s['year_level'] as int?;
      if (_gradeExact == 0) {
        if (_isValidGrade(yr)) return false;
      } else {
        if (_gradeLevel == 'jhs' && (yr == null || yr < 7 || yr > 10))
          return false;
        if (_gradeLevel == 'shs' && (yr == null || yr < 11 || yr > 12))
          return false;
        if (_gradeExact != null && yr != _gradeExact) return false;
        if (_gradeStrand != null && _strandOf(s) != _gradeStrand) return false;
      }
      if (q.isNotEmpty) {
        final name = (s['full_name'] as String? ?? '').toLowerCase();
        final lrn = (s['lrn'] as String? ?? '').toLowerCase();
        if (!name.contains(q) && !lrn.contains(q)) return false;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      int cmp;
      if (_sortField == 'full_name') {
        cmp = (a['full_name'] as String? ?? '').compareTo(
          b['full_name'] as String? ?? '',
        );
      } else if (_sortField == 'lrn') {
        cmp = (a['lrn'] as String? ?? '').compareTo(b['lrn'] as String? ?? '');
      } else if (_sortField == 'year_level') {
        cmp = ((a['year_level'] as int?) ?? 0).compareTo(
          (b['year_level'] as int?) ?? 0,
        );
      } else if (_sortField == 'is_active') {
        final ai = a['is_active'] == true ? 1 : 0;
        final bi = b['is_active'] == true ? 1 : 0;
        cmp = bi.compareTo(ai);
      } else if (_sortField == 'reg_count') {
        final ac = _regCounts[a['lrn'] as String? ?? ''] ?? 0;
        final bc = _regCounts[b['lrn'] as String? ?? ''] ?? 0;
        cmp = ac.compareTo(bc);
      } else {
        cmp = ((a['created_at'] as String?) ?? '').compareTo(
          (b['created_at'] as String?) ?? '',
        );
      }
      return _sortAsc ? cmp : -cmp;
    });

    final visibleLrns = list
        .map((s) => s['lrn'] as String? ?? '')
        .where((lrn) => lrn.isNotEmpty)
        .toSet();
    _selectedLrns.removeWhere((lrn) => !visibleLrns.contains(lrn));
    setState(() => _filtered = list);
  }

  bool _allFilteredSelected(List<Map<String, dynamic>> rows) =>
      rows.isNotEmpty &&
      rows.every((s) => _selectedLrns.contains(s['lrn'] as String? ?? ''));

  void _toggleStudentSelection(String lrn) {
    setState(() {
      if (!_selectedLrns.add(lrn)) _selectedLrns.remove(lrn);
    });
  }

  void _toggleAllFilteredSelection(List<Map<String, dynamic>> rows) {
    setState(() {
      if (_allFilteredSelected(rows)) {
        _selectedLrns.removeAll(
          rows
              .map((s) => s['lrn'] as String? ?? '')
              .where((id) => id.isNotEmpty),
        );
      } else {
        _selectedLrns.addAll(
          rows
              .map((s) => s['lrn'] as String? ?? '')
              .where((id) => id.isNotEmpty),
        );
      }
    });
  }

  Future<void> _bulkDeactivateStudents() async {
    final lrns = _selectedLrns.toList();
    if (lrns.isEmpty || _bulkWorking) return;

    final ok = await WebAlert.confirm(
      context: context,
      title: 'Deactivate ${lrns.length} Students?',
      message:
          'Selected students will no longer be able to log in. '
          'Their profiles and registration history will be kept.',
      confirmLabel: 'Deactivate',
      confirmColor: const Color(0xFFF59E0B),
      iconColor: const Color(0xFFF59E0B),
      iconBg: const Color(0xFFFFFBEB),
      icon: Icons.person_off_outlined,
    );
    if (ok != true || !mounted) return;

    setState(() => _bulkWorking = true);
    try {
      final updated = await SupabaseService.client
          .from('students')
          .update({'is_active': false})
          .in_('lrn', lrns)
          .select('lrn');
      final updatedLrns = (updated as List)
          .map((row) => (row as Map<String, dynamic>)['lrn'] as String)
          .toSet();
      if (updatedLrns.isEmpty) {
        throw const FriendlyException(
            'None of the selected students could be updated. They may have '
            'been removed, or you don’t have permission to change them.');
      }

      for (final student in _all) {
        final lrn = student['lrn'] as String?;
        if (lrn != null && updatedLrns.contains(lrn)) {
          student['is_active'] = false;
        }
      }
      _selectedLrns.removeAll(updatedLrns);
      _applyFilter();

      if (mounted) {
        final failedCount = lrns.length - updatedLrns.length;
        if (failedCount == 0) {
          await WebAlert.success(
            context: context,
            title: 'Students Deactivated',
            message:
                '${updatedLrns.length} student accounts have been deactivated.',
          );
        } else {
          adminErrorAlert(context,
              FriendlyException('${updatedLrns.length} students were deactivated, but '
                  '$failedCount couldn’t be updated. Please try those again.'),
              title: 'Some students weren’t updated', icon: SwalIcon.warning);
        }
      }
    } catch (e) {
      if (mounted) adminErrorAlert(context, e, title: 'Couldn’t deactivate the students');
    } finally {
      if (mounted) setState(() => _bulkWorking = false);
    }
  }

  Future<void> _bulkActivateStudents() async {
    final lrns = _selectedLrns.toList();
    if (lrns.isEmpty || _bulkWorking) return;

    final ok = await WebAlert.confirm(
      context: context,
      title: 'Activate ${lrns.length} Students?',
      message: 'Selected students will regain access to their accounts.',
      confirmLabel: 'Activate',
      confirmColor: const Color(0xFF10B981),
      iconColor: const Color(0xFF10B981),
      iconBg: const Color(0xFFECFDF5),
      icon: Icons.person_add_outlined,
    );
    if (ok != true || !mounted) return;

    setState(() => _bulkWorking = true);
    try {
      final updated = await SupabaseService.client
          .from('students')
          .update({'is_active': true})
          .in_('lrn', lrns)
          .select('lrn');
      final updatedLrns = (updated as List)
          .map((row) => (row as Map<String, dynamic>)['lrn'] as String)
          .toSet();
      if (updatedLrns.isEmpty) {
        throw const FriendlyException(
            'None of the selected students could be updated. They may have '
            'been removed, or you don’t have permission to change them.');
      }

      for (final student in _all) {
        final lrn = student['lrn'] as String?;
        if (lrn != null && updatedLrns.contains(lrn)) {
          student['is_active'] = true;
        }
      }
      _selectedLrns.removeAll(updatedLrns);
      _applyFilter();

      if (mounted) {
        final failedCount = lrns.length - updatedLrns.length;
        if (failedCount == 0) {
          await WebAlert.success(
            context: context,
            title: 'Students Activated',
            message: '${updatedLrns.length} student accounts are active again.',
          );
        } else {
          adminErrorAlert(context,
              FriendlyException('${updatedLrns.length} students were activated, but '
                  '$failedCount couldn’t be updated. Please try those again.'),
              title: 'Some students weren’t updated', icon: SwalIcon.warning);
        }
      }
    } catch (e) {
      if (mounted) adminErrorAlert(context, e, title: 'Couldn’t activate the students');
    } finally {
      if (mounted) setState(() => _bulkWorking = false);
    }
  }

  Future<void> _bulkDeleteStudents() async {
    var lrns = _selectedLrns.toList();
    if (lrns.isEmpty || _bulkWorking) return;

    // Students with archived attendance can only be deactivated.
    final Set<String> kept;
    try {
      kept = await _withArchivedAttendance(lrns);
    } catch (e) {
      if (mounted) adminErrorAlert(context, e, title: 'Couldn’t delete the students');
      return;
    }
    if (!mounted) return;
    if (kept.length == lrns.length) {
      await _offerDeactivate(lrns);
      return;
    }
    lrns = [for (final l in lrns) if (!kept.contains(l)) l];

    final ok = await WebAlert.confirm(
      context: context,
      title: kept.isEmpty
          ? 'Delete ${lrns.length} Students?'
          : 'Delete ${lrns.length} of the Selected Students?',
      message: kept.isEmpty
          ? 'This permanently removes the selected profiles, revokes '
            'their login access, and deletes their event registration history. '
            'This cannot be undone.'
          : '${kept.length} of the selected students ${kept.length == 1 ? 'has' : 'have'} '
            'attendance in archived events, so they can only be deactivated — they stay '
            'selected. Deleting the other ${lrns.length} permanently removes their profiles, '
            'login access and registration history. This cannot be undone.',
      confirmLabel: kept.isEmpty ? 'Delete Students' : 'Delete ${lrns.length}',
      confirmColor: const Color(0xFFEF4444),
      iconColor: const Color(0xFFEF4444),
      iconBg: const Color(0xFFFEF2F2),
      icon: Icons.delete_outline_rounded,
    );
    if (ok != true || !mounted) return;

    setState(() => _bulkWorking = true);
    final deletedLrns = <String>{};
    final failures = <String>[];
    try {
      for (final lrn in lrns) {
        try {
          final response = await SupabaseService.client.functions.invoke(
            'delete-student',
            body: {'lrn': lrn},
          );
          final body = response.data is Map
              ? Map<String, dynamic>.from(response.data as Map)
              : null;
          if (response.status != 200) {
            failures.add('$lrn: ${friendlyError(body?['message'], fallback: 'It couldn’t be deleted.')}');
          } else {
            deletedLrns.add(lrn);
          }
        } catch (e) {
          debugPrint('delete-student $lrn failed: $e');
          failures.add('$lrn: ${friendlyError(e)}');
        }
      }

      _all.removeWhere(
        (student) => deletedLrns.contains(student['lrn'] as String? ?? ''),
      );
      _selectedLrns.removeAll(deletedLrns);
      _applyFilter();
      if (mounted) {
        if (failures.isEmpty) {
          await WebAlert.success(
            context: context,
            title: 'Students Deleted',
            message:
                '${deletedLrns.length} student profiles and their associated '
                'registration history have been removed.',
          );
        } else {
          adminErrorAlert(context,
              FriendlyException('${deletedLrns.length} students were deleted, but '
                  '${failures.length} couldn’t be and are still selected. ${failures.first}'),
              title: 'Some students weren’t deleted', icon: SwalIcon.warning);
        }
      }
    } finally {
      if (mounted) setState(() => _bulkWorking = false);
    }
  }

  void _setSort(String field) {
    if (_sortField == field) {
      _sortAsc = !_sortAsc;
    } else {
      _sortField = field;
      _sortAsc =
          field == 'full_name' ||
          field == 'lrn' ||
          field == 'year_level' ||
          field == 'is_active';
    }
    _applyFilter(resetPage: true);
  }

  Future<void> _toggleActive(String lrn, bool cur) async {
    final ok = await WebAlert.confirm(
      context: context,
      title: cur ? 'Deactivate Student?' : 'Activate Student?',
      message: cur
          ? 'This student will no longer be able to log in.'
          : 'This student will regain access to their account.',
      confirmLabel: cur ? 'Deactivate' : 'Activate',
      confirmColor: cur ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
      iconColor: cur ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
      iconBg: cur ? const Color(0xFFFFFBEB) : const Color(0xFFECFDF5),
      icon: cur ? Icons.person_off_outlined : Icons.person_add_outlined,
    );
    if (ok != true) return;
    try {
      final updated = await SupabaseService.client
          .from('students')
          .update({'is_active': !cur})
          .eq('lrn', lrn)
          .select();
      if ((updated as List).isEmpty) {
        if (mounted) {
          adminErrorAlert(context, _notUpdated,
              title: cur ? 'Couldn’t deactivate the student' : 'Couldn’t activate the student');
        }
        return;
      }
      final idx = _all.indexWhere((s) => s['lrn'] == lrn);
      if (idx != -1) {
        _all[idx] = {..._all[idx], 'is_active': !cur};
        _applyFilter();
      }
      if (cur && mounted) {
        await WebAlert.success(
          context: context,
          title: 'Student Deactivated',
          message: 'The student can no longer log in to their account.',
        );
      } else if (mounted) {
        await WebAlert.success(
          context: context,
          title: 'Student Activated',
          message: 'The student can now log in to their account.',
        );
      }
    } catch (e) {
      if (mounted) {
        adminErrorAlert(context, e,
            title: cur ? 'Couldn’t deactivate the student' : 'Couldn’t activate the student');
      }
    }
  }

  static const _notUpdated = FriendlyException(
      'This student couldn’t be updated — the record may have been removed, '
      'or you don’t have permission to change it.');

  Future<void> _editStudent(Map<String, dynamic> student) async {
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (_) => _StudentDialog(student: student),
    );
    if (result == null) return;
    final newPassword = result.remove('_new_password') as String?;
    try {
      final updated = await SupabaseService.client
          .from('students')
          .update(result)
          .eq('lrn', student['lrn'] as String)
          .select();
      if ((updated as List).isEmpty) {
        if (mounted) adminErrorAlert(context, _notUpdated, title: 'Couldn’t save the student');
        return;
      }
      final idx = _all.indexWhere((s) => s['lrn'] == student['lrn']);
      if (idx != -1) {
        _all[idx] = {..._all[idx], ...result};
        _applyFilter();
      }

      if (newPassword != null) {
        final err = await adminResetPassword(
          role: 'student',
          id: student['lrn'] as String,
          password: newPassword,
        );
        if (err != null) {
          if (mounted) {
            adminErrorAlert(context,
                FriendlyException('The profile was saved, but the password wasn’t reset. $err'),
                title: 'Password not reset', icon: SwalIcon.warning);
          }
          return;
        }
      }
      if (mounted) {
        WebAlert.success(
          context: context,
          title: 'Saved',
          message: newPassword == null
              ? 'Student profile updated.'
              : 'Profile updated and password reset. Share the new password '
                    'with ${result['full_name'] ?? 'the student'}.',
        );
      }
    } catch (e) {
      if (mounted) adminErrorAlert(context, e, title: 'Couldn’t save the student');
    }
  }

  Future<void> _importStudents() async {
    final changed = await AdminStudentImportDialog.show(context, _all);
    if (changed == true && mounted) await _load(silent: true);
  }

  Future<void> _addStudent() async {
    String? createdName;
    final ok = await showDialog<bool?>(
      context: context,
      builder: (_) => _StudentDialog(
        student: null,
        onCreate: (data) async {
          try {
            createdName = data['full_name'] as String?;
            final password = data['password'] as String;
            final studentData = Map<String, dynamic>.from(data)
              ..remove('password');
            final res = await SupabaseService.client.functions.invoke(
              'create-student',
              body: {...studentData, 'password': password},
            );
            final body = res.data is Map
                ? Map<String, dynamic>.from(res.data as Map)
                : null;
            if (res.status != 200) {
              return friendlyError(body?['message'],
                  fallback: 'The account couldn’t be created. Please try again.');
            }
            return null; // success
          } catch (e) {
            debugPrint('create-student failed: $e');
            return friendlyError(e,
                fallback: 'The account couldn’t be created. Please try again.');
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
        message:
            'Student account for ${createdName ?? 'student'} has been created.',
      );
    }
  }

  // ── Archived attendance: deactivate, don't delete ───────────────────────────
  // Deleting a student would take their rows out of archived attendance
  // records, so those accounts are deactivated instead (the database refuses
  // the delete too — migration 202610230003).

  String _studentName(String lrn) {
    final s = _all.firstWhere((s) => s['lrn'] == lrn, orElse: () => const {});
    final name = (s['full_name'] as String? ?? '').trim();
    return name.isEmpty ? lrn : name;
  }

  /// The LRNs in [lrns] whose student has attendance in archived events.
  Future<Set<String>> _withArchivedAttendance(List<String> lrns) async {
    final byLrn = {for (final s in _all) s['lrn'] as String?: s};
    final counts = await EventArchiveService.archivedAttendanceByStudent(
        lrns.map((l) => byLrn[l]?['user_id'] as String?));
    return {
      for (final l in lrns)
        if ((counts[byLrn[l]?['user_id']] ?? 0) > 0) l,
    };
  }

  /// Says why [lrns] can't be deleted, and offers to deactivate the ones
  /// that are still active.
  Future<void> _offerDeactivate(List<String> lrns) async {
    final active = [
      for (final l in lrns)
        if (_all.any((s) => s['lrn'] == l && s['is_active'] == true)) l,
    ];
    final one = lrns.length == 1;
    final who = one ? _studentName(lrns.first) : '${lrns.length} students';
    final r = await Swal.fire(context,
      icon: SwalIcon.info,
      title: one ? 'This student can’t be deleted' : 'These students can’t be deleted',
      text: '$who ${one ? 'has' : 'have'} attendance in archived events. Archived attendance '
          'is kept as the school’s record, so ${one ? 'this account' : 'these accounts'} can '
          'be deactivated but not deleted. '
          '${active.isEmpty
              ? (one ? 'It’s already deactivated.' : 'They’re already deactivated.')
              : 'A deactivated student can’t sign in, and their records stay complete.'}',
      showCancelButton: active.isNotEmpty,
      confirmButtonText: active.isEmpty
          ? 'OK'
          : one ? 'Deactivate instead' : 'Deactivate ${active.length}',
      confirmButtonColor: active.isEmpty ? kSwalConfirmColor : const Color(0xFFB45309),
      cancelButtonText: 'Close',
      preConfirm: active.isEmpty
          ? null
          : (_) async {
              try {
                final done = await _deactivate(active);
                return done.isEmpty ? 'Nothing was changed. Please try again.' : null;
              } catch (e) {
                return friendlyError(e);
              }
            },
    );
    if (!r.isConfirmed || active.isEmpty || !mounted) return;
    await WebAlert.success(
      context: context,
      title: active.length == 1 ? 'Student Deactivated' : 'Students Deactivated',
      message: active.length == 1
          ? 'The student can no longer log in. Their attendance records are kept.'
          : '${active.length} student accounts have been deactivated. Their attendance '
            'records are kept.',
    );
  }

  /// Deactivates [lrns] — the caller has already asked.
  Future<Set<String>> _deactivate(List<String> lrns) async {
    final updated = await SupabaseService.client
        .from('students')
        .update({'is_active': false})
        .in_('lrn', lrns)
        .select('lrn');
    final done = {
      for (final r in updated as List) (r as Map<String, dynamic>)['lrn'] as String,
    };
    for (final s in _all) {
      if (done.contains(s['lrn'])) s['is_active'] = false;
    }
    if (mounted) _applyFilter();
    return done;
  }

  Future<void> _deleteStudent(String lrn, String name) async {
    // Archived attendance is the school's record: deactivate instead.
    try {
      final kept = await _withArchivedAttendance([lrn]);
      if (!mounted) return;
      if (kept.isNotEmpty) {
        await _offerDeactivate([lrn]);
        return;
      }
    } catch (e) {
      if (mounted) adminErrorAlert(context, e, title: 'Couldn’t delete the student');
      return;
    }
    final ok = await WebAlert.confirm(
      context: context,
      title: 'Delete Student?',
      message:
          'This will permanently remove $name\'s profile, revoke their login, '
          'and delete all their event registration history.',
      confirmLabel: 'Delete',
    );
    if (ok != true) return;
    try {
      final res = await SupabaseService.client.functions.invoke(
        'delete-student',
        body: {'lrn': lrn},
      );
      final body = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : null;
      if (res.status != 200) {
        if (mounted) {
          adminErrorAlert(context, body?['message'],
              title: 'Couldn’t delete the student',
              fallback: 'The student couldn’t be deleted. Please try again.');
        }
        return;
      }
      _all.removeWhere((s) => s['lrn'] == lrn);
      _applyFilter();
      if (mounted)
        WebAlert.success(
          context: context,
          title: 'Deleted',
          message: 'Student record removed and login access revoked.',
        );
    } catch (e) {
      if (mounted) adminErrorAlert(context, e, title: 'Couldn’t delete the student');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final totalCount = _all.length;
    final activeCount = _all.where((s) => s['is_active'] == true).length;
    final inactiveCount = totalCount - activeCount;
    final unregisteredCount = _all
        .where((s) => (_regCounts[s['lrn'] as String? ?? ''] ?? 0) == 0)
        .length;
    final hasFilter =
        _search.isNotEmpty || _statusFilter != 'All' || _hasGradeFilter;
    // Current page (clamped — a delete or filter can shrink the list).
    final pageCount = _filtered.isEmpty
        ? 1
        : (_filtered.length + kAdminPageSize - 1) ~/ kAdminPageSize;
    final page = _page.clamp(0, pageCount - 1);
    final pageRows = _filtered
        .skip(page * kAdminPageSize)
        .take(kAdminPageSize)
        .toList();
    final gradeCounts = {
      for (final g in [7, 8, 9, 10, 11, 12])
        g: _all.where((s) => (s['year_level'] as int?) == g).length,
    };
    // SHS counts keyed by strand ('HUMSS' | 'GAS' | 'STEM') → grade.
    final strandCounts = {
      for (final st in _kStrands)
        st: {
          for (final g in _kShsGrades)
            g: _all
                .where(
                  (s) => (s['year_level'] as int?) == g && _strandOf(s) == st,
                )
                .length,
        },
    };
    final unassignedCount = _all
        .where((s) => !_isValidGrade(s['year_level'] as int?))
        .length;
    final filterDesc = [
      if (_statusFilter != 'All') _statusFilter,
      if (_hasGradeFilter) _gradeLabel(_gradeLevel, _gradeExact, _gradeStrand),
      if (_search.isNotEmpty) '"$_search"',
    ].join(' · ');
    final emptySubtitle = filterDesc.isEmpty
        ? 'Add your first student to get started.'
        : 'No students match $filterDesc.';

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
                            'Students',
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
                    WebBtn(
                      label: 'Import from registrar',
                      icon: Icons.upload_file_rounded,
                      onTap: _importStudents,
                      outlined: true,
                    ),
                    const SizedBox(width: 10),
                    WebBtn(
                      label: 'Add Student',
                      icon: Icons.add_rounded,
                      onTap: _addStudent,
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
              color: t.bg,
              border: Border(bottom: BorderSide(color: t.border)),
            ),
            child: Row(
              children: [
                WebSearchField(
                  controller: _searchCtrl,
                  hint: 'Search name or LRN…',
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
                  menuWidth: 220,
                  selected: _statusFilter,
                  options: [
                    WebFilterOption(
                      value: 'All',
                      label: 'All',
                      count: totalCount,
                    ),
                    WebFilterOption(
                      value: 'Active',
                      label: 'Active',
                      count: activeCount,
                      color: const Color(0xFF10B981),
                    ),
                    WebFilterOption(
                      value: 'Inactive',
                      label: 'Inactive',
                      count: inactiveCount,
                      color: kMuted,
                    ),
                    WebFilterOption(
                      value: 'No Regs',
                      label: 'No Regs',
                      count: unregisteredCount,
                      color: const Color(0xFFF59E0B),
                    ),
                  ],
                  onSelect: (status) {
                    _statusFilter = status;
                    _applyFilter(resetPage: true);
                  },
                ),
                const SizedBox(width: 8),
                Container(width: 1, height: 18, color: t.border),
                const SizedBox(width: 14),
                _GradeFilterMenu(
                  total: totalCount,
                  counts: gradeCounts,
                  strandCounts: strandCounts,
                  unassigned: unassignedCount,
                  level: _gradeLevel,
                  exact: _gradeExact,
                  strand: _gradeStrand,
                  onSelect: _setGrade,
                ),
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
                    if (_selectedLrns.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: kAdminAccent.withValues(alpha: 0.06),
                          border: Border(bottom: BorderSide(color: t.border)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${_selectedLrns.length} selected from ${_filtered.length} filtered students',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: t.text,
                                ),
                              ),
                            ),
                            _StudentBulkActionButton(
                              label: 'Deactivate',
                              icon: Icons.person_off_outlined,
                              backgroundColor: const Color(0xFFFFF4CC),
                              foregroundColor: const Color(0xFF9A6700),
                              onTap: _bulkWorking
                                  ? () {}
                                  : _bulkDeactivateStudents,
                            ),
                            const SizedBox(width: 8),
                            _StudentBulkActionButton(
                              label: 'Activate',
                              icon: Icons.person_add_outlined,
                              backgroundColor: const Color(0xFFE4F8EE),
                              foregroundColor: const Color(0xFF087443),
                              onTap: _bulkWorking ? () {} : _bulkActivateStudents,
                            ),
                            const SizedBox(width: 8),
                            _StudentBulkActionButton(
                              label: 'Delete',
                              icon: Icons.delete_outline_rounded,
                              backgroundColor: const Color(0xFFFFE4E4),
                              foregroundColor: const Color(0xFFB42318),
                              onTap: _bulkWorking ? () {} : _bulkDeleteStudents,
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: _bulkWorking
                                  ? null
                                  : () => setState(_selectedLrns.clear),
                              child: Text(
                                'Clear',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  color: t.sub,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    _StudentTableHeader(
                      sortField: _sortField,
                      sortAsc: _sortAsc,
                      onSort: _setSort,
                      allSelected: _allFilteredSelected(_filtered),
                      onToggleAll: () => _toggleAllFilteredSelection(_filtered),
                    ),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: pageRows.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: t.border),
                      itemBuilder: (_, i) {
                        final s = pageRows[i];
                        return _StudentRow(
                          student: s,
                          regCount: _regCounts[s['lrn'] as String? ?? ''] ?? 0,
                          selected: _selectedLrns.contains(
                            s['lrn'] as String? ?? '',
                          ),
                          onSelect: () => _toggleStudentSelection(
                            s['lrn'] as String? ?? '',
                          ),
                          onEdit: () => _editStudent(s),
                          onToggle: () => _toggleActive(
                            s['lrn'] as String,
                            s['is_active'] == true,
                          ),
                          onDelete: () => _deleteStudent(
                            s['lrn'] as String,
                            s['full_name'] as String? ?? '—',
                          ),
                        );
                      },
                    ),
                    AdminPaginationBar(
                      page: page,
                      total: _filtered.length,
                      unfiltered: hasFilter ? totalCount : null,
                      noun: 'students',
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

class _StudentBulkActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onTap;

  const _StudentBulkActionButton({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: backgroundColor,
    borderRadius: BorderRadius.circular(9),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: foregroundColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: foregroundColor,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _StudentRow extends StatefulWidget {
  final Map<String, dynamic> student;
  final int regCount;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onEdit, onToggle, onDelete;
  const _StudentRow({
    required this.student,
    required this.regCount,
    required this.selected,
    required this.onSelect,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });
  @override
  State<_StudentRow> createState() => _StudentRowState();
}

class _StudentRowState extends State<_StudentRow> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final s = widget.student;
    final active = s['is_active'] == true;
    final linked = s['user_id'] != null;
    final yr = s['year_level'] as int?;
    final initials = (s['full_name'] as String? ?? '?')
        .trim()
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase())
        .take(2)
        .join();
    final avatarColor = active ? kAdminAccent : t.muted;

    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _h ? kAdminAccent.withValues(alpha: 0.03) : Colors.transparent,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 3,
                color: active
                    ? Colors.transparent
                    : t.muted.withValues(alpha: 0.30),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 32,
                        child: Checkbox(
                          value: widget.selected,
                          onChanged: (_) => widget.onSelect(),
                          activeColor: kAdminAccent,
                          side: BorderSide(
                            color: t.muted.withValues(alpha: 0.55),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Avatar
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
                              color: avatarColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Name + "no auth" warning
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s['full_name'] as String? ?? '—',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: active ? t.text : t.muted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (!linked)
                              const Text(
                                'No auth account',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 10,
                                  color: Color(0xFFF59E0B),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                      // LRN
                      Expanded(
                        flex: 2,
                        child: Text(
                          formatLrn(s['lrn'] as String? ?? '—'),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            color: t.sub,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Year level badge
                      Expanded(
                        child: yr != null
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF6D28D9,
                                  ).withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(
                                      0xFF6D28D9,
                                    ).withValues(alpha: 0.18),
                                  ),
                                ),
                                child: Text(
                                  s['strand'] is String &&
                                          (yr == 11 || yr == 12)
                                      ? 'G$yr · ${s['strand']}'
                                      : 'G$yr',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF6D28D9),
                                  ),
                                ),
                              )
                            : Text(
                                '—',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  color: t.muted,
                                ),
                              ),
                      ),
                      // Registration count
                      Expanded(
                        child: widget.regCount > 0
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF10B981,
                                  ).withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.how_to_reg_rounded,
                                      size: 11,
                                      color: const Color(
                                        0xFF10B981,
                                      ).withValues(alpha: 0.80),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${widget.regCount}',
                                      style: const TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF10B981),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: t.muted.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '0',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: t.muted,
                                  ),
                                ),
                              ),
                      ),
                      // Status badge
                      Expanded(
                        child: WebStatusBadge(
                          label: active ? 'Active' : 'Inactive',
                          color: active ? const Color(0xFF10B981) : t.muted,
                        ),
                      ),
                      // Account link status — amber when unlinked
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: linked
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFF59E0B),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              linked ? 'Linked' : 'No account',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11.5,
                                fontWeight: linked
                                    ? FontWeight.w400
                                    : FontWeight.w600,
                                color: linked
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFF59E0B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Created date
                      Expanded(
                        flex: 2,
                        child: Text(
                          webFmtDate(s['created_at'] as String?),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11.5,
                            color: t.muted,
                          ),
                        ),
                      ),
                      // Actions — always visible so they're discoverable without hovering
                      // (and never focusable/clickable while invisible).
                      SizedBox(
                        width: 108,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            AdminActBtn(
                              icon: Icons.edit_outlined,
                              color: kAdminAccent,
                              tip: 'Edit',
                              onTap: widget.onEdit,
                            ),
                            const SizedBox(width: 6),
                            AdminActBtn(
                              icon: active
                                  ? Icons.person_off_outlined
                                  : Icons.person_add_outlined,
                              color: active
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFF10B981),
                              tip: active ? 'Deactivate' : 'Activate',
                              onTap: widget.onToggle,
                            ),
                            const SizedBox(width: 6),
                            AdminActBtn(
                              icon: Icons.delete_outline_rounded,
                              color: const Color(0xFFEF4444),
                              tip: 'Delete',
                              onTap: widget.onDelete,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ), // closes inner Row (Padding child)
                ), // closes Padding
              ), // closes Expanded
            ],
          ), // closes outer Row (IntrinsicHeight child)
        ), // closes IntrinsicHeight
      ), // closes AnimatedContainer
    ); // closes MouseRegion
  }
}

// ─── Grade filter menu ───────────────────────────────────────────────────────
// Trigger:  [ 🎓 Grade · All grades ▾ ]   active: [ 🎓 Grade · STEM · Grade 12 ✕ ]
// Menu:
//   ✓ All grades                                                  15
//   ─────────────────────────────┬─────────────────────────────────
//   JUNIOR HIGH               6  │ SENIOR HIGH                    9
//       Grade 7               3  │    STEM                        4
//       Grade 8               1  │        Grade 11                2
//       …                        │        Grade 12                2
//                                │    HUMSS / GAS …
//   ─────────────────────────────┴─────────────────────────────────
//   ⚠ Unassigned grade                                             2
// The trigger mirrors WebFilterChip's metrics so it sits flush with the
// Status chips; the menu uses the card surface so it matches both themes.

const _kJhsGrades = [7, 8, 9, 10];
const _kShsGrades = [11, 12];
const _kStrands = ['STEM', 'HUMSS', 'GAS'];

// Menu geometry: panel padding 6, item horizontal padding 10, 1px column rule.
// Panel 420 → inner 412 (4px padding). Two 200px columns + 9px rule = 409.
// Item horizontal padding is 8, so content = column − 16.
const double _kMenuWidth = 420;
const double _kColWidth = 200;
const double _kColItemW = 184;
const double _kFullItemW = 396;

// SHS strand of a student row, normalized: 'HUMSS' | 'GAS' | 'STEM' | 'none'.
String _strandOf(Map<String, dynamic> s) {
  final v = s['strand'];
  return v is String && _kStrands.contains(v) ? v : 'none';
}

String _strandName(String strand) => strand == 'none' ? 'No strand' : strand;

String _gradeLabel(String level, int? exact, String? strand) {
  if (exact == 0) return 'Unassigned';
  if (strand != null) {
    return exact != null
        ? '${_strandName(strand)} · Grade $exact'
        : _strandName(strand);
  }
  if (exact != null) return 'Grade $exact';
  return switch (level) {
    'jhs' => 'Junior High',
    'shs' => 'Senior High',
    _ => 'All grades',
  };
}

class _GradeFilterMenu extends StatefulWidget {
  final int total, unassigned;
  final Map<int, int> counts; // grade → students
  final Map<String, Map<int, int>> strandCounts; // strand → grade → students
  final String level; // 'all' | 'jhs' | 'shs'
  final int? exact; // 7–12, 0 = unassigned
  final String? strand; // 'HUMSS' | 'GAS' | 'STEM' | 'none'
  final void Function(String level, int? exact, String? strand) onSelect;

  const _GradeFilterMenu({
    required this.total,
    required this.counts,
    required this.strandCounts,
    required this.unassigned,
    required this.level,
    required this.exact,
    required this.strand,
    required this.onSelect,
  });

  @override
  State<_GradeFilterMenu> createState() => _GradeFilterMenuState();
}

class _GradeFilterMenuState extends State<_GradeFilterMenu> {
  final _menu = MenuController();

  bool get _active =>
      widget.level != 'all' || widget.exact != null || widget.strand != null;

  bool _isSel(String level, int? exact, String? strand) =>
      widget.level == level && widget.exact == exact && widget.strand == strand;

  int _sum(List<int> grades) =>
      grades.fold(0, (acc, g) => acc + (widget.counts[g] ?? 0));

  int _strandTotal(String st) =>
      (widget.strandCounts[st] ?? const {}).values.fold(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);

    Widget divider() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      child: Divider(height: 1, thickness: 1, color: t.border),
    );

    // ── Left column: Junior High ────────────────────────────────────────────
    final jhsColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _GradeMenuItem(
          label: 'JUNIOR HIGH',
          count: _sum(_kJhsGrades),
          heading: true,
          width: _kColItemW,
          selected: _isSel('jhs', null, null),
          onPressed: () => widget.onSelect('jhs', null, null),
        ),
        for (final g in _kJhsGrades)
          _GradeMenuItem(
            label: 'Grade $g',
            count: widget.counts[g] ?? 0,
            indent: 1,
            width: _kColItemW,
            selected: _isSel('all', g, null),
            onPressed: () => widget.onSelect('all', g, null),
          ),
      ],
    );

    // ── Right column: Senior High, strand first ─────────────────────────────
    final shsColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _GradeMenuItem(
          label: 'SENIOR HIGH',
          count: _sum(_kShsGrades),
          heading: true,
          width: _kColItemW,
          selected: _isSel('shs', null, null),
          onPressed: () => widget.onSelect('shs', null, null),
        ),
        for (final st in _kStrands) ...[
          _GradeMenuItem(
            label: st,
            count: _strandTotal(st),
            indent: 1,
            strong: true,
            width: _kColItemW,
            selected: _isSel('shs', null, st),
            onPressed: () => widget.onSelect('shs', null, st),
          ),
          for (final g in _kShsGrades)
            _GradeMenuItem(
              label: 'Grade $g',
              count: widget.strandCounts[st]?[g] ?? 0,
              indent: 2,
              width: _kColItemW,
              selected: _isSel('shs', g, st),
              onPressed: () => widget.onSelect('shs', g, st),
            ),
        ],
      ],
    );

    return MenuAnchor(
      controller: _menu,
      alignmentOffset: const Offset(0, 6),
      style: adminFilterMenuStyle(t, width: _kMenuWidth, maxHeight: 680),
      menuChildren: [
        _GradeMenuItem(
          label: 'All grades',
          count: widget.total,
          width: _kFullItemW,
          selected: !_active,
          onPressed: () => widget.onSelect('all', null, null),
        ),
        divider(),
        // Two columns: Junior High │ Senior High (by strand). Each column
        // needs a fixed width: MenuItemButton's label row expands to fill
        // its parent, and a bare Row hands its children unbounded width.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _kColWidth,
                child: Align(alignment: Alignment.topLeft, child: jhsColumn),
              ),
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: t.border,
              ),
              SizedBox(
                width: _kColWidth,
                child: Align(alignment: Alignment.topLeft, child: shsColumn),
              ),
            ],
          ),
        ),
        if (widget.unassigned > 0) ...[
          divider(),
          _GradeMenuItem(
            label: 'Unassigned grade',
            count: widget.unassigned,
            warning: true,
            width: _kFullItemW,
            tooltip: 'No grade set, or a grade outside 7–12',
            selected: widget.exact == 0,
            onPressed: () => widget.onSelect('all', 0, null),
          ),
        ],
      ],
      builder: (context, controller, _) => AdminFilterTrigger(
        icon: Icons.school_rounded,
        label: 'Grade',
        value: _gradeLabel(widget.level, widget.exact, widget.strand),
        active: _active,
        open: controller.isOpen,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        onClear: () {
          controller.close();
          widget.onSelect('all', null, null);
        },
      ),
    );
  }
}

// One compact menu row: check · label · right-aligned count.
// Built on MenuItemButton so arrow keys / Enter / Esc work out of the box.
class _GradeMenuItem extends StatelessWidget {
  final String label;
  final int count;
  final bool selected, heading, strong, warning;
  final int indent; // 0 = flush, 1 = under a heading, 2 = under a strand
  final double width; // content width (column vs full-width row)
  final String? tooltip;
  final VoidCallback onPressed;

  const _GradeMenuItem({
    required this.label,
    required this.count,
    required this.selected,
    required this.onPressed,
    required this.width,
    this.heading = false,
    this.strong = false,
    this.warning = false,
    this.indent = 0,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    const amber = Color(0xFFF59E0B);
    final accent = warning ? amber : kAdminAccent;
    final empty = count == 0;

    final labelColor = selected
        ? accent
        : warning
        ? amber
        : heading
        ? t.sub
        : empty
        ? t.muted
        : t.text;

    final item = MenuItemButton(
      onPressed: onPressed,
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8),
        ),
        minimumSize: WidgetStatePropertyAll(Size(0, heading ? 26 : 30)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (selected) return accent.withValues(alpha: 0.10);
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return t.dark
                ? Colors.white.withValues(alpha: 0.05)
                : const Color(0xFFF1F5F9);
          }
          return Colors.transparent;
        }),
      ),
      child: SizedBox(
        width: width,
        child: Row(
          children: [
            SizedBox(
              width: 14,
              child: warning && !selected
                  ? const Icon(
                      Icons.warning_amber_rounded,
                      size: 12,
                      color: amber,
                    )
                  : selected
                  ? Icon(Icons.check_rounded, size: 13, color: accent)
                  : null,
            ),
            SizedBox(width: 6.0 + indent * 12),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: heading ? 10 : 12,
                  letterSpacing: heading ? 0.8 : 0,
                  fontWeight: selected || heading
                      ? FontWeight.w700
                      : strong
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: labelColor,
                ),
              ),
            ),
            SizedBox(
              width: 24,
              child: Text(
                '$count',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: selected ? accent : t.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Semantics(
      selected: selected,
      label: '$label, $count students',
      child: tooltip == null ? item : Tooltip(message: tooltip!, child: item),
    );
  }
}

// ─── Sortable table header for Students ────────────────────────────────────

class _StudentTableHeader extends StatelessWidget {
  final String sortField;
  final bool sortAsc;
  final bool allSelected;
  final void Function(String) onSort;
  final VoidCallback onToggleAll;
  const _StudentTableHeader({
    required this.sortField,
    required this.sortAsc,
    required this.onSort,
    required this.allSelected,
    required this.onToggleAll,
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

  Widget _staticCol(String label, Color color, {int flex = 1}) => Expanded(
    flex: flex,
    child: Text(
      label,
      style: TextStyle(
        fontFamily: 'Poppins',
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 0.8,
      ),
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
          SizedBox(
            width: 32,
            child: Tooltip(
              message: 'Select all filtered students',
              child: Checkbox(
                value: allSelected,
                onChanged: (_) => onToggleAll(),
                activeColor: kAdminAccent,
                side: BorderSide(color: t.muted.withValues(alpha: 0.55)),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _sortCol('FULL NAME', 'full_name', flex: 3),
          _sortCol('LRN', 'lrn', flex: 2),
          _sortCol('GRADE', 'year_level'),
          _sortCol('REGS', 'reg_count'),
          _sortCol('STATUS', 'is_active'),
          _staticCol('AUTH', t.sub),
          _sortCol('CREATED', 'created_at', flex: 2),
          // Same width as the row's 3 action buttons (3×32 + 2×6 gaps), so
          // centring it puts it over the middle (Activate/Deactivate) button.
          SizedBox(
            width: 108,
            child: Text(
              'ACTIONS',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: t.sub,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Student dialog ────────────────────────────────────────────────────────
// Three short sections — Student · Grade level · Login — with labels above
// every field and errors shown inline under the field that caused them.
//   • LRN: the school prefix (123456 - 26) is filled in and the admin types
//     only the last 4 digits; "Different LRN prefix?" switches to all 12
//     (transferees, other enrollment years). The student signs in with the
//     full LRN, shown live under the field.
//   • Grade: compact number chips grouped by level; Strand slides in for 11–12.
//   • Password: one visible field + Generate, since the admin has to hand it
//     to the student and there is no self-service reset.

class _StudentDialog extends StatefulWidget {
  final Map<String, dynamic>? student;
  // For add mode only: called with the validated form data.
  // Returns an error message string on failure, or null on success.
  final Future<String?> Function(Map<String, dynamic>)? onCreate;
  const _StudentDialog({required this.student, this.onCreate});
  @override
  State<_StudentDialog> createState() => _StudentDialogState();
}

class _StudentDialogState extends State<_StudentDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale, _fade;
  // The last 4 digits after kSchoolLrnPrefix — or, with _fullLrn, the whole
  // 12-digit LRN (auto-formatted).
  final _lrnCtrl = TextEditingController();
  bool _fullLrn = false;
  final _sectionCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _firstCtrl = TextEditingController();
  final _middleCtrl = TextEditingController(); // optional
  // True when an older student (saved before name parts existed) was split
  // from full_name by guesswork — the admin is asked to double-check it.
  bool _nameGuessed = false;
  final _pwCtrl = TextEditingController();
  bool _pwHidden = false; // visible: admin must share it
  bool _saving = false;
  bool _resetPw = false; // edit mode: "Reset password" opened
  int? _selectedYear;
  String? _selectedStrand;
  Map<String, String> _errors = {};


  static const _strandNames = {
    'STEM': 'Science, Technology, Engineering & Mathematics',
    'HUMSS': 'Humanities & Social Sciences',
    'GAS': 'General Academic Strand',
  };

  bool get _isEdit => widget.student != null;
  bool get _isShs => _selectedYear == 11 || _selectedYear == 12;
  // Edit mode: only accounts with a login have a password to reset.
  bool get _hasLogin => widget.student?['user_id'] != null;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _scale = Tween<double>(
      begin: 0.94,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    if (_isEdit) {
      final s = widget.student!;
      final first = (s['first_name'] as String? ?? '').trim();
      final last = (s['last_name'] as String? ?? '').trim();
      if (first.isNotEmpty && last.isNotEmpty) {
        _firstCtrl.text = first;
        _lastCtrl.text = last;
      } else {
        // Best guess for older rows: last word = last name, rest = first name.
        final words = (s['full_name'] as String? ?? '')
            .trim()
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .toList();
        if (words.length >= 2) {
          _lastCtrl.text = words.last;
          _firstCtrl.text = words.sublist(0, words.length - 1).join(' ');
          _nameGuessed = true;
        } else if (words.length == 1) {
          _firstCtrl.text = words.first;
          _nameGuessed = true;
        }
      }
      _middleCtrl.text = (s['middle_name'] as String? ?? '').trim();
      _selectedYear = widget.student!['year_level'] as int?;
      final st = widget.student!['strand'];
      _selectedStrand = st is String && _kStrands.contains(st) ? st : null;
      _sectionCtrl.text = widget.student!['section'] as String? ?? '';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _lrnCtrl.dispose();
    _sectionCtrl.dispose();
    _lastCtrl.dispose();
    _firstCtrl.dispose();
    _middleCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  // ── Validation / submit ────────────────────────────────────────────────────

  // The full 12-digit LRN the form describes.
  String get _lrn => _fullLrn
      ? lrnDigits(_lrnCtrl.text)
      : '$kSchoolLrnPrefix${lrnDigits(_lrnCtrl.text)}';

  Map<String, String> _validate() {
    final yr = _selectedYear;
    return {
      if (!_isEdit && lrnDigits(_lrnCtrl.text).length != (_fullLrn ? 12 : 4))
        'lrn': _fullLrn
            ? 'Enter the full 12-digit LRN'
            : 'Enter the last 4 digits of the LRN',
      if (_lastCtrl.text.trim().isEmpty) 'last': 'Last name is required',
      if (_firstCtrl.text.trim().isEmpty) 'first': 'First name is required',
      if (yr == null || yr < 7 || yr > 12) 'grade': 'Select a grade level',
      if (_isShs && _selectedStrand == null) 'strand': 'Select a strand',
      if ((!_isEdit || _resetPw) && _pwCtrl.text.length < 6)
        'password': 'Use at least 6 characters',
    };
  }

  void _clearError(String key) {
    if (_errors.containsKey(key)) setState(() => _errors.remove(key));
  }

  Future<void> _submit() async {
    if (_saving) return;
    final errs = _validate();
    setState(() => _errors = errs);
    if (errs.isNotEmpty) return;

    final data = <String, dynamic>{
      'first_name': _cleanName(_firstCtrl.text),
      'middle_name': _cleanOptional(_middleCtrl.text),
      'last_name': _cleanName(_lastCtrl.text),
      // Display value, natural order — greetings/avatars/tickets read this.
      // The middle name is kept separately and not added here.
      'full_name':
          '${_cleanName(_firstCtrl.text)} ${_cleanName(_lastCtrl.text)}',
      'year_level': _selectedYear,
      'strand': _isShs ? _selectedStrand : null,
      'section': _cleanSection(_sectionCtrl.text),
    };

    if (_isEdit) {
      // Edit mode: pop immediately with data for the parent to save.
      // '_new_password' is stripped by the parent before the profile update.
      if (_resetPw) data['_new_password'] = _pwCtrl.text;
      Navigator.of(context).pop(data);
      return;
    }

    data['lrn'] = _lrn;
    data['password'] = _pwCtrl.text;
    data['is_active'] = true;

    // Add mode: call onCreate inside the dialog so we can show a loading state.
    setState(() => _saving = true);
    final err = await widget.onCreate!(data);
    if (!mounted) return;
    if (err != null) {
      setState(() => _saving = false);
      // [err] is already in plain words (friendlyError in onCreate).
      adminErrorAlert(context, FriendlyException(err), title: 'Couldn’t create the account');
      return;
    }
    Navigator.of(context).pop(true); // true = success
  }

  void _generatePassword() {
    setState(() {
      _pwCtrl.text = adminGeneratePassword();
      _pwHidden = false;
      _errors.remove('password');
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 28,
            vertical: 40,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460, maxHeight: 700),
            child: adminDialogShell(
              icon: _isEdit
                  ? Icons.edit_outlined
                  : Icons.person_add_alt_1_rounded,
              iconColor: kAdminAccent,
              title: _isEdit ? 'Edit Student' : 'Add Student',
              subtitle: _isEdit
                  ? 'Update this student’s profile.'
                  : 'Create a login for a new student.',
              loading: _saving,
              confirmLabel: _isEdit ? 'Save Changes' : 'Add Student',
              confirmColor: kAdminAccent,
              onConfirm: _submit,
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [

                  // ── Student ────────────────────────────────────────────────
                  _section('STUDENT', t),
                  _label('LRN', t),
                  if (_isEdit)
                    _readOnlyField(
                      formatLrn(widget.student!['lrn'] as String? ?? '—'),
                      t,
                    )
                  else
                    _lrnField(t),
                  const SizedBox(height: 14),
                  // Last name first — matches how school rosters list students.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _label('Last name', t),
                            _nameField(
                              _lastCtrl,
                              'last',
                              'e.g. Dela Cruz',
                              t,
                              autofocus: _isEdit,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _label('First name', t),
                            _nameField(_firstCtrl, 'first', 'e.g. Juan', t),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  adminFormLabel('Middle name', t, hint: 'Optional'),
                  _nameField(
                    _middleCtrl,
                    'middle',
                    'e.g. Santos',
                    t,
                    submitOnEnter: _isEdit,
                  ),
                  if (_nameGuessed) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: Color(0xFFF59E0B),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Split automatically from the saved name — check the last, '
                            'first and middle names before saving.',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              color: t.sub,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // ── Grade level ────────────────────────────────────────────
                  const SizedBox(height: 24),
                  _section('GRADE LEVEL', t),
                  _choiceRow('Junior High', [
                    for (final y in _kJhsGrades) _gradeChip(y, t),
                  ], t),
                  const SizedBox(height: 8),
                  _choiceRow('Senior High', [
                    for (final y in _kShsGrades) _gradeChip(y, t),
                  ], t),
                  if (_errors['grade'] != null)
                    _inlineError(_errors['grade']!, indent: true),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: _isShs
                        ? Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _choiceRow('Strand', [
                                  for (final st in _kStrands)
                                    Tooltip(
                                      message: _strandNames[st]!,
                                      waitDuration: const Duration(
                                        milliseconds: 400,
                                      ),
                                      child: _ChoiceChip(
                                        label: st,
                                        selected: _selectedStrand == st,
                                        enabled: !_saving,
                                        onTap: () => setState(() {
                                          _selectedStrand = st;
                                          _errors.remove('strand');
                                        }),
                                      ),
                                    ),
                                ], t),
                                if (_errors['strand'] != null)
                                  _inlineError(
                                    _errors['strand']!,
                                    indent: true,
                                  ),
                              ],
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                  const SizedBox(height: 14),
                  adminFormLabel('Section', t, hint: 'Optional'),
                  TextField(
                    controller: _sectionCtrl,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    style: _inputStyle(t),
                    decoration: _deco('e.g. Sampaguita', t),
                  ),

                  // ── Login ──────────────────────────────────────────────────
                  const SizedBox(height: 24),
                  _section('LOGIN', t),
                  if (_isEdit && !_hasLogin)
                    const AdminNoLoginNote(recipient: 'student')
                  else if (_isEdit && !_resetPw)
                    AdminResetPasswordPrompt(
                      recipient: 'student',
                      accent: kAdminAccent,
                      enabled: !_saving,
                      onReset: () => setState(() {
                        _resetPw = true;
                        _pwCtrl.text = adminGeneratePassword();
                        _pwHidden = false;
                      }),
                    )
                  else ...[
                    AdminInitialPasswordField(
                      controller: _pwCtrl,
                      hidden: _pwHidden,
                      enabled: !_saving,
                      error: _errors['password'],
                      recipient: 'student',
                      accent: kAdminAccent,
                      autofocus: _isEdit,
                      label: _isEdit ? 'New password' : 'Initial password',
                      note: _isEdit
                          ? 'Saved with Save Changes. Share it with the student — '
                                'their old password stops working.'
                          : null,
                      onToggleHidden: () =>
                          setState(() => _pwHidden = !_pwHidden),
                      onGenerate: _generatePassword,
                      onSubmitted: _submit,
                      onChanged: (_) {
                        _clearError('password');
                        setState(() {});
                      },
                    ),
                    if (_isEdit)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: _saving
                              ? null
                              : () => setState(() {
                                  _resetPw = false;
                                  _pwCtrl.clear();
                                  _errors.remove('password');
                                }),
                          style: TextButton.styleFrom(
                            foregroundColor: t.sub,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            minimumSize: const Size(0, 30),
                          ),
                          child: const Text(
                            'Keep current password',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Pieces ─────────────────────────────────────────────────────────────────

  // "123456 - 26" — the school prefix as people read it.
  static final _schoolPrefix =
      '${kSchoolLrnPrefix.substring(0, 6)} - ${kSchoolLrnPrefix.substring(6)}';

  // Add mode: the school prefix sits inside the field and only the last 4
  // digits are typed. "Different LRN prefix?" switches to all 12 digits.
  Widget _lrnField(WebTk t) {
    final complete = lrnDigits(_lrnCtrl.text).length == (_fullLrn ? 12 : 4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: ValueKey(_fullLrn),   // a fresh field (and focus) after switching
          controller: _lrnCtrl,
          enabled: !_saving,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          inputFormatters: _fullLrn
              ? const [LrnInputFormatter()]
              : [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
          onChanged: (_) {
            _clearError('lrn');
            setState(() {});   // keeps the "signs in with …" line live
          },
          style: _inputStyle(t).copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            letterSpacing: 0.5,
          ),
          decoration: _deco(_fullLrn ? '123456 - 26 - 0001' : '0001', t,
              error: _errors['lrn']).copyWith(
            // The school prefix is shown as part of the field — never typed.
            prefixIcon: _fullLrn ? null : adminFieldPrefix('$_schoolPrefix -', t),
            prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            helperText: _errors['lrn'] != null
                ? null
                : complete
                    ? 'The student signs in with ${formatLrn(_lrn)}'
                    : _fullLrn
                        ? 'Type all 12 digits — the student signs in with this LRN.'
                        : 'Type the last 4 digits — the student signs in with the full LRN.',
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _saving ? null : _toggleLrnMode,
            style: TextButton.styleFrom(
              foregroundColor: kAdminAccent,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                  fontWeight: FontWeight.w600),
            ),
            child: Text(_fullLrn
                ? 'Use the school prefix ($_schoolPrefix)'
                : 'Different LRN prefix?'),
          ),
        ),
      ],
    );
  }

  void _toggleLrnMode() {
    final digits = lrnDigits(_lrnCtrl.text);
    setState(() {
      _errors.remove('lrn');
      _fullLrn = !_fullLrn;
      if (_fullLrn) {
        // Start from the school prefix so only the part that differs is retyped.
        _lrnCtrl.text = const LrnInputFormatter()
            .formatEditUpdate(TextEditingValue.empty,
                TextEditingValue(text: '$kSchoolLrnPrefix$digits'))
            .text;
      } else {
        // Keep the last 4 digits when the LRN already uses the school prefix.
        _lrnCtrl.text = digits.length == 12 && digits.startsWith(kSchoolLrnPrefix)
            ? digits.substring(8)
            : '';
      }
    });
  }

  Widget _nameField(
    TextEditingController ctrl,
    String errorKey,
    String hint,
    WebTk t, {
    bool autofocus = false,
    bool submitOnEnter = false,
  }) => TextField(
    controller: ctrl,
    enabled: !_saving,
    autofocus: autofocus,
    textCapitalization: TextCapitalization.words,
    textInputAction: submitOnEnter
        ? TextInputAction.done
        : TextInputAction.next,
    onSubmitted: submitOnEnter ? (_) => _submit() : null,
    onChanged: (_) => _clearError(errorKey),
    style: _inputStyle(t),
    decoration: _deco(hint, t, error: _errors[errorKey]),
  );

  static String _cleanName(String raw) => adminCleanName(raw);

  // Optional fields (middle name, section); blank → null. Title-cased like
  // names ("SAMPAGUITA" → "Sampaguita").
  static String? _cleanOptional(String raw) {
    final s = adminCleanName(raw);
    return s.isEmpty ? null : s;
  }

  static String? _cleanSection(String raw) => _cleanOptional(raw);

  Widget _readOnlyField(String value, WebTk t) => AdminReadOnlyField(
    value: value,
    lockMessage: 'LRN can’t be changed after the account is created',
  );

  Widget _gradeChip(int y, WebTk t) => _ChoiceChip(
    label: '$y',
    selected: _selectedYear == y,
    enabled: !_saving,
    minWidth: 46,
    onTap: () => setState(() {
      _selectedYear = y;
      if (!_isShs) _selectedStrand = null;
      _errors.remove('grade');
    }),
  );

  // Row label on the left, chips on the right — keeps the two levels aligned.
  Widget _choiceRow(String label, List<Widget> chips, WebTk t) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      SizedBox(
        width: 96,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: t.sub,
          ),
        ),
      ),
      Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: chips)),
    ],
  );

  // Thin wrappers over the shared admin form blocks (admin_shared.dart).
  Widget _section(String text, WebTk t) => adminFormSection(text, t);

  Widget _label(String text, WebTk t, {double bottom = 6}) =>
      adminFormLabel(text, t, bottom: bottom);

  Widget _inlineError(String text, {bool indent = false}) =>
      adminFormInlineError(text, indent: indent ? 96 : 0);



  TextStyle _inputStyle(WebTk t) => adminInputStyle(t);

  InputDecoration _deco(String hint, WebTk t, {String? error}) =>
      adminFormDeco(hint, t, error: error);
}

// ─── Choice chip (grade / strand pickers) ─────────────────────────────────────
// Material + InkWell so it gets hover, focus ring and Enter/Space activation.
class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool selected, enabled;
  final double minWidth;
  final VoidCallback onTap;
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
    this.minWidth = 64,
  });

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? kAdminAccent.withValues(alpha: 0.10) : t.inputBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: selected ? kAdminAccent : t.border,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          hoverColor: kAdminAccent.withValues(alpha: 0.05),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minWidth, minHeight: 34),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? kAdminAccent : t.text,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

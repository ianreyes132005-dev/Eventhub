// ─────────────────────────────────────────────────────────────────────────────
// Admin — Organizers tab.
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

// ═════════════════════════════════════════════════════════════════════════════
// Organizers page
// ═════════════════════════════════════════════════════════════════════════════

class AdminOrganizersPage extends StatefulWidget {
  const AdminOrganizersPage({super.key});
  @override
  State<AdminOrganizersPage> createState() => _AdminOrganizersPageState();
}

class _AdminOrganizersPageState extends State<AdminOrganizersPage> {
  bool _loading = true, _error = false;
  String _errorMsg = '';
  List<Map<String, dynamic>> _all = [], _filtered = [];
  final Set<String> _selectedOrganizerIds = {};
  bool _bulkWorking = false;
  int _page = 0; // 0-based; kAdminPageSize rows per page
  Map<String, int> _eventCounts = {};
  String _search = '';
  String _statusFilter = 'All';
  String _sortField = 'created_at';
  bool _sortAsc = false;
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
    if (mounted)
      setState(() {
        if (!silent) _loading = true;
        _error = false;
      });
    try {
      final results = await Future.wait([
        SupabaseService.client
            .from('organizers')
            .select() // all columns — tolerant of not-yet-run optional migrations
            .order('created_at', ascending: false),
        SupabaseService.client.from('events').select('organizer_id'),
      ]);
      if (!mounted) return;
      final organizers = List<Map<String, dynamic>>.from(results[0] as List);
      final eventRows = results[1] as List;
      final counts = <String, int>{};
      for (final r in eventRows) {
        final id = (r as Map<String, dynamic>)['organizer_id'] as String?;
        if (id != null) counts[id] = (counts[id] ?? 0) + 1;
      }
      _all = organizers;
      _eventCounts = counts;
      _loading = false;
      _applyFilter();
    } catch (e) {
      debugPrint('Admin organizers failed to load: $e');
      if (mounted)
        setState(() {
          _loading = false;
          _error = true;
          _errorMsg = friendlyError(
            e,
            fallback: 'The organizers couldn’t be loaded. Please try again.',
          );
        });
    }
  }

  // resetPage: a new search / filter / sort starts from page 1. Edits,
  // deletes and live reloads keep the current page (clamped in build).
  void _applyFilter({bool resetPage = false}) {
    if (resetPage) _page = 0;
    final q = _search.toLowerCase();
    var list = _all.where((o) {
      if (_statusFilter == 'Active' && o['is_active'] != true) return false;
      if (_statusFilter == 'Inactive' && o['is_active'] == true) return false;
      if (_statusFilter == '0 Events' &&
          (_eventCounts[o['organizer_id'] as String? ?? ''] ?? 0) > 0) {
        return false;
      }
      if (q.isNotEmpty) {
        final name = (o['full_name'] as String? ?? '').toLowerCase();
        final id = (o['organizer_id'] as String? ?? '').toLowerCase();
        final org = (o['organization'] as String? ?? '').toLowerCase();
        if (!name.contains(q) && !id.contains(q) && !org.contains(q))
          return false;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      int cmp;
      if (_sortField == 'full_name') {
        cmp = (a['full_name'] as String? ?? '').compareTo(
          b['full_name'] as String? ?? '',
        );
      } else if (_sortField == 'organizer_id') {
        cmp = (a['organizer_id'] as String? ?? '').compareTo(
          b['organizer_id'] as String? ?? '',
        );
      } else if (_sortField == 'event_count') {
        final ac = _eventCounts[a['organizer_id'] as String? ?? ''] ?? 0;
        final bc = _eventCounts[b['organizer_id'] as String? ?? ''] ?? 0;
        cmp = ac.compareTo(bc);
      } else if (_sortField == 'is_active') {
        final ai = a['is_active'] == true ? 1 : 0;
        final bi = b['is_active'] == true ? 1 : 0;
        cmp = bi.compareTo(ai);
      } else {
        cmp = ((a['created_at'] as String?) ?? '').compareTo(
          (b['created_at'] as String?) ?? '',
        );
      }
      return _sortAsc ? cmp : -cmp;
    });

    final filteredIds = list
        .map((o) => o['organizer_id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    _selectedOrganizerIds.removeWhere((id) => !filteredIds.contains(id));
    setState(() => _filtered = list);
  }

  bool _allFilteredSelected(List<Map<String, dynamic>> rows) =>
      rows.isNotEmpty &&
      rows.every(
        (o) =>
            _selectedOrganizerIds.contains(o['organizer_id'] as String? ?? ''),
      );

  void _toggleOrganizerSelection(String id) {
    setState(() {
      if (!_selectedOrganizerIds.add(id)) _selectedOrganizerIds.remove(id);
    });
  }

  void _toggleAllFilteredSelection(List<Map<String, dynamic>> rows) {
    setState(() {
      if (_allFilteredSelected(rows)) {
        _selectedOrganizerIds.removeAll(
          rows
              .map((o) => o['organizer_id'] as String? ?? '')
              .where((id) => id.isNotEmpty),
        );
      } else {
        _selectedOrganizerIds.addAll(
          rows
              .map((o) => o['organizer_id'] as String? ?? '')
              .where((id) => id.isNotEmpty),
        );
      }
    });
  }

  Future<void> _bulkDeactivateOrganizers() async {
    final ids = _selectedOrganizerIds.toList();
    if (ids.isEmpty || _bulkWorking) return;

    final ok = await WebAlert.confirm(
      context: context,
      title: 'Deactivate ${ids.length} Organizers?',
      message:
          'Selected organizers will lose access and cannot manage events. '
          'Their profiles, events, and registrations will be kept.',
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
          .from('organizers')
          .update({'is_active': false})
          .in_('organizer_id', ids)
          .select('organizer_id');
      final updatedIds = (updated as List)
          .map((row) => (row as Map<String, dynamic>)['organizer_id'] as String)
          .toSet();
      if (updatedIds.isEmpty) {
        throw const FriendlyException(
          'None of the selected organizers could be updated. They may have '
          'been removed, or you don’t have permission to change them.',
        );
      }

      for (final organizer in _all) {
        final id = organizer['organizer_id'] as String?;
        if (id != null && updatedIds.contains(id)) {
          organizer['is_active'] = false;
        }
      }
      _selectedOrganizerIds.removeAll(updatedIds);
      _applyFilter();

      if (mounted) {
        final failedCount = ids.length - updatedIds.length;
        if (failedCount == 0) {
          await WebAlert.success(
            context: context,
            title: 'Organizers Deactivated',
            message:
                '${updatedIds.length} organizer accounts have been deactivated.',
          );
        } else {
          adminErrorAlert(
            context,
            FriendlyException(
              '${updatedIds.length} organizers were deactivated, but '
              '$failedCount couldn’t be updated. Please try those again.',
            ),
            title: 'Some organizers weren’t updated',
            icon: SwalIcon.warning,
          );
        }
      }
    } catch (e) {
      if (mounted)
        adminErrorAlert(
          context,
          e,
          title: 'Couldn’t deactivate the organizers',
        );
    } finally {
      if (mounted) setState(() => _bulkWorking = false);
    }
  }

  Future<void> _bulkActivateOrganizers() async {
    final ids = _selectedOrganizerIds.toList();
    if (ids.isEmpty || _bulkWorking) return;

    final ok = await WebAlert.confirm(
      context: context,
      title: 'Activate ${ids.length} Organizers?',
      message: 'Selected organizers will regain access to manage events.',
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
          .from('organizers')
          .update({'is_active': true})
          .in_('organizer_id', ids)
          .select('organizer_id');
      final updatedIds = (updated as List)
          .map((row) => (row as Map<String, dynamic>)['organizer_id'] as String)
          .toSet();
      if (updatedIds.isEmpty) {
        throw const FriendlyException(
          'None of the selected organizers could be updated. They may have '
          'been removed, or you don’t have permission to change them.',
        );
      }

      for (final organizer in _all) {
        final id = organizer['organizer_id'] as String?;
        if (id != null && updatedIds.contains(id)) {
          organizer['is_active'] = true;
        }
      }
      _selectedOrganizerIds.removeAll(updatedIds);
      _applyFilter();

      if (mounted) {
        final failedCount = ids.length - updatedIds.length;
        if (failedCount == 0) {
          await WebAlert.success(
            context: context,
            title: 'Organizers Activated',
            message:
                '${updatedIds.length} organizer accounts are active again.',
          );
        } else {
          adminErrorAlert(
            context,
            FriendlyException(
              '${updatedIds.length} organizers were activated, but '
              '$failedCount couldn’t be updated. Please try those again.',
            ),
            title: 'Some organizers weren’t updated',
            icon: SwalIcon.warning,
          );
        }
      }
    } catch (e) {
      if (mounted)
        adminErrorAlert(context, e, title: 'Couldn’t activate the organizers');
    } finally {
      if (mounted) setState(() => _bulkWorking = false);
    }
  }

  Future<void> _bulkDeleteOrganizers() async {
    var ids = _selectedOrganizerIds.toList();
    if (ids.isEmpty || _bulkWorking) return;

    // Organizers with archived events can only be deactivated.
    final Set<String> kept;
    try {
      kept = await _withArchivedEvents(ids);
    } catch (e) {
      if (mounted)
        adminErrorAlert(context, e, title: 'Couldn’t delete the organizers');
      return;
    }
    if (!mounted) return;
    if (kept.length == ids.length) {
      await _offerDeactivate(ids);
      return;
    }
    ids = [
      for (final id in ids)
        if (!kept.contains(id)) id,
    ];

    final totalEvents = ids.fold<int>(
      0,
      (total, id) => total + (_eventCounts[id] ?? 0),
    );
    final ok = await WebAlert.confirm(
      context: context,
      title: kept.isEmpty
          ? 'Delete ${ids.length} Organizers?'
          : 'Delete ${ids.length} of the Selected Organizers?',
      message:
          '${kept.isEmpty ? '' : '${kept.length} of the selected organizers '
                    '${kept.length == 1 ? 'has' : 'have'} archived events, so they can only be '
                    'deactivated — they stay selected. '}'
          'This permanently removes the ${kept.isEmpty ? 'selected' : 'other'} profiles and revokes '
          'their login access. Their $totalEvents event${totalEvents == 1 ? '' : 's'} '
          'and associated student registrations will also be deleted. '
          'This cannot be undone.',
      confirmLabel: kept.isEmpty ? 'Delete Organizers' : 'Delete ${ids.length}',
      confirmColor: const Color(0xFFEF4444),
      iconColor: const Color(0xFFEF4444),
      iconBg: const Color(0xFFFEF2F2),
      icon: Icons.delete_outline_rounded,
    );
    if (ok != true || !mounted) return;

    setState(() => _bulkWorking = true);
    final deletedIds = <String>{};
    final failures = <String>[];
    try {
      for (final id in ids) {
        try {
          final response = await SupabaseService.client.functions.invoke(
            'delete-organizer',
            body: {'organizer_id': id},
          );
          final body = response.data is Map
              ? Map<String, dynamic>.from(response.data as Map)
              : null;
          if (response.status != 200) {
            failures.add(
              '$id: ${friendlyError(body?['message'], fallback: 'It couldn’t be deleted.')}',
            );
          } else {
            deletedIds.add(id);
          }
        } catch (e) {
          debugPrint('delete-organizer $id failed: $e');
          failures.add('$id: ${friendlyError(e)}');
        }
      }

      _all.removeWhere(
        (o) => deletedIds.contains(o['organizer_id'] as String? ?? ''),
      );
      for (final id in deletedIds) {
        _eventCounts.remove(id);
      }
      _selectedOrganizerIds.removeAll(deletedIds);
      _applyFilter();
      if (mounted) {
        if (failures.isEmpty) {
          await WebAlert.success(
            context: context,
            title: 'Organizers Deleted',
            message:
                '${deletedIds.length} organizer profiles, their events, and '
                'associated student registrations have been removed.',
          );
        } else {
          adminErrorAlert(
            context,
            FriendlyException(
              '${deletedIds.length} organizers were deleted, but '
              '${failures.length} couldn’t be and are still selected. ${failures.first}',
            ),
            title: 'Some organizers weren’t deleted',
            icon: SwalIcon.warning,
          );
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
          field == 'organizer_id' ||
          field == 'is_active';
    }
    _applyFilter(resetPage: true);
  }

  Future<void> _toggleActive(String id, bool cur) async {
    final ok = await WebAlert.confirm(
      context: context,
      title: cur ? 'Deactivate Organizer?' : 'Activate Organizer?',
      message: cur
          ? 'This organizer will lose access and cannot manage events.'
          : 'This organizer will regain access to manage events.',
      confirmLabel: cur ? 'Deactivate' : 'Activate',
      confirmColor: cur ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
      iconColor: cur ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
      iconBg: cur ? const Color(0xFFFFFBEB) : const Color(0xFFECFDF5),
      icon: cur ? Icons.person_off_outlined : Icons.person_add_outlined,
    );
    if (ok != true) return;
    try {
      final updated = await SupabaseService.client
          .from('organizers')
          .update({'is_active': !cur})
          .eq('organizer_id', id)
          .select();
      if ((updated as List).isEmpty) {
        if (mounted) {
          adminErrorAlert(
            context,
            _notUpdated,
            title: cur
                ? 'Couldn’t deactivate the organizer'
                : 'Couldn’t activate the organizer',
          );
        }
        return;
      }
      final idx = _all.indexWhere((o) => o['organizer_id'] == id);
      if (idx != -1) {
        _all[idx] = {..._all[idx], 'is_active': !cur};
        _applyFilter();
      }
      if (cur && mounted) {
        await WebAlert.success(
          context: context,
          title: 'Organizer Deactivated',
          message: 'The organizer can no longer access or manage events.',
        );
      } else if (mounted) {
        await WebAlert.success(
          context: context,
          title: 'Organizer Activated',
          message: 'The organizer can now access and manage events.',
        );
      }
    } catch (e) {
      if (mounted) {
        adminErrorAlert(
          context,
          e,
          title: cur
              ? 'Couldn’t deactivate the organizer'
              : 'Couldn’t activate the organizer',
        );
      }
    }
  }

  static const _notUpdated = FriendlyException(
    'This organizer couldn’t be updated — the account may have been removed, '
    'or you don’t have permission to change it.',
  );

  Future<void> _editOrganizer(Map<String, dynamic> org) async {
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (_) => _OrganizerDialog(organizer: org),
    );
    if (result == null) return;
    final newPassword = result.remove('_new_password') as String?;
    try {
      final updated = await SupabaseService.client
          .from('organizers')
          .update(result)
          .eq('organizer_id', org['organizer_id'] as String)
          .select();
      if ((updated as List).isEmpty) {
        if (mounted)
          adminErrorAlert(
            context,
            _notUpdated,
            title: 'Couldn’t save the organizer',
          );
        return;
      }
      final idx = _all.indexWhere(
        (o) => o['organizer_id'] == org['organizer_id'],
      );
      if (idx != -1) {
        _all[idx] = {..._all[idx], ...result};
        _applyFilter();
      }

      if (newPassword != null) {
        final err = await adminResetPassword(
          role: 'organizer',
          id: org['organizer_id'] as String,
          password: newPassword,
        );
        if (err != null) {
          if (mounted) {
            adminErrorAlert(
              context,
              FriendlyException(
                'The profile was saved, but the password wasn’t reset. $err',
              ),
              title: 'Password not reset',
              icon: SwalIcon.warning,
            );
          }
          return;
        }
      }
      if (mounted) {
        WebAlert.success(
          context: context,
          title: 'Saved',
          message: newPassword == null
              ? 'Organizer profile updated.'
              : 'Profile updated and password reset. Share the new password '
                    'with ${result['full_name'] ?? 'the organizer'}.',
        );
      }
    } catch (e) {
      if (mounted)
        adminErrorAlert(context, e, title: 'Couldn’t save the organizer');
    }
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
            final password = data['password'] as String;
            final organizerData = Map<String, dynamic>.from(data)
              ..remove('password');
            final res = await SupabaseService.client.functions.invoke(
              'create-organizer',
              body: {...organizerData, 'password': password},
            );
            final body = res.data is Map
                ? Map<String, dynamic>.from(res.data as Map)
                : null;
            if (res.status != 200) {
              return friendlyError(
                body?['message'],
                fallback: 'The account couldn’t be created. Please try again.',
              );
            }
            return null; // success
          } catch (e) {
            debugPrint('create-organizer failed: $e');
            return friendlyError(
              e,
              fallback: 'The account couldn’t be created. Please try again.',
            );
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
            'Organizer account for ${createdName ?? 'organizer'} has been created.',
      );
    }
  }

  Future<String> _nextOrgId() async {
    try {
      final rows = await SupabaseService.client
          .from('organizers')
          .select('organizer_id')
          .order('organizer_id', ascending: false)
          .limit(1);
      final list = rows as List;
      if (list.isEmpty) return 'Org0001';
      final last = list.first['organizer_id'] as String? ?? 'Org0000';
      final num = int.tryParse(last.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return 'Org${(num + 1).toString().padLeft(4, '0')}';
    } catch (_) {
      return 'Org0001';
    }
  }

  // ── Archived events: deactivate, don't delete ───────────────────────────────
  // Deleting an organizer deletes their events — archived ones would take the
  // school's attendance records with them — so those accounts are deactivated
  // instead (the database refuses the delete too — migration 202610230003).

  String _organizerName(String id) {
    final o = _all.firstWhere(
      (o) => o['organizer_id'] == id,
      orElse: () => const {},
    );
    final name = (o['full_name'] as String? ?? '').trim();
    return name.isEmpty ? id : name;
  }

  /// The organizer ids in [ids] that have archived events.
  Future<Set<String>> _withArchivedEvents(List<String> ids) async {
    final counts = await EventArchiveService.archivedEventsByOrganizer(ids);
    return {
      for (final id in ids)
        if ((counts[id] ?? 0) > 0) id,
    };
  }

  /// Says why [ids] can't be deleted, and offers to deactivate the ones that
  /// are still active.
  Future<void> _offerDeactivate(List<String> ids) async {
    final active = [
      for (final id in ids)
        if (_all.any((o) => o['organizer_id'] == id && o['is_active'] == true))
          id,
    ];
    final one = ids.length == 1;
    final who = one ? _organizerName(ids.first) : '${ids.length} organizers';
    final r = await Swal.fire(
      context,
      icon: SwalIcon.info,
      title: one
          ? 'This organizer can’t be deleted'
          : 'These organizers can’t be deleted',
      text:
          '$who ${one ? 'has' : 'have'} archived events. Archived events keep the '
          'school’s attendance records, so ${one ? 'this account' : 'these accounts'} can be '
          'deactivated but not deleted. '
          '${active.isEmpty ? (one ? 'It’s already deactivated.' : 'They’re already deactivated.') : 'A deactivated organizer can’t sign in or manage events, and the records stay complete.'}',
      showCancelButton: active.isNotEmpty,
      confirmButtonText: active.isEmpty
          ? 'OK'
          : one
          ? 'Deactivate instead'
          : 'Deactivate ${active.length}',
      confirmButtonColor: active.isEmpty
          ? kSwalConfirmColor
          : const Color(0xFFB45309),
      cancelButtonText: 'Close',
      preConfirm: active.isEmpty
          ? null
          : (_) async {
              try {
                final done = await _deactivate(active);
                return done.isEmpty
                    ? 'Nothing was changed. Please try again.'
                    : null;
              } catch (e) {
                return friendlyError(e);
              }
            },
    );
    if (!r.isConfirmed || active.isEmpty || !mounted) return;
    await WebAlert.success(
      context: context,
      title: active.length == 1
          ? 'Organizer Deactivated'
          : 'Organizers Deactivated',
      message: active.length == 1
          ? 'The organizer can no longer log in. Their events and attendance records are kept.'
          : '${active.length} organizer accounts have been deactivated. Their events and '
                'attendance records are kept.',
    );
  }

  /// Deactivates [ids] — the caller has already asked.
  Future<Set<String>> _deactivate(List<String> ids) async {
    final updated = await SupabaseService.client
        .from('organizers')
        .update({'is_active': false})
        .in_('organizer_id', ids)
        .select('organizer_id');
    final done = {
      for (final r in updated as List)
        (r as Map<String, dynamic>)['organizer_id'] as String,
    };
    for (final o in _all) {
      if (done.contains(o['organizer_id'])) o['is_active'] = false;
    }
    if (mounted) _applyFilter();
    return done;
  }

  Future<void> _deleteOrganizer(String id, String name) async {
    // Archived events are the school's record: deactivate instead.
    try {
      final kept = await _withArchivedEvents([id]);
      if (!mounted) return;
      if (kept.isNotEmpty) {
        await _offerDeactivate([id]);
        return;
      }
    } catch (e) {
      if (mounted)
        adminErrorAlert(context, e, title: 'Couldn’t delete the organizer');
      return;
    }
    final eventCount = _eventCounts[id] ?? 0;
    final message = eventCount > 0
        ? 'This will permanently delete $name\'s profile, their $eventCount event${eventCount == 1 ? '' : 's'}, and all student registrations for those events.'
        : 'This will permanently remove $name\'s profile and their account link.';
    final ok = await WebAlert.confirm(
      context: context,
      title: 'Delete Organizer?',
      message: message,
      confirmLabel: 'Delete',
    );
    if (ok != true) return;
    try {
      final res = await SupabaseService.client.functions.invoke(
        'delete-organizer',
        body: {'organizer_id': id},
      );
      final body = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : null;
      if (res.status != 200) {
        if (mounted) {
          adminErrorAlert(
            context,
            body?['message'],
            title: 'Couldn’t delete the organizer',
            fallback: 'The organizer couldn’t be deleted. Please try again.',
          );
        }
        return;
      }
      _all.removeWhere((o) => o['organizer_id'] == id);
      _eventCounts.remove(id);
      _applyFilter();
      if (mounted)
        WebAlert.success(
          context: context,
          title: 'Deleted',
          message: 'Organizer removed and login access revoked.',
        );
    } catch (e) {
      if (mounted)
        adminErrorAlert(context, e, title: 'Couldn’t delete the organizer');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final totalCount = _all.length;
    final activeCount = _all.where((o) => o['is_active'] == true).length;
    final inactiveCount = totalCount - activeCount;
    final noEventsCount = _all
        .where(
          (o) => (_eventCounts[o['organizer_id'] as String? ?? ''] ?? 0) == 0,
        )
        .length;
    final hasFilter = _search.isNotEmpty || _statusFilter != 'All';
    // Current page (clamped — a delete or filter can shrink the list).
    final pageCount = _filtered.isEmpty
        ? 1
        : (_filtered.length + kAdminPageSize - 1) ~/ kAdminPageSize;
    final page = _page.clamp(0, pageCount - 1);
    final pageRows = _filtered
        .skip(page * kAdminPageSize)
        .take(kAdminPageSize)
        .toList();
    final filterDesc = [
      if (_statusFilter != 'All') _statusFilter,
      if (_search.isNotEmpty) '"$_search"',
    ].join(' · ');
    final emptySubtitle = filterDesc.isEmpty
        ? 'Add your first organizer to get started.'
        : 'No organizers match $filterDesc.';

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
                            'Organizers',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: t.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                        ],
                      ),
                    ),
                    WebBtn(
                      label: 'Add Organizer',
                      icon: Icons.add_rounded,
                      onTap: _addOrganizer,
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
            child: Row(
              children: [
                WebSearchField(
                  controller: _searchCtrl,
                  hint: 'Search name, ID, or org…',
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
                      color: t.muted,
                    ),
                    WebFilterOption(
                      value: '0 Events',
                      label: '0 Events',
                      count: noEventsCount,
                      color: kAdminAccent,
                    ),
                  ],
                  onSelect: (status) {
                    _statusFilter = status;
                    _applyFilter(resetPage: true);
                  },
                ),
                if (hasFilter) ...[
                  const Spacer(),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () {
                        _search = '';
                        _statusFilter = 'All';
                        _searchCtrl.clear();
                        _applyFilter(resetPage: true);
                      },
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
                icon: Icons.badge_outlined,
                title: 'No organizers found',
                subtitle: emptySubtitle,
                action: hasFilter
                    ? TextButton(
                        onPressed: () {
                          _search = '';
                          _statusFilter = 'All';
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
                    if (_selectedOrganizerIds.isNotEmpty)
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
                                '${_selectedOrganizerIds.length} selected from '
                                '${_filtered.length} filtered organizers',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: t.text,
                                ),
                              ),
                            ),
                            _OrganizerBulkActionButton(
                              label: 'Deactivate',
                              icon: Icons.person_off_outlined,
                              backgroundColor: const Color(0xFFFFF4CC),
                              foregroundColor: const Color(0xFF9A6700),
                              onTap: _bulkWorking
                                  ? () {}
                                  : _bulkDeactivateOrganizers,
                            ),
                            const SizedBox(width: 8),
                            _OrganizerBulkActionButton(
                              label: 'Activate',
                              icon: Icons.person_add_outlined,
                              backgroundColor: const Color(0xFFE4F8EE),
                              foregroundColor: const Color(0xFF087443),
                              onTap: _bulkWorking
                                  ? () {}
                                  : _bulkActivateOrganizers,
                            ),
                            const SizedBox(width: 8),
                            _OrganizerBulkActionButton(
                              label: 'Delete',
                              icon: Icons.delete_outline_rounded,
                              backgroundColor: const Color(0xFFFFE4E4),
                              foregroundColor: const Color(0xFFB42318),
                              onTap: _bulkWorking
                                  ? () {}
                                  : _bulkDeleteOrganizers,
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: _bulkWorking
                                  ? null
                                  : () => setState(_selectedOrganizerIds.clear),
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
                    _OrganizerTableHeader(
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
                        final o = pageRows[i];
                        final id = o['organizer_id'] as String? ?? '';
                        return _OrganizerRow(
                          org: o,
                          eventCount: _eventCounts[id] ?? 0,
                          selected: _selectedOrganizerIds.contains(id),
                          onSelect: () => _toggleOrganizerSelection(id),
                          onEdit: () => _editOrganizer(o),
                          onToggle: () =>
                              _toggleActive(id, o['is_active'] == true),
                          onDelete: () => _deleteOrganizer(
                            id,
                            o['full_name'] as String? ?? '',
                          ),
                        );
                      },
                    ),
                    AdminPaginationBar(
                      page: page,
                      total: _filtered.length,
                      unfiltered: hasFilter ? totalCount : null,
                      noun: 'organizers',
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

class _OrganizerBulkActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onTap;

  const _OrganizerBulkActionButton({
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

// ─── Sortable table header for Organizers ──────────────────────────────────

class _OrganizerTableHeader extends StatelessWidget {
  final String sortField;
  final bool sortAsc;
  final bool allSelected;
  final void Function(String) onSort;
  final VoidCallback onToggleAll;
  const _OrganizerTableHeader({
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
              message: 'Select all filtered organizers',
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
          _sortCol('ORG ID', 'organizer_id'),
          _sortCol('EVENTS', 'event_count'),
          _sortCol('STATUS', 'is_active'),
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

class _OrganizerRow extends StatefulWidget {
  final Map<String, dynamic> org;
  final int eventCount;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onEdit, onToggle, onDelete;
  const _OrganizerRow({
    required this.org,
    required this.eventCount,
    required this.selected,
    required this.onSelect,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });
  @override
  State<_OrganizerRow> createState() => _OrganizerRowState();
}

class _OrganizerRowState extends State<_OrganizerRow> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final o = widget.org;
    final active = o['is_active'] == true;
    final orgName = o['organization'] as String?;
    final orgId = o['organizer_id'] as String? ?? '—';
    final initials = (o['full_name'] as String? ?? '?')
        .trim()
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase())
        .take(2)
        .join();
    final avatarColor = active ? kGold : t.muted;

    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _h ? kGold.withValues(alpha: 0.04) : Colors.transparent,
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
                            color: avatarColor.withValues(alpha: 0.22),
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
                                alpha: active ? 1.0 : 0.55,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Name + organization + auth warning
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              o['full_name'] as String? ?? '—',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: active ? t.text : t.muted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (orgName != null && orgName.isNotEmpty)
                              Text(
                                orgName,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 10.5,
                                  color: t.sub,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      // Org ID — gold-tinted badge, hugs content
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: kGold.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: kGold.withValues(alpha: 0.22),
                              ),
                            ),
                            child: Text(
                              orgId,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: kGold.withValues(alpha: 0.90),
                                letterSpacing: 0.4,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                      // Events count
                      Expanded(
                        child: widget.eventCount > 0
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: kGold.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.event_rounded,
                                      size: 11,
                                      color: kGold.withValues(alpha: 0.80),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${widget.eventCount}',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: kGold.withValues(alpha: 0.90),
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
                      // Created date
                      Expanded(
                        flex: 2,
                        child: Text(
                          webFmtDate(o['created_at'] as String?),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11.5,
                            color: t.muted,
                          ),
                        ),
                      ),
                      // Actions — always visible so they're discoverable without
                      // hovering (and never focusable/clickable while invisible).
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

// ─── Organizer dialog ──────────────────────────────────────────────────────
// Mirrors the Student dialog so the two complement each other: same accent,
// same subtitle style and the same section rhythm (Organizer · Affiliation ·
// Login), labels above fields, errors inline.
//   • Organizer ID: "Org" is a fixed prefix; the admin types (or keeps the
//     pre-filled next free) 4 digits. The login username is shown right under it.
//   • Password: one visible field + Generate — the admin hands it over and
//     there is no self-service reset.

class _OrganizerDialog extends StatefulWidget {
  final Map<String, dynamic>? organizer;
  final String? suggestedId;
  // For add mode only: returns an error message on failure, null on success.
  final Future<String?> Function(Map<String, dynamic>)? onCreate;
  const _OrganizerDialog({
    required this.organizer,
    this.suggestedId,
    this.onCreate,
  });
  @override
  State<_OrganizerDialog> createState() => _OrganizerDialogState();
}

class _OrganizerDialogState extends State<_OrganizerDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale, _fade;
  final _idCtrl = TextEditingController(); // 4 digits after "Org"
  final _lastCtrl = TextEditingController();
  final _firstCtrl = TextEditingController();
  final _middleCtrl = TextEditingController(); // optional
  // True when an older organizer (saved before name parts existed) was split
  // from full_name by guesswork — the admin is asked to double-check it.
  bool _nameGuessed = false;
  final _orgCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  bool _pwHidden = false; // visible: admin must share it
  bool _saving = false;
  bool _resetPw = false; // edit mode: "Reset password" opened
  String _suggestedDigits = '';
  Map<String, String> _errors = {};

  bool get _isEdit => widget.organizer != null;
  // Edit mode: only accounts with a login have a password to reset.
  bool get _hasLogin => widget.organizer?['user_id'] != null;

  static String _digitsOf(String? id) =>
      (id ?? '').replaceAll(RegExp(r'\D'), '');

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
      final o = widget.organizer!;
      final first = (o['first_name'] as String? ?? '').trim();
      final last = (o['last_name'] as String? ?? '').trim();
      if (first.isNotEmpty && last.isNotEmpty) {
        _firstCtrl.text = first;
        _lastCtrl.text = last;
      } else {
        // Best guess for older rows: last word = last name, rest = first name.
        final words = (o['full_name'] as String? ?? '')
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
      _middleCtrl.text = (o['middle_name'] as String? ?? '').trim();
      _orgCtrl.text = widget.organizer!['organization'] as String? ?? '';
    } else {
      final d = _digitsOf(widget.suggestedId);
      _suggestedDigits = d.length == 4 ? d : '';
      _idCtrl.text = _suggestedDigits;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _idCtrl.dispose();
    _lastCtrl.dispose();
    _firstCtrl.dispose();
    _middleCtrl.dispose();
    _orgCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  // ── Validation / submit ────────────────────────────────────────────────────

  Map<String, String> _validate() => {
    if (!_isEdit && _idCtrl.text.length != 4)
      'id': 'Enter 4 digits (e.g. 0004)',
    if (_lastCtrl.text.trim().isEmpty) 'last': 'Last name is required',
    if (_firstCtrl.text.trim().isEmpty) 'first': 'First name is required',
    if ((!_isEdit || _resetPw) && _pwCtrl.text.length < 6)
      'password': 'Use at least 6 characters',
  };

  void _clearError(String key) {
    if (_errors.containsKey(key)) setState(() => _errors.remove(key));
  }

  Future<void> _submit() async {
    if (_saving) return;
    final errs = _validate();
    setState(() => _errors = errs);
    if (errs.isNotEmpty) return;

    final first = adminCleanName(_firstCtrl.text);
    final middle = adminCleanName(_middleCtrl.text);
    final last = adminCleanName(_lastCtrl.text);
    // Organization is kept as typed (acronyms like "SSG" must stay uppercase).
    final org = _orgCtrl.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final nameFields = <String, dynamic>{
      'first_name': first,
      'middle_name': middle.isEmpty ? null : middle,
      'last_name': last,
      // Display value, natural order — event cards, logs, dashboards read this.
      // The middle name is kept separately and not added here.
      'full_name': '$first $last',
    };

    if (_isEdit) {
      // '_new_password' is stripped by the parent before the profile update.
      Navigator.of(context).pop(<String, dynamic>{
        ...nameFields,
        'organization': org.isEmpty ? null : org,
        if (_resetPw) '_new_password': _pwCtrl.text,
      });
      return;
    }

    // Add mode: call onCreate inside the dialog so we can show a loading state.
    setState(() => _saving = true);
    final err = await widget.onCreate!(<String, dynamic>{
      'organizer_id': 'Org${_idCtrl.text}',
      ...nameFields,
      'organization': org.isEmpty ? null : org,
      'password': _pwCtrl.text,
      'is_active': true,
    });
    if (!mounted) return;
    if (err != null) {
      setState(() => _saving = false);
      // [err] is already in plain words (friendlyError in onCreate).
      adminErrorAlert(
        context,
        FriendlyException(err),
        title: 'Couldn’t create the account',
      );
      return;
    }
    Navigator.of(context).pop(true); // true = success
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final id = widget.organizer?['organizer_id'] as String? ?? '—';
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
              icon: _isEdit ? Icons.edit_outlined : Icons.badge_rounded,
              iconColor: kAdminAccent,
              title: _isEdit ? 'Edit Organizer' : 'Add Organizer',
              subtitle: _isEdit
                  ? 'Update this organizer’s profile.'
                  : 'Create a login for an event organizer.',
              loading: _saving,
              confirmLabel: _isEdit ? 'Save Changes' : 'Add Organizer',
              confirmColor: kAdminAccent,
              onConfirm: _submit,
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Organizer ──────────────────────────────────────────────
                  adminFormSection('ORGANIZER', t),
                  adminFormLabel('Organizer ID', t),
                  if (_isEdit)
                    AdminReadOnlyField(
                      value: id,
                      lockMessage:
                          'Organizer ID can’t be changed — it is the login username',
                    )
                  else
                    _idField(t),
                  const SizedBox(height: 14),
                  // Last name first — same order as the Add Student dialog.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            adminFormLabel('Last name', t),
                            _nameField(
                              _lastCtrl,
                              'last',
                              'e.g. Santos',
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
                            adminFormLabel('First name', t),
                            _nameField(_firstCtrl, 'first', 'e.g. Maria', t),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  adminFormLabel('Middle name', t, hint: 'Optional'),
                  _nameField(_middleCtrl, 'middle', 'e.g. Reyes', t),
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
                  // ── Affiliation ────────────────────────────────────────────
                  const SizedBox(height: 24),
                  adminFormSection('AFFILIATION', t),
                  adminFormLabel(
                    'Organization or department',
                    t,
                    hint: 'Optional',
                  ),
                  TextField(
                    controller: _orgCtrl,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: _isEdit
                        ? TextInputAction.done
                        : TextInputAction.next,
                    onSubmitted: _isEdit ? (_) => _submit() : null,
                    style: adminInputStyle(t),
                    decoration: adminFormDeco('e.g. Student Council', t),
                  ),

                  // ── Login ──────────────────────────────────────────────────
                  const SizedBox(height: 24),
                  adminFormSection('LOGIN', t),
                  if (_isEdit && !_hasLogin)
                    const AdminNoLoginNote(recipient: 'organizer')
                  else if (_isEdit && !_resetPw)
                    AdminResetPasswordPrompt(
                      recipient: 'organizer',
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
                      recipient: 'organizer',
                      accent: kAdminAccent,
                      autofocus: _isEdit,
                      label: _isEdit ? 'New password' : 'Initial password',
                      note: _isEdit
                          ? 'Saved with Save Changes. Share it with the organizer — '
                                'their old password stops working.'
                          : null,
                      onToggleHidden: () =>
                          setState(() => _pwHidden = !_pwHidden),
                      onGenerate: () => setState(() {
                        _pwCtrl.text = adminGeneratePassword();
                        _pwHidden = false;
                        _errors.remove('password');
                      }),
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

  Widget _nameField(
    TextEditingController ctrl,
    String errorKey,
    String hint,
    WebTk t, {
    bool autofocus = false,
  }) => TextField(
    controller: ctrl,
    enabled: !_saving,
    autofocus: autofocus,
    textCapitalization: TextCapitalization.words,
    textInputAction: TextInputAction.next,
    onChanged: (_) => _clearError(errorKey),
    style: adminInputStyle(t),
    decoration: adminFormDeco(hint, t, error: _errors[errorKey]),
  );

  Widget _idField(WebTk t) {
    final digits = _idCtrl.text;
    final username = digits.isEmpty ? 'org····' : 'org$digits';
    final isNext = digits.isNotEmpty && digits == _suggestedDigits;
    return TextField(
      controller: _idCtrl,
      enabled: !_saving,
      autofocus: true,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
      ],
      onChanged: (_) {
        _clearError('id');
        setState(() {});
      },
      style: adminInputStyle(t).copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
        letterSpacing: 0.5,
      ),
      decoration: adminFormDeco('0001', t, error: _errors['id']).copyWith(
        // Fixed "Org" prefix shown as part of the field — never typed.
        prefixIcon: adminFieldPrefix('Org', t),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        helperText: _errors['id'] == null
            ? 'Username: $username${isNext ? '  ·  next available ID' : ''}'
            : null,
      ),
    );
  }
}

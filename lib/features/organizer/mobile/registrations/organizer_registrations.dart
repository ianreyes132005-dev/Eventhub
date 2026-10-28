import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/registration_service.dart';
import '../../../../core/services/selfie_links.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../../../shared/widgets/error_alert.dart';
import '../../../../core/app_colors.dart';
import '../org_tab_ui.dart';
import 'organizer_registrations_ui.dart';

// ── Reject reason prompt ─────────────────────────────────────────────────────
// Shared by the main list's Reject button. Returns the typed reason, or null
// if the organizer backed out — callers should treat null as "don't reject."

class _RejectReasonDialog extends StatefulWidget {
  final String? studentName;
  final int? selectedCount;
  const _RejectReasonDialog({this.studentName, this.selectedCount});

  @override
  State<_RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<_RejectReasonDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTk(Theme.of(context).brightness == Brightness.dark);

    return Dialog(
      backgroundColor: t.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.block_rounded,
                    size: 19,
                    color: Color(0xFFDC2626),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.selectedCount == null
                        ? 'Reject ${widget.studentName}?'
                        : 'Reject ${widget.selectedCount} selected students?',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              widget.selectedCount == null
                  ? 'This student will not be checked in. Give a reason so they know what to fix.'
                  : 'The same reason will be recorded for every selected student.',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11.5,
                color: t.sub,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 3,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: t.text,
              ),
              decoration: InputDecoration(
                hintText: 'e.g. Selfie doesn\'t match student ID photo',
                hintStyle: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: t.muted,
                ),
                filled: true,
                fillColor: t.inputBg,
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: t.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: t.border),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                  borderSide: BorderSide(color: kGold, width: 1.5),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: t.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        color: t.sub,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _controller.text.trim().isEmpty
                        ? null
                        : () => Navigator.of(
                            context,
                          ).pop(_controller.text.trim()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(
                        0xFFDC2626,
                      ).withValues(alpha: 0.35),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Confirm Reject',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _promptRejectReason(BuildContext context, String studentName) {
  return showDialog<String>(
    context: context,
    builder: (_) => _RejectReasonDialog(studentName: studentName),
  );
}

Future<String?> _promptBulkRejectReason(BuildContext context, int count) {
  return showDialog<String>(
    context: context,
    builder: (_) => _RejectReasonDialog(selectedCount: count),
  );
}

// ── Screen ────────────────────────────────────────────────────────────────────

class RegistrationsScreen extends StatefulWidget {
  final bool showAsEmbedded;
  const RegistrationsScreen({this.showAsEmbedded = false, super.key});

  @override
  State<RegistrationsScreen> createState() => _RegistrationsScreenState();
}

class _RegistrationsScreenState extends State<RegistrationsScreen> {
  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String _filter = 'All';
  String _eventFilter = 'All';
  final _search = TextEditingController();
  RealtimeChannel? _channel;
  // Links to the selfies on screen, renewed before they expire — this tab
  // stays open for the whole session (see SelfieLinks).
  final _selfies = SelfieLinks();
  Timer? _selfieRenewal;
  List<Map<String, dynamic>> _organizerEvents = [];
  final Set<String> _selectedIds = {};
  final Set<String> _statusUpdatingIds = {};
  bool _bulkProcessing = false;

  // Organizer identity — resolved once and reused for scoped queries.
  String? _organizerId;

  /// Every event of this organizer — live changes are kept to these. Taken
  /// from the events themselves, not from the registrations, so an event
  /// nobody has registered for yet counts too; events created while the tab
  /// is open join through the subscription (organizerId).
  final Set<String> _orgEventIds = {};
  // Events the admin archived: their registrations are read-only records.
  final Set<String> _archivedEventIds = {};
  // _organizerEvents by id (see _refreshEventOptions).
  Map<String, Map<String, dynamic>> _eventsById = {};
  bool _fetching = false; // a load is running…
  bool _refetch = false; // …and a change arrived meanwhile
  // Check-in closing makes rows final while the tab is open.
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
    _selfieRenewal = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _loadSelfies(),
    );
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(_applyFilter);
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _selfieRenewal?.cancel();
    _search.dispose();
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  /// [silent]: refresh in place (pull to refresh, a change that arrived
  /// mid-load) — no shimmer, and a failure keeps what's on screen.
  Future<void> _load({bool silent = false}) async {
    if (_fetching) {
      _refetch = true;
      return;
    }
    _fetching = true;
    if (!silent) setState(() => _loading = true);
    try {
      // Resolve the organizer ID once so all subsequent queries are scoped.
      if (_organizerId == null) {
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          final orgRow = await Supabase.instance.client
              .from('organizers')
              .select('organizer_id')
              .eq('user_id', user.id)
              .maybeSingle();
          _organizerId = orgRow?['organizer_id'] as String?;
        }
      }
      final organizerId = _organizerId;
      if (organizerId == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      // The organizer's events first, then the live channel, then the
      // registrations — so nothing that happens meanwhile slips through.
      final events = await RegistrationService.organizerEventsWithArchive(
        organizerId,
      );
      final eventIds = events.ids;
      _orgEventIds
        ..clear()
        ..addAll(eventIds);
      _archivedEventIds
        ..clear()
        ..addAll(events.archived);
      _organizerEvents = events.events;
      _subscribeRealtime(organizerId);

      final rows = await RegistrationService.getAllRegistrations(
        eventIds: eventIds,
      );

      if (!mounted) return;
      setState(() {
        _all = rows;
        _refreshEventOptions();
        _loading = false;
        _applyFilter();
      });
      _loadSelfies();
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      debugPrint('RegistrationsScreen load error: $e');
    } finally {
      _fetching = false;
      if (_refetch && mounted) {
        _refetch = false;
        _load(silent: true);
      }
    }
  }

  // Links for the selfies waiting for review — new ones, and old ones
  // renewed (every 5 minutes) before they stop working.
  Future<void> _loadSelfies() async {
    final paths = {
      for (final r in _all)
        if (r['status'] == 'photo_submitted' && r['selfie_url'] != null)
          r['id'] as String: r['selfie_url'] as String,
    };
    if (await _selfies.fetch(paths) && mounted) setState(() {});
  }

  void _subscribeRealtime(String organizerId) {
    if (_channel != null) return;
    _channel = RegistrationService.subscribeToAllRegistrations(
      (eventType, record) {
        if (!mounted) return;
        final id = record['id'] as String?;
        if (id == null) return;
        // A load is running and may not include this change — load again
        // once it's done.
        if (_fetching) {
          _refetch = true;
          return;
        }

        if (eventType == 'DELETE') {
          // Only the row id comes with a delete; ignore other organizers'.
          if (!_all.any((r) => r['id'] == id)) return;
          setState(() {
            _all.removeWhere((r) => r['id'] == id);
            _selfies.remove(id);
            _selectedIds.remove(id);
            _refreshEventOptions();
            _applyFilter();
          });
          return;
        }

        // Only this organizer's events come through (allowedEventIds).
        setState(() {
          final idx = _all.indexWhere((r) => r['id'] == id);
          if (idx >= 0) {
            _all[idx] = record;
          } else {
            _all.insert(0, record);
          }
          _refreshEventOptions();
          _applyFilter();
        });
        // A new selfie: a new link (the file path is the same as a re-taken
        // one's, so the old link would show the old photo).
        final path = record['selfie_url'] as String?;
        if (record['status'] == 'photo_submitted' && path != null) {
          _selfies.fetch({id: path}, fresh: true).then((changed) {
            if (changed && mounted) setState(() {});
          });
        }
      },
      channelSuffix: organizerId,
      allowedEventIds: _orgEventIds,
      organizerId: organizerId,
      // The admin archiving or restoring an event makes its rows read-only
      // or editable again.
      onEventRow: (event) {
        final id = event['event_id'];
        if (id is! String || !mounted) return;
        setState(() {
          final existingIndex = _organizerEvents.indexWhere(
            (row) => row['event_id'] == id,
          );
          if (existingIndex >= 0) {
            _organizerEvents[existingIndex] = event;
          } else {
            _organizerEvents.add(event);
            _orgEventIds.add(id);
          }
          final archived = eventIsArchived(event);
          archived ? _archivedEventIds.add(id) : _archivedEventIds.remove(id);
          if (archived) {
            _selectedIds.removeWhere(
              (rid) => _all.any((r) => r['id'] == rid && r['event_id'] == id),
            );
          }
          _refreshEventOptions();
          _applyFilter();
        });
      },
    );
  }

  void _applyFilter() {
    final q = _search.text.toLowerCase();
    final validEventIds = _organizerEvents
        .map((event) => event['event_id'] as String? ?? '')
        .toSet();
    if (_eventFilter != 'All' && !validEventIds.contains(_eventFilter)) {
      _eventFilter = 'All';
    }

    _filtered = _all.where((r) {
      final status = r['status'] as String? ?? '';
      final name = (r['student_name'] as String? ?? '').toLowerCase();
      final sid = (r['student_school_id'] as String? ?? '').toLowerCase();
      final evt = (r['event_title'] as String? ?? '').trim();
      final eventTitle = evt.toLowerCase();

      final matchesFilter =
          _filter == 'All' ||
          (_filter == 'Pending' && status == 'pending') ||
          (_filter == 'QR Scanned' && status == 'qr_scanned') ||
          (_filter == 'Awaiting Selfie' && status == 'photo_required') ||
          (_filter == 'Photo Submitted' && status == 'photo_submitted') ||
          (_filter == 'Checked In' && status == 'checked_in') ||
          (_filter == 'Rejected' && status == 'rejected');

      final matchesEvent =
          _eventFilter == 'All' || r['event_id'] == _eventFilter;
      final matchesSearch =
          q.isEmpty ||
          name.contains(q) ||
          sid.contains(q) ||
          eventTitle.contains(q);

      return matchesFilter && matchesEvent && matchesSearch;
    }).toList();
    final reviewableIds = _filteredReviewableIds.toSet();
    _selectedIds.removeWhere((id) => !reviewableIds.contains(id));
  }

  List<String> get _filteredReviewableIds => _filtered
      .where((r) =>
          r['status'] == 'photo_submitted' && !_isArchived(r) && !_isFinal(r))
      .map((r) => r['id'] as String? ?? '')
      .where((id) => id.isNotEmpty)
      .toList();

  // Its event is archived: a read-only record.
  bool _isArchived(Map<String, dynamic> r) =>
      _archivedEventIds.contains(r['event_id']);

  // Its event's check-in has closed: the attendance is final, and only the
  // admin can correct it.
  bool _isFinal(Map<String, dynamic> r) {
    final event = _eventsById[r['event_id']];
    return event != null && attendanceFinal(event);
  }

  bool get _allReviewableSelected =>
      _filteredReviewableIds.isNotEmpty &&
      _filteredReviewableIds.every(_selectedIds.contains);

  void _toggleRegistrationSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleSelectAllReviewable() {
    final ids = _filteredReviewableIds.toSet();
    setState(() {
      if (_allReviewableSelected) {
        _selectedIds.removeAll(ids);
      } else {
        _selectedIds.addAll(ids);
      }
    });
  }

  Future<void> _bulkApproveSelected() => _bulkUpdateSelected('checked_in');

  Future<void> _bulkRejectSelected() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty || _bulkProcessing) return;

    final reason = await _promptBulkRejectReason(context, ids.length);
    if (reason == null || reason.trim().isEmpty || !mounted) return;
    await _bulkUpdateSelected('rejected', rejectionReason: reason);
  }

  Future<void> _bulkUpdateSelected(
    String status, {
    String? rejectionReason,
  }) async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty || _bulkProcessing) return;

    setState(() => _bulkProcessing = true);
    final succeeded = <String>[];
    final failed = <String>[];
    for (final id in ids) {
      try {
        await RegistrationService.updateStatus(
          id,
          status,
          rejectionReason: rejectionReason,
        );
        succeeded.add(id);
      } catch (_) {
        failed.add(id);
      }
    }

    if (!mounted) return;
    setState(() {
      for (final id in succeeded) {
        final index = _all.indexWhere((r) => r['id'] == id);
        if (index >= 0) {
          _all[index] = {
            ..._all[index],
            'status': status,
            if (status == 'checked_in')
              'checked_in_at': DateTime.now().toIso8601String(),
            if (status == 'rejected') 'rejection_reason': rejectionReason,
          };
        }
      }
      _selectedIds.removeAll(succeeded);
      _bulkProcessing = false;
      _applyFilter();
    });

    final verb = status == 'checked_in' ? 'approved' : 'rejected';
    final message = failed.isEmpty
        ? '${succeeded.length} ${succeeded.length == 1 ? 'student' : 'students'} $verb.'
        : '${succeeded.length} $verb; ${failed.length} could not be updated.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: failed.isEmpty
            ? const Color(0xFF16A34A)
            : const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _refreshEventOptions() {
    _eventsById = {
      for (final e in _organizerEvents)
        if (e['event_id'] is String) e['event_id'] as String: e,
    };
    _organizerEvents.sort((a, b) {
      final titleA = (a['title'] as String? ?? '').toLowerCase();
      final titleB = (b['title'] as String? ?? '').toLowerCase();
      final byTitle = titleA.compareTo(titleB);
      if (byTitle != 0) return byTitle;
      return (a['event_date'] as String? ?? '').compareTo(
        b['event_date'] as String? ?? '',
      );
    });
    final eventIds = _organizerEvents
        .map((event) => event['event_id'] as String? ?? '')
        .toSet();
    if (_eventFilter != 'All' && !eventIds.contains(_eventFilter)) {
      _eventFilter = 'All';
    }
  }

  String _eventLabel(Map<String, dynamic> event) {
    final title = (event['title'] as String? ?? '').trim();
    final label = title.isEmpty ? 'Untitled event' : title;
    final sameTitleCount = _organizerEvents
        .where((candidate) => candidate['title'] == event['title'])
        .length;
    if (sameTitleCount < 2) return label;
    final date = event['event_date'] as String?;
    return date == null || date.isEmpty ? label : '$label · $date';
  }

  int _countForEvent(String eventId) {
    if (eventId == 'All') return _all.length;
    return _all.where((r) => r['event_id'] == eventId).length;
  }

  Future<void> _updateStatus(
    String id,
    String newStatus, {
    String? rejectionReason,
  }) async {
    if (_statusUpdatingIds.contains(id)) return;
    final idx = _all.indexWhere((r) => r['id'] == id);
    if (idx < 0) return;
    final oldStatus = _all[idx]['status'] as String? ?? '';
    if (newStatus == 'photo_required' && oldStatus != 'qr_scanned') return;

    // Optimistic update — reflect the change immediately.
    _statusUpdatingIds.add(id);
    setState(() {
      _all[idx] = {..._all[idx], 'status': newStatus};
      _applyFilter();
    });

    try {
      await RegistrationService.updateStatus(
        id,
        newStatus,
        rejectionReason: rejectionReason,
      );
    } catch (e) {
      // Roll back to the previous status on failure.
      if (mounted) {
        final rollbackIdx = _all.indexWhere((r) => r['id'] == id);
        setState(() {
          if (rollbackIdx >= 0) {
            _all[rollbackIdx] = {..._all[rollbackIdx], 'status': oldStatus};
          }
          _applyFilter();
        });
        // Rule messages (e.g. "Check-in opens 1 hour before…") show as written.
        showErrorAlert(
          context,
          e,
          title: 'Couldn’t update the status',
          fallback: 'The status couldn’t be updated. Please try again.',
        );
      }
    } finally {
      _statusUpdatingIds.remove(id);
      if (mounted) setState(() {});
    }
  }

  // Reject requires a reason and a second confirm step — this is the more
  // consequential of the two decisions available here (it denies a student
  // attendance), so it deliberately gets more friction than Check In.
  Future<void> _confirmReject(String id, String name) async {
    final reason = await _promptRejectReason(context, name);
    if (reason == null) return;
    await _updateStatus(id, 'rejected', rejectionReason: reason);
  }

  Future<void> _deleteRegistration(String id, String name) async {
    bool confirmed = false;
    await AppAlert.confirm(
      context,
      title: 'Delete Registration?',
      message: "Remove $name's registration?\nThis cannot be undone.",
      confirmText: 'Delete',
      cancelText: 'Cancel',
      onConfirm: () => confirmed = true,
    );
    if (!confirmed) return;
    try {
      await RegistrationService.deleteRegistration(id);
      setState(() {
        _all.removeWhere((r) => r['id'] == id);
        _selfies.remove(id);
        _applyFilter();
      });
    } catch (e) {
      if (mounted) {
        showErrorAlert(context, e, title: 'Couldn’t delete the registration');
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD — the look lives in organizer_registrations_ui.dart and, shared with
  // the Events tab, org_tab_ui.dart
  // ══════════════════════════════════════════════════════════════════════════

  static const _statusFilters = [
    'All',
    'Pending',
    'QR Scanned',
    'Awaiting Selfie',
    'Photo Submitted',
    'Checked In',
    'Rejected',
  ];

  @override
  Widget build(BuildContext context) {
    final t = AppTk(Theme.of(context).brightness == Brightness.dark);
    return Scaffold(
      backgroundColor: widget.showAsEmbedded ? Colors.transparent : t.bg,
      body: SafeArea(
        child: Column(
          children: [
            if (!widget.showAsEmbedded) _buildTopBar(t),
            Expanded(
              child: _loading
                  ? _buildLoadingState(t)
                  : RefreshIndicator(
                      color: kGold,
                      backgroundColor: t.card,
                      onRefresh: () => _load(silent: true),
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(child: _buildPageHeader(t)),
                          SliverToBoxAdapter(child: _buildSearchBar(t)),
                          // The status filters stay in reach while the list
                          // scrolls, as on the Events tab.
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: OrgFilterBarDelegate(
                              (scrolled) =>
                                  _buildFilterRow(t, scrolled: scrolled),
                            ),
                          ),
                          SliverToBoxAdapter(child: _buildResultCount(t)),
                          if (_selectedIds.isNotEmpty)
                            SliverToBoxAdapter(child: _buildBulkActionsBar(t)),
                          if (_filtered.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: _buildEmptyState(t),
                            )
                          else
                            SliverPadding(
                              // Bottom room so the AI assistant button never
                              // covers the last card's buttons.
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                8,
                                20,
                                104,
                              ),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (_, i) =>
                                      _buildRegistrationCard(_filtered[i], t),
                                  childCount: _filtered.length,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Loading ───────────────────────────────────────────────────────────────

  Widget _buildLoadingState(AppTk t) {
    return Column(
      children: [
        _buildPageHeader(t),
        _buildSearchBar(t),
        const SizedBox(height: 8),
        const Expanded(
          child: AppShimmerList(itemCount: 6, hasAvatar: true, hasImage: false),
        ),
      ],
    );
  }

  // ── Top bar (non-embedded) ────────────────────────────────────────────────

  Widget _buildTopBar(AppTk t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: t.shadow,
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 18,
                color: t.text,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Registrations',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: t.text,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Header, search, filters ───────────────────────────────────────────────

  Widget _buildPageHeader(AppTk t) =>
      OrgTabHeader(title: 'Registrations', t: t);

  Widget _buildSearchBar(AppTk t) => OrgSearchField(
    controller: _search,
    hint: 'Search by name, school ID, or event…',
    onChanged: (_) {
      _applyFilter();
      setState(() {});
    },
    onClear: () {
      _search.clear();
      _applyFilter();
      setState(() {});
    },
    t: t,
  );

  Widget _buildFilterRow(AppTk t, {bool scrolled = false}) => AnimatedContainer(
    duration: const Duration(milliseconds: 180),
    height: kOrgFilterBarHeight,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
    decoration: BoxDecoration(
      color: t.bg,
      border: Border(
        bottom: BorderSide(
          color: scrolled ? t.border : t.border.withValues(alpha: 0),
        ),
      ),
    ),
    child: Row(
      children: [
        Expanded(
          child: CompactFilterMenu<String>(
            label: 'Status',
            icon: Icons.filter_list_rounded,
            selected: _filter,
            accent: kGold,
            t: t,
            options: [
              for (final status in _statusFilters)
                CompactFilterOption(
                  value: status,
                  label: status,
                  count: _countForStatus(status),
                  color: status == 'All'
                      ? null
                      : registrationStatusColor(
                          {
                            'Pending': 'pending',
                            'QR Scanned': 'qr_scanned',
                            'Awaiting Selfie': 'photo_required',
                            'Photo Submitted': 'photo_submitted',
                            'Checked In': 'checked_in',
                            'Rejected': 'rejected',
                          }[status]!,
                        ),
                ),
            ],
            onSelect: (status) => setState(() {
              _filter = status;
              _applyFilter();
            }),
          ),
        ),
        if (_organizerEvents.length > 1) ...[
          const SizedBox(width: 8),
          Expanded(
            child: CompactFilterMenu<String>(
              label: 'Event',
              icon: Icons.event_rounded,
              selected: _eventFilter,
              accent: kRegSelectColor,
              searchable: _organizerEvents.length > 8,
              t: t,
              options: [
                CompactFilterOption(
                  value: 'All',
                  label: 'All events',
                  count: _all.length,
                ),
                for (final event in _organizerEvents)
                  CompactFilterOption(
                    value: event['event_id'] as String,
                    label: _eventLabel(event),
                    count: _countForEvent(event['event_id'] as String),
                    color: kRegSelectColor,
                  ),
              ],
              onSelect: (eventId) => setState(() {
                _eventFilter = eventId;
                _applyFilter();
              }),
            ),
          ),
        ],
      ],
    ),
  );

  // Status counts are scoped to the selected event, matching the web filters.
  int _countForStatus(String filter) {
    final inEvent = _all.where(
      (r) => _eventFilter == 'All' || r['event_id'] == _eventFilter,
    );
    if (filter == 'All') return inEvent.length;
    return inEvent.where((r) {
      final status = r['status'] as String? ?? '';
      return switch (filter) {
        'Pending' => status == 'pending',
        'QR Scanned' => status == 'qr_scanned',
        'Awaiting Selfie' => status == 'photo_required',
        'Photo Submitted' => status == 'photo_submitted',
        'Checked In' => status == 'checked_in',
        'Rejected' => status == 'rejected',
        _ => false,
      };
    }).length;
  }

  Widget _buildResultCount(AppTk t) => OrgRegistrationsToolbar(
    count: _filtered.length,
    canSelect: _filteredReviewableIds.isNotEmpty,
    allSelected: _allReviewableSelected,
    busy: _bulkProcessing,
    onToggleSelectAll: _toggleSelectAllReviewable,
    t: t,
  );

  Widget _buildBulkActionsBar(AppTk t) => OrgBulkActionBar(
    selectedCount: _selectedIds.length,
    busy: _bulkProcessing,
    onClear: () => setState(() => _selectedIds.clear()),
    onApprove: _bulkApproveSelected,
    onReject: _bulkRejectSelected,
    t: t,
  );

  // ── Registration card ─────────────────────────────────────────────────────

  Widget _buildRegistrationCard(Map<String, dynamic> r, AppTk t) {
    final id = r['id'] as String;
    final name = r['student_name'] as String? ?? '—';
    return OrgRegistrationCard(
      key: ValueKey(id),
      registration: r,
      selfieUrl: _selfies[id],
      selected: _selectedIds.contains(id),
      busy: _bulkProcessing,
      sending: _statusUpdatingIds.contains(id),
      archived: _isArchived(r),
      attendanceFinal: _isFinal(r),
      onToggleSelect: () => _toggleRegistrationSelection(id),
      onRequestSelfie: () => _updateStatus(id, 'photo_required'),
      onCheckIn: () => _updateStatus(id, 'checked_in'),
      onReject: () => _confirmReject(id, name),
      onDetails: () => _showDetails(r),
      onDelete: () => _deleteRegistration(id, name),
      t: t,
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────

  Widget _buildEmptyState(AppTk t) {
    final isFiltered = _filter != 'All' || _search.text.isNotEmpty;
    return OrgMessage(
      icon: isFiltered ? Icons.search_off_rounded : Icons.inbox_rounded,
      title: isFiltered ? 'No registrations found' : 'No registrations yet',
      message: isFiltered
          ? 'Try adjusting your search or filter'
          : 'Students who register for events will appear here',
      action: isFiltered
          ? OrgSecondaryButton(
              label: 'Clear filters',
              icon: Icons.filter_alt_off_outlined,
              onPressed: () {
                _search.clear();
                setState(() => _filter = 'All');
                _applyFilter();
              },
              t: t,
            )
          : null,
      t: t,
    );
  }

  // ── Details sheet ─────────────────────────────────────────────────────────

  void _showDetails(Map<String, dynamic> r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OrgRegistrationDetailsSheet(
        registration: r,
        selfieUrl: _selfies[r['id'] as String? ?? ''],
      ),
    );
  }
}

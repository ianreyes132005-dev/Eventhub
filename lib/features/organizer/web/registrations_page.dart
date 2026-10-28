import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/app_colors.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/registration_service.dart';
import '../../../core/services/selfie_links.dart';
import 'web_shared.dart';
import 'student_registration_panel.dart';

class WebRegistrationsPage extends StatefulWidget {
  final String? orgId;

  /// The status filter to open on, e.g. 'Photo Submitted' when the organizer
  /// comes from the sidebar's "waiting for your review" badge.
  final String? initialStatus;

  const WebRegistrationsPage({super.key, this.orgId, this.initialStatus});

  @override
  State<WebRegistrationsPage> createState() => _WebRegistrationsPageState();
}

class _WebRegistrationsPageState extends State<WebRegistrationsPage>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  String _statusFilter = 'All';
  String _eventFilter = 'All';
  final _search = TextEditingController();

  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _displayed = [];
  List<Map<String, dynamic>> _events = [];
  // Selfie links — a new one for every new submission, and renewed when
  // the organizer opens a photo after the link got old (see SelfieLinks).
  final _selfies = SelfieLinks();
  Map<String, Map<String, dynamic>> _profiles = {}; // student_user_id → profile
  final Set<String> _processingIds = {};
  final Set<String> _selectedIds = {};

  // Realtime subscription — scoped to this organizer's events. Set up once;
  // the set is refilled by every load, and events created while the page is
  // open join it through the subscription.
  RealtimeChannel? _channel;
  final Set<String> _orgEventIds = {};
  // Events the admin archived: their registrations are read-only records.
  final Set<String> _archivedEventIds = {};
  // The organizer's events by id, with their schedule (see _isFinal).
  final Map<String, Map<String, dynamic>> _eventsById = {};
  bool _fetching = false; // a load is running…
  bool _refetch = false; // …and a change arrived meanwhile
  // Check-in closing makes rows final while the page is open.
  Timer? _clock;

  final _statusFilters = [
    'All',
    'Pending',
    'QR Scanned',
    'Awaiting Selfie',
    'Photo Submitted',
    'Checked In',
    'Rejected',
  ];

  late final AnimationController _staggerCtrl;

  @override
  void initState() {
    super.initState();
    final start = widget.initialStatus;
    if (start != null && _statusFilters.contains(start)) _statusFilter = start;
    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _search.addListener(_applyFilter);
    _load();
    _subscribeRealtime();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) _applyFilter();
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    if (_channel != null) SupabaseService.client.removeChannel(_channel!);
    _staggerCtrl.dispose();
    _search.dispose();
    super.dispose();
  }

  Widget _stagger(Widget child, {required double start, required double end}) {
    return AnimatedBuilder(
      animation: _staggerCtrl,
      builder: (_, c) {
        final raw = ((_staggerCtrl.value - start) / (end - start)).clamp(
          0.0,
          1.0,
        );
        final t = Curves.easeOut.transform(raw);
        final ts = Curves.easeOutCubic.transform(raw);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 18.0 * (1 - ts)),
            child: c,
          ),
        );
      },
      child: child,
    );
  }

  // ── Data loading ─────────────────────────────────────────────────────────────

  /// [silent]: refresh in place (a change that arrived mid-load) — no
  /// loading skeleton.
  Future<void> _load({bool silent = false}) async {
    if (widget.orgId == null) return;
    if (_fetching) {
      _refetch = true;
      return;
    }
    _fetching = true;
    if (!silent) setState(() => _loading = true);
    try {
      final eventsRaw = await SupabaseService.client
          .from('events')
          .select('event_id, title, event_date, end_date, start_time, end_time, '
              'event_status, archived_at')
          .eq('organizer_id', widget.orgId!);
      final events = List<Map<String, dynamic>>.from(eventsRaw as List);
      final eventIds = events.map((e) => e['event_id'] as String).toList();
      _archivedEventIds
        ..clear()
        ..addAll([
          for (final e in events)
            if (eventIsArchived(e)) e['event_id'] as String,
        ]);
      _eventsById
        ..clear()
        ..addAll({for (final e in events) e['event_id'] as String: e});
      // Live changes are kept to these events (see _subscribeRealtime).
      _orgEventIds
        ..clear()
        ..addAll(eventIds);

      if (eventIds.isEmpty) {
        if (mounted) {
          setState(() {
            _all = [];
            _displayed = [];
            _events = [];
            _eventFilter = 'All';
            _loading = false;
          });
          _staggerCtrl.forward(from: 0);
        }
        return;
      }

      final regsRaw = await SupabaseService.client
          .from('registrations')
          .select()
          .in_('event_id', eventIds)
          .order('registered_at', ascending: false);
      final regs = List<Map<String, dynamic>>.from(regsRaw as List);

      final profiles = await loadRegistrantProfiles(
        regs.map((r) => r['student_user_id'] as String?),
      );

      if (!mounted) return;
      _all = regs;
      _events = events
        ..sort((a, b) {
          final titleOrder = (a['title'] as String? ?? '').compareTo(
            b['title'] as String? ?? '',
          );
          if (titleOrder != 0) return titleOrder;
          return (a['event_date'] as String? ?? '').compareTo(
            b['event_date'] as String? ?? '',
          );
        });
      if (_eventFilter != 'All' &&
          !_events.any((event) => event['event_id'] == _eventFilter)) {
        _eventFilter = 'All';
      }
      _profiles = profiles;
      _applyFilter();
      _fetchSelfieUrls(regs);
      setState(() => _loading = false);
      if (!silent) _staggerCtrl.forward(from: 0);
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        if (!silent) _staggerCtrl.forward(from: 0);
      }
    } finally {
      _fetching = false;
      if (_refetch && mounted) {
        _refetch = false;
        _load(silent: true);
      }
    }
  }

  /// Links for the rows with a selfie that don't have one yet (or a link
  /// that's getting old); [fresh] makes new ones regardless — a just-
  /// submitted selfie keeps the old one's file path.
  Future<void> _fetchSelfieUrls(
    List<Map<String, dynamic>> rows, {
    bool fresh = false,
  }) async {
    final paths = {
      for (final r in rows)
        if ((r['selfie_url'] as String?)?.isNotEmpty == true && r['id'] != null)
          r['id'] as String: r['selfie_url'] as String,
    };
    if (await _selfies.fetch(paths, fresh: fresh) && mounted) setState(() {});
  }

  void _subscribeRealtime() {
    final orgId = widget.orgId;
    if (orgId == null) return;

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
        // A delete only carries the row id: ignore other organizers' rows.
        if (eventType == 'DELETE' && !_all.any((r) => r['id'] == id)) return;

        setState(() {
          if (eventType == 'DELETE') {
            _all.removeWhere((r) => r['id'] == id);
            _selfies.remove(id);
            _selectedIds.remove(id);
          } else if (eventType == 'INSERT') {
            _all.insert(0, record);
          } else {
            final idx = _all.indexWhere((r) => r['id'] == id);
            if (idx >= 0) {
              _all[idx] = record;
            } else {
              _all.insert(0, record);
            }
          }
          _applyFilter();
        });

        // A new selfie gets a new link (see _fetchSelfieUrls).
        if (eventType != 'DELETE' &&
            record['status'] == 'photo_submitted' &&
            record['selfie_url'] != null) {
          _fetchSelfieUrls([record], fresh: true);
        }
      },
      channelSuffix: orgId,
      allowedEventIds: _orgEventIds,
      organizerId: orgId,
      // The admin archiving or restoring an event makes its rows read-only
      // or editable again.
      onEventRow: (event) {
        final id = event['event_id'];
        if (id is! String || !mounted) return;
        // A new schedule moves when the rows become final.
        _eventsById[id] = {...?_eventsById[id], ...event};
        final archived = eventIsArchived(event);
        if (archived == _archivedEventIds.contains(id)) return;
        setState(() {
          archived ? _archivedEventIds.add(id) : _archivedEventIds.remove(id);
          if (archived) {
            _selectedIds.removeWhere(
              (rid) => _all.any((r) => r['id'] == rid && r['event_id'] == id),
            );
          }
          _applyFilter();
        });
      },
    );
  }

  // Its event is archived: a read-only record (no selection, no actions).
  bool _isArchived(Map<String, dynamic> r) =>
      _archivedEventIds.contains(r['event_id']);

  // Its event's check-in has closed: the attendance is final (no selection,
  // no actions); only the admin can correct it.
  bool _isFinal(Map<String, dynamic> r) {
    final event = _eventsById[r['event_id']];
    return event != null && attendanceFinal(event);
  }

  // Bulk Approve / Reject decide submitted selfies, as on the app: a
  // check-in without one is done by hand, one student at a time, with a
  // reason.
  bool _selectable(Map<String, dynamic> r) =>
      r['status'] == 'photo_submitted' && !_isArchived(r) && !_isFinal(r);

  Iterable<String> get _selectableVisibleIds => _displayed
      .where(_selectable)
      .map((r) => r['id'] as String? ?? '')
      .where((id) => id.isNotEmpty);

  // Renews the link first when it's getting old, so the photo always opens.
  Future<void> _openSelfie(String id, String path, String name, WebTk t) async {
    final url = await _selfies.linkFor(id, path) ?? _selfies[id];
    if (!mounted || url == null) return;
    _viewSelfie(url, name, t);
  }

  void _applyFilter() {
    final q = _search.text.toLowerCase();
    final statusKey = _statusKeyMap[_statusFilter];
    setState(() {
      _displayed = _all.where((r) {
        final matchStatus = statusKey == null || r['status'] == statusKey;
        final matchEvent =
            _eventFilter == 'All' ||
            (r['event_id'] as String? ?? '') == _eventFilter;
        final name = (r['student_name'] as String? ?? '').toLowerCase();
        final event = (r['event_title'] as String? ?? '').toLowerCase();
        final sid = (r['student_school_id'] as String? ?? '').toLowerCase();
        final matchSearch =
            q.isEmpty ||
            name.contains(q) ||
            event.contains(q) ||
            sid.contains(q);
        return matchStatus && matchEvent && matchSearch;
      }).toList();
      // A selfie decided elsewhere, or check-in closing, ends a selection.
      _selectedIds.removeWhere(
        (id) => !_all.any((r) => r['id'] == id && _selectable(r)),
      );
    });
  }

  bool get _allVisibleSelected =>
      _selectableVisibleIds.isNotEmpty &&
      _selectableVisibleIds.every(_selectedIds.contains);

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleSelectAllVisible() {
    final visibleIds = _selectableVisibleIds.toSet();

    setState(() {
      if (visibleIds.every(_selectedIds.contains)) {
        for (final id in visibleIds) {
          _selectedIds.remove(id);
        }
      } else {
        _selectedIds.addAll(visibleIds);
      }
    });
  }

  Future<void> _bulkApproveSelected() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;

    final processing = <String>{...ids};
    setState(() => _processingIds.addAll(processing));

    try {
      for (final id in ids) {
        await RegistrationService.updateStatus(id, 'checked_in');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${ids.length} ${ids.length == 1 ? 'student was' : 'students were'} approved.',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }

      if (mounted) {
        setState(() {
          _selectedIds.clear();
          _processingIds.removeAll(processing);
        });
      }

      await _load();
    } catch (e) {
      if (mounted) {
        showErrorAlert(
          context,
          e,
          title: 'Couldn’t check in every selected student',
        );
        _load(); // some may have gone through before the failure
      }
    } finally {
      if (mounted) {
        setState(() => _processingIds.removeAll(processing));
      }
    }
  }

  Future<void> _bulkRejectSelected() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;

    final reason = await _promptBulkRejectReason(context, ids.length);
    if (reason == null || reason.trim().isEmpty) return;

    final processing = <String>{...ids};
    setState(() => _processingIds.addAll(processing));

    try {
      for (final id in ids) {
        await RegistrationService.updateStatus(
          id,
          'rejected',
          rejectionReason: reason,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${ids.length} ${ids.length == 1 ? 'student was' : 'students were'} rejected.',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
            ),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }

      if (mounted) {
        setState(() {
          _selectedIds.clear();
          _processingIds.removeAll(processing);
        });
      }

      await _load();
    } catch (e) {
      if (mounted) {
        showErrorAlert(
          context,
          e,
          title: 'Couldn’t reject every selected student',
        );
        _load(); // some may have gone through before the failure
      }
    } finally {
      if (mounted) {
        setState(() => _processingIds.removeAll(processing));
      }
    }
  }

  static const _statusKeyMap = {
    'All': null,
    'Pending': 'pending',
    'QR Scanned': 'qr_scanned',
    'Awaiting Selfie': 'photo_required',
    'Photo Submitted': 'photo_submitted',
    'Checked In': 'checked_in',
    'Rejected': 'rejected',
  };

  Future<void> _updateStatus(
    String id,
    String newStatus, {
    String? rejectionReason,
    String? attendanceNote,
  }) async {
    setState(() => _processingIds.add(id));
    try {
      await RegistrationService.updateStatus(
        id,
        newStatus,
        rejectionReason: rejectionReason,
        attendanceNote: attendanceNote,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _processingIds.remove(id));
        // Rule messages (e.g. "Check-in opens 1 hour before…") show as written.
        showErrorAlert(context, e, title: 'Couldn’t update the status');
      }
      return;
    }
    setState(() => _processingIds.remove(id));
    await _load();
  }

  Future<void> _delete(String id) async {
    final ok = await WebAlert.confirm(
      context: context,
      title: 'Delete Registration?',
      message:
          'This registration will be permanently removed. This action cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (ok != true) return;
    setState(() => _processingIds.add(id));
    try {
      await RegistrationService.deleteRegistration(id);
    } catch (e) {
      if (mounted) {
        setState(() => _processingIds.remove(id));
        showErrorAlert(context, e, title: 'Couldn’t delete the registration');
      }
      return;
    }
    setState(() => _processingIds.remove(id));
    await _load();
  }

  // ── Selfie dialog ─────────────────────────────────────────────────────────────

  Future<void> _openDetails(Map<String, dynamic> reg) async {
    final changed = await showStudentRegistrationPanel(
      context,
      registration: reg,
      organizerId: widget.orgId,
      profile: _profiles[reg['student_user_id'] as String? ?? ''],
      archived: _isArchived(reg),
      attendanceFinal: _isFinal(reg),
    );
    if (changed == true && mounted) _load();
  }

  // Checking in a student who hasn't sent an approved selfie: allowed while
  // check-in is open, with a reason that's kept with the attendance.
  Future<void> _checkInByHand(String id, String studentName, String status) async {
    final r = await Swal.fire(
      context,
      icon: SwalIcon.question,
      title: 'Check in $studentName by hand?',
      text: status == 'pending'
          ? 'Their ticket wasn’t scanned and they sent no selfie. Say why '
              'you’re checking them in; it’s saved with their attendance.'
          : 'They haven’t sent a selfie for review. Say why you’re checking '
              'them in; it’s saved with their attendance.',
      input: true,
      inputLabel: 'Reason',
      inputPlaceholder: 'e.g. Phone battery died, ID checked at the door',
      inputValidator: (v) =>
          v.trim().isEmpty ? 'Give a reason for checking them in by hand.' : null,
      showCancelButton: true,
      confirmButtonText: 'Check In',
      confirmButtonColor: kSwalGold,
    );
    if (!r.isConfirmed || !mounted) return;
    await _updateStatus(id, 'checked_in', attendanceNote: r.value);
  }

  Future<void> _sendSelfieRequest(String id, String studentName) async {
    final ok = await WebAlert.confirm(
      context: context,
      title: 'Send Selfie Request?',
      message:
          '$studentName will be prompted to submit a selfie photo to complete their check-in.',
      confirmLabel: 'Send Request',
    );
    if (ok != true) return;
    await _updateStatus(id, 'photo_required');
  }

  void _viewSelfie(String url, String studentName, WebTk t) {
    final initials = studentName
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase())
        .take(2)
        .join();

    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: t.card,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 400,
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
                decoration: BoxDecoration(
                  color: t.inputBg,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  border: Border(bottom: BorderSide(color: t.border)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.photo_camera_rounded,
                        size: 18,
                        color: Color(0xFF8B5CF6),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Check-in Selfie',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: t.text,
                            ),
                          ),
                          Text(
                            studentName,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              color: t.sub,
                            ),
                          ),
                        ],
                      ),
                    ),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: t.divider,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: t.sub,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Selfie image — Flexible so it fills available space without overflowing
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      loadingBuilder: (_, child, progress) => progress == null
                          ? child
                          : Container(
                              height: 240,
                              decoration: BoxDecoration(
                                color: t.inputBg,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const CircularProgressIndicator(
                                      color: kGold,
                                      strokeWidth: 2,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Loading selfie…',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 12,
                                        color: t.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                      errorBuilder: (_, _, _) => Container(
                        height: 160,
                        decoration: BoxDecoration(
                          color: t.inputBg,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: t.divider,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  size: 22,
                                  color: t.muted,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Could not load image',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
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
              ),
              // Avatar + name footer
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: t.inputBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF8B5CF6,
                          ).withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(
                              0xFF8B5CF6,
                            ).withValues(alpha: 0.25),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            initials,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF8B5CF6),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        studentName,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: t.text,
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

  // ── Build ─────────────────────────────────────────────────────────────────────

  Widget _buildBulkActionsBar(WebTk t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: t.inputBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.22),
              ),
            ),
            child: Text(
              '${_selectedIds.length} selected',
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF8B5CF6),
              ),
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _bulkApproveSelected,
            icon: const Icon(Icons.check_circle_rounded, size: 16),
            label: const Text(
              'Approve',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF10B981),
              side: const BorderSide(color: Color(0xFF10B981), width: 1.2),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: _bulkRejectSelected,
            icon: const Icon(Icons.block_rounded, size: 16),
            label: const Text(
              'Reject',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFEF4444),
              side: const BorderSide(color: Color(0xFFEF4444), width: 1.2),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(width: 10),
          TextButton.icon(
            onPressed: () => setState(() => _selectedIds.clear()),
            icon: const Icon(Icons.close_rounded, size: 16),
            label: const Text(
              'Clear',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kGold));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(kWebPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPageHeader(t),
          const SizedBox(height: 20),
          _stagger(_buildFilterBar(t), start: 0.36, end: 0.66),
          const SizedBox(height: 16),
          if (_selectedIds.isNotEmpty) ...[
            _buildBulkActionsBar(t),
            const SizedBox(height: 12),
          ],
          WebCard(
            padding: EdgeInsets.zero,
            child: _displayed.isEmpty
                ? _stagger(
                    WebEmptyState(
                      icon: Icons.how_to_reg_rounded,
                      title: _all.isEmpty
                          ? 'No registrations yet'
                          : 'No results match your filter',
                      subtitle: _all.isEmpty
                          ? 'Registrations will appear once students sign up for your events.'
                          : 'Try adjusting your search or filters.',
                    ),
                    start: 0.50,
                    end: 0.85,
                  )
                : _buildTable(t),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Page header ───────────────────────────────────────────────────────────────

  Widget _buildPageHeader(WebTk t) {
    return _stagger(
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
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
          const Spacer(),
        ],
      ),
      start: 0.00,
      end: 0.35,
    );
  }

  // ── Filter bar ────────────────────────────────────────────────────────────────

  Widget _buildFilterBar(WebTk t) {
    // Counts per status and per event, shown in the filter menus so the
    // organizer sees how many are in each state without clicking through.
    final counts = <String, int>{
      'All': _all.length,
      for (final f in _statusFilters.skip(1))
        f: _all.where((r) => r['status'] == _statusKeyMap[f]).length,
    };
    final events = _events;
    final titleCounts = <String, int>{};
    for (final event in events) {
      final title = event['title'] as String? ?? 'Untitled event';
      titleCounts[title] = (titleCounts[title] ?? 0) + 1;
    }
    String eventLabel(Map<String, dynamic> event) {
      final title = event['title'] as String? ?? 'Untitled event';
      if (titleCounts[title] == 1) return title;
      final date = event['event_date'] as String?;
      return date == null || date.isEmpty ? title : '$title · $date';
    }

    // Two compact menus instead of a row of status chips plus a row of event
    // chips: the status chips ran off narrower screens (and laptops at 125%
    // zoom), and the event chips grew with every event.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        WebFilterMenu<String>(
          icon: Icons.filter_list_rounded,
          label: 'Status',
          options: [
            for (final f in _statusFilters)
              WebFilterOption(
                value: f,
                label: f,
                count: counts[f] ?? 0,
                color: f == 'All' ? kGold : webStatusColor(_statusKeyMap[f]),
              ),
          ],
          selected: _statusFilter,
          onSelect: (f) {
            setState(() => _statusFilter = f);
            _applyFilter();
          },
        ),
        // Only worth a menu when there's more than one event to choose from.
        if (events.length > 1) ...[
          const SizedBox(width: 8),
          WebFilterMenu<String>(
            icon: Icons.event_rounded,
            label: 'Event',
            accent: const Color(0xFF8B5CF6),
            menuWidth: 320,
            searchable: events.length > 8,
            searchHint: 'Search events…',
            options: [
              WebFilterOption(
                value: 'All',
                label: 'All events',
                count: _all.length,
              ),
              for (final event in events)
                WebFilterOption(
                  value: event['event_id'] as String,
                  label: eventLabel(event),
                  count: _all
                      .where((r) => r['event_id'] == event['event_id'])
                      .length,
                ),
            ],
            selected: _eventFilter,
            onSelect: (eventId) {
              setState(() => _eventFilter = eventId);
              _applyFilter();
            },
          ),
        ],
        const Spacer(),
        WebSearchField(
          controller: _search,
          hint: 'Search name, event, ID…',
          onChanged: (_) {},
        ),
      ],
    );
  }

  // ── Table ─────────────────────────────────────────────────────────────────────

  Widget _buildTable(WebTk t) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header row
        _stagger(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            decoration: BoxDecoration(
              color: t.inputBg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: t.border)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Tooltip(
                    message: _selectableVisibleIds.isEmpty
                        ? 'Selecting is for submitted selfies waiting for review'
                        : 'Select every submitted selfie shown',
                    child: Checkbox(
                      value: _allVisibleSelected,
                      onChanged: _selectableVisibleIds.isEmpty
                          ? null
                          : (_) => _toggleSelectAllVisible(),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      activeColor: const Color(0xFF8B5CF6),
                    ),
                  ),
                ),
                Expanded(flex: 4, child: WebColHeader('STUDENT')),
                Expanded(flex: 3, child: WebColHeader('EVENT')),
                Expanded(flex: 2, child: WebColHeader('STATUS')),
                Expanded(flex: 2, child: WebColHeader('REGISTERED')),
                const SizedBox(width: 146, child: WebColHeader('ACTIONS')),
              ],
            ),
          ),
          start: 0.48,
          end: 0.68,
        ),
        // Data rows
        ...(_displayed.asMap().entries.map((entry) {
          final i = entry.key;
          final reg = entry.value;
          final id = reg['id'] as String? ?? '';
          final status = reg['status'] as String?;
          final sc = webStatusColor(status);
          final isLast = i == _displayed.length - 1;

          final name = reg['student_name'] as String? ?? '—';
          final lrn = reg['student_school_id'] as String? ?? '—';
          final selfieUrl = _selfies[id];

          final initials = name
              .split(' ')
              .where((w) => w.isNotEmpty)
              .map((w) => w[0].toUpperCase())
              .take(2)
              .join();

          final regAt = reg['registered_at'] as String?;
          final isProcessing = _processingIds.contains(id);
          final isSelected = _selectedIds.contains(id);
          final archived = _isArchived(reg);
          final isFinal = !archived && _isFinal(reg);
          final s = 0.55 + (i * 0.07).clamp(0.0, 0.27);

          return _stagger(
            _RegHoverRow(
              isLast: isLast,
              onTap: () => _openDetails(reg),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 13,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 36,
                      child: !_selectable(reg)
                          ? null
                          : Checkbox(
                              value: isSelected,
                              onChanged: (_) => _toggleSelection(id),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              activeColor: const Color(0xFF8B5CF6),
                            ),
                    ),

                    // ── Student (avatar + name + LRN) ──
                    Expanded(
                      flex: 4,
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: sc.withValues(alpha: 0.10),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: sc.withValues(alpha: 0.28),
                              ),
                            ),
                            child: Center(
                              child: Text(
                                initials,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: sc,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  name,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: t.text,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: t.inputBg,
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: Text(
                                        lrn,
                                        style: TextStyle(
                                          fontFamily: 'Courier',
                                          fontSize: 10.5,
                                          color: t.sub,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Event ──
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 30,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              color: kGold.withValues(alpha: 0.50),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              reg['event_title'] as String? ?? '—',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: t.text,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Status ──
                    Expanded(
                      flex: 2,
                      child: WebStatusBadge(
                        label: webStatusLabel(status),
                        color: sc,
                      ),
                    ),

                    // ── Registered ──
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            webTimeAgo(regAt),
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: t.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            webFmtDate(regAt),
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 10.5,
                              color: t.muted,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Actions - 4 fixed slots
                    // Slot 0: selfie request  |  Slot 1: selfie view
                    // Slot 2: status          |  Slot 3: delete
                    SizedBox(
                      width: 146,
                      child: archived
                          ? const Align(
                              alignment: Alignment.centerRight,
                              child: Tooltip(
                                message:
                                    'The admin archived this event. Its attendance '
                                    'is kept as a record and can’t be changed.',
                                child: WebStatusBadge(
                                  label: 'Archived',
                                  color: kArchivedColor,
                                ),
                              ),
                            )
                          : isFinal
                          ? const Align(
                              alignment: Alignment.centerRight,
                              child: Tooltip(
                                message:
                                    'Check-in closed 2 hours after the event ended, '
                                    'so this attendance is final. Only the '
                                    'administrator can correct it.',
                                child: WebStatusBadge(
                                  label: 'Final',
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            )
                          : isProcessing
                          ? const Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: kGold,
                                ),
                              ),
                            )
                          : Row(
                              children: [
                                // Slot 0 - Send selfie request
                                if (status == 'qr_scanned')
                                  _RegAction(
                                    icon: Icons.add_a_photo_rounded,
                                    color: const Color(0xFFF97316),
                                    tooltip: 'Send selfie request',
                                    onTap: () => _sendSelfieRequest(id, name),
                                  )
                                else if (status == 'pending')
                                  _RegAction(
                                    icon: Icons.add_a_photo_rounded,
                                    color: const Color(0xFF9CA3AF),
                                    tooltip:
                                        "Scan the student's QR code with the EventHub app before requesting a selfie",
                                    onTap: null,
                                  )
                                else
                                  const SizedBox(width: 32),
                                const SizedBox(width: 6),
                                // Slot 1 - Selfie viewer
                                if (selfieUrl != null)
                                  _RegAction(
                                    icon: Icons.photo_camera_rounded,
                                    color: const Color(0xFF8B5CF6),
                                    tooltip: 'View selfie',
                                    onTap: () => _openSelfie(
                                      id,
                                      reg['selfie_url'] as String? ?? '',
                                      name,
                                      t,
                                    ),
                                  )
                                else
                                  Tooltip(
                                    message: status == 'photo_required'
                                        ? 'Awaiting selfie from student'
                                        : 'No selfie submitted yet',
                                    child: Opacity(
                                      opacity: 0.25,
                                      child: Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFF8B5CF6,
                                          ).withValues(alpha: 0.06),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.photo_camera_outlined,
                                          size: 15,
                                          color: Color(0xFF8B5CF6),
                                        ),
                                      ),
                                    ),
                                  ),
                                const SizedBox(width: 6),
                                // Slot 2 - Status advance / lock
                                _StatusMenu(
                                  currentStatus: status,
                                  canStart: switch (_eventsById[reg['event_id']]) {
                                    final event? => scanBlockedReason(event) == null,
                                    null => true,
                                  },
                                  onSelect: (s) async {
                                    if (s == 'checked_in' &&
                                        status != 'photo_submitted') {
                                      await _checkInByHand(
                                        id,
                                        name,
                                        status ?? 'pending',
                                      );
                                    } else if (s == 'rejected') {
                                      final reason = await _promptRejectReason(
                                        context,
                                        name,
                                      );
                                      if (reason == null) return;
                                      await _updateStatus(
                                        id,
                                        s,
                                        rejectionReason: reason,
                                      );
                                    } else {
                                      await _updateStatus(id, s);
                                    }
                                  },
                                ),
                                const SizedBox(width: 6),
                                // Slot 3 - Delete (not once checked in:
                                // that's the attendance record)
                                if (registrationDeletable(reg))
                                  _RegAction(
                                    icon: Icons.delete_outline_rounded,
                                    color: const Color(0xFFEF4444),
                                    tooltip: 'Delete registration',
                                    onTap: () => _delete(id),
                                  )
                                else
                                  const _RegAction(
                                    icon: Icons.delete_outline_rounded,
                                    color: Color(0xFF9CA3AF),
                                    tooltip:
                                        'Checked-in registrations are kept as the attendance record',
                                    onTap: null,
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
            start: s,
            end: (s + 0.20).clamp(0.0, 1.0),
          );
        })),
      ],
    );
  }
}

// ── Reject reason prompt ─────────────────────────────────────────────────────
// Reject requires a reason and this explicit dialog — more friction than the
// other forward status transitions, deliberately, since it's the one
// decision here that denies a student attendance.

Future<String?> _promptRejectReason(BuildContext context, String studentName) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (dialogCtx, setState) {
        final t = WebTk(Theme.of(dialogCtx).brightness == Brightness.dark);
        return Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
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
              padding: const EdgeInsets.all(24),
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
                          color: const Color(
                            0xFFEF4444,
                          ).withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.block_rounded,
                          size: 19,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Reject $studentName?',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: t.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This student will not be checked in. Give a reason so they know what to fix.',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: t.sub,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    maxLines: 3,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12.5,
                      color: t.text,
                    ),
                    decoration: webInputDeco(
                      'e.g. Selfie doesn\'t match student ID photo',
                      dark: t.dark,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: t.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
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
                          onPressed: ctrl.text.trim().isEmpty
                              ? null
                              : () => Navigator.of(
                                  dialogCtx,
                                ).pop(ctrl.text.trim()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(
                              0xFFEF4444,
                            ).withValues(alpha: 0.35),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
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
          ),
        );
      },
    ),
  ).whenComplete(ctrl.dispose);
}

Future<String?> _promptBulkRejectReason(BuildContext context, int count) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (dialogCtx, setState) {
        final t = WebTk(Theme.of(dialogCtx).brightness == Brightness.dark);
        return Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
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
              padding: const EdgeInsets.all(24),
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
                          color: const Color(
                            0xFFEF4444,
                          ).withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.block_rounded,
                          size: 19,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Reject $count selected?',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: t.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This will reject the selected registrations and record the same reason for every student.',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: t.sub,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    maxLines: 3,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12.5,
                      color: t.text,
                    ),
                    decoration: webInputDeco(
                      'e.g. Attendance criteria not met',
                      dark: t.dark,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: t.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
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
                          onPressed: ctrl.text.trim().isEmpty
                              ? null
                              : () => Navigator.of(
                                  dialogCtx,
                                ).pop(ctrl.text.trim()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(
                              0xFFEF4444,
                            ).withValues(alpha: 0.35),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          child: const Text(
                            'Reject Selected',
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
          ),
        );
      },
    ),
  ).whenComplete(ctrl.dispose);
}

// ── Status advance menu ───────────────────────────────────────────────────────

class _StatusMenu extends StatefulWidget {
  final String? currentStatus;
  /// A Registered (unscanned) student can be checked in by hand only while
  /// tickets can be scanned (scanBlockedReason).
  final bool canStart;
  final ValueChanged<String> onSelect;
  const _StatusMenu({this.currentStatus, this.canStart = true, required this.onSelect});

  @override
  State<_StatusMenu> createState() => _StatusMenuState();
}

class _StatusMenuState extends State<_StatusMenu> {
  bool _hovered = false;

  static const _statuses = [
    ('pending', 'Pending'),
    ('qr_scanned', 'QR Scanned'),
    ('photo_required', 'Awaiting Selfie'),
    ('photo_submitted', 'Photo Submitted'),
    ('checked_in', 'Check In'),
    ('rejected', 'Reject'),
  ];

  // Forward-only state machine, the same one the database enforces
  // (enforce_registration_update_rules, migration 202610280001).
  // checked_in and rejected are both terminal — rejected is only reachable
  // from photo_submitted (the same point admin's now-removed dialog used to
  // decide from). Only the student's own upload makes a selfie
  // "submitted"; checking in from any other step is done by hand and needs
  // a reason.
  static const _allowed = <String, Set<String>>{
    'pending': {'checked_in'},
    'qr_scanned': {'photo_required', 'checked_in'},
    'photo_required': {'checked_in'},
    'photo_submitted': {'checked_in', 'rejected'},
    'checked_in': {},
    'rejected': {},
  };

  static IconData _statusIcon(String key) => switch (key) {
    'pending' => Icons.hourglass_empty_rounded,
    'qr_scanned' => Icons.qr_code_scanner_rounded,
    'photo_required' => Icons.photo_camera_rounded,
    'photo_submitted' => Icons.check_circle_outline_rounded,
    'checked_in' => Icons.how_to_reg_rounded,
    'rejected' => Icons.block_rounded,
    _ => Icons.circle_outlined,
  };

  // [current]: checking in from anything but a submitted selfie is done by
  // hand.
  static String _statusDesc(String key, String? current) => switch (key) {
    'qr_scanned' => 'Student\'s QR code has been scanned',
    'photo_required' => 'Request a selfie from the student',
    'photo_submitted' => 'Selfie received, awaiting review',
    'checked_in' when current != 'photo_submitted' =>
      'Check in by hand, without a selfie — requires a reason',
    'checked_in' => 'Confirm and finalise attendance',
    'rejected' => 'Deny attendance — requires a reason',
    _ => '',
  };

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final current = widget.currentStatus;
    final currentColor = webStatusColor(current);

    // Terminal states — locked, no menu.
    if (current == 'checked_in' || current == 'rejected') {
      final isRejected = current == 'rejected';
      final c = isRejected ? const Color(0xFFEF4444) : const Color(0xFF10B981);
      return Tooltip(
        message: isRejected
            ? 'Rejected — status cannot be changed'
            : 'Check-in is final — status cannot be changed',
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.withValues(alpha: 0.20)),
          ),
          child: Icon(Icons.lock_rounded, size: 13, color: c),
        ),
      );
    }

    final allowedSet = current == 'pending' && !widget.canStart
        ? const <String>{}
        : _allowed[current] ?? const <String>{};
    final items = _statuses.where((s) => allowedSet.contains(s.$1)).toList();
    if (items.isEmpty) return const SizedBox(width: 32);

    final currentLabel = _statuses
        .firstWhere((s) => s.$1 == current, orElse: () => ('', '—'))
        .$2;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: PopupMenuButton<String>(
        tooltip: '',
        constraints: const BoxConstraints(minWidth: 252),
        onSelected: (s) {
          setState(() => _hovered = false);
          widget.onSelect(s);
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        color: t.card,
        elevation: 8,
        shadowColor: t.shadow,
        itemBuilder: (_) => [
          // ── Header — shows context before the organizer picks ──────────
          PopupMenuItem<String>(
            enabled: false,
            padding: EdgeInsets.zero,
            height: 58,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.arrow_circle_right_rounded,
                        size: 13,
                        color: t.text,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Advance Status',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: t.text,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        'Current: ',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          color: t.muted,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: currentColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: currentColor.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: currentColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              currentLabel,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: currentColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const PopupMenuDivider(height: 1),

          // ── Selectable status items ────────────────────────────────────
          ...items.map((s) {
            final (key, label) = s;
            final c = webStatusColor(key);
            final icon = _statusIcon(key);
            final desc = _statusDesc(key, current);
            final isTerminal = key == 'checked_in' || key == 'rejected';

            return PopupMenuItem<String>(
              value: key,
              padding: EdgeInsets.zero,
              height: 60,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    // Status icon in a tinted circle
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                        border: Border.all(color: c.withValues(alpha: 0.22)),
                      ),
                      child: Icon(icon, size: 17, color: c),
                    ),
                    const SizedBox(width: 12),
                    // Label + short description
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Text(
                                label,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: isTerminal ? c : t.text,
                                ),
                              ),
                              if (isTerminal) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'FINAL',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 8,
                                      fontWeight: FontWeight.w800,
                                      color: c,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (desc.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              desc,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 10.5,
                                color: t.muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Forward arrow in the status color
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 10,
                      color: c.withValues(alpha: 0.55),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],

        // ── Trigger button ─────────────────────────────────────────────────
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _hovered
                ? currentColor.withValues(alpha: 0.16)
                : currentColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hovered
                  ? currentColor.withValues(alpha: 0.38)
                  : currentColor.withValues(alpha: 0.20),
            ),
          ),
          child: Icon(
            Icons.arrow_circle_right_rounded,
            size: 15,
            color: currentColor,
          ),
        ),
      ),
    );
  }
}

// ── Hover row ─────────────────────────────────────────────────────────────────

class _RegHoverRow extends StatefulWidget {
  final Widget child;
  final bool isLast;
  final VoidCallback? onTap; // opens the Student details panel
  const _RegHoverRow({required this.child, required this.isLast, this.onTap});

  @override
  State<_RegHoverRow> createState() => _RegHoverRowState();
}

class _RegHoverRowState extends State<_RegHoverRow> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    // Buttons inside the row (checkbox, status menu, actions) win the tap —
    // only a click on the row's empty space / text opens the details panel.
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _h ? t.divider : t.card,
            borderRadius: widget.isLast
                ? const BorderRadius.vertical(bottom: Radius.circular(16))
                : BorderRadius.zero,
            border: widget.isLast
                ? null
                : Border(bottom: BorderSide(color: t.border)),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

// ── Icon action button ────────────────────────────────────────────────────────

class _RegAction extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;
  const _RegAction({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_RegAction> createState() => _RegActionState();
}

class _RegActionState extends State<_RegAction> {
  bool _h = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.onTap == null
        ? SystemMouseCursors.basic
        : SystemMouseCursors.click,
    onEnter: (_) => setState(() => _h = widget.onTap != null),
    onExit: (_) => setState(() => _h = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: Tooltip(
        message: widget.tooltip,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _h
                ? widget.color.withValues(alpha: 0.15)
                : widget.color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _h
                  ? widget.color.withValues(alpha: 0.30)
                  : Colors.transparent,
            ),
          ),
          child: Icon(widget.icon, size: 15, color: widget.color),
        ),
      ),
    ),
  );
}

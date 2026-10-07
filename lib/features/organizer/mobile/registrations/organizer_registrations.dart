import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/registration_service.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../../../core/app_colors.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

String _statusLabel(String s) {
  const map = {
    'pending': 'Pending',
    'qr_scanned': 'QR Scanned',
    'photo_required': 'Awaiting Selfie',
    'photo_submitted': 'Photo Submitted',
    'checked_in': 'Checked In',
    'rejected': 'Rejected',
  };
  return map[s] ?? s;
}

Color _statusColor(String s) {
  switch (s) {
    case 'pending':
      return const Color(0xFFE87A00);
    case 'qr_scanned':
      return const Color(0xFF2979C8);
    case 'photo_required':
      return const Color(0xFF9333EA);
    case 'photo_submitted':
      return const Color(0xFF0891B2);
    case 'checked_in':
      return const Color(0xFF16A34A);
    case 'rejected':
      return const Color(0xFFDC2626);
    default:
      return kMuted;
  }
}

String _initials(String name) {
  final parts = name.trim().split(' ');
  if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  return parts.isNotEmpty && parts[0].isNotEmpty
      ? parts[0][0].toUpperCase()
      : '?';
}

String _fmtDate(String iso) {
  try {
    final d = DateTime.parse(iso).toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  } catch (_) {
    return iso;
  }
}

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

// ── Reject icon button — sits next to Check In on a photo_submitted row ──────

class _RejectIconBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _RejectIconBtn({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AppTk(Theme.of(context).brightness == Brightness.dark);
    return Tooltip(
      message: 'Reject',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFFDC2626).withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          child: const Icon(
            Icons.block_rounded,
            size: 16,
            color: Color(0xFFDC2626),
          ),
        ),
      ),
    );
  }
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
  final Map<String, String> _selfieUrls = {};
  List<String> _eventTitles = ['All'];
  final Set<String> _selectedIds = {};
  bool _bulkProcessing = false;

  // Organizer identity — resolved once and reused for scoped queries.
  String? _organizerId;
  final Set<String> _orgEventIds = {};

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _search.dispose();
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() => _loading = true);
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

      final rows = await RegistrationService.getAllRegistrations(
        organizerId: _organizerId,
      );

      // Track which events belong to this organizer so the realtime handler
      // can reject events from other organizers' registrations.
      _orgEventIds
        ..clear()
        ..addAll(
          rows
              .map((r) => r['event_id'] as String? ?? '')
              .where((id) => id.isNotEmpty),
        );

      if (!mounted) return;
      setState(() {
        _all = rows;
        _refreshEventTitles();
        _loading = false;
        _applyFilter();
      });
      for (final r in rows) {
        if (r['status'] == 'photo_submitted' && r['selfie_url'] != null) {
          _fetchSelfieUrl(r['id'] as String, r['selfie_url'] as String);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      debugPrint('RegistrationsScreen load error: $e');
    }
  }

  Future<void> _fetchSelfieUrl(String regId, String path) async {
    try {
      final url = await RegistrationService.getSelfieSignedUrl(path);
      if (mounted) setState(() => _selfieUrls[regId] = url);
    } catch (_) {}
  }

  void _subscribeRealtime() {
    _channel = RegistrationService.subscribeToAllRegistrations(
      (eventType, record) {
        if (!mounted) return;

        // If we've already loaded our event set, reject records from other
        // organizers. During initial load _orgEventIds may be empty — in that
        // brief window we accept all events (the UI is still loading anyway).
        if (_orgEventIds.isNotEmpty) {
          final evId = record['event_id'] as String?;
          if (evId == null || !_orgEventIds.contains(evId)) return;
        }

        final id = record['id'] as String?;
        if (id == null) return;
        setState(() {
          if (eventType == 'INSERT') {
            _all.insert(0, record);
            final evId = record['event_id'] as String?;
            if (evId != null) _orgEventIds.add(evId);
          } else if (eventType == 'DELETE') {
            _all.removeWhere((r) => r['id'] == id);
            _selfieUrls.remove(id);
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
        if (eventType != 'DELETE' &&
            record['status'] == 'photo_submitted' &&
            record['selfie_url'] != null) {
          _fetchSelfieUrl(id, record['selfie_url'] as String);
        }
      },
      channelSuffix: _organizerId,
      allowedEventIds: _orgEventIds.isEmpty ? null : _orgEventIds.toList(),
    );
  }

  void _applyFilter() {
    final q = _search.text.toLowerCase();
    final validEventTitles = _eventTitles.toSet();
    if (!validEventTitles.contains(_eventFilter)) {
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
          (_filter == 'Pending' &&
              (status == 'pending' || status == 'qr_scanned')) ||
          (_filter == 'Awaiting Selfie' && status == 'photo_required') ||
          (_filter == 'Photo Submitted' && status == 'photo_submitted') ||
          (_filter == 'Checked In' && status == 'checked_in');

      final matchesEvent = _eventFilter == 'All' || evt == _eventFilter;
      final matchesSearch =
          q.isEmpty ||
          name.contains(q) ||
          sid.contains(q) ||
          eventTitle.contains(q);

      return matchesFilter && matchesEvent && matchesSearch;
    }).toList();
    final reviewableIds = _filtered
        .where((r) => r['status'] == 'photo_submitted')
        .map((r) => r['id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    _selectedIds.removeWhere((id) => !reviewableIds.contains(id));
  }

  List<String> get _filteredReviewableIds => _filtered
      .where((r) => r['status'] == 'photo_submitted')
      .map((r) => r['id'] as String? ?? '')
      .where((id) => id.isNotEmpty)
      .toList();

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

  void _refreshEventTitles() {
    final titles =
        _all
            .map((r) => (r['event_title'] as String? ?? '').trim())
            .where((title) => title.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    _eventTitles = ['All', ...titles];
    if (!titles.contains(_eventFilter)) {
      _eventFilter = 'All';
    }
  }

  int _countForEvent(String title) {
    if (title == 'All') return _all.length;
    return _all
        .where((r) => (r['event_title'] as String? ?? '').trim() == title)
        .length;
  }

  Future<void> _updateStatus(
    String id,
    String newStatus, {
    String? rejectionReason,
  }) async {
    final idx = _all.indexWhere((r) => r['id'] == id);
    if (idx < 0) return;
    final oldStatus = _all[idx]['status'] as String? ?? '';

    // Optimistic update — reflect the change immediately.
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Failed to update status. Please try again.',
              style: TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
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
        _selfieUrls.remove(id);
        _applyFilter();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error: $e',
              style: const TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

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
                      onRefresh: _load,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(child: _buildPageHeader(t)),
                          SliverToBoxAdapter(child: _buildFilterRow(t)),
                          SliverToBoxAdapter(child: _buildSearchBar(t)),
                          if (_eventTitles.length > 2)
                            SliverToBoxAdapter(
                              child: _buildEventFilterSection(t),
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
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (_, i) => Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: _buildRegistrationCard(
                                      _filtered[i],
                                      t,
                                    ),
                                  ),
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
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildPageHeader(t),
          const AppShimmerList(itemCount: 6, hasAvatar: true, hasImage: false),
        ],
      ),
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

  // ── Page header (embedded) ────────────────────────────────────────────────

  Widget _buildPageHeader(AppTk t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            'Registrations',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: t.text,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 7),

          // Gold accent underline
          Container(
            width: 38,
            height: 3,
            decoration: BoxDecoration(
              gradient: kGoldGradient,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  // ── Scan QR CTA card ──────────────────────────────────────────────────────

  // ── Filter pills ──────────────────────────────────────────────────────────

  Widget _buildFilterRow(AppTk t) {
    const filters = [
      'All',
      'Pending',
      'Awaiting Selfie',
      'Photo Submitted',
      'Checked In',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: SizedBox(
        height: 42,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: filters.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final f = filters[i];
            final selected = _filter == f;
            return GestureDetector(
              onTap: () => setState(() {
                _filter = f;
                _applyFilter();
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  gradient: selected ? kGoldGradient : null,
                  color: selected ? null : t.card,
                  borderRadius: BorderRadius.circular(21),
                  border: Border.all(
                    color: selected ? const Color(0xFFC49230) : t.border,
                    width: 1.5,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: kGold.withValues(alpha: 0.32),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    f,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : t.sub,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Search bar ────────────────────────────────────────────────────────────

  Widget _buildSearchBar(AppTk t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: t.shadow,
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextField(
          controller: _search,
          onChanged: (_) {
            _applyFilter();
            setState(() {});
          },
          style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: t.text),
          decoration: InputDecoration(
            hintText: 'Search by name, school ID, or event…',
            hintStyle: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: t.muted.withValues(alpha: 0.8),
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: kGold,
              size: 22,
            ),
            suffixIcon: _search.text.isNotEmpty
                ? IconButton(
                    icon: Icon(
                      Icons.cancel_rounded,
                      color: t.muted.withValues(alpha: 0.6),
                      size: 20,
                    ),
                    onPressed: () {
                      _search.clear();
                      _applyFilter();
                      setState(() {});
                    },
                  )
                : null,
            filled: false,
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: kGold, width: 2),
            ),
          ),
        ),
      ),
    );
  }

  // ── Event filter section ──────────────────────────────────────────────────

  Widget _buildEventFilterSection(AppTk t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Filter by Event',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: t.sub,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '(${_eventTitles.length - 1})',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  color: t.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _eventTitles.map((title) {
              final selected = _eventFilter == title;
              final count = _countForEvent(title);
              return GestureDetector(
                onTap: () {
                  setState(() => _eventFilter = title);
                  _applyFilter();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF8B5CF6).withValues(alpha: 0.10)
                        : t.card,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF8B5CF6).withValues(alpha: 0.35)
                          : t.border,
                      width: selected ? 1.5 : 1,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: const Color(
                                0xFF8B5CF6,
                              ).withValues(alpha: 0.18),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selected)
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFF8B5CF6),
                            shape: BoxShape.circle,
                          ),
                        ),
                      if (selected) const SizedBox(width: 6),
                      Text(
                        title.length > 26
                            ? '${title.substring(0, 26)}…'
                            : title,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11.5,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: selected ? const Color(0xFF8B5CF6) : t.sub,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFF8B5CF6).withValues(alpha: 0.14)
                              : t.divider,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: selected ? const Color(0xFF8B5CF6) : t.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Result count ──────────────────────────────────────────────────────────

  Widget _buildResultCount(AppTk t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_filtered.length} registration${_filtered.length == 1 ? '' : 's'} found',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: t.sub,
              ),
            ),
          ),
          if (_filteredReviewableIds.isNotEmpty)
            TextButton.icon(
              onPressed: _bulkProcessing ? null : _toggleSelectAllReviewable,
              icon: Icon(
                _allReviewableSelected
                    ? Icons.check_box_rounded
                    : Icons.select_all_rounded,
                size: 17,
              ),
              label: Text(
                _allReviewableSelected ? 'Clear ready' : 'Select ready',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF8B5CF6),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBulkActionsBar(AppTk t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.border),
          boxShadow: [BoxShadow(color: t.shadow, blurRadius: 8)],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_selectedIds.length} selected',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _bulkProcessing
                      ? null
                      : () => setState(() => _selectedIds.clear()),
                  child: const Text(
                    'Clear',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _bulkProcessing ? null : _bulkApproveSelected,
                    icon: const Icon(Icons.check_circle_rounded, size: 16),
                    label: const Text(
                      'Approve & Check In',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 11,
                        horizontal: 8,
                      ),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _bulkProcessing ? null : _bulkRejectSelected,
                    icon: const Icon(Icons.block_rounded, size: 16),
                    label: const Text(
                      'Reject',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFDC2626)),
                      padding: const EdgeInsets.symmetric(
                        vertical: 11,
                        horizontal: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
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

  // ══════════════════════════════════════════════════════════════════════════
  // Registration card
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildRegistrationCard(Map<String, dynamic> r, AppTk t) {
    final id = r['id'] as String;
    final name = r['student_name'] as String? ?? '—';
    final sid = r['student_school_id'] as String? ?? '—';
    final event = r['event_title'] as String? ?? '—';
    final date = r['registered_at'] as String? ?? '';
    final status = r['status'] as String? ?? 'pending';
    final statusColor = _statusColor(status);
    final statusText = _statusLabel(status);
    final isSelected = _selectedIds.contains(id);

    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? const Color(0xFF8B5CF6) : t.border,
        ),
        boxShadow: [
          BoxShadow(
            color: t.shadow,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left status accent strip
            Container(width: 4, color: statusColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: avatar + name/ID + status pill
                    Row(
                      children: [
                        if (status == 'photo_submitted')
                          SizedBox(
                            width: 34,
                            child: Checkbox(
                              value: isSelected,
                              onChanged: _bulkProcessing
                                  ? null
                                  : (_) => _toggleRegistrationSelection(id),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              activeColor: const Color(0xFF8B5CF6),
                            ),
                          )
                        else
                          const SizedBox(width: 34),
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Center(
                            child: Text(
                              _initials(name),
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: t.text,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                sid,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11,
                                  color: t.sub,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: statusColor.withValues(alpha: 0.3),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            statusText,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // Event + date info block
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: t.bg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.event_rounded,
                                size: 13,
                                color: kGold,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  event,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: t.text,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.schedule_rounded,
                                size: 12,
                                color: t.sub,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Registered: ${_fmtDate(date)}',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11,
                                  color: t.sub,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Selfie preview
                    if (status == 'photo_submitted') ...[
                      const SizedBox(height: 10),
                      _buildSelfiePreview(id, r['selfie_url'] as String?, t),
                    ],

                    // Waiting spinner
                    if (status == 'photo_required') ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF9333EA,
                          ).withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            SizedBox(
                              width: 11,
                              height: 11,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF9333EA),
                              ),
                            ),
                            SizedBox(width: 7),
                            Text(
                              'Waiting for student selfie…',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF9333EA),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 10),

                    // Action row
                    Row(
                      children: [
                        Expanded(
                          child: _buildPrimaryAction(r, id, name, status, t),
                        ),
                        const SizedBox(width: 8),
                        PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'delete') _deleteRegistration(id, name);
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Delete',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 13,
                                      color: Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          icon: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: t.border,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.more_vert_rounded,
                              color: t.sub,
                              size: 20,
                            ),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ],
                    ),

                    // Checked-in confirmation
                    if (status == 'checked_in') ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(
                            Icons.check_circle_rounded,
                            size: 13,
                            color: Color(0xFF16A34A),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Successfully Checked In',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF16A34A),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Selfie preview ────────────────────────────────────────────────────────

  Widget _buildSelfiePreview(String regId, String? path, AppTk t) {
    final url = _selfieUrls[regId];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.photo_camera_rounded, size: 13, color: kGold),
            const SizedBox(width: 5),
            Text(
              'Student Selfie',
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
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: url != null
              ? Image.network(
                  url,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, prog) => prog == null
                      ? child
                      : Container(
                          height: 140,
                          color: t.bg,
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: kGold,
                              strokeWidth: 3,
                            ),
                          ),
                        ),
                  errorBuilder: (_, _, _) => _selfieError(t),
                )
              : (path != null ? _selfieSpinner(t) : _selfieError(t)),
        ),
      ],
    );
  }

  Widget _selfieSpinner(AppTk t) => Container(
    height: 100,
    color: t.bg,
    child: const Center(
      child: CircularProgressIndicator(color: kGold, strokeWidth: 3),
    ),
  );

  Widget _selfieError(AppTk t) => Container(
    height: 100,
    decoration: BoxDecoration(
      color: kGold.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: kGold.withValues(alpha: 0.15)),
    ),
    child: Center(
      child: Icon(
        Icons.broken_image_outlined,
        color: kGold.withValues(alpha: 0.4),
        size: 36,
      ),
    ),
  );

  // ── Primary action buttons ────────────────────────────────────────────────

  Widget _buildPrimaryAction(
    Map<String, dynamic> r,
    String id,
    String name,
    String status,
    AppTk t,
  ) {
    switch (status) {
      case 'pending':
      case 'qr_scanned':
        return _actionBtn(
          label: 'Confirm & Request Selfie',
          icon: Icons.camera_alt_outlined,
          color: const Color(0xFF16A34A),
          onTap: () => _updateStatus(id, 'photo_required'),
          t: t,
        );
      case 'photo_required':
        return _awaitingBtn();
      case 'photo_submitted':
        return Row(
          children: [
            Expanded(
              child: _actionBtn(
                label: 'Check In Student',
                icon: Icons.how_to_reg_rounded,
                color: kGold,
                onTap: () => _updateStatus(id, 'checked_in'),
                t: t,
              ),
            ),
            const SizedBox(width: 8),
            _RejectIconBtn(onTap: () => _confirmReject(id, name)),
          ],
        );
      case 'checked_in':
      default:
        return _actionBtn(
          label: 'View Details',
          icon: Icons.info_outline_rounded,
          color: const Color(0xFF2979C8),
          outlined: true,
          onTap: () => _showDetails(r),
          t: t,
        );
    }
  }

  Widget _awaitingBtn() {
    return OutlinedButton.icon(
      onPressed: null,
      icon: const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Color(0xFF9333EA),
        ),
      ),
      label: const Text(
        'Awaiting Selfie',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF9333EA),
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF9333EA),
        disabledForegroundColor: const Color(0xFF9333EA),
        side: const BorderSide(color: Color(0x669333EA), width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _actionBtn({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required AppTk t,
    bool outlined = false,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(
        label,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: outlined ? color : Colors.white,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: outlined ? t.card : color,
        foregroundColor: outlined ? color : Colors.white,
        elevation: 0,
        side: BorderSide(
          color: outlined ? color.withValues(alpha: 0.4) : color,
          width: 1.5,
        ),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────

  Widget _buildEmptyState(AppTk t) {
    final isFiltered = _filter != 'All' || _search.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: kGold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Icon(
              isFiltered ? Icons.search_off_rounded : Icons.inbox_rounded,
              size: 42,
              color: kGold.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            isFiltered ? 'No registrations found' : 'No registrations yet',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isFiltered
                ? 'Try adjusting your search or filter'
                : 'Students who register for events will appear here',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: t.muted,
              height: 1.6,
            ),
          ),
          if (isFiltered) ...[
            const SizedBox(height: 28),
            GestureDetector(
              onTap: () {
                _search.clear();
                setState(() => _filter = 'All');
                _applyFilter();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: kGold,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: kGold.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Text(
                  'Clear filters',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Details sheet ─────────────────────────────────────────────────────────

  void _showDetails(Map<String, dynamic> r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RegistrationDetailsSheet(
        r: r,
        selfieUrl: _selfieUrls[r['id'] as String? ?? ''],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Registration details bottom sheet
// ══════════════════════════════════════════════════════════════════════════════

class _RegistrationDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> r;
  final String? selfieUrl;
  const _RegistrationDetailsSheet({required this.r, this.selfieUrl});

  @override
  Widget build(BuildContext context) {
    final t = AppTk(Theme.of(context).brightness == Brightness.dark);
    final name = r['student_name'] as String? ?? '—';
    final sid = r['student_school_id'] as String? ?? '—';
    final event = r['event_title'] as String? ?? '—';
    final status = r['status'] as String? ?? 'pending';
    final regDate = r['registered_at'] as String? ?? '';
    final checkedInAt = r['checked_in_at'] as String?;
    final statusColor = _statusColor(status);
    final statusText = _statusLabel(status);
    final initials = _initials(name);
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: t.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 8, 20, bottomPad + 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Gold accent strip
                  Container(
                    width: 44,
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: kGoldGradient,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Student avatar
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.35),
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        initials,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Student name
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: t.text,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),

                  // School ID
                  Text(
                    sid,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: t.sub,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Status chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.30),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          statusText,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Event card
                  _infoCard(
                    t,
                    children: [
                      _infoRow(
                        t,
                        Icons.event_rounded,
                        'Event',
                        event,
                        kGold,
                        multiLine: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Timeline card
                  _infoCard(
                    t,
                    children: [
                      _infoRow(
                        t,
                        Icons.schedule_rounded,
                        'Registered',
                        _fmtDate(regDate),
                        t.sub,
                      ),
                      if (checkedInAt != null) ...[
                        Divider(height: 1, thickness: 1, color: t.divider),
                        _infoRow(
                          t,
                          Icons.check_circle_rounded,
                          'Checked In',
                          _fmtDate(checkedInAt),
                          const Color(0xFF16A34A),
                        ),
                      ],
                    ],
                  ),

                  // Selfie card
                  if (selfieUrl != null) ...[
                    const SizedBox(height: 12),
                    _infoCard(
                      t,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.photo_camera_rounded,
                                    size: 14,
                                    color: kGold,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Student Selfie',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: t.text,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  selfieUrl!,
                                  height: 160,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (_, child, prog) =>
                                      prog == null
                                      ? child
                                      : Container(
                                          height: 160,
                                          color: t.bg,
                                          child: const Center(
                                            child: CircularProgressIndicator(
                                              color: kGold,
                                              strokeWidth: 3,
                                            ),
                                          ),
                                        ),
                                  errorBuilder: (_, _, e2) => Container(
                                    height: 100,
                                    decoration: BoxDecoration(
                                      color: kGold.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: kGold.withValues(alpha: 0.15),
                                      ),
                                    ),
                                    child: Center(
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: kGold.withValues(alpha: 0.4),
                                        size: 36,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Close button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kGold,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Close',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(AppTk t, {required List<Widget> children}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.border),
        boxShadow: [
          BoxShadow(
            color: t.shadow,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _infoRow(
    AppTk t,
    IconData icon,
    String label,
    String value,
    Color iconColor, {
    bool multiLine = false,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 15, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: t.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                    height: 1.3,
                  ),
                  maxLines: multiLine ? 3 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

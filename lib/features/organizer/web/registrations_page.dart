import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/app_colors.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/registration_service.dart';
import 'web_shared.dart';

class WebRegistrationsPage extends StatefulWidget {
  final String? orgId;
  const WebRegistrationsPage({super.key, this.orgId});

  @override
  State<WebRegistrationsPage> createState() => _WebRegistrationsPageState();
}

class _WebRegistrationsPageState extends State<WebRegistrationsPage> with SingleTickerProviderStateMixin {
  bool   _loading      = true;
  String _statusFilter = 'All';
  String _eventFilter  = 'All';
  final  _search       = TextEditingController();

  List<Map<String, dynamic>> _all          = [];
  List<Map<String, dynamic>> _displayed   = [];
  List<String>               _eventTitles = [];
  final Map<String, String>  _selfieUrls  = {};
  final Set<String>          _processingIds = {};
  final Set<String>          _selectedIds = {};

  // Realtime subscription — scoped to this organizer's events.
  RealtimeChannel? _channel;
  List<String>     _orgEventIds = [];

  final _statusFilters = [
    'All', 'Pending', 'QR Scanned', 'Awaiting Selfie',
    'Photo Submitted', 'Checked In',
  ];

  String? _hoveredTab;   // tracks which status chip the cursor is over

  late final AnimationController _staggerCtrl;

  @override
  void initState() {
    super.initState();
    _staggerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _search.addListener(_applyFilter);
    _load();
  }

  @override
  void dispose() {
    if (_channel != null) SupabaseService.client.removeChannel(_channel!);
    _staggerCtrl.dispose();
    _search.dispose();
    super.dispose();
  }

  Widget _stagger(Widget child, {required double start, required double end}) {
    return AnimatedBuilder(
      animation: _staggerCtrl,
      builder: (_, c) {
        final raw = ((_staggerCtrl.value - start) / (end - start)).clamp(0.0, 1.0);
        final t  = Curves.easeOut.transform(raw);
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

  Future<void> _load() async {
    if (widget.orgId == null) return;
    setState(() => _loading = true);
    try {
      final eventsRaw = await SupabaseService.client
          .from('events')
          .select('event_id, title')
          .eq('organizer_id', widget.orgId!);
      final events   = List<Map<String, dynamic>>.from(eventsRaw as List);
      final eventIds = events.map((e) => e['event_id'] as String).toList();

      if (eventIds.isEmpty) {
        if (mounted) {
          setState(() { _all = []; _displayed = []; _loading = false; });
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

      final titles = {'All', ...regs.map((r) => r['event_title'] as String? ?? '—').toSet()};
      _eventTitles = titles.toList()..sort((a, b) => a == 'All' ? -1 : a.compareTo(b));

      // Store event IDs for realtime filtering, then (re)start the subscription.
      _orgEventIds = eventIds;
      _subscribeRealtime();

      if (!mounted) return;
      _all = regs;
      _applyFilter();
      _fetchSelfieUrls(regs);
      setState(() => _loading = false);
      _staggerCtrl.forward(from: 0);
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        _staggerCtrl.forward(from: 0);
      }
    }
  }

  Future<void> _fetchSelfieUrls(List<Map<String, dynamic>> rows) async {
    final toFetch = <String, String>{};
    for (final r in rows) {
      final path = r['selfie_url'] as String?;
      final id   = r['id']        as String?;
      if (path != null && path.isNotEmpty && id != null &&
          !_selfieUrls.containsKey(id)) {
        toFetch[id] = path;
      }
    }
    if (toFetch.isEmpty) return;
    final entries = await Future.wait(
      toFetch.entries.map((e) async {
        try {
          final url = await RegistrationService.getSelfieSignedUrl(e.value);
          return MapEntry(e.key, url);
        } catch (_) { return null; }
      }),
    );
    if (!mounted) return;
    final newUrls = <String, String>{};
    for (final entry in entries) {
      if (entry != null) newUrls[entry.key] = entry.value;
    }
    if (newUrls.isNotEmpty) setState(() => _selfieUrls.addAll(newUrls));
  }

  void _subscribeRealtime() {
    // Cancel any existing channel before creating a new one (called on each
    // _load so the event-ID whitelist stays current after a refresh).
    if (_channel != null) SupabaseService.client.removeChannel(_channel!);

    if (_orgEventIds.isEmpty) return;

    _channel = RegistrationService.subscribeToAllRegistrations(
      (eventType, record) {
        if (!mounted) return;
        final id = record['id'] as String?;
        if (id == null) return;

        setState(() {
          if (eventType == 'DELETE') {
            _all.removeWhere((r) => r['id'] == id);
            _selfieUrls.remove(id);
          } else if (eventType == 'INSERT') {
            _all.insert(0, record);
            // Keep event titles list up to date for the filter chips.
            final title = record['event_title'] as String?;
            if (title != null && !_eventTitles.contains(title)) {
              _eventTitles = ['All', ...(_eventTitles..remove('All')), title]
                ..sort((a, b) => a == 'All' ? -1 : a.compareTo(b));
            }
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

        // Fetch a signed URL when a new selfie arrives.
        if (eventType != 'DELETE' &&
            record['status'] == 'photo_submitted' &&
            record['selfie_url'] != null) {
          _fetchSelfieUrls([record]);
        }
      },
      channelSuffix:   widget.orgId,
      allowedEventIds: _orgEventIds,
    );
  }

  void _applyFilter() {
    final q         = _search.text.toLowerCase();
    final statusKey = _statusKeyMap[_statusFilter];
    setState(() {
      _displayed = _all.where((r) {
        final matchStatus = statusKey == null || r['status'] == statusKey;
        final matchEvent  = _eventFilter == 'All' ||
            (r['event_title'] as String? ?? '') == _eventFilter;
        final name  = (r['student_name']     as String? ?? '').toLowerCase();
        final event = (r['event_title']      as String? ?? '').toLowerCase();
        final sid   = (r['student_school_id'] as String? ?? '').toLowerCase();
        final matchSearch = q.isEmpty ||
            name.contains(q) || event.contains(q) || sid.contains(q);
        return matchStatus && matchEvent && matchSearch;
      }).toList();
    });
  }

  bool get _allVisibleSelected =>
      _displayed.isNotEmpty &&
      _displayed.every((r) {
        final id = r['id'] as String? ?? '';
        return id.isNotEmpty && _selectedIds.contains(id);
      });

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
    final visibleIds = _displayed
        .map((r) => r['id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Failed to approve selected students: ${e.toString().replaceAll('Exception:', '').trim()}',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
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
        await RegistrationService.updateStatus(id, 'rejected', rejectionReason: reason);
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Failed to reject selected students: ${e.toString().replaceAll('Exception:', '').trim()}',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } finally {
      if (mounted) {
        setState(() => _processingIds.removeAll(processing));
      }
    }
  }

  static const _statusKeyMap = {
    'All':             null,
    'Pending':         'pending',
    'QR Scanned':      'qr_scanned',
    'Awaiting Selfie': 'photo_required',
    'Photo Submitted': 'photo_submitted',
    'Checked In':      'checked_in',
    'Rejected':        'rejected',
  };

  Future<void> _updateStatus(String id, String newStatus, {String? rejectionReason}) async {
    setState(() => _processingIds.add(id));
    try {
      await RegistrationService.updateStatus(id, newStatus, rejectionReason: rejectionReason);
    } catch (e) {
      if (mounted) {
        setState(() => _processingIds.remove(id));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Failed to update status: ${e.toString().replaceAll('Exception:', '').trim()}',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
      return;
    }
    setState(() => _processingIds.remove(id));
    await _load();
  }

  Future<void> _delete(String id) async {
    final ok = await WebAlert.confirm(
      context:      context,
      title:        'Delete Registration?',
      message:      'This registration will be permanently removed. This action cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (ok != true) return;
    setState(() => _processingIds.add(id));
    try {
      await RegistrationService.deleteRegistration(id);
    } catch (e) {
      if (mounted) {
        setState(() => _processingIds.remove(id));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Failed to delete registration: ${e.toString().replaceAll('Exception:', '').trim()}',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
      return;
    }
    setState(() => _processingIds.remove(id));
    await _load();
  }

  // ── Selfie dialog ─────────────────────────────────────────────────────────────

  Future<void> _sendSelfieRequest(String id, String studentName) async {
    final ok = await WebAlert.confirm(
      context:      context,
      title:        'Send Selfie Request?',
      message:      '$studentName will be prompted to submit a selfie photo to complete their check-in.',
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
                child: Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.photo_camera_rounded,
                      size: 18, color: Color(0xFF8B5CF6)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Check-in Selfie',
                          style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 14,
                            fontWeight: FontWeight.w700, color: t.text,
                          )),
                        Text(studentName,
                          style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 11, color: t.sub,
                          )),
                      ],
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: t.divider,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.close_rounded, size: 16, color: t.sub),
                      ),
                    ),
                  ),
                ]),
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
                                const CircularProgressIndicator(color: kGold, strokeWidth: 2),
                                const SizedBox(height: 12),
                                Text('Loading selfie…',
                                  style: TextStyle(
                                    fontFamily: 'Poppins', fontSize: 12,
                                    color: t.muted,
                                  )),
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
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: t.divider,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.broken_image_outlined,
                                size: 22, color: t.muted),
                            ),
                            const SizedBox(height: 10),
                            Text('Could not load image',
                              style: TextStyle(
                                fontFamily: 'Poppins', fontSize: 12, color: t.muted,
                              )),
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
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: t.inputBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.border),
                  ),
                  child: Row(children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.25)),
                      ),
                      child: Center(
                        child: Text(initials,
                          style: const TextStyle(
                            fontFamily: 'Poppins', fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF8B5CF6),
                          )),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(studentName,
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 13,
                        fontWeight: FontWeight.w600, color: t.text,
                      )),
                  ]),
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
              border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.22)),
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
            label: const Text('Approve', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF10B981),
              side: const BorderSide(color: Color(0xFF10B981), width: 1.2),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: _bulkRejectSelected,
            icon: const Icon(Icons.block_rounded, size: 16),
            label: const Text('Reject', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFEF4444),
              side: const BorderSide(color: Color(0xFFEF4444), width: 1.2),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(width: 10),
          TextButton.icon(
            onPressed: () => setState(() => _selectedIds.clear()),
            icon: const Icon(Icons.close_rounded, size: 16),
            label: const Text('Clear', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
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
          const SizedBox(height: 12),
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
                  start: 0.50, end: 0.85,
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
              Text('Registrations',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: t.text,
                  height: 1.1,
                )),
            ],
          ),
          const Spacer(),
        ],
      ),
      start: 0.00, end: 0.35,
    );
  }

  // ── Filter bar ────────────────────────────────────────────────────────────────

  Widget _buildFilterBar(WebTk t) {
    // Counts per status — shown as live badges on each filter chip so the
    // organizer sees at a glance how many registrations are in each state
    // without having to click through each filter.
    final counts = <String, int>{
      'All':             _all.length,
      'Pending':         _all.where((r) => r['status'] == 'pending').length,
      'QR Scanned':      _all.where((r) => r['status'] == 'qr_scanned').length,
      'Awaiting Selfie': _all.where((r) => r['status'] == 'photo_required').length,
      'Photo Submitted': _all.where((r) => r['status'] == 'photo_submitted').length,
      'Checked In':      _all.where((r) => r['status'] == 'checked_in').length,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status pill chips + search
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _statusFilters.map((f) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _statusTab(f, counts[f] ?? 0, t),
                  )).toList(),
                ),
              ),
            ),
            const SizedBox(width: 16),
            WebSearchField(
              controller: _search,
              hint: 'Search name, event, ID…',
              onChanged: (_) {},
            ),
          ],
        ),
        // Event filter grid — shown only when there are multiple events.
        // Uses Wrap so chips automatically reflow into additional rows on
        // narrower viewports instead of scrolling off-screen horizontally.
        if (_eventTitles.length > 2) ...[
          const SizedBox(height: 16),
          // Section label
          Row(
            children: [
              Container(
                width: 3, height: 14,
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
                  fontSize:   11,
                  fontWeight: FontWeight.w700,
                  color:      t.sub,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '(${_eventTitles.length - 1})',   // -1 for the "All" entry
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize:   10,
                  color:      t.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Chip grid — Wrap reflows into a new row when the row is full
          Wrap(
            spacing:    8,
            runSpacing: 8,
            children: _eventTitles.map((t) {
              final count = t == 'All'
                  ? _all.length
                  : _all.where((r) => r['event_title'] == t).length;
              return WebFilterChip(
                label:         t.length > 30 ? '${t.substring(0, 30)}…' : t,
                selected:      _eventFilter == t,
                selectedColor: const Color(0xFF8B5CF6),
                count:         count,
                onTap: () {
                  setState(() => _eventFilter = t);
                  _applyFilter();
                },
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _statusTab(String f, int count, WebTk t) {
    final selected    = _statusFilter == f;
    final hovered     = _hoveredTab == f;
    final accent      = f == 'All' ? kGold : webStatusColor(_statusKeyMap[f]);

    final unselectedBg = hovered
        ? (t.dark ? t.divider : const Color(0xFFEEF2F7))
        : t.inputBg;
    final unselectedBorder = hovered
        ? (t.dark ? const Color(0xFF2A3040) : const Color(0xFFD1D5DB))
        : t.border;
    final unselectedCountBg = t.dark ? const Color(0xFF20252E) : const Color(0xFFE5E7EB);

    return MouseRegion(
      cursor:  SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoveredTab = f),
      onExit:  (_) => setState(() => _hoveredTab = null),
      child: GestureDetector(
        onTap: () {
          setState(() { _statusFilter = f; _hoveredTab = null; });
          _applyFilter();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve:    Curves.easeOut,
          padding:  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.08)
                : unselectedBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.35)
                  : unselectedBorder,
              width: selected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status dot — visible only when selected
              if (selected) ...[
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    color: accent, shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                f,
                style: TextStyle(
                  fontFamily:  'Poppins',
                  fontSize:    12,
                  fontWeight:  selected ? FontWeight.w700 : FontWeight.w500,
                  color:       selected ? accent : t.sub,
                  letterSpacing: selected ? 0.1 : 0,
                ),
              ),
              const SizedBox(width: 7),
              // Live count badge
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: selected
                      ? accent.withValues(alpha: 0.15)
                      : unselectedCountBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontFamily:  'Poppins',
                    fontSize:    10,
                    fontWeight:  FontWeight.w700,
                    color:       selected ? accent : t.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
            child: Row(children: [
              SizedBox(
                width: 36,
                child: Checkbox(
                  value: _allVisibleSelected && _displayed.isNotEmpty,
                  onChanged: (_) => _toggleSelectAllVisible(),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  activeColor: const Color(0xFF8B5CF6),
                ),
              ),
              Expanded(flex: 4, child: WebColHeader('STUDENT')),
              Expanded(flex: 3, child: WebColHeader('EVENT')),
              Expanded(flex: 2, child: WebColHeader('STATUS')),
              Expanded(flex: 2, child: WebColHeader('REGISTERED')),
              const SizedBox(width: 146, child: WebColHeader('ACTIONS')),
            ]),
          ),
          start: 0.48, end: 0.68,
        ),
        // Data rows
        ...(_displayed.asMap().entries.map((entry) {
          final i      = entry.key;
          final reg    = entry.value;
          final id     = reg['id']     as String? ?? '';
          final status = reg['status'] as String?;
          final sc     = webStatusColor(status);
          final isLast = i == _displayed.length - 1;

          final name     = reg['student_name']     as String? ?? '—';
          final lrn      = reg['student_school_id'] as String? ?? '—';
          final selfieUrl = _selfieUrls[id];

          final initials = name
              .split(' ')
              .where((w) => w.isNotEmpty)
              .map((w) => w[0].toUpperCase())
              .take(2)
              .join();

          final regAt        = reg['registered_at'] as String?;
          final isProcessing = _processingIds.contains(id);
          final isSelected   = _selectedIds.contains(id);
          final s            = 0.55 + (i * 0.07).clamp(0.0, 0.27);

          return _stagger(
            _RegHoverRow(
              isLast: isLast,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 36,
                      child: Checkbox(
                        value: isSelected,
                        onChanged: (_) => _toggleSelection(id),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        activeColor: const Color(0xFF8B5CF6),
                      ),
                    ),

                    // ── Student (avatar + name + LRN) ──
                    Expanded(
                      flex: 4,
                      child: Row(children: [
                        Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            color: sc.withValues(alpha: 0.10),
                            shape: BoxShape.circle,
                            border: Border.all(color: sc.withValues(alpha: 0.28)),
                          ),
                          child: Center(
                            child: Text(initials,
                              style: TextStyle(
                                fontFamily: 'Poppins', fontSize: 12.5,
                                fontWeight: FontWeight.w700, color: sc,
                              )),
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(name,
                                style: TextStyle(
                                  fontFamily: 'Poppins', fontSize: 13,
                                  fontWeight: FontWeight.w600, color: t.text,
                                ),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Row(children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: t.inputBg,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(lrn,
                                    style: TextStyle(
                                      fontFamily: 'Courier',
                                      fontSize: 10.5,
                                      color: t.sub,
                                      letterSpacing: 0.3,
                                    )),
                                ),
                              ]),
                            ],
                          ),
                        ),
                      ]),
                    ),

                  // ── Event ──
                  Expanded(
                    flex: 3,
                    child: Row(children: [
                      Container(
                        width: 4, height: 30,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: kGold.withValues(alpha: 0.50),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Expanded(
                        child: Text(reg['event_title'] as String? ?? '—',
                          style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 12.5,
                            fontWeight: FontWeight.w500, color: t.text,
                          ),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                    ]),
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
                        Text(webTimeAgo(regAt),
                          style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 12,
                            fontWeight: FontWeight.w600, color: t.text,
                          )),
                        const SizedBox(height: 2),
                        Text(webFmtDate(regAt),
                          style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 10.5, color: t.muted,
                          )),
                      ],
                    ),
                  ),

                  // Actions - 4 fixed slots
                  // Slot 0: selfie request  |  Slot 1: selfie view
                  // Slot 2: status          |  Slot 3: delete
                  SizedBox(
                    width: 146,
                    child: isProcessing
                      ? const Center(
                          child: SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: kGold),
                          ),
                        )
                      : Row(
                          children: [
                            // Slot 0 - Send selfie request
                            if (status == 'qr_scanned')
                              _RegAction(
                                icon:    Icons.add_a_photo_rounded,
                                color:   const Color(0xFFF97316),
                                tooltip: 'Send selfie request',
                                onTap:   () => _sendSelfieRequest(id, name),
                              )
                            else if (status == 'pending')
                              _RegAction(
                                icon:    Icons.add_a_photo_rounded,
                                color:   const Color(0xFF9CA3AF),
                                tooltip: "Scan the student's QR code before requesting a selfie",
                                onTap:   null,
                              )
                            else
                              const SizedBox(width: 32),
                            const SizedBox(width: 6),
                            // Slot 1 - Selfie viewer
                            if (selfieUrl != null)
                              _RegAction(
                                icon:    Icons.photo_camera_rounded,
                                color:   const Color(0xFF8B5CF6),
                                tooltip: 'View selfie',
                                onTap:   () => _viewSelfie(selfieUrl, name, t),
                              )
                            else
                              Tooltip(
                                message: status == 'photo_required'
                                    ? 'Awaiting selfie from student'
                                    : 'No selfie submitted yet',
                                child: Opacity(
                                  opacity: 0.25,
                                  child: Container(
                                    width: 32, height: 32,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF8B5CF6)
                                          .withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(8),
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
                              onSelect: (s) async {
                                if (s == 'rejected') {
                                  final reason = await _promptRejectReason(context, name);
                                  if (reason == null) return;
                                  await _updateStatus(id, s, rejectionReason: reason);
                                } else {
                                  await _updateStatus(id, s);
                                }
                              },
                            ),
                            const SizedBox(width: 6),
                            // Slot 3 - Delete
                            _RegAction(
                              icon:    Icons.delete_outline_rounded,
                              color:   const Color(0xFFEF4444),
                              tooltip: 'Delete registration',
                              onTap:   () => _delete(id),
                            ),
                          ],
                        ),
                  ),
                ],
              ),
              ),
            ),
            start: s, end: (s + 0.20).clamp(0.0, 1.0),
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
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 40, offset: const Offset(0, 14))],
              ),
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.block_rounded, size: 19, color: Color(0xFFEF4444)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Reject $studentName?',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 16,
                        fontWeight: FontWeight.w800, color: t.text))),
                ]),
                const SizedBox(height: 8),
                Text('This student will not be checked in. Give a reason so they know what to fix.',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.sub, height: 1.5)),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  maxLines: 3,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: t.text),
                  decoration: webInputDeco('e.g. Selfie doesn\'t match student ID photo', dark: t.dark),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogCtx).pop(),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: t.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: Text('Cancel', style: TextStyle(fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600, color: t.sub)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: ctrl.text.trim().isEmpty
                          ? null
                          : () => Navigator.of(dialogCtx).pop(ctrl.text.trim()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.35),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text('Confirm Reject',
                          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
              ]),
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
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 40, offset: const Offset(0, 14))],
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.block_rounded, size: 19, color: Color(0xFFEF4444)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Reject $count selected?',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 16,
                              fontWeight: FontWeight.w800, color: t.text)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('This will reject the selected registrations and record the same reason for every student.',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.sub, height: 1.5)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    maxLines: 3,
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: t.text),
                    decoration: webInputDeco('e.g. Attendance criteria not met', dark: t.dark),
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
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          child: Text('Cancel', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: t.sub)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: ctrl.text.trim().isEmpty
                              ? null
                              : () => Navigator.of(dialogCtx).pop(ctrl.text.trim()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.35),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          child: const Text('Reject Selected', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
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
  final String?              currentStatus;
  final ValueChanged<String> onSelect;
  const _StatusMenu({this.currentStatus, required this.onSelect});

  @override
  State<_StatusMenu> createState() => _StatusMenuState();
}

class _StatusMenuState extends State<_StatusMenu> {
  bool _hovered = false;

  static const _statuses = [
    ('pending',         'Pending'),
    ('qr_scanned',      'QR Scanned'),
    ('photo_required',  'Awaiting Selfie'),
    ('photo_submitted', 'Photo Submitted'),
    ('checked_in',      'Check In'),
    ('rejected',        'Reject'),
  ];

  // Forward-only state machine. checked_in and rejected are both terminal —
  // rejected is only reachable from photo_submitted (the same point admin's
  // now-removed dialog used to decide from).
  static const _allowed = <String, Set<String>>{
    'pending':         {'photo_submitted', 'checked_in'},
    'qr_scanned':      {'photo_required', 'photo_submitted', 'checked_in'},
    'photo_required':  {'photo_submitted', 'checked_in'},
    'photo_submitted': {'checked_in', 'rejected'},
    'checked_in':      {},
    'rejected':        {},
  };

  static IconData _statusIcon(String key) => switch (key) {
    'pending'         => Icons.hourglass_empty_rounded,
    'qr_scanned'      => Icons.qr_code_scanner_rounded,
    'photo_required'  => Icons.photo_camera_rounded,
    'photo_submitted' => Icons.check_circle_outline_rounded,
    'checked_in'      => Icons.how_to_reg_rounded,
    'rejected'        => Icons.block_rounded,
    _                 => Icons.circle_outlined,
  };

  static String _statusDesc(String key) => switch (key) {
    'qr_scanned'      => 'Student\'s QR code has been scanned',
    'photo_required'  => 'Request a selfie from the student',
    'photo_submitted' => 'Selfie received, awaiting review',
    'checked_in'      => 'Confirm and finalise attendance',
    'rejected'        => 'Deny attendance — requires a reason',
    _                 => '',
  };

  @override
  Widget build(BuildContext context) {
    final t            = WebTk(Theme.of(context).brightness == Brightness.dark);
    final current      = widget.currentStatus;
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
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.withValues(alpha: 0.20)),
          ),
          child: Icon(Icons.lock_rounded, size: 13, color: c),
        ),
      );
    }

    final allowedSet   = _allowed[current] ?? {};
    final items        = _statuses.where((s) => allowedSet.contains(s.$1)).toList();
    if (items.isEmpty) return const SizedBox(width: 32);

    final currentLabel = _statuses
        .firstWhere((s) => s.$1 == current, orElse: () => ('', '—'))
        .$2;

    return MouseRegion(
      cursor:  SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: PopupMenuButton<String>(
        tooltip: '',
        constraints: const BoxConstraints(minWidth: 252),
        onSelected: (s) {
          setState(() => _hovered = false);
          widget.onSelect(s);
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        color:     t.card,
        elevation: 8,
        shadowColor: t.shadow,
        itemBuilder: (_) => [
          // ── Header — shows context before the organizer picks ──────────
          PopupMenuItem<String>(
            enabled: false,
            padding: EdgeInsets.zero,
            height:  58,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Icon(Icons.arrow_circle_right_rounded,
                        size: 13, color: t.text),
                    const SizedBox(width: 6),
                    Text('Advance Status',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 12,
                        fontWeight: FontWeight.w700, color: t.text,
                      )),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    Text('Current: ',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 10, color: t.muted)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color:        currentColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                        border:       Border.all(
                            color: currentColor.withValues(alpha: 0.25)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 5, height: 5,
                          decoration: BoxDecoration(
                              color: currentColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 5),
                        Text(currentLabel,
                          style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 10,
                            fontWeight: FontWeight.w600, color: currentColor,
                          )),
                      ]),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          const PopupMenuDivider(height: 1),

          // ── Selectable status items ────────────────────────────────────
          ...items.map((s) {
            final (key, label) = s;
            final c          = webStatusColor(key);
            final icon       = _statusIcon(key);
            final desc       = _statusDesc(key);
            final isTerminal = key == 'checked_in' || key == 'rejected';

            return PopupMenuItem<String>(
              value:   key,
              padding: EdgeInsets.zero,
              height:  60,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                child: Row(children: [
                  // Status icon in a tinted circle
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color:  c.withValues(alpha: 0.10),
                      shape:  BoxShape.circle,
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
                        Row(children: [
                          Text(label,
                            style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: isTerminal ? c : t.text,
                            )),
                          if (isTerminal) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: c.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('FINAL',
                                style: TextStyle(
                                  fontFamily:    'Poppins',
                                  fontSize:      8,
                                  fontWeight:    FontWeight.w800,
                                  color:         c,
                                  letterSpacing: 0.5,
                                )),
                            ),
                          ],
                        ]),
                        if (desc.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(desc,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize:   10.5,
                              color:      t.muted,
                            )),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Forward arrow in the status color
                  Icon(Icons.arrow_forward_ios_rounded,
                      size: 10, color: c.withValues(alpha: 0.55)),
                ]),
              ),
            );
          }),
        ],

        // ── Trigger button ─────────────────────────────────────────────────
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 32, height: 32,
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
  final bool   isLast;
  const _RegHoverRow({required this.child, required this.isLast});

  @override
  State<_RegHoverRow> createState() => _RegHoverRowState();
}

class _RegHoverRowState extends State<_RegHoverRow> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
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
    );
  }
}

// ── Icon action button ────────────────────────────────────────────────────────

class _RegAction extends StatefulWidget {
  final IconData     icon;
  final Color        color;
  final String       tooltip;
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
    onExit:  (_) => setState(() => _h = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: Tooltip(
        message: widget.tooltip,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          width: 32, height: 32,
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

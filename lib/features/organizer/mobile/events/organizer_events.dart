import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'create_event_screen.dart';
import 'manage_event_screen.dart';
import 'event_details.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/services/audit_service.dart';

class OrganizerEventsScreen extends StatefulWidget {
  final bool showAsEmbedded;
  const OrganizerEventsScreen({this.showAsEmbedded = false, super.key});

  @override
  State<OrganizerEventsScreen> createState() => _OrganizerEventsScreenState();
}

class _OrganizerEventsScreenState extends State<OrganizerEventsScreen> {
  String _filter = 'All';
  bool _loading = true;
  bool _loadError = false;
  String? _deletingEventId;
  String? _organizerId;
  Timer? _statusTimer;

  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _filtered = [];
  // event_id → total registration count
  final Map<String, int> _registrationCountMap = {};
  // event_id → checked-in count (loaded alongside events)
  final Map<String, int> _checkedInMap = {};

  static const _filterOptions = ['All', 'Upcoming', 'Ongoing', 'Ended'];

  @override
  void initState() {
    super.initState();
    _loadData();
    _statusTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) _applyFilter();
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ────────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;

      final orgRow = await client
          .from('organizers')
          .select('organizer_id')
          .eq('user_id', user.id)
          .maybeSingle();

      if (orgRow == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      _organizerId = orgRow['organizer_id'] as String;

      final rows = await client
          .from('events')
          .select()
          .eq('organizer_id', _organizerId!)
          .order('created_at', ascending: false);

      final events = List<Map<String, dynamic>>.from(rows as List);

      // Load registration and checked-in counts for all events in one query.
      final registrationCounts = <String, int>{};
      final checkedIn = <String, int>{};
      if (events.isNotEmpty) {
        final eventIds = events.map((e) => e['event_id'] as String).toList();
        final regRows = await client
            .from('registrations')
            .select('event_id, status')
            .in_('event_id', eventIds);
        for (final r in (regRows as List)) {
          final eid = r['event_id'] as String;
          registrationCounts[eid] = (registrationCounts[eid] ?? 0) + 1;
          if (r['status'] == 'checked_in') {
            checkedIn[eid] = (checkedIn[eid] ?? 0) + 1;
          }
        }
      }

      if (mounted) {
        setState(() {
          _events = events;
          _registrationCountMap
            ..clear()
            ..addAll(registrationCounts);
          _checkedInMap
            ..clear()
            ..addAll(checkedIn);
          _loading = false;
          _applyFilter();
        });
      }
    } catch (e) {
      debugPrint('OrganizerEventsScreen load error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = true;
        });
      }
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.toLowerCase();
    _filtered = _events.where((e) {
      final label = _statusLabel(e);
      final matchFilter =
          _filter == 'All' ||
          label == _filter ||
          (_filter == 'Ended' && label == 'Cancelled');
      final title = (e['title'] as String? ?? '').toLowerCase();
      final location = (e['location'] as String? ?? '').toLowerCase();
      final type = (e['event_type'] as String? ?? '').toLowerCase();
      final matchSearch =
          q.isEmpty ||
          title.contains(q) ||
          location.contains(q) ||
          type.contains(q);
      return matchFilter && matchSearch;
    }).toList();

    int statusOrder(String label) {
      if (label == 'Upcoming') return 0;
      if (label == 'Ongoing') return 1;
      if (label == 'Ended') return 2;
      return 3; // Cancelled
    }

    _filtered.sort((a, b) {
      final po = statusOrder(
        _statusLabel(a),
      ).compareTo(statusOrder(_statusLabel(b)));
      if (po != 0) return po;
      final da = a['event_date'] as String? ?? '';
      final db = b['event_date'] as String? ?? '';
      return da.compareTo(db);
    });

    setState(() {});
  }

  int _countFor(String filter) {
    if (filter == 'All') return _events.length;
    return _events.where((e) {
      final label = _statusLabel(e);
      return label == filter || (filter == 'Ended' && label == 'Cancelled');
    }).length;
  }

  // ── Status helpers ─────────────────────────────────────────────────────────

  // event_status only ever holds upcoming/ongoing/completed/cancelled (DB
  // CHECK constraint) — draft/pending were never real values here. Approval
  // state (pending admin review / rejected) is a separate concept, shown as
  // its own badge in _buildEventCard, not folded into this lifecycle label.
  String _statusLabel(Map<String, dynamic> e) => eventStatusLabel(e);

  Color _statusColor(String label) {
    switch (label) {
      case 'Ongoing':
        return const Color(0xFF16A34A);
      case 'Ended':
        return const Color(0xFF6B7280);
      case 'Cancelled':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFFE87A00); // Upcoming
    }
  }

  String _formatDate(Map<String, dynamic> e) {
    final d = e['event_date'] as String?;
    if (d == null) return '—';
    try {
      final dt = DateTime.parse(d);
      const m = [
        'JAN',
        'FEB',
        'MAR',
        'APR',
        'MAY',
        'JUN',
        'JUL',
        'AUG',
        'SEP',
        'OCT',
        'NOV',
        'DEC',
      ];
      return '${m[dt.month - 1]} ${dt.day}';
    } catch (_) {
      return d;
    }
  }

  String _formatTime(Map<String, dynamic> e) {
    final s = e['start_time'] as String?;
    final en = e['end_time'] as String?;
    if (s == null) return '—';
    String fmt(String t) {
      final p = t.split(':');
      if (p.length < 2) return t;
      final h = int.tryParse(p[0]) ?? 0;
      return '${h % 12 == 0 ? 12 : h % 12}:${p[1]} ${h >= 12 ? 'PM' : 'AM'}';
    }

    return en != null ? '${fmt(s)} — ${fmt(en)}' : fmt(s);
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _openCreate() {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateEventScreen()),
    ).then((_) => _loadData());
  }

  void _openDetails(Map<String, dynamic> e) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EventDetailsScreen(eventData: e)),
    ).then((_) => _loadData());
  }

  void _openManage(Map<String, dynamic> e) {
    if (!_canEditEvent(e)) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ManageEventScreen(eventData: e)),
    ).then((_) => _loadData());
  }

  bool _canEditEvent(Map<String, dynamic> event) {
    final status = _statusLabel(event);
    return status != 'Ongoing' && status != 'Ended';
  }

  Future<void> _confirmDeleteEvent(Map<String, dynamic> event) async {
    final eventId = event['event_id'] as String?;
    if (eventId == null || _organizerId == null) return;

    var confirmed = false;
    await AppAlert.confirm(
      context,
      title: 'Delete Event?',
      message:
          'Are you sure you want to delete "${event['title'] ?? 'this event'}"? '
          'All registrations for this event will also be permanently removed. '
          'This cannot be undone.',
      confirmText: 'Delete',
      cancelText: 'Cancel',
      onConfirm: () => confirmed = true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _deletingEventId = eventId);
    try {
      final client = Supabase.instance.client;
      final registrations = await client
          .from('registrations')
          .select()
          .eq('event_id', eventId);
      final savedRegistrations = List<Map<String, dynamic>>.from(
        registrations as List,
      );

      await client.from('registrations').delete().eq('event_id', eventId);

      try {
        final deleted = await client
            .from('events')
            .delete()
            .eq('event_id', eventId)
            .eq('organizer_id', _organizerId!)
            .select('event_id');
        if ((deleted as List).isEmpty) {
          throw Exception('The event could not be deleted.');
        }
      } catch (deleteError) {
        if (savedRegistrations.isNotEmpty) {
          try {
            await client.from('registrations').insert(savedRegistrations);
          } catch (restoreError) {
            throw StateError(
              'Event deletion failed and its registrations could not be '
              'restored: $restoreError',
            );
          }
        }
        rethrow;
      }

      AuditService.logEvent(
        action: 'deleted',
        eventTitle: event['title'] as String? ?? 'Unknown event',
        eventId: eventId,
        organizerId: _organizerId,
        details: savedRegistrations.isEmpty
            ? 'Event deleted (no registrations)'
            : 'Event deleted · ${savedRegistrations.length} registration'
                  '${savedRegistrations.length == 1 ? '' : 's'} removed',
      );

      if (!mounted) return;
      _events.removeWhere((item) => item['event_id'] == eventId);
      _registrationCountMap.remove(eventId);
      _checkedInMap.remove(eventId);
      setState(() => _deletingEventId = null);
      _applyFilter();
    } catch (error) {
      if (!mounted) return;
      setState(() => _deletingEventId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to delete event: '
            '${error.toString().replaceFirst('Exception: ', '')}',
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
                  : _loadError
                  ? _buildErrorState(t)
                  : RefreshIndicator(
                      color: kGold,
                      backgroundColor: t.card,
                      onRefresh: _loadData,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(child: _buildHeader(t)),
                          SliverToBoxAdapter(child: _buildSearchBar(t)),
                          SliverToBoxAdapter(child: _buildCreateButton()),
                          SliverToBoxAdapter(child: _buildFilterRow(t)),
                          if (_filtered.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: _buildEmptyState(t),
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (_, i) => _buildEventCard(_filtered[i], t),
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

  // ── Loading state ──────────────────────────────────────────────────────────

  Widget _buildLoadingState(AppTk t) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        children: [
          _buildHeader(t),
          _buildSearchBar(t),
          const SizedBox(height: 8),
          const AppShimmerList(itemCount: 4, hasAvatar: false, hasImage: true),
        ],
      ),
    );
  }

  // ── Error state ────────────────────────────────────────────────────────────

  Widget _buildErrorState(AppTk t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.22),
                ),
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                size: 32,
                color: Color(0xFFEF4444),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Could not load events',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check your connection and try again.',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: t.muted,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text(
                'Retry',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: kGold,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Standalone top bar (non-embedded mode) ────────────────────────────────

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
            child: Text(
              'My Events',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: t.text,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header — matches the student events tab pattern ───────────────────────

  Widget _buildHeader(AppTk t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFC49230), kGold, Color(0xFFEAB866)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            'My Events',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: t.text,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }

  // ── Search bar ─────────────────────────────────────────────────────────────

  Widget _buildSearchBar(AppTk t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Container(
        decoration: BoxDecoration(
          color: t.inputBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.border),
          boxShadow: [
            BoxShadow(
              color: t.shadow,
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (_) => _applyFilter(),
          style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: t.text),
          decoration: InputDecoration(
            hintText: 'Search events, venue, or type…',
            hintStyle: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: t.muted,
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: kGold,
              size: 22,
            ),
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.cancel_rounded, color: t.muted, size: 20),
                    onPressed: () {
                      _searchCtrl.clear();
                      _applyFilter();
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
              borderSide: const BorderSide(color: kGold, width: 1.8),
            ),
          ),
        ),
      ),
    );
  }

  // ── Create new event (gradient CTA — parallels the student shortcut) ───────

  Widget _buildCreateButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: GestureDetector(
        onTap: _openCreate,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFC49230), kGold, Color(0xFFE8C26C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: kGold.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Create New Event',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Publish a school event for students',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11.5,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white,
                  size: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Filter chips with live count badges ────────────────────────────────────

  Widget _buildFilterRow(AppTk t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SizedBox(
        height: 38,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: _filterOptions.length,
          itemBuilder: (_, i) {
            final f = _filterOptions[i];
            final selected = _filter == f;
            final count = _countFor(f);

            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _filter = f);
                _applyFilter();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  gradient: selected ? kGoldGradient : null,
                  color: selected ? null : t.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected ? const Color(0xFFC49230) : t.border,
                    width: 1.5,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: kGold.withValues(alpha: 0.28),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      f,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : t.sub,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.white.withValues(alpha: 0.25)
                            : t.divider,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: selected ? Colors.white : t.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Event card — image header, meta, capacity + check-in stats, actions
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildEventCard(Map<String, dynamic> e, AppTk t) {
    final eventId = e['event_id'] as String;
    final title = e['title'] as String? ?? '—';
    final location = e['location'] as String? ?? '—';
    final type = e['event_type'] as String?;
    final imageUrl = e['event_image_url'] as String?;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final registered =
        _registrationCountMap[eventId] ??
        (e['current_participants'] as int? ?? 0);
    final capacity = e['max_participants'] as int?;
    final checkedIn = _checkedInMap[eventId] ?? 0;
    final statusLabel = _statusLabel(e);
    final canEdit = _canEditEvent(e);
    final statusColor = _statusColor(statusLabel);
    final approval = e['approval_status'] as String? ?? 'approved';
    final needsAttention = approval != 'approved';
    final maxSet = capacity != null && capacity > 0;
    final isFull = maxSet && registered >= capacity;
    final attendancePct = registered > 0
        ? ((checkedIn / registered) * 100).round()
        : 0;
    final shortId = eventId.length > 8
        ? '…${eventId.substring(eventId.length - 8)}'
        : eventId;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.border),
        boxShadow: [
          BoxShadow(
            color: t.shadow,
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Image header: date pill + status chip ────────────────────────
          GestureDetector(
            onTap: () => _openDetails(e),
            child: Stack(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 150,
                  child: hasImage
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _imagePlaceholder(t),
                        )
                      : _imagePlaceholder(t),
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      statusLabel,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: IconButton(
                    tooltip: 'Delete event',
                    onPressed: _deletingEventId == eventId
                        ? null
                        : () => _confirmDeleteEvent(e),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.55),
                      foregroundColor: const Color(0xFFEF4444),
                      disabledBackgroundColor: Colors.black.withValues(
                        alpha: 0.55,
                      ),
                      disabledForegroundColor: const Color(0xFFEF4444),
                      minimumSize: const Size(40, 40),
                      maximumSize: const Size(40, 40),
                      padding: EdgeInsets.zero,
                    ),
                    icon: _deletingEventId == eventId
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.delete_outline_rounded,
                            color: Color(0xFFEF4444),
                            size: 20,
                          ),
                  ),
                ),
                // Only shown while it needs the organizer's attention —
                // "Approved" is the normal, expected state and would just
                // be noise on every card.
                if (needsAttention)
                  Positioned(
                    top: 46,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: approvalStatusColor(approval),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            approval == 'rejected'
                                ? Icons.block_rounded
                                : Icons.pending_actions_rounded,
                            size: 11,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            approvalStatusLabel(approval),
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Body ─────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title + type chip
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          color: t.text,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (type != null && type.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: kGold.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: kGold.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          type,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFB8861C),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  shortId,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11.5,
                    color: t.muted,
                  ),
                ),
                const SizedBox(height: 12),

                // ── Venue + schedule panel ──────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: kGold.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kGold.withValues(alpha: 0.14)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_month_rounded,
                            size: 13,
                            color: t.sub,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _formatDate(e),
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: t.sub,
                            ),
                          ),
                          Text(
                            '  ·  ',
                            style: TextStyle(fontSize: 12.5, color: t.muted),
                          ),
                          Icon(
                            Icons.access_time_rounded,
                            size: 13,
                            color: t.sub,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              _formatTime(e),
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12.5,
                                color: t.sub,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            size: 15,
                            color: kGold,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              location,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: t.sub,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(
                            Icons.people_alt_outlined,
                            size: 13,
                            color: isFull ? const Color(0xFFEF4444) : kGold,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$registered / ${maxSet ? capacity : '∞'}',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: isFull ? const Color(0xFFEF4444) : t.sub,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ── Stats: Checked In / Attendance ───────────────────────
                IntrinsicHeight(
                  child: Row(
                    children: [
                      _statCol(
                        '$checkedIn',
                        'Checked In',
                        const Color(0xFF16A34A),
                        t,
                        first: true,
                      ),
                      Container(width: 1, color: t.divider),
                      _statCol(
                        '$attendancePct%',
                        'Attendance',
                        const Color(0xFF3B82F6),
                        t,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: t.divider),
                const SizedBox(height: 14),

                // ── Actions ─────────────────────────────────────────────
                Row(
                  children: [
                    if (canEdit) ...[
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: ElevatedButton(
                            onPressed: () => _openManage(e),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kGold,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Edit',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: OutlinedButton(
                          onPressed: () => _openDetails(e),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kGold,
                            side: BorderSide(
                              color: kGold.withValues(alpha: 0.55),
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Details',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
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
    );
  }

  Widget _statCol(
    String value,
    String label,
    Color color,
    AppTk t, {
    bool first = false,
  }) {
    return Expanded(
      child: Padding(
        padding: EdgeInsets.fromLTRB(first ? 0 : 12, 0, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11.5,
                color: t.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePlaceholder(AppTk t) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            kGold.withValues(alpha: 0.14),
            kGold.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.event_rounded,
          size: 42,
          color: kGold.withValues(alpha: 0.35),
        ),
      ),
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────────

  Widget _buildEmptyState(AppTk t) {
    final isFiltered = _filter != 'All' || _searchCtrl.text.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: kGold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kGold.withValues(alpha: 0.18)),
            ),
            child: Icon(
              isFiltered ? Icons.search_off_rounded : Icons.event_busy_rounded,
              size: 32,
              color: kGold.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isFiltered ? 'No results found' : 'No events yet',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isFiltered
                ? 'Try a different search or filter.'
                : 'Create your first event to get started.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12.5,
              color: t.muted,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 24),
          if (isFiltered)
            OutlinedButton(
              onPressed: () {
                _searchCtrl.clear();
                setState(() => _filter = 'All');
                _applyFilter();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: kGold,
                side: const BorderSide(color: kGold, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'Clear filters',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: kGold,
                ),
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: _openCreate,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text(
                'Create Event',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: kGold,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

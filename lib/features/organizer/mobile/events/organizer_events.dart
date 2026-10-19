import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'create_event_screen.dart';
import 'event_actions.dart';
import 'event_details.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../../../shared/widgets/error_alert.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/services/audit_service.dart';
import '../../../../core/services/event_cancellation_service.dart';
import '../../../../core/services/student_count_service.dart';
import '../../../../shared/utils/event_labels.dart';
import '../../../../shared/utils/realtime_utils.dart';

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
  // Every event's capacity = active students (StudentCountService).
  int? _studentCount = StudentCountService.cached;

  static const _filterOptions = [
    'All',
    'Upcoming',
    'Ongoing',
    'Ended',
    'Cancelled',
    'Rejected',
    'Archived',
  ];

  // Live updates — same tables as the web Events page.
  RealtimeChannel? _channel;
  Timer? _debounce;
  bool _fetching = false; // a load is running…
  bool _refetch = false; // …and another change arrived meanwhile

  @override
  void initState() {
    super.initState();
    _loadData();
    _subscribeRealtime();
    _statusTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) _applyFilter();
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _debounce?.cancel();
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Live updates ────────────────────────────────────────────────────────────
  // New registrations, check-ins, admin approvals / rejections and edits made
  // on the web show up without pulling to refresh.

  void _subscribeRealtime() {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final channel = Supabase.instance.client.channel('org-mobile-events-$uid');
    for (final table in const ['events', 'registrations']) {
      channel.on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(event: '*', schema: 'public', table: table),
        (payload, [ref]) {
          if (_concernsMyEvents(table, payload)) _scheduleRefresh();
        },
      );
    }
    _channel = channel..subscribe();
  }

  // Other organizers' activity arrives on the same tables — skip it.
  bool _concernsMyEvents(String table, Object? payload) {
    if (_organizerId == null) return true; // not loaded yet
    final row = realtimeRow(payload);
    if (row == null) return true;
    bool mine(Object? eventId) => _events.any((e) => e['event_id'] == eventId);
    if (table == 'events') {
      final org = row['organizer_id'];
      return org != null ? org == _organizerId : mine(row['event_id']);
    }
    final eventId = row['event_id'];
    // A deleted registration only carries its id — refresh to be safe.
    return eventId == null || mine(eventId);
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted && !_loading) _loadData(silent: true);
    });
  }

  // ── Data loading ────────────────────────────────────────────────────────────

  /// [silent]: refresh in place (live updates, pull-to-refresh, coming back
  /// from another screen) — no shimmer, the scroll position and filter stay,
  /// and a failure keeps the list that's on screen.
  Future<void> _loadData({bool silent = false}) async {
    if (_fetching) {
      _refetch = true;
      return;
    }
    _fetching = true;
    if (!silent) {
      setState(() {
        _loading = true;
        _loadError = false;
      });
    }
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      if (_organizerId == null) {
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
      }

      final studentCount = StudentCountService.activeStudents(); // in parallel
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
      final students = await studentCount;

      if (mounted) {
        setState(() {
          _events = events;
          _studentCount = students;
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
      if (mounted && !silent) {
        setState(() {
          _loading = false;
          _loadError = true;
        });
      }
    } finally {
      _fetching = false;
      if (_refetch && mounted) {
        _refetch = false;
        _loadData(silent: true);
      }
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.toLowerCase();
    _filtered = _events.where((e) {
      final label = _statusLabel(e);
      final approval = (e['approval_status'] as String? ?? 'approved')
          .toLowerCase();
      final matchFilter = eventIsArchived(e)
          ? _filter == 'Archived'
          : _filter == 'All' ||
                (_filter == 'Rejected'
                    ? approval == 'rejected'
                    : approval != 'rejected' && label == _filter);
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

    // Cancelled tab: most recently cancelled first.
    if (_filter == 'Cancelled') {
      _filtered.sort((a, b) => _cancelledAt(b).compareTo(_cancelledAt(a)));
      setState(() {});
      return;
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
    if (filter == 'Archived') return _events.where(eventIsArchived).length;
    final active = _events.where((e) => !eventIsArchived(e));
    if (filter == 'All') return active.length;
    if (filter == 'Rejected') {
      return active
          .where(
            (e) =>
                (e['approval_status'] as String? ?? 'approved').toLowerCase() ==
                'rejected',
          )
          .length;
    }
    return active.where((e) {
      final approval = (e['approval_status'] as String? ?? 'approved')
          .toLowerCase();
      return approval != 'rejected' && _statusLabel(e) == filter;
    }).length;
  }

  // When the event was cancelled (rows cancelled before the cancellation
  // migration have no cancelled_at — fall back to updated_at).
  DateTime _cancelledAt(Map<String, dynamic> e) =>
      DateTime.tryParse(e['cancelled_at'] as String? ?? '')?.toLocal() ??
      DateTime.tryParse(e['updated_at'] as String? ?? '')?.toLocal() ??
      DateTime(2000);

  // ── Status helpers ─────────────────────────────────────────────────────────

  // event_status only ever holds upcoming/ongoing/completed/cancelled (DB
  // CHECK constraint) — draft/pending were never real values here. Approval
  // state (pending admin review / rejected) is a separate concept, shown as
  // its own badge in _buildEventCard, not folded into this lifecycle label.
  String _statusLabel(Map<String, dynamic> e) => eventStatusLabel(e);

  // Same compact labels as the web Events table, no year: "Oct 25",
  // "Oct 25–27", "Oct 30 – Nov 2".
  String _dateLabel(Map<String, dynamic> e) {
    final start = DateTime.tryParse(e['event_date'] as String? ?? '');
    if (start == null) return '—';
    return dateRangeLabel(
      start,
      DateTime.tryParse(e['end_date'] as String? ?? ''),
    );
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  // Coming back refreshes in place — no shimmer, the scroll position stays.
  void _openCreate() {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateEventScreen()),
    ).then((_) => _loadData(silent: true));
  }

  void _openDetails(Map<String, dynamic> e) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EventDetailsScreen(eventData: e)),
    ).then((_) => _loadData(silent: true));
  }

  // Full edit form — schedule and banner included, like the web.
  void _openManage(Map<String, dynamic> e) {
    if (!organizerCanEditEvent(e)) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CreateEventScreen(existing: e)),
    ).then((_) => _loadData(silent: true));
  }

  // Events with registrations are never deleted — that would erase students'
  // registrations and attendance. Offer to cancel instead (server enforces too).
  Future<void> _confirmDeleteEvent(Map<String, dynamic> event) async {
    final eventId = event['event_id'] as String?;
    // The list may be stale — an event that has since ended can't be deleted.
    if (eventId == null ||
        _organizerId == null ||
        _statusLabel(event) == 'Ended' ||
        eventIsArchived(event)) {
      return;
    }
    final title = event['title'] as String? ?? 'this event';

    final count = await EventCancellationService.registrationCount(eventId);
    if (!mounted) return;
    if (count > 0) {
      final cancellable = organizerCanCancelEvent(event);
      var cancelInstead = false;
      await AppAlert.confirm(
        context,
        title: 'This event can’t be deleted',
        message:
            '"$title" has $count registration${count == 1 ? '' : 's'}. Deleting it '
            'would erase their registrations and attendance records.'
            '${cancellable ? ' Cancel it instead — students are notified and records are kept.' : ''}',
        confirmText: cancellable ? 'Cancel Event Instead' : 'OK',
        cancelText: 'Close',
        onConfirm: () => cancelInstead = true,
      );
      if (cancelInstead &&
          cancellable &&
          mounted &&
          await cancelEventFlow(context, event, registrationCount: count)) {
        _loadData(silent: true);
      }
      return;
    }

    var confirmed = false;
    await AppAlert.confirm(
      context,
      title: 'Delete Event?',
      message:
          'Delete "$title"? Nobody has registered yet. This cannot be undone.',
      confirmText: 'Delete',
      cancelText: 'Keep',
      onConfirm: () => confirmed = true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _deletingEventId = eventId);
    try {
      final deleted = await Supabase.instance.client
          .from('events')
          .delete()
          .eq('event_id', eventId)
          .eq('organizer_id', _organizerId!)
          .select('event_id');
      if ((deleted as List).isEmpty) {
        throw Exception('The event could not be deleted.');
      }

      AuditService.logEvent(
        action: 'deleted',
        eventTitle: title,
        eventId: eventId,
        organizerId: _organizerId,
        details: 'Event deleted (no registrations)',
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
      showErrorAlert(context, error, title: 'Couldn’t delete the event');
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
                      onRefresh: () => _loadData(silent: true),
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
    // Capacity = every active student (null until the count loads).
    final capacity = _studentCount;
    final checkedIn = _checkedInMap[eventId] ?? 0;
    final statusLabel = _statusLabel(e);
    final canEdit = organizerCanEditEvent(e);
    final archived = eventIsArchived(e);
    // One status, nothing under it — the same words and colours as the web
    // Events table (reasons and deadlines are in the event's details).
    final status = organizerEventStatus(e);
    final time = timeRangeLabel(
      e['start_time'] as String?,
      e['end_time'] as String?,
    );
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
          // ── Image header: status chip + delete ───────────────────────────
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
                  child: _StatusChip(
                    label: status.label,
                    color: status.color,
                    t: t,
                  ),
                ),
                // Ended events are part of the record — no delete.
                if (statusLabel != 'Ended' && !archived)
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
                            _dateLabel(e),
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: t.sub,
                            ),
                          ),
                          if (time.isNotEmpty) ...[
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
                                time,
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
                          const Icon(
                            Icons.people_alt_outlined,
                            size: 13,
                            color: kGold,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            capacity != null
                                ? '$registered / $capacity students'
                                : '$registered registered',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: t.sub,
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
    // An empty Cancelled tab (no search) is good news, not a failed filter.
    final noneCancelled = _filter == 'Cancelled' && _searchCtrl.text.isEmpty;
    final noneArchived = _filter == 'Archived' && _searchCtrl.text.isEmpty;

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
              noneArchived
                  ? Icons.inventory_2_outlined
                  : noneCancelled
                  ? Icons.event_available_rounded
                  : isFiltered
                  ? Icons.search_off_rounded
                  : Icons.event_busy_rounded,
              size: 32,
              color: kGold.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            noneArchived
                ? 'No archived events'
                : noneCancelled
                ? 'No cancelled events'
                : isFiltered
                ? 'No results found'
                : 'No events yet',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            noneArchived
                ? 'The administrator archives finished events. They show here, read-only.'
                : noneCancelled
                ? 'Events you cancel appear here with the reason students were given.'
                : isFiltered
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
              child: Text(
                noneCancelled ? 'Show all events' : 'Clear filters',
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

// ── Status chip ─────────────────────────────────────────────────────────────
// The event's one status, nothing under it: the same words, colours and dot
// as the web Events table's pill (organizerEventStatus), on a solid card so
// it reads over any banner image.

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final AppTk t;
  const _StatusChip({
    required this.label,
    required this.color,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Status: $label',
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 5, 11, 5),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.2,
                color: readableStatusColor(color, t.dark),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

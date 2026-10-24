import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'create_event_screen.dart';
import 'event_actions.dart';
import 'event_details.dart';
import 'organizer_events_ui.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../../../shared/widgets/error_alert.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/services/audit_service.dart';
import '../../../../core/services/event_cancellation_service.dart';
import '../../../../core/services/student_count_service.dart';
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
          // Declined registrations don't count as registered.
          if (!countsAsRegistered(r as Map<String, dynamic>)) continue;
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
      final approval = approvalStatusOf(e);
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
      return active.where((e) => approvalStatusOf(e) == 'rejected').length;
    }
    return active.where((e) {
      final approval = approvalStatusOf(e);
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
    // The list may be stale — an approved event that has since ended can't
    // be deleted.
    if (eventId == null ||
        _organizerId == null ||
        !organizerCanDeleteEvent(event)) {
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
  // BUILD — the look lives in organizer_events_ui.dart
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
                          // The filters stay in reach while the list scrolls.
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: OrgFilterBarDelegate(
                              (scrolled) => _buildFilterRow(t, scrolled: scrolled),
                            ),
                          ),
                          if (_filtered.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: _buildEmptyState(t),
                            )
                          else
                            SliverPadding(
                              // Bottom room so the AI assistant button never
                              // covers the last card's buttons.
                              padding: const EdgeInsets.fromLTRB(20, 12, 20, 104),
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
      child: SingleChildScrollView(
        child: OrgMessage(
          icon: Icons.wifi_off_rounded,
          isError: true,
          title: 'Could not load events',
          message: 'Check your connection and try again.',
          action: OrgPrimaryButton(
            label: 'Retry',
            icon: Icons.refresh_rounded,
            onPressed: _loadData,
          ),
          t: t,
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

  // ── Header, search, filters ────────────────────────────────────────────────

  Widget _buildHeader(AppTk t) => OrgEventsHeader(
    onCreate: _openCreate,
    t: t,
  );

  Widget _buildSearchBar(AppTk t) => OrgSearchField(
    controller: _searchCtrl,
    hint: 'Search events, venue, or type…',
    onChanged: (_) => _applyFilter(),
    onClear: () {
      _searchCtrl.clear();
      _applyFilter();
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
    child: CompactFilterMenu<String>(
      label: 'Status',
      icon: Icons.filter_list_rounded,
      selected: _filter,
      accent: kGold,
      t: t,
      options: [
        for (final status in _filterOptions)
          CompactFilterOption(
            value: status,
            label: status,
            count: _countFor(status),
            color: switch (status) {
              'Upcoming' => eventStatusColor('Upcoming'),
              'Ongoing' => eventStatusColor('Ongoing'),
              'Ended' => eventStatusColor('Ended'),
              'Cancelled' => eventStatusColor('Cancelled'),
              'Rejected' => approvalStatusColor('rejected'),
              'Archived' => kArchivedColor,
              _ => null,
            },
          ),
      ],
      onSelect: (status) {
        HapticFeedback.selectionClick();
        setState(() => _filter = status);
        _applyFilter();
      },
    ),
  );

  // ── Event card ─────────────────────────────────────────────────────────────

  Widget _buildEventCard(Map<String, dynamic> e, AppTk t) {
    final eventId = e['event_id'] as String;
    return OrganizerEventCard(
      key: ValueKey(eventId),
      event: e,
      registered:
          _registrationCountMap[eventId] ??
          (e['current_participants'] as int? ?? 0),
      // Capacity = every active student (null until the count loads).
      capacity: _studentCount,
      checkedIn: _checkedInMap[eventId] ?? 0,
      canEdit: organizerCanEditEvent(e),
      // Ended live events are part of the record — no delete.
      canDelete: organizerCanDeleteEvent(e),
      deleting: _deletingEventId == eventId,
      onOpen: () => _openDetails(e),
      onEdit: () => _openManage(e),
      onDelete: () => _confirmDeleteEvent(e),
      t: t,
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────────

  Widget _buildEmptyState(AppTk t) {
    final isFiltered = _filter != 'All' || _searchCtrl.text.isNotEmpty;
    // An empty Cancelled tab (no search) is good news, not a failed filter.
    final noneCancelled = _filter == 'Cancelled' && _searchCtrl.text.isEmpty;
    final noneArchived = _filter == 'Archived' && _searchCtrl.text.isEmpty;

    return OrgMessage(
      icon: noneArchived
          ? Icons.inventory_2_outlined
          : noneCancelled
          ? Icons.event_available_rounded
          : isFiltered
          ? Icons.search_off_rounded
          : Icons.event_busy_rounded,
      title: noneArchived
          ? 'No archived events'
          : noneCancelled
          ? 'No cancelled events'
          : isFiltered
          ? 'No results found'
          : 'No events yet',
      message: noneArchived
          ? 'The administrator archives finished events. They show here, read-only.'
          : noneCancelled
          ? 'Events you cancel appear here with the reason students were given.'
          : isFiltered
          ? 'Try a different search or filter.'
          : 'Create your first event to get started.',
      action: isFiltered
          ? OrgSecondaryButton(
              label: noneCancelled ? 'Show all events' : 'Clear filters',
              icon: Icons.filter_alt_off_outlined,
              onPressed: () {
                _searchCtrl.clear();
                setState(() => _filter = 'All');
                _applyFilter();
              },
              t: t,
            )
          : OrgPrimaryButton(
              label: 'Create Event',
              icon: Icons.add_rounded,
              onPressed: _openCreate,
            ),
      t: t,
    );
  }
}

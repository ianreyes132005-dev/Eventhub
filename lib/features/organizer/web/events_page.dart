import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/app_colors.dart';
import '../../../core/friendly_error.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/services/event_cancellation_service.dart';
import '../../../core/services/event_change_request_service.dart';
import '../../../core/services/student_count_service.dart';
import '../../../shared/widgets/cancel_event_dialog.dart';
import 'web_shared.dart';
import 'student_registration_panel.dart';
import 'attendance_export_dialog.dart';
import 'event_table_cells.dart';
import '../../../shared/utils/event_form_validation.dart';
import '../../../shared/widgets/form_errors.dart';
import '../../../shared/widgets/stepped_wheel.dart';
import '../../../shared/utils/realtime_utils.dart';

// ── Banner upload constraints ─────────────────────────────────────────────
const _kAllowedBannerExts = {'jpg', 'jpeg', 'png', 'webp'};

// Stands in for a newly picked banner while comparing changes — the file is
// only uploaded once the organizer confirms.
const _kNewBanner = '\u0000new-banner';

String _bannerContentType(String ext) {
  switch (ext) {
    case 'jpg':
    case 'jpeg': return 'image/jpeg';
    case 'png':  return 'image/png';
    case 'webp': return 'image/webp';
    default:     return 'application/octet-stream';
  }
}

// Returns the display status for an event, overriding 'upcoming'/'ongoing'
// with 'ended' when the event's end time (or whole event day) has passed.
String _resolveDisplayStatus(Map<String, dynamic> event) {
  return eventStatusValue(event);
}

TimeOfDay _suggestedEndTime(TimeOfDay? start) {
  if (start == null) return const TimeOfDay(hour: 17, minute: 0);
  return TimeOfDay(hour: (start.hour + 1) % 24, minute: start.minute);
}

// End date / time accent. Not red: on the event form red only means an error.
const _kEndAccent = Color(0xFF4F46E5);

// Event type definitions
const _kTypes = [
  ('Concert',  Icons.music_note_rounded,   Color(0xFF7C3AED)),
  ('Sports',   Icons.sports_rounded,       Color(0xFF2563EB)),
  ('Workshop', Icons.build_rounded,        Color(0xFFEA580C)),
  ('Seminar',  Icons.school_rounded,       Color(0xFF0D9488)),
  ('Other',    Icons.more_horiz_rounded,   Color(0xFF6B7280)),
];

class WebEventsPage extends StatefulWidget {
  final String? orgId;
  const WebEventsPage({super.key, this.orgId});

  @override
  State<WebEventsPage> createState() => _WebEventsPageState();
}

class _WebEventsPageState extends State<WebEventsPage> with SingleTickerProviderStateMixin {
  bool   _loading = true;
  String _filter  = 'All';
  String _sortField = 'event_date';
  bool _sortAsc = false;
  bool _sortTouched = false;
  // Capacity of every event = active students (StudentCountService).
  int?   _studentCount = StudentCountService.cached;
  final  _search  = TextEditingController();
  final  _tableScroll = ScrollController();   // sideways, on narrow screens
  List<Map<String, dynamic>> _events    = [];
  List<Map<String, dynamic>> _displayed = [];

  final _filters = [
    'All',
    'Upcoming',
    'Ongoing',
    'Ended',
    'Cancelled',
    'Rejected',
    'Archived',
  ];


  late final AnimationController _staggerCtrl;
  RealtimeChannel? _channel;
  Timer?           _debounce;
  Timer?           _statusTimer;

  @override
  void initState() {
    super.initState();
    _staggerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _search.addListener(_applyFilter);
    _load();
    _subscribeRealtime();
    _statusTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) _applyFilter();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _statusTimer?.cancel();
    if (_channel != null) SupabaseService.client.removeChannel(_channel!);
    _staggerCtrl.dispose();
    _search.dispose();
    _tableScroll.dispose();
    super.dispose();
  }

  void _subscribeRealtime() {
    _channel = SupabaseService.client.channel('org-events-${widget.orgId}');
    for (final table in ['events', 'registrations']) {
      _channel!.on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(event: '*', schema: 'public', table: table),
        (_, [a]) => _debounceLoad(),
      );
    }
    // The admin's answer to a change request only touches event_revisions
    // when it's a rejection — "Your last changes were rejected" shows at once.
    if (widget.orgId != null) {
      _channel!.on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(
          event: '*',
          schema: 'public',
          table: 'event_revisions',
          filter: 'organizer_id=eq.${widget.orgId}',
        ),
        (_, [a]) => _debounceLoad(),
      );
    }
    _channel!.subscribe();
  }

  void _debounceLoad() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted && !_loading) _load(silent: true);
    });
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

  Future<void> _load({bool silent = false}) async {
    if (widget.orgId == null) return;
    if (!silent) setState(() => _loading = true);
    try {
      final rows = await SupabaseService.client
          .from('events')
          .select()
          .eq('organizer_id', widget.orgId!)
          .order('event_date', ascending: false);
      final events = List<Map<String, dynamic>>.from(rows as List);
      final more = await Future.wait<Object?>([
        EventChangeRequestService.latestFor(events.map((e) => e['event_id'] as String)),
        StudentCountService.activeStudents(),
      ]);
      if (!mounted) return;
      _events = events;
      _revisions = more[0] as Map<String, Map<String, dynamic>>;
      _studentCount = more[1] as int?;
      _applyFilter();
      setState(() => _loading = false);
      _staggerCtrl.forward(from: 0);
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        _staggerCtrl.forward(from: 0);
      }
    }
  }

  void _applyFilter() {
    final q = _search.text.toLowerCase();
    setState(() {
      _displayed = _events.where((e) {
        final status = _resolveDisplayStatus(e);
        final approval = approvalStatusOf(e);
        final title  = (e['title'] as String? ?? '').toLowerCase();
        final loc    = (e['location'] as String? ?? '').toLowerCase();
        final type   = (e['event_type'] as String? ?? '').toLowerCase();
        // Archived events (admin) only show under the Archived filter.
        final matchFilter = eventIsArchived(e)
            ? _filter == 'Archived'
            : _filter == 'All' ||
                (_filter == 'Rejected'
                    ? approval == 'rejected'
                    : approval != 'rejected' &&
                        status == _filter.toLowerCase());
        final matchSearch = q.isEmpty ||
            title.contains(q) || loc.contains(q) || type.contains(q);
        return matchFilter && matchSearch;
      }).toList();
      if (_filter == 'Cancelled' && !_sortTouched) {
        _displayed.sort((a, b) => _cancelledAt(b).compareTo(_cancelledAt(a)));
      } else {
        _displayed.sort((a, b) {
          final comparison = switch (_sortField) {
            'title' => (a['title'] as String? ?? '')
                .toLowerCase()
                .compareTo((b['title'] as String? ?? '').toLowerCase()),
            'location' => (a['location'] as String? ?? '')
                .toLowerCase()
                .compareTo((b['location'] as String? ?? '').toLowerCase()),
            'registered' => ((a['current_participants'] as num?)?.toInt() ?? 0)
                .compareTo(
                  (b['current_participants'] as num?)?.toInt() ?? 0,
                ),
            'status' => _resolveDisplayStatus(a)
                .compareTo(_resolveDisplayStatus(b)),
            _ => _eventDate(a).compareTo(_eventDate(b)),
          };
          return _sortAsc ? comparison : -comparison;
        });
      }
    });
  }

  DateTime _eventDate(Map<String, dynamic> event) =>
      DateTime.tryParse(event['event_date'] as String? ?? '') ??
      DateTime(2000);

  DateTime _cancelledAt(Map<String, dynamic> event) =>
      DateTime.tryParse(event['cancelled_at'] as String? ?? '') ??
      DateTime.tryParse(event['updated_at'] as String? ?? '') ??
      DateTime(2000);

  void _setSort(String field) {
    _sortTouched = true;
    if (_sortField == field) {
      _sortAsc = !_sortAsc;
    } else {
      _sortField = field;
      _sortAsc = field == 'title' || field == 'location' || field == 'status';
    }
    _applyFilter();
  }

  Future<void> _openDialog({Map<String, dynamic>? existing}) async {
    if (existing != null && !_canEditEvent(existing)) return;
    final isEdit = existing != null;
    final pending = isEdit ? _pendingRevision(existing) : null;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EventDialog(
        orgId:          widget.orgId,
        existing:       existing,
        pendingChanges: pending?['changes'] as Map<String, dynamic>?,
      ),
    );
    if (!mounted || result == null) return;
    _load();
    // Sent to the admin (change request, or a rejected event resubmitted) →
    // SweetAlert2 success, like the submit confirm.
    if (result == 'requested' || result == 'resubmitted') {
      await Swal.fire(context,
        icon: SwalIcon.success,
        title: result == 'requested' ? 'Submitted!' : 'Resubmitted!',
        text: result == 'requested'
            ? 'An admin will review your changes. The event stays live with its '
              'current details until they’re approved.'
            : 'Your changes were saved and the event is back in the admin’s review '
              'queue. You’ll see it as Pending review until they decide.',
        confirmButtonColor: kSwalGold,
        timer: const Duration(seconds: 4),
        timerProgressBar: true,
      );
      return;
    }
    await WebAlert.success(
      context: context,
      title: result == 'created' ? 'Event Submitted!' : 'Event Updated!',
      message: result == 'created'
          ? 'Your new event has been sent to the admin for approval and will go live once reviewed.'
          : 'Your changes have been saved.',
    );
  }

  // Change requests (edits to live events awaiting admin review), by event_id.
  Map<String, Map<String, dynamic>> _revisions = {};

  Map<String, dynamic>? _pendingRevision(Map<String, dynamic> e) {
    final r = _revisions[e['event_id']];
    return r != null && r['status'] == 'pending' ? r : null;
  }

  Map<String, dynamic>? _rejectedRevision(Map<String, dynamic> e) {
    final r = _revisions[e['event_id']];
    return r != null && r['status'] == 'rejected' ? r : null;
  }

  bool _canEditEvent(Map<String, dynamic> event) => organizerCanEditEvent(event);

  void _openDetails(Map<String, dynamic> e) {
    showDialog(
      context: context,
      builder: (_) => _EventDetailsDialog(event: e),
    );
  }

  // ── Cancel / restore / delete ──────────────────────────────────────────────
  // Cancelling keeps every registration and notifies the students; deleting
  // is only for events nobody has registered for (enforced server-side too).

  bool _isApproved(Map<String, dynamic> e) =>
      (e['approval_status'] as String? ?? 'approved') == 'approved';

  bool _hasEnded(Map<String, dynamic> e) {
    final w = eventWindow(e);
    return w != null && !DateTime.now().isBefore(w.end);
  }

  bool _canCancel(Map<String, dynamic> e) =>
      !eventIsArchived(e) && _isApproved(e) && !eventIsCancelled(e) && !_hasEnded(e);

  bool _canRestore(Map<String, dynamic> e) =>
      !eventIsArchived(e) && eventIsCancelled(e) && !_hasEnded(e);

  // Success notes only — failures get a SweetAlert2 popup (showErrorAlert).
  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
      backgroundColor: const Color(0xFF16A34A),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _cancel(Map<String, dynamic> e) async {
    final id = e['event_id'] as String?;
    if (id == null) return;
    final title = e['title'] as String? ?? 'this event';
    try {
      final count = await EventCancellationService.registrationCount(id);
      if (!mounted) return;
      final reason = await showCancelEventDialog(context,
          eventTitle: title, registrationCount: count);
      if (reason == null) return;
      await EventCancellationService.cancel(
          eventId: id, eventTitle: title, reason: reason, organizerId: widget.orgId);
      _toast(count == 0
          ? 'Event cancelled.'
          : 'Event cancelled · $count student${count == 1 ? '' : 's'} notified.');
      _load();
    } catch (err) {
      if (mounted) showErrorAlert(context, err, title: 'Couldn’t cancel the event');
    }
  }

  Future<void> _restore(Map<String, dynamic> e) async {
    final id = e['event_id'] as String?;
    if (id == null) return;
    final title = e['title'] as String? ?? 'this event';
    final ok = await WebAlert.confirm(
      context:      context,
      title:        'Restore event?',
      message:      '"$title" will be back on. Students can register and check in again '
                    'following the normal schedule rules.',
      confirmLabel: 'Restore',
      confirmColor: const Color(0xFF16A34A),
      icon:         Icons.restore_rounded,
      iconColor:    const Color(0xFF16A34A),
      iconBg:       const Color(0xFFECFDF5),
    );
    if (ok != true) return;
    try {
      await EventCancellationService.restore(
          eventId: id, eventTitle: title, organizerId: widget.orgId);
      _toast('Event restored.');
      _load();
    } catch (err) {
      if (mounted) showErrorAlert(context, err, title: 'Couldn’t restore the event');
    }
  }

  Future<void> _delete(Map<String, dynamic> e) async {
    final id = e['event_id'] as String?;
    // The list may be stale — an approved event that has since ended can't be
    // deleted.
    if (id == null || !organizerCanDeleteEvent(e)) return;
    final title = e['title'] as String? ?? 'this event';

    // Events with registrations are never deleted — that would erase
    // students' registrations and attendance. Offer to cancel instead.
    final int count;
    try {
      count = await EventCancellationService.registrationCount(id);
    } catch (err) {
      if (mounted) showErrorAlert(context, err, title: 'Couldn’t delete the event');
      return;
    }
    if (!mounted) return;
    if (count > 0) {
      final cancelInstead = await WebAlert.confirm(
        context:      context,
        title:        'This event can’t be deleted',
        message:      '"$title" has $count registration${count == 1 ? '' : 's'}. Deleting it '
                      'would erase their registrations and attendance records.'
                      '${_canCancel(e) ? ' Cancel it instead — students are notified and records are kept.' : ''}',
        confirmLabel: _canCancel(e) ? 'Cancel event instead' : 'OK',
        icon:         Icons.inventory_2_outlined,
      );
      if (cancelInstead == true && _canCancel(e)) await _cancel(e);
      return;
    }

    final ok = await WebAlert.confirm(
      context:      context,
      title:        'Delete Event?',
      message:      'Delete "$title"? Nobody has registered yet. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (ok != true) return;
    try {
      final deleted = await SupabaseService.client
          .from('events').delete().eq('event_id', id).select('event_id');
      if ((deleted as List).isEmpty) {
        throw Exception('The event wasn’t deleted — you may not have permission.');
      }
      AuditService.logEvent(
        action: 'deleted',
        eventTitle: title,
        eventId: id,
        organizerId: widget.orgId,
        details: 'Event deleted (no registrations)',
      );
      _load();
    } catch (err) {
      if (mounted) showErrorAlert(context, err, title: 'Couldn’t delete the event');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kGold));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(kWebPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPageHeader(),
          const SizedBox(height: 20),
          _stagger(_buildFilterBar(), start: 0.36, end: 0.66),
          const SizedBox(height: 16),
          WebCard(
            padding: EdgeInsets.zero,
            child: _displayed.isEmpty
              ? _stagger(
                  _filter == 'Archived' && _search.text.isEmpty
                    ? const WebEmptyState(
                        icon: Icons.inventory_2_outlined,
                        title: 'No archived events',
                        subtitle: 'The administrator archives finished events. They '
                            'show here, read-only, and you can still export their attendance.',
                      )
                  : _filter == 'Cancelled' && _search.text.isEmpty
                    // An empty Cancelled tab is good news, not a failed filter.
                    ? const WebEmptyState(
                        icon: Icons.event_available_rounded,
                        title: 'No cancelled events',
                        subtitle: 'Events you cancel appear here with the reason '
                            'students were given. Their registrations are kept.',
                      )
                    : WebEmptyState(
                        icon: Icons.event_busy_rounded,
                        title: _filter == 'All' && _search.text.isEmpty
                          ? 'No events created yet'
                          : 'No events match your filter',
                        subtitle: _filter == 'All' && _search.text.isEmpty
                          ? 'Click "New Event" to create your first event.'
                          : 'Try adjusting your search or filter.',
                        action: WebBtn(
                          label: 'New Event',
                          icon: Icons.add_rounded,
                          onTap: () => _openDialog(),
                        ),
                      ),
                  start: 0.50, end: 0.85,
                )
              : _buildTable(),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildPageHeader() {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);

    return _stagger(
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('Events',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: t.text,
              height: 1.1,
            )),
          const Spacer(),
          WebBtn(label: 'New Event', icon: Icons.add_rounded, onTap: () => _openDialog()),
        ],
      ),
      start: 0.00, end: 0.35,
    );
  }

  Widget _buildFilterBar() {
    // Live counts per status — displayed as badges on each chip so the
    // organizer sees event distribution at a glance without filtering.
    final active = _events.where((e) => !eventIsArchived(e));
    final scheduled = active.where(eventIsApproved);
    final counts = <String, int>{
      'All':       active.length,
      'Upcoming':  scheduled.where((e) => _resolveDisplayStatus(e) == 'upcoming').length,
      'Ongoing':   scheduled.where((e) => _resolveDisplayStatus(e) == 'ongoing').length,
      'Ended':     scheduled.where((e) => _resolveDisplayStatus(e) == 'ended').length,
      'Cancelled': scheduled.where((e) => _resolveDisplayStatus(e) == 'cancelled').length,
      'Rejected':  active.where((e) => approvalStatusOf(e) == 'rejected').length,
      'Archived':  _events.length - active.length,
    };

    // One Status menu instead of seven chips: the chips ran off narrower
    // screens (and laptops at 125% zoom), hiding Rejected and Archived
    // behind a sideways scroll. Every status and its count is one click away.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        WebFilterMenu<String>(
          icon: Icons.filter_list_rounded,
          label: 'Status',
          options: [
            for (final f in _filters)
              WebFilterOption(value: f, label: f, count: counts[f] ?? 0,
                  color: _filterColor(f)),
          ],
          selected: _filter,
          onSelect: (f) {
            setState(() => _filter = f);
            _applyFilter();
          },
        ),
        const Spacer(),
        WebSearchField(
          controller: _search,
          hint: 'Search events…',
          onChanged: (_) {},
        ),
      ],
    );
  }

  // The dot in front of each status in the menu — the table's pill colours.
  static Color _filterColor(String f) => switch (f) {
        'All'       => kGold,
        'Rejected'  => approvalStatusColor('rejected'),
        'Archived'  => kArchivedColor,
        _           => eventStatusColor(f),
      };

  // ── Table ───────────────────────────────────────────────────────────────────
  // One column layout for the header and every row, with a gutter after each
  // column so cells never run into each other. Short, predictable content
  // (counts, status, icons) gets fixed widths so it never truncates; event,
  // date and location share what's left.
  static const _kGutter   = 16.0;
  static const _kRegW     = 104.0;
  static const _kStatusW  = 150.0;
  static const _kActionsW = 150.0;

  Widget _col(int flex, Widget child) => Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.only(right: _kGutter),
          child: child,
        ),
      );

  Widget _fixed(double width, Widget child) => SizedBox(
        width: width + _kGutter,
        child: Padding(
          padding: const EdgeInsets.only(right: _kGutter),
          child: child,
        ),
      );

  Widget _sortableHeader(String label, String field) {
    final active = _sortField == field;
    return InkWell(
      onTap: () => _setSort(field),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            WebColHeader(label),
            const SizedBox(width: 4),
            Icon(
              active
                  ? (_sortAsc
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded)
                  : Icons.unfold_more_rounded,
              size: 13,
              color: active ? kGold : WebTk(
                Theme.of(context).brightness == Brightness.dark,
              ).muted,
            ),
          ],
        ),
      ),
    );
  }

  // What the Status column shows: one pill — the state that matters most,
  // the same as the app's event card (organizerEventStatus) — with nothing
  // under it. An event that isn't approved shows its review state, never a
  // schedule state like "Ongoing". What it means is in the hover text.
  EventStatusView _statusView(Map<String, dynamic> e) {
    final s = organizerEventStatus(e);
    return EventStatusView(s.label, s.color, tip: _statusTip(e, s.label));
  }

  // The context that used to sit under the pill: reasons, the check-in
  // deadline, and any change request on an approved event.
  String? _statusTip(Map<String, dynamic> e, String label) {
    final lines = <String>[];
    switch (label) {
      case 'Archived':
        lines.add('Archived by the administrator — hidden from students’ Events tab. Read-only.');
      case 'Rejected':
        final reason = rejectionReasonOf(e) ?? '';
        if (reason.isNotEmpty) lines.add('Reason: $reason');
        final w = eventWindow(e);
        lines.add(w != null && !DateTime.now().isBefore(w.start)
            ? 'Its date has passed — edit it with a new date to resubmit, or delete it.'
            : 'Edit and save it to resubmit.');
      case 'Pending review':
        lines.add('Waiting for admin approval — students can’t see it yet.');
      case 'Cancelled':
        final reason = (e['cancel_reason'] as String?)?.trim() ?? '';
        final when   = webTimeAgo(e['cancelled_at'] as String? ?? e['updated_at'] as String?);
        lines.add('Cancelled${when.isNotEmpty ? ' $when' : ''}. '
            '${reason.isNotEmpty ? 'Reason: $reason' : 'No reason recorded.'}');
      case 'Check-in open':
        final closes = checkInOpenUntil(e);
        if (closes != null) {
          lines.add('The event has ended — late check-in is open until ${clockLabel(closes)}.');
        }
    }

    // Approved and on the schedule: any change request.
    if (const {'Upcoming', 'Ongoing', 'Ended', 'Check-in open'}.contains(label)) {
      final rejected = _rejectedRevision(e);
      if (_pendingRevision(e) != null) {
        lines.add('Your changes are waiting for admin approval. Students still see the current details.');
      } else if (rejected != null) {
        final reason = (rejected['rejection_reason'] as String?)?.trim() ?? '';
        lines.add(reason.isNotEmpty
            ? 'Your last changes were rejected: $reason'
            : 'Your last changes were rejected.');
      }
    }
    return lines.isEmpty ? null : lines.join('\n');
  }

  // Only what this event allows right now, right-aligned.
  List<Widget> _rowActions(Map<String, dynamic> e, String resolved) => [
    if (_canEditEvent(e))
      _IconBtn(
        icon: Icons.edit_rounded,
        color: const Color(0xFF3B82F6),
        tooltip: 'Edit',
        onTap: () => _openDialog(existing: e),
      ),
    _IconBtn(
      icon: Icons.visibility_outlined,
      color: kGold,
      tooltip: 'Details',
      onTap: () => _openDetails(e),
    ),
    // Ended live events: download the attendance record. One that was never
    // approved had no registrations, so there's nothing to export.
    if (resolved == 'ended' && eventIsApproved(e))
      _IconBtn(
        icon: Icons.download_rounded,
        color: const Color(0xFF16A34A),
        tooltip: 'Export attendance record',
        onTap: () => showAttendanceExportDialog(context, e),
      ),
    // Cancel ↔ restore (approved events that haven't ended).
    if (_canRestore(e))
      _IconBtn(
        icon: Icons.restore_rounded,
        color: const Color(0xFF16A34A),
        tooltip: 'Restore event',
        onTap: () => _restore(e),
      )
    else if (_canCancel(e))
      _IconBtn(
        icon: Icons.event_busy_rounded,
        color: const Color(0xFFF59E0B),
        tooltip: 'Cancel event',
        onTap: () => _cancel(e),
      ),
    // Ended live events and archived ones are part of the record — no delete.
    if (organizerCanDeleteEvent(e))
      _IconBtn(
        icon: Icons.delete_outline_rounded,
        color: const Color(0xFFEF4444),
        tooltip: 'Delete',
        onTap: () => _delete(e),
      ),
  ];

  // Below this width the columns get too tight to read (titles break mid-word),
  // so the table scrolls sideways instead of squeezing.
  static const _kMinTableW = 960.0;

  Widget _buildTable() => LayoutBuilder(
        builder: (context, c) => c.maxWidth >= _kMinTableW
            ? _tableBody()
            : Scrollbar(
                controller: _tableScroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _tableScroll,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(width: _kMinTableW, child: _tableBody()),
                ),
              ),
      );

  Widget _tableBody() {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stagger(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            decoration: BoxDecoration(
              color: t.inputBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: t.border)),
            ),
            child: Row(
              children: [
                _col(3, _sortableHeader('EVENT', 'title')),
                _col(2, _sortableHeader('DATE', 'event_date')),
                _col(2, _sortableHeader('LOCATION', 'location')),
                _fixed(_kRegW, _sortableHeader('REGISTERED', 'registered')),
                _fixed(_kStatusW, _sortableHeader('STATUS', 'status')),
                const SizedBox(
                  width: _kActionsW,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: WebColHeader('ACTIONS'),
                  ),
                ),
              ],
            ),
          ),
          start: 0.48, end: 0.68,
        ),
        ...(_displayed.asMap().entries.map((entry) {
          final i        = entry.key;
          final e        = entry.value;
          final isLast   = i == _displayed.length - 1;
          final resolved = _resolveDisplayStatus(e);
          final type     = e['event_type'] as String?;
          final typeData = _kTypes.firstWhere(
            (t) => t.$1 == type,
            orElse: () => _kTypes.last,
          );
          final current  = e['current_participants'] as int? ?? 0;
          final actions  = _rowActions(e, resolved);
          final s        = 0.55 + (i * 0.07).clamp(0.0, 0.27);

          return _stagger(
            _HoverRow(
              isLast: isLast,
              // The whole row opens the details; the icons keep their own actions.
              onTap: () => _openDetails(e),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                child: Row(
                  children: [
                    _col(3, Row(
                      children: [
                        Container(
                          width: 50, height: 50,
                          decoration: BoxDecoration(
                            color: typeData.$3.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: typeData.$3.withValues(alpha: 0.18)),
                          ),
                          clipBehavior: Clip.hardEdge,
                          child: e['event_image_url'] != null &&
                              (e['event_image_url'] as String).isNotEmpty
                            ? Image.network(
                                e['event_image_url'] as String,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Icon(
                                  typeData.$2, color: typeData.$3, size: 22,
                                ),
                              )
                            : Icon(typeData.$2, color: typeData.$3, size: 22),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e['title'] as String? ?? '—',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: t.text,
                                  height: 1.25,
                                ),
                                // Two lines still fit beside the 50px banner.
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 3),
                              Row(children: [
                                Container(
                                  width: 7, height: 7,
                                  decoration: BoxDecoration(
                                    color: typeData.$3,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(typeData.$1,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 11,
                                    color: typeData.$3,
                                    fontWeight: FontWeight.w600,
                                  )),
                              ]),
                            ],
                          ),
                        ),
                      ],
                    )),
                    _col(2, EventDateCell(event: e)),
                    _col(2, Text(e['location'] as String? ?? '—',
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                          color: t.sub, height: 1.35))),
                    _fixed(_kRegW, EventRegistrationsCell(
                        registered: current, capacity: _studentCount)),
                    _fixed(_kStatusW, EventStatusCell(view: _statusView(e))),
                    SizedBox(
                      width: _kActionsW,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          for (var a = 0; a < actions.length; a++) ...[
                            if (a > 0) const SizedBox(width: 6),
                            actions[a],
                          ],
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

// ── Event create/edit dialog ─────────────────────────────────────────────────

class _EventDialog extends StatefulWidget {
  final String?                  orgId;
  final Map<String, dynamic>?    existing;
  /// Values from an open change request — shown instead of the live values
  /// so the organizer amends what they already proposed.
  final Map<String, dynamic>?    pendingChanges;
  const _EventDialog({this.orgId, this.existing, this.pendingChanges});

  @override
  State<_EventDialog> createState() => _EventDialogState();
}

class _EventDialogState extends State<_EventDialog> {
  final _titleCtrl     = TextEditingController();
  final _descCtrl      = TextEditingController();
  final _locationCtrl  = TextEditingController();
  final _otherTypeCtrl = TextEditingController();
  // Capacity isn't entered — it's every active student.
  int?      _studentCount = StudentCountService.cached;

  String    _type         = 'Concert';
  String    _status       = 'upcoming';
  DateTime? _date;
  DateTime? _endDate;
  TimeOfDay?_startTime;
  TimeOfDay?_endTime;
  bool      _showCalendar     = false;
  bool      _showEndCalendar  = false;
  bool      _showStartPicker  = false;
  bool      _showEndPicker    = false;

  String?    _existingBannerUrl;
  Uint8List? _bannerBytes;
  String?    _bannerName;
  bool       _saving = false;
  String?    _error;

  // Field problems show only after the first Create / Save attempt, then
  // update live as the organizer fixes them.
  bool _submitted = false;
  final _fieldKeys = {for (final f in EventFormField.values) f: GlobalKey()};
  final _summaryKey = GlobalKey();

  static const _fieldLabels = {
    EventFormField.title:     'Title',
    EventFormField.otherType: 'Event type',
    EventFormField.startDate: 'Start date',
    EventFormField.endDate:   'End date',
    EventFormField.startTime: 'Start time',
    EventFormField.endTime:   'End time',
    EventFormField.location:  'Location',
  };

  Map<EventFormField, String> _validate() => validateEventForm(
        title: _titleCtrl.text, needsOtherType: _type == 'Other',
        otherType: _otherTypeCtrl.text,
        startDate: _date, endDate: _endDate,
        startTime: _startTime, endTime: _endTime,
        location: _locationCtrl.text);

  Map<EventFormField, String> get _errors => _submitted ? _validate() : const {};

  // After a failed save: if the first problem is in the top section, show the
  // summary (it sits right above it); otherwise go straight to the field.
  void _revealFirstProblem(EventFormField first) {
    final ctx = first.index <= EventFormField.otherType.index
        ? _summaryKey.currentContext : null;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    } else {
      _scrollTo(first);
    }
  }

  void _scrollTo(EventFormField f) {
    final ctx = _fieldKeys[f]!.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, alignment: 0.1,
          duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    }
  }

  // Red outline on a text field that has a problem.
  InputDecoration _withError(InputDecoration d, bool hasError, WebTk t) => !hasError ? d
      : d.copyWith(
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: formErrorColor(t.dark), width: 1.5)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: formErrorColor(t.dark), width: 2)));

  bool get _isEdit => widget.existing != null;
  bool get _isRejected =>
      widget.existing?['approval_status'] == 'rejected';
  String get _rejectionReason =>
      rejectionReasonOf(widget.existing ?? const {})?.trim() ?? '';

  // Tracks the 5 most important required fields so the progress bar animates
  // as the organizer fills in the form.  Each field counts as 1/5 = 20%.
  double get _formProgress {
    int done = 0;
    if (_titleCtrl.text.trim().isNotEmpty) done++;
    if (_date != null)                     done++;
    if (_endDate != null)                  done++;
    if (_startTime != null)                done++;
    if (_endTime != null)                  done++;
    if (_locationCtrl.text.trim().isNotEmpty) done++;
    return done / 6;
  }

  @override
  void initState() {
    super.initState();
    // Rebuild whenever the user edits a text field that feeds _formProgress.
    _titleCtrl.addListener(() { if (mounted) setState(() {}); });
    _locationCtrl.addListener(() { if (mounted) setState(() {}); });
    // Keep field errors live once they're showing.
    _otherTypeCtrl.addListener(() { if (mounted && _submitted) setState(() {}); });
    StudentCountService.activeStudents().then((n) {
      if (mounted && n != _studentCount) setState(() => _studentCount = n);
    });
    final e = widget.existing == null
        ? null
        : <String, dynamic>{...widget.existing!, ...?widget.pendingChanges};
    if (e != null) {
      _titleCtrl.text    = e['title'] as String? ?? '';
      _descCtrl.text     = e['description'] as String? ?? '';
      _locationCtrl.text = e['location'] as String? ?? '';
      // Custom types (saved via "Other") don't match a preset chip — select
      // Other and surface the stored value in the specify field.
      final loadedType = e['event_type'] as String? ?? 'Concert';
      if (_kTypes.any((tp) => tp.$1 == loadedType)) {
        _type = loadedType;
      } else {
        _type = 'Other';
        _otherTypeCtrl.text = loadedType;
      }
      _status            = e['event_status'] as String? ?? 'upcoming';
      _existingBannerUrl = e['event_image_url'] as String?;
      final dateStr      = e['event_date'] as String?;
      if (dateStr != null) _date = DateTime.tryParse(dateStr);
      final endDateStr   = e['end_date'] as String?;
      if (endDateStr != null) _endDate = DateTime.tryParse(endDateStr);
      final st = e['start_time'] as String?;
      final et = e['end_time']   as String?;
      if (st != null) {
        final p = st.split(':');
        _startTime = TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
      }
      if (et != null) {
        final p = et.split(':');
        _endTime = TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
      }
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    _otherTypeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickBanner() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final ext  = (file.extension ?? '').toLowerCase();
    if (!_kAllowedBannerExts.contains(ext)) {
      setState(() => _error = 'Banner must be a JPG, PNG, or WEBP image.');
      return;
    }
    const maxBytes = 10 * 1024 * 1024; // 10 MB
    if (file.size > maxBytes) {
      setState(() => _error =
          'Image must be 10 MB or smaller '
          '(selected: ${(file.size / (1024 * 1024)).toStringAsFixed(1)} MB).');
      return;
    }
    setState(() {
      _bannerBytes = file.bytes;
      _bannerName  = file.name;
      _error       = null;
    });
  }



  String? _fmtTimeOfDay(TimeOfDay? t) => t == null
      ? null
      : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  /// Edits to a live event: submit a change request instead of updating it.
  /// The event stays live with its current details until an admin approves.
  /// SweetAlert2 confirm: the request is sent behind its loader, and a failure
  /// shows inside the alert so the organizer can simply try again.
  Future<void> _submitChangeRequest() async {
    final live    = widget.existing!;
    final eventId = live['event_id'] as String;
    setState(() { _saving = true; _error = null; });
    try {
      // A new banner is only uploaded once the organizer confirms. The live one
      // is NOT deleted — the event keeps showing it until the change is approved.
      final changes = EventChangeRequestService.diff(live, {
        'title':            _titleCtrl.text.trim(),
        'description':      _descCtrl.text.trim(),
        'location':         _locationCtrl.text.trim(),
        'event_type':       _type == 'Other' ? _otherTypeCtrl.text.trim() : _type,
        'event_date':       _date!.toIso8601String().split('T').first,
        'end_date':         _endDate!.toIso8601String().split('T').first,
        'start_time':       _fmtTimeOfDay(_startTime),
        'end_time':         _fmtTimeOfDay(_endTime),
        'event_image_url':  _bannerBytes != null ? _kNewBanner : _existingBannerUrl,
      });
      if (changes.isEmpty) {
        setState(() { _saving = false; _error = 'Nothing has changed.'; });
        return;
      }

      // Say who will be told, if the date/time/venue moves.
      final count = EventChangeRequestService.touchesSchedule(changes)
          ? await EventCancellationService.registrationCount(eventId)
          : 0;
      if (!mounted) return;
      setState(() => _saving = false);   // the alert shows its own loader

      final r = await Swal.fire(context,
        icon: SwalIcon.question,
        title: 'Submit for approval?',
        text: 'This event is approved, so an admin needs to approve your changes. '
            'It keeps its current details until then.'
            '${count > 0 ? '\n\n$count registered student${count == 1 ? '' : 's'} will be notified '
                'of the new date, time or venue once it’s approved.' : ''}',
        showCancelButton: true,
        confirmButtonText: 'Yes, submit it',
        cancelButtonText: 'Keep editing',
        confirmButtonColor: kSwalGold,
        reverseButtons: true,
        buttonTextStyle: const TextStyle(fontFamily: 'Poppins',
            fontSize: 14, fontWeight: FontWeight.w700),
        preConfirm: (_) async {
          final client = SupabaseService.client;
          String? uploadedPath;
          try {
            if (_bannerBytes != null) {
              final ext = (_bannerName ?? 'banner.jpg').split('.').last.toLowerCase();
              uploadedPath = 'banner_${DateTime.now().millisecondsSinceEpoch}_${webUuid()}.$ext';
              await client.storage.from('event-banners').uploadBinary(uploadedPath, _bannerBytes!,
                  fileOptions: FileOptions(contentType: _bannerContentType(ext), upsert: false));
              changes['event_image_url'] =
                  client.storage.from('event-banners').getPublicUrl(uploadedPath);
            }
            await EventChangeRequestService.submit(
              eventId: eventId,
              organizerId: widget.orgId!,
              eventTitle: live['title'] as String? ?? _titleCtrl.text.trim(),
              changes: changes,
            );
            return null;
          } catch (e) {
            // Don't leave an upload behind that nothing points to.
            if (uploadedPath != null) {
              try {
                await client.storage.from('event-banners').remove([uploadedPath]);
              } catch (_) {}
            }
            return friendlyError(e);
          }
        },
      );
      if (r.isConfirmed && mounted) Navigator.of(context).pop('requested');
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showErrorAlert(context, e, title: 'Couldn’t submit your changes');
      }
    }
  }

  Future<void> _save() async {
    // Show every problem at once, next to its field, and jump to the first.
    // (The schedule rules are also enforced by the database.)
    final problems = _validate();
    if (problems.isNotEmpty) {
      setState(() { _submitted = true; _error = null; });
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealFirstProblem(problems.keys.first));
      return;
    }
    if (widget.orgId == null) return;

    // Live event → changes go to admin review as a change request.
    if (_isEdit && EventChangeRequestService.needsApproval(widget.existing!)) {
      await _submitChangeRequest();
      return;
    }

    setState(() { _saving = true; _error = null; });

    try {
      final client = SupabaseService.client;

      // Upload banner if new bytes provided
      String? imageUrl = _existingBannerUrl;
      if (_bannerBytes != null) {
        // Delete the old banner so orphaned files don't accumulate in storage.
        if (_isEdit && _existingBannerUrl != null && _existingBannerUrl!.isNotEmpty) {
          try {
            final uri = Uri.tryParse(_existingBannerUrl!);
            if (uri != null) {
              final segments  = uri.pathSegments;
              final bucketIdx = segments.indexOf('event-banners');
              if (bucketIdx >= 0 && bucketIdx < segments.length - 1) {
                final oldPath = segments.sublist(bucketIdx + 1).join('/');
                await client.storage.from('event-banners').remove([oldPath]);
              }
            }
          } catch (_) {
            // Removal failure is non-fatal — the old file becomes orphaned
            // but the save should still proceed.
          }
        }

        final ext  = (_bannerName ?? 'banner.jpg').split('.').last.toLowerCase();
        final path = 'banner_${DateTime.now().millisecondsSinceEpoch}_${webUuid()}.$ext';
        await client.storage.from('event-banners').uploadBinary(
          path, _bannerBytes!,
          fileOptions: FileOptions(contentType: _bannerContentType(ext), upsert: false),
        );
        imageUrl = client.storage.from('event-banners').getPublicUrl(path);
      }

      final dateStr    = _date!.toIso8601String().split('T').first;
      final endDateStr = _endDate!.toIso8601String().split('T').first;
      final startStr   = _startTime != null
        ? '${_startTime!.hour.toString().padLeft(2,'0')}:${_startTime!.minute.toString().padLeft(2,'0')}:00'
        : null;
      final endStr     = _endTime != null
        ? '${_endTime!.hour.toString().padLeft(2,'0')}:${_endTime!.minute.toString().padLeft(2,'0')}:00'
        : null;

      final payload = {
        'title':              _titleCtrl.text.trim(),
        'description':        _descCtrl.text.trim(),
        'location':           _locationCtrl.text.trim(),
        'event_type':         _type == 'Other'
            ? _otherTypeCtrl.text.trim()
            : _type,
        // Only a cancellation is stored; everything else follows the clock.
        'event_status':       _status == 'cancelled' ? 'cancelled' : 'upcoming',
        'event_date':         dateStr,
        'end_date':           endDateStr,
        'start_time':         startStr,
        'end_time':           endStr,
        'event_image_url':    imageUrl,
        // No capacity — it's the number of active students.
      };

      var resubmitted = false;
      if (_isEdit) {
        final eventId     = widget.existing!['event_id'] as String;
        final wasRejected = widget.existing!['approval_status'] == 'rejected';
        // Saving a rejected event sends it back to the admin's review queue.
        // The database only does that when the save asks for 'pending' —
        // without it the event quietly stays Rejected.
        final rows = await client.from('events')
            .update({...payload, if (wasRejected) 'approval_status': 'pending'})
            .eq('event_id', eventId)
            .select('event_id, approval_status');
        if ((rows as List).isEmpty) {
          throw Exception('The event wasn’t updated — it may have been removed, '
              'or you don’t have permission to change it.');
        }
        if (wasRejected && (rows.first as Map)['approval_status'] != 'pending') {
          throw Exception('Your changes were saved, but the event couldn’t be sent '
              'back for review. Please try again.');
        }
        resubmitted = wasRejected;
        AuditService.logEvent(
          action: 'updated',
          eventTitle: _titleCtrl.text.trim(),
          eventId: eventId,
          organizerId: widget.orgId,
          details: wasRejected
              ? 'Event edited and resubmitted for review'
              : 'Event details updated',
        );
      } else {
        await client.from('events')
            .insert({...payload, 'organizer_id': widget.orgId!});
        AuditService.logEvent(
          action: 'created',
          eventTitle: _titleCtrl.text.trim(),
          organizerId: widget.orgId,
          details: 'New event created',
        );
      }

      if (mounted) {
        Navigator.of(context).pop(!_isEdit ? 'created' : resubmitted ? 'resubmitted' : 'updated');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showErrorAlert(context, e,
            title: _isEdit ? 'Couldn’t save your changes' : 'Couldn’t create the event');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final errs = _errors;
    int errorsIn(List<EventFormField> fields) => fields.where(errs.containsKey).length;
    Widget fieldError(EventFormField f) => errs[f] == null
        ? const SizedBox.shrink() : FormFieldError(errs[f]!, dark: t.dark);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: t.card,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: t.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: kGold.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.event_rounded, color: kGold, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_isEdit ? 'Edit Event' : 'Create New Event',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: t.text,
                            )),
                          Text(_isEdit
                            ? 'Update event details below'
                            : 'Fill in the details for your new event',
                            style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 11, color: t.sub,
                            )),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, color: t.muted),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  // ── Form completion progress bar ──────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Form completion',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: t.muted,
                        ),
                      ),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: _formProgress),
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOut,
                        builder: (_, value, _) => Text(
                          '${(value * 100).toInt()}%',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: value == 1.0
                                ? const Color(0xFF16A34A)
                                : kGold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: _formProgress),
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOut,
                      builder: (_, value, _) => LinearProgressIndicator(
                        value: value,
                        minHeight: 5,
                        backgroundColor: t.border,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          value == 1.0
                              ? const Color(0xFF16A34A)
                              : kGold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Form
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isRejected) ...[
                      _DialogSection(
                        icon: Icons.block_rounded,
                        iconBg: const Color(0x1AEF4444),
                        iconColor: const Color(0xFFEF4444),
                        title: 'Rejected by Admin',
                        child: Text(
                          _rejectionReason.isNotEmpty
                              ? _rejectionReason
                              : 'No rejection reason was provided.',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            color: t.text,
                            height: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (errs.isNotEmpty) ...[
                      FormErrorSummary<EventFormField>(
                        key: _summaryKey,
                        errors: errs, labels: _fieldLabels, onTap: _scrollTo,
                        dark: t.dark, textColor: t.text),
                      const SizedBox(height: 10),
                    ],
                    // ── Event Details ─────────────────────────────────────────
                    _DialogSection(
                      icon: Icons.event_note_rounded,
                      iconBg: kGoldLight,
                      iconColor: kGold,
                      title: 'Event Details',
                      errorCount: errorsIn(const [EventFormField.title]),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          KeyedSubtree(key: _fieldKeys[EventFormField.title],
                              child: _label('Event Title  *')),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _titleCtrl,
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 13.5, color: t.text),
                            decoration: _withError(webInputDeco('e.g. Annual Science Fair', dark: t.dark),
                                errs.containsKey(EventFormField.title), t),
                          ),
                          fieldError(EventFormField.title),
                          const SizedBox(height: 14),
                          _label('Description'),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _descCtrl,
                            maxLines: 3,
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.text),
                            decoration: webInputDeco('Tell students what this event is about…', dark: t.dark),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    // ── Event Type ─────────────────────────────────────────────
                    _DialogSection(
                      icon: Icons.tune_rounded,
                      iconBg: const Color(0x1A7C3AED),
                      iconColor: const Color(0xFF7C3AED),
                      title: 'Event Type',
                      errorCount: errorsIn(const [EventFormField.otherType]),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Event Type'),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: List.generate(_kTypes.length, (i) {
                              final tp  = _kTypes[i];
                              final sel = _type == tp.$1;
                              return MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => setState(() => _type = tp.$1),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    width: 74, height: 76,
                                    decoration: BoxDecoration(
                                      color: sel ? kGold : t.inputBg,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: sel ? kGold : t.border, width: 1.5),
                                      boxShadow: sel ? [BoxShadow(
                                        color: kGold.withValues(alpha: 0.28),
                                        blurRadius: 8, offset: const Offset(0, 3),
                                      )] : null,
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(tp.$2, size: 22, color: sel ? Colors.white : tp.$3),
                                        const SizedBox(height: 5),
                                        Text(tp.$1,
                                          style: TextStyle(
                                            fontFamily: 'Poppins', fontSize: 9.5,
                                            fontWeight: FontWeight.w600,
                                            color: sel ? Colors.white : t.text,
                                          )),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                          if (_type == 'Other') ...[
                            const SizedBox(height: 14),
                            KeyedSubtree(key: _fieldKeys[EventFormField.otherType],
                                child: _label('Specify type  *')),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _otherTypeCtrl,
                              maxLength: 40,
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 13.5,
                                  color: t.text),
                              decoration: _withError(webInputDeco(
                                'e.g. Quiz Bee, Sports Fest, Job Fair',
                                icon: Icons.edit_rounded,
                                dark: t.dark,
                              ).copyWith(
                                counterStyle: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 10,
                                    color: t.muted),
                              ), errs.containsKey(EventFormField.otherType), t),
                            ),
                            fieldError(EventFormField.otherType),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    // ── Schedule ──────────────────────────────────────────────
                    _DialogSection(
                      icon: Icons.schedule_rounded,
                      iconBg: const Color(0x1A2563EB),
                      iconColor: const Color(0xFF2563EB),
                      title: 'Schedule',
                      errorCount: errorsIn(const [EventFormField.startDate, EventFormField.endDate,
                          EventFormField.startTime, EventFormField.endTime]),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          KeyedSubtree(key: _fieldKeys[EventFormField.startDate],
                              child: _buildDateTrigger(errs.containsKey(EventFormField.startDate))),
                          _buildInlineCalendar(),
                          fieldError(EventFormField.startDate),
                          const SizedBox(height: 12),
                          KeyedSubtree(key: _fieldKeys[EventFormField.endDate],
                              child: _buildEndDateTrigger(errs.containsKey(EventFormField.endDate))),
                          _buildInlineEndCalendar(),
                          fieldError(EventFormField.endDate),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(key: _fieldKeys[EventFormField.startTime], child: _buildTimeCard(
                              label: 'Start Time', isRequired: true,
                              hasError: errs.containsKey(EventFormField.startTime),
                              time: _startTime,
                              accentColor: const Color(0xFF16A34A),
                              icon: Icons.play_circle_outline_rounded,
                              isActive: _showStartPicker,
                              onTap: () => setState(() {
                                _showStartPicker = !_showStartPicker;
                                _showEndPicker   = false;
                              }),
                            )),
                            const SizedBox(width: 10),
                            Expanded(key: _fieldKeys[EventFormField.endTime], child: _buildTimeCard(
                              label: 'End Time', isRequired: true,
                              hasError: errs.containsKey(EventFormField.endTime),
                              time: _endTime,
                              accentColor: _kEndAccent,
                              icon: Icons.stop_circle_outlined,
                              isActive: _showEndPicker,
                              onTap: () => setState(() {
                                _showEndPicker   = !_showEndPicker;
                                _showStartPicker = false;
                              }),
                            )),
                          ]),
                          _buildInlineTimePicker(),
                          fieldError(EventFormField.startTime),
                          fieldError(EventFormField.endTime),
                          Builder(builder: (ctx) {
                            if (_date == null || _startTime == null || _endTime == null) {
                              return const SizedBox.shrink();
                            }
                            final endDay = _endDate ?? _date!;
                            final diff = DateTime(endDay.year, endDay.month, endDay.day,
                                    _endTime!.hour, _endTime!.minute)
                                .difference(DateTime(_date!.year, _date!.month, _date!.day,
                                    _startTime!.hour, _startTime!.minute))
                                .inMinutes;
                            final bad = diff <= 0;
                            // Once errors show, the message under the time says it.
                            if (bad && errs.containsKey(EventFormField.endTime)) {
                              return const SizedBox.shrink();
                            }
                            final d = diff ~/ 1440, h = (diff % 1440) ~/ 60, m = diff % 60;
                            final lbl = [if (d > 0) '${d}d', if (h > 0) '${h}h', if (m > 0) '${m}m']
                                .join(' ');
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                decoration: BoxDecoration(
                                  color: bad ? const Color(0xFFFFF7ED) : const Color(0xFFF0FDF4),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: bad ? const Color(0xFFFBBF24) : const Color(0xFF86EFAC)),
                                ),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(bad ? Icons.warning_amber_rounded : Icons.timer_outlined,
                                    size: 13, color: bad ? const Color(0xFFB45309) : const Color(0xFF15803D)),
                                  const SizedBox(width: 6),
                                  Text(bad ? 'The end must be after the start' : 'Duration: $lbl',
                                    style: TextStyle(
                                      fontFamily: 'Poppins', fontSize: 10.5, fontWeight: FontWeight.w600,
                                      color: bad ? const Color(0xFFB45309) : const Color(0xFF15803D),
                                    )),
                                ]),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    // ── Location & Capacity ───────────────────────────────────
                    _DialogSection(
                      icon: Icons.place_rounded,
                      iconBg: const Color(0x1A16A34A),
                      iconColor: const Color(0xFF16A34A),
                      title: 'Location & Capacity',
                      errorCount: errorsIn(const [EventFormField.location]),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          KeyedSubtree(key: _fieldKeys[EventFormField.location],
                              child: _label('Location  *')),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _locationCtrl,
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.text),
                            decoration: _withError(
                                webInputDeco('Venue or room name', icon: Icons.location_on_rounded, dark: t.dark),
                                errs.containsKey(EventFormField.location), t),
                          ),
                          fieldError(EventFormField.location),
                          const SizedBox(height: 14),
                          _label('Capacity'),
                          const SizedBox(height: 6),
                          _buildCapacityInfo(t),
                          const SizedBox(height: 5),
                          Text('Set automatically — it grows as students are added. '
                              'Registration closes 2 hours after the event starts.',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5, color: t.muted)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    // ── Banner ────────────────────────────────────────────────
                    _DialogSection(
                      icon: Icons.image_rounded,
                      iconBg: const Color(0x1A7C3AED),
                      iconColor: const Color(0xFF7C3AED),
                      title: 'Event Banner',
                      child: _buildBannerPicker(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _ErrorBar(message: _error!),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            // Footer buttons
            Container(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: t.border)),
              ),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: t.border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: Text('Cancel',
                      style: TextStyle(
                        fontFamily: 'Poppins', color: t.sub, fontWeight: FontWeight.w600,
                      )),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kGold,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: _saving
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2,
                          ))
                      // Says what saving will do — approved events need the admin.
                      : Text(!_isEdit
                              ? 'Create Event'
                              : _isRejected
                                  ? 'Save & Resubmit'
                                  : EventChangeRequestService.needsApproval(widget.existing!)
                                      ? 'Submit for Approval'
                                      : 'Save Changes',
                          style: const TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                          )),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBannerPicker() {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final hasBanner = _bannerBytes != null ||
        (_existingBannerUrl != null && _existingBannerUrl!.isNotEmpty);

    return GestureDetector(
      onTap: _pickBanner,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasBanner ? kGold.withValues(alpha: 0.50) : t.border,
              style: hasBanner ? BorderStyle.solid : BorderStyle.solid,
            ),
            color: hasBanner
              ? kGold.withValues(alpha: 0.04)
              : t.inputBg,
          ),
          child: hasBanner
            ? Stack(fit: StackFit.expand, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: _bannerBytes != null
                    ? Image.memory(_bannerBytes!, fit: BoxFit.cover)
                    : Image.network(
                        _existingBannerUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.35),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_rounded, color: Colors.white, size: 22),
                          SizedBox(height: 6),
                          Text('Click to replace',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            )),
                        ],
                      ),
                    ),
                  ),
                ),
              ])
            : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add_photo_alternate_rounded,
                  size: 28, color: kGold.withValues(alpha: 0.60)),
                const SizedBox(height: 8),
                Text('Click to upload banner',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 13, color: t.sub,
                  )),
                const SizedBox(height: 2),
                Text('PNG, JPG up to 10 MB',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 11, color: t.muted,
                  )),
              ]),
        ),
      ),
    );
  }

  Widget _label(String text) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return Text(text,
      style: TextStyle(
        fontFamily: 'Poppins',
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: t.text,
      ));
  }

  Widget _buildTimeCard({
    required String    label,
    required bool      isRequired,
    required TimeOfDay? time,
    required Color     accentColor,
    required IconData  icon,
    required VoidCallback onTap,
    bool isActive = false,
    bool hasError = false,
  }) {
    final tk = WebTk(Theme.of(context).brightness == Brightness.dark);
    final filled = time != null;
    String fmt12(TimeOfDay t) {
      final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
      return '$h:${t.minute.toString().padLeft(2, '0')}';
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: filled || isActive ? accentColor.withValues(alpha: 0.04) : tk.inputBg,
            borderRadius: BorderRadius.only(
              topLeft:     const Radius.circular(12),
              topRight:    const Radius.circular(12),
              bottomLeft:  Radius.circular(isActive ? 0 : 12),
              bottomRight: Radius.circular(isActive ? 0 : 12),
            ),
            border: Border.all(
              color: hasError
                ? formErrorColor(tk.dark)
                : isActive
                ? accentColor.withValues(alpha: 0.50)
                : filled
                ? accentColor.withValues(alpha: 0.35)
                : tk.border,
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 11, color: filled ? accentColor : tk.muted),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(label,
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w600,
                      color: filled ? accentColor : tk.muted,
                    )),
                ),
                if (isRequired && !filled)
                  const Text('*', style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 10,
                    color: Color(0xFFEF4444), fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 8),
              if (filled) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(fmt12(time),
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 24, fontWeight: FontWeight.w800,
                        color: accentColor, height: 1.0,
                      )),
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(time.hour >= 12 ? 'PM' : 'AM',
                          style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 8,
                            fontWeight: FontWeight.w800, color: accentColor,
                          )),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text('Tap to edit',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 9.5,
                    color: accentColor.withValues(alpha: 0.6),
                  )),
              ] else ...[
                Text('--:--',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 24, fontWeight: FontWeight.w800,
                    color: tk.border, height: 1.0,
                  )),
                const SizedBox(height: 2),
                Text('Tap to set',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 9.5, color: tk.muted,
                  )),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Capacity is fixed to the student body — every active student can
  // register, and it grows as students are added — so it's shown, not entered.
  Widget _buildCapacityInfo(WebTk t) {
    final n          = _studentCount;
    final registered = widget.existing?['current_participants'] as int? ?? 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.inputBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.border),
      ),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: kGoldLight, borderRadius: BorderRadius.circular(9)),
          child: const Icon(Icons.groups_rounded, size: 17, color: kGold),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(n != null ? '$n students' : 'All students',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13.5,
                  fontWeight: FontWeight.w700, color: t.text)),
            Text(
              registered > 0
                  ? 'Every student can register · $registered registered so far'
                  : 'Every student can register',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.sub)),
          ]),
        ),
        Tooltip(
          message: 'Set automatically from the number of active students',
          child: Icon(Icons.lock_outline_rounded, size: 14, color: t.muted),
        ),
      ]),
    );
  }

  void _toggleCalendar() => setState(() {
    _showCalendar = !_showCalendar;
    if (_showCalendar) _showEndCalendar = false;
  });

  void _toggleEndCalendar() => setState(() {
    _showEndCalendar = !_showEndCalendar;
    if (_showEndCalendar) _showCalendar = false;
  });

  String _weekdayAbbr(int w) {
    const d = ['MON','TUE','WED','THU','FRI','SAT','SUN'];
    return d[(w - 1).clamp(0, 6)];
  }

  String _weekdayFull(int w) {
    const d = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    return d[(w - 1).clamp(0, 6)];
  }

  Widget _buildDateTrigger([bool hasError = false]) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final filled = _date != null;
    const accent = Color(0xFF2563EB);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _toggleCalendar,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: filled ? accent.withValues(alpha: 0.04) : t.inputBg,
            borderRadius: BorderRadius.only(
              topLeft:     const Radius.circular(12),
              topRight:    const Radius.circular(12),
              bottomLeft:  Radius.circular(_showCalendar ? 0 : 12),
              bottomRight: Radius.circular(_showCalendar ? 0 : 12),
            ),
            border: Border.all(
              color: hasError
                  ? formErrorColor(t.dark)
                  : _showCalendar
                  ? accent.withValues(alpha: 0.50)
                  : filled
                  ? accent.withValues(alpha: 0.30)
                  : t.border,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: filled ? accent : t.divider,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: filled
                  ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(_weekdayAbbr(_date!.weekday),
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 7,
                          fontWeight: FontWeight.w700, color: Colors.white60, letterSpacing: 0.5)),
                      Text('${_date!.day}',
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 20,
                          fontWeight: FontWeight.w800, color: Colors.white, height: 1.1)),
                    ])
                  : Icon(Icons.calendar_month_rounded, color: t.muted, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: filled
                  ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(webFmtDate(_date!.toIso8601String()),
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                          fontWeight: FontWeight.w700, color: t.text)),
                      const SizedBox(height: 2),
                      Text(_weekdayFull(_date!.weekday),
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted)),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text('Event Date', style: TextStyle(fontFamily: 'Poppins',
                          fontSize: 13, fontWeight: FontWeight.w600, color: t.text)),
                        const Text(' *', style: TextStyle(fontFamily: 'Poppins',
                          fontSize: 13, color: Color(0xFFEF4444), fontWeight: FontWeight.w700)),
                      ]),
                      const SizedBox(height: 2),
                      Text('Tap to open calendar',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted)),
                    ]),
              ),
              AnimatedRotation(
                turns: _showCalendar ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(
                    color: _showCalendar
                      ? accent.withValues(alpha: 0.10)
                      : t.divider,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(Icons.keyboard_arrow_down_rounded, size: 16,
                    color: _showCalendar ? accent : t.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEndDateTrigger([bool hasError = false]) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final filled = _endDate != null;
    const accent = _kEndAccent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _toggleEndCalendar,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: filled ? accent.withValues(alpha: 0.04) : t.inputBg,
            borderRadius: BorderRadius.only(
              topLeft:     const Radius.circular(12),
              topRight:    const Radius.circular(12),
              bottomLeft:  Radius.circular(_showEndCalendar ? 0 : 12),
              bottomRight: Radius.circular(_showEndCalendar ? 0 : 12),
            ),
            border: Border.all(
              color: hasError
                  ? formErrorColor(t.dark)
                  : _showEndCalendar
                  ? accent.withValues(alpha: 0.50)
                  : filled
                  ? accent.withValues(alpha: 0.30)
                  : t.border,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: filled ? accent : t.divider,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: filled
                  ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(_weekdayAbbr(_endDate!.weekday),
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 7,
                          fontWeight: FontWeight.w700, color: Colors.white60, letterSpacing: 0.5)),
                      Text('${_endDate!.day}',
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 20,
                          fontWeight: FontWeight.w800, color: Colors.white, height: 1.1)),
                    ])
                  : Icon(Icons.date_range_rounded, color: t.muted, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: filled
                  ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(webFmtDate(_endDate!.toIso8601String()),
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                          fontWeight: FontWeight.w700, color: t.text)),
                      const SizedBox(height: 2),
                      Text(_weekdayFull(_endDate!.weekday),
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted)),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text('End Date', style: TextStyle(fontFamily: 'Poppins',
                          fontSize: 13, fontWeight: FontWeight.w600, color: t.text)),
                        const Text(' *', style: TextStyle(fontFamily: 'Poppins',
                          fontSize: 13, color: Color(0xFFEF4444), fontWeight: FontWeight.w700)),
                      ]),
                      const SizedBox(height: 2),
                      Text('Tap to choose end date',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted)),
                    ]),
              ),
              AnimatedRotation(
                turns: _showEndCalendar ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(
                    color: _showEndCalendar ? accent.withValues(alpha: 0.10) : t.divider,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(Icons.keyboard_arrow_down_rounded, size: 16,
                    color: _showEndCalendar ? accent : t.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInlineEndCalendar() {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    const accent = _kEndAccent;
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: _showEndCalendar
        ? Container(
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: const BorderRadius.only(
                bottomLeft:  Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              border: Border(
                left:   BorderSide(color: accent.withValues(alpha: 0.50), width: 1.5),
                right:  BorderSide(color: accent.withValues(alpha: 0.50), width: 1.5),
                bottom: BorderSide(color: accent.withValues(alpha: 0.50), width: 1.5),
              ),
            ),
            child: _WebCalendar(
              selectedDate:   _endDate,
              firstDate:      _date ?? DateUtils.dateOnly(DateTime.now()),
              lastDate:       DateTime.now().add(const Duration(days: 365 * 3)),
              accentColor:    accent,
              onDateSelected: (date) => setState(() {
                _endDate        = date;
                _showEndCalendar = false;
              }),
            ),
          )
        : const SizedBox.shrink(),
    );
  }

  Widget _buildInlineTimePicker() {
    final showStart = _showStartPicker;
    final showEnd   = _showEndPicker;
    if (!showStart && !showEnd) return const SizedBox.shrink();
    final wtk         = WebTk(Theme.of(context).brightness == Brightness.dark);
    final accentColor = showStart ? const Color(0xFF16A34A) : _kEndAccent;
    final label       = showStart ? 'Start Time' : 'End Time';
    final initTime    = showStart
        ? _startTime
        : _endTime ?? _suggestedEndTime(_startTime);
    final now         = DateTime.now();
    final isToday     = _date != null &&
        DateUtils.isSameDay(DateUtils.dateOnly(_date!), DateUtils.dateOnly(now));
    final minTime     = isToday ? TimeOfDay(hour: now.hour, minute: now.minute) : null;

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: Container(
        decoration: BoxDecoration(
          color: wtk.card,
          borderRadius: const BorderRadius.only(
            bottomLeft:  Radius.circular(12),
            bottomRight: Radius.circular(12),
          ),
          border: Border(
            left:   BorderSide(color: accentColor.withValues(alpha: 0.50), width: 1.5),
            right:  BorderSide(color: accentColor.withValues(alpha: 0.50), width: 1.5),
            bottom: BorderSide(color: accentColor.withValues(alpha: 0.50), width: 1.5),
          ),
        ),
        child: _WebTimePicker(
          key: ValueKey(label),
          initialTime: initTime,
          accentColor: accentColor,
          label: label,
          minTime: minTime,
          onTimeSet: (t) => setState(() {
            if (showStart) { _startTime = t; _showStartPicker = false; }
            else           { _endTime   = t; _showEndPicker   = false; }
          }),
        ),
      ),
    );
  }

  Widget _buildInlineCalendar() {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    const accent = Color(0xFF2563EB);
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: _showCalendar
        ? Container(
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: const BorderRadius.only(
                bottomLeft:  Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              border: Border(
                left:   BorderSide(color: accent.withValues(alpha: 0.50), width: 1.5),
                right:  BorderSide(color: accent.withValues(alpha: 0.50), width: 1.5),
                bottom: BorderSide(color: accent.withValues(alpha: 0.50), width: 1.5),
              ),
            ),
            child: _WebCalendar(
              selectedDate:   _date,
              firstDate:      DateUtils.dateOnly(DateTime.now()),
              lastDate:       DateTime.now().add(const Duration(days: 365 * 2)),
              accentColor:    accent,
              onDateSelected: (date) => setState(() {
                _date         = date;
                _showCalendar = false;
              }),
            ),
          )
        : const SizedBox.shrink(),
    );
  }
}

// ── Dialog section card ───────────────────────────────────────────────────────

class _DialogSection extends StatelessWidget {
  final IconData icon;
  final Color    iconBg;
  final Color    iconColor;
  final String   title;
  final Widget   child;
  final int      errorCount;   // > 0 shows a "N to fix" tag in the header
  const _DialogSection({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.child,
    this.errorCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return Container(
    decoration: BoxDecoration(
      color: t.card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: t.border),
      boxShadow: [
        BoxShadow(color: t.shadow, blurRadius: 8, offset: const Offset(0, 2)),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, color: iconColor, size: 15),
            ),
            const SizedBox(width: 10),
            Text(title,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: t.text,
              )),
            if (errorCount > 0) ...[
              const Spacer(),
              FormSectionErrorPill(count: errorCount, dark: t.dark),
            ],
          ]),
        ),
        const SizedBox(height: 10),
        Divider(height: 1, color: t.divider),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: child,
        ),
      ],
    ),
    );
  }
}

// ── Shared micro-widgets ──────────────────────────────────────────────────────

class _HoverRow extends StatefulWidget {
  final Widget child;
  final bool   isLast;
  final VoidCallback? onTap;
  const _HoverRow({required this.child, required this.isLast, this.onTap});

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return MouseRegion(
    cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
    onEnter: (_) => setState(() => _h = true),
    onExit:  (_) => setState(() => _h = false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Container(
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

class _IconBtn extends StatefulWidget {
  final IconData     icon;
  final Color        color;
  final String       tooltip;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.color, required this.tooltip, required this.onTap});

  @override
  State<_IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<_IconBtn> {
  bool _h = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _h = true),
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
              ? widget.color.withValues(alpha: 0.12)
              : widget.color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(widget.icon, size: 16, color: widget.color),
        ),
      ),
    ),
  );
}

// ── Inline calendar ───────────────────────────────────────────────────────────

class _WebCalendar extends StatefulWidget {
  final DateTime?              selectedDate;
  final DateTime               firstDate;
  final DateTime               lastDate;
  final Color                  accentColor;
  final ValueChanged<DateTime> onDateSelected;
  const _WebCalendar({
    required this.selectedDate,
    required this.firstDate,
    required this.lastDate,
    required this.accentColor,
    required this.onDateSelected,
  });

  @override
  State<_WebCalendar> createState() => _WebCalendarState();
}

class _WebCalendarState extends State<_WebCalendar> {
  late int _month;
  late int _year;

  static const _weekdays = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
  static const _months   = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December',
  ];

  @override
  void initState() {
    super.initState();
    final base = widget.selectedDate ?? DateTime.now();
    _month = base.month;
    _year  = base.year;
  }

  void _prev() => setState(() { if (_month == 1) { _month = 12; _year--; } else { _month--; } });
  void _next() => setState(() { if (_month == 12) { _month = 1; _year++; } else { _month++; } });

  List<DateTime?> _cells() {
    final first  = DateTime(_year, _month, 1);
    final offset = first.weekday % 7;
    final days   = DateUtils.getDaysInMonth(_year, _month);
    final list   = <DateTime?>[];
    for (var i = 0; i < offset; i++) { list.add(null); }
    for (var d = 1; d <= days; d++)  { list.add(DateTime(_year, _month, d)); }
    while (list.length % 7 != 0)     { list.add(null); }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final t      = WebTk(Theme.of(context).brightness == Brightness.dark);
    final today  = DateUtils.dateOnly(DateTime.now());
    final cells  = _cells();
    final accent = widget.accentColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
      child: Column(
        children: [
          // Month navigation
          Row(children: [
            _CalBtn(icon: Icons.chevron_left_rounded,  onTap: _prev, color: accent),
            Expanded(
              child: Text('${_months[_month - 1]} $_year',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13.5,
                  fontWeight: FontWeight.w700, color: t.text)),
            ),
            _CalBtn(icon: Icons.chevron_right_rounded, onTap: _next, color: accent),
          ]),
          const SizedBox(height: 12),
          // Weekday header
          Row(children: _weekdays.map((d) => Expanded(
            child: Text(d,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5, fontWeight: FontWeight.w700,
                color: d == 'Su' || d == 'Sa' ? accent.withValues(alpha: 0.55) : t.muted)),
          )).toList()),
          const SizedBox(height: 6),
          // Day grid
          ...List.generate(cells.length ~/ 7, (week) => Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(children: List.generate(7, (col) {
              final date = cells[week * 7 + col];
              if (date == null) return const Expanded(child: SizedBox(height: 38));
              final isSel    = widget.selectedDate != null && DateUtils.isSameDay(date, widget.selectedDate);
              final isToday  = DateUtils.isSameDay(date, today);
              final isPast   = date.isBefore(widget.firstDate);
              final isFuture = date.isAfter(widget.lastDate);
              final disabled = isPast || isFuture;
              return Expanded(
                child: MouseRegion(
                  cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: disabled ? null : () => widget.onDateSelected(date),
                    child: Container(
                      height: 38, alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color:  isSel ? accent : Colors.transparent,
                        shape:  BoxShape.circle,
                        border: isToday && !isSel ? Border.all(color: accent, width: 1.5) : null,
                      ),
                      child: Text('${date.day}',
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 12.5,
                          fontWeight: isSel || isToday ? FontWeight.w700 : FontWeight.w500,
                          color: isSel     ? Colors.white
                              : disabled   ? t.muted
                              : isToday    ? accent
                              : t.text,
                        )),
                    ),
                  ),
                ),
              );
            })),
          )),
        ],
      ),
    );
  }
}

class _CalBtn extends StatelessWidget {
  final IconData     icon;
  final VoidCallback onTap;
  final Color        color;
  const _CalBtn({required this.icon, required this.onTap, required this.color});

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30, height: 30,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
    ),
  );
}

// ── Inline time picker (drum-style, matches mobile) ──────────────────────────

class _WebTimePicker extends StatefulWidget {
  final TimeOfDay?              initialTime;
  final Color                   accentColor;
  final String                  label;
  final ValueChanged<TimeOfDay> onTimeSet;
  final TimeOfDay?              minTime;
  const _WebTimePicker({
    super.key,
    required this.initialTime,
    required this.accentColor,
    required this.label,
    required this.onTimeSet,
    this.minTime,
  });

  @override
  State<_WebTimePicker> createState() => _WebTimePickerState();
}

class _WebTimePickerState extends State<_WebTimePicker> {
  late FixedExtentScrollController _hourCtrl;
  late FixedExtentScrollController _minCtrl;
  late bool _isAm;
  bool _pastError = false;

  static const _itemH = 46.0;

  @override
  void initState() {
    super.initState();
    final t = widget.initialTime ?? TimeOfDay.now();
    _isAm     = t.hour < 12;
    final h   = t.hour % 12 == 0 ? 12 : t.hour % 12;
    _hourCtrl = FixedExtentScrollController(initialItem: 600 + (h - 1));
    _minCtrl  = FixedExtentScrollController(initialItem: 600 + t.minute);
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minCtrl.dispose();
    super.dispose();
  }

  TimeOfDay _result() {
    final h12 = (_hourCtrl.selectedItem % 12) + 1;
    final min  = _minCtrl.selectedItem % 60;
    final h24  = _isAm ? (h12 == 12 ? 0 : h12) : (h12 == 12 ? 12 : h12 + 12);
    return TimeOfDay(hour: h24, minute: min);
  }

  String _fmtMinTime(TimeOfDay t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final p = t.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $p';
  }

  @override
  Widget build(BuildContext context) {
    final t      = WebTk(Theme.of(context).brightness == Brightness.dark);
    final accent = widget.accentColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.access_time_rounded, color: accent, size: 15),
            ),
            const SizedBox(width: 10),
            Text(widget.label,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                fontWeight: FontWeight.w700, color: accent)),
            const Spacer(),
            Text(
              widget.minTime != null
                  ? 'Today — from ${_fmtMinTime(widget.minTime!)} onwards'
                  : 'Scroll to select',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5, color: t.muted),
            ),
          ]),
          const SizedBox(height: 10),
          Divider(height: 1, color: t.divider),
          const SizedBox(height: 10),
          // Drums row
          SizedBox(
            height: _itemH * 3,
            child: Row(
              children: [
                // Hour drum
                Expanded(child: _drum(
                  ctrl: _hourCtrl, count: 12,
                  label: (i) => '${i + 1}'.padLeft(2, '0'),
                  accent: accent,
                )),
                // Colon separator
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(width: 5, height: 5,
                      decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
                    const SizedBox(height: 8),
                    Container(width: 5, height: 5,
                      decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
                  ]),
                ),
                // Minute drum
                Expanded(child: _drum(
                  ctrl: _minCtrl, count: 60,
                  label: (i) => '$i'.padLeft(2, '0'),
                  accent: accent,
                )),
                const SizedBox(width: 12),
                // AM / PM
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: ['AM', 'PM'].map((p) {
                    final sel = (p == 'AM') == _isAm;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => setState(() { _isAm = p == 'AM'; _pastError = false; }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 52, height: _itemH,
                            decoration: BoxDecoration(
                              color: sel ? accent : t.inputBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: sel ? accent : t.border, width: 1.5),
                            ),
                            child: Center(child: Text(p,
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: sel ? Colors.white : t.sub))),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Past-time error
          if (_pastError)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.schedule_rounded, color: Colors.red.shade700, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'This time has already passed. Please pick a later time.',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                            fontWeight: FontWeight.w500, color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Set button
          SizedBox(
            width: double.infinity, height: 42,
            child: ElevatedButton.icon(
              onPressed: () {
                final res = _result();
                if (widget.minTime != null) {
                  final selMin = res.hour * 60 + res.minute;
                  final minMin = widget.minTime!.hour * 60 + widget.minTime!.minute;
                  if (selMin < minMin) { setState(() => _pastError = true); return; }
                }
                widget.onTimeSet(res);
              },
              icon: const Icon(Icons.check_rounded, size: 16),
              label: Text('Set ${widget.label}',
                style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _drum({
    required FixedExtentScrollController ctrl,
    required int count,
    required String Function(int) label,
    required Color accent,
  }) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          height: _itemH,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: 0.22)),
          ),
        ),
        // One number per wheel notch / swipe (a notch used to skip one).
        SteppedWheel(
          controller: ctrl,
          itemExtent: _itemH,
          childCount: count * 1000,
          onSelectedItemChanged: (_) => setState(() => _pastError = false),
          itemBuilder: (_, i) {
            final idx   = i % count;
            final isSel = ctrl.hasClients && ctrl.selectedItem % count == idx;
            return Center(child: Text(label(idx),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize:   isSel ? 28 : 18,
                fontWeight: isSel ? FontWeight.w800 : FontWeight.w400,
                color:      isSel ? accent : t.muted,
              )));
          },
        ),
        Positioned(top: 0, left: 0, right: 0,
          child: IgnorePointer(child: Container(
            height: _itemH * 1.2,
            decoration: BoxDecoration(gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [t.card, t.card.withValues(alpha: 0)],
            )),
          ))),
        Positioned(bottom: 0, left: 0, right: 0,
          child: IgnorePointer(child: Container(
            height: _itemH * 1.2,
            decoration: BoxDecoration(gradient: LinearGradient(
              begin: Alignment.bottomCenter, end: Alignment.topCenter,
              colors: [t.card, t.card.withValues(alpha: 0)],
            )),
          ))),
      ],
    );
  }
}

// ── Event details dialog ──────────────────────────────────────────────────────

class _EventDetailsDialog extends StatefulWidget {
  final Map<String, dynamic> event;
  const _EventDetailsDialog({required this.event});

  @override
  State<_EventDetailsDialog> createState() => _EventDetailsDialogState();
}

class _EventDetailsDialogState extends State<_EventDetailsDialog> {
  bool _loading = true;
  // Live copy of the event: approval, cancellation and edits from the app
  // or the admin show while the dialog is open.
  late Map<String, dynamic> _event = widget.event;
  List<Map<String, dynamic>> _registrations = [];
  RealtimeChannel? _channel;
  Timer? _debounce;
  // Upcoming → Ongoing → Check-in open → Ended follow the clock.
  Timer? _clock;
  bool _fetching = false;     // a load is running…
  bool _refetch = false;      // …and a change arrived meanwhile
  String? _organizerName;
  int?    _studentCount = StudentCountService.cached;

  // Student profiles (photo, grade, strand, section) keyed by user_id.
  Map<String, Map<String, dynamic>> _profiles = {};
  bool   _showAllRegs = false;
  String _regQuery    = '';
  String _regStatus   = 'all';

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _debounce?.cancel();
    if (_channel != null) SupabaseService.client.removeChannel(_channel!);
    super.dispose();
  }

  String? get _eventId => widget.event['event_id'] as String?;

  void _subscribe() {
    final id = _eventId;
    if (id == null) return;
    _channel = SupabaseService.client.channel('org-event-details-$id')
      ..on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(
          event: 'UPDATE',
          schema: 'public',
          table: 'events',
          filter: 'event_id=eq.$id',
        ),
        (payload, [_]) {
          final row = realtimeRow(payload);
          if (row != null && mounted) setState(() => _event = {..._event, ...row});
        },
      )
      ..on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(event: '*', schema: 'public', table: 'registrations'),
        (payload, [_]) {
          final row = realtimeRow(payload);
          if (row == null) return;
          final eventId = row['event_id'];
          // A deleted registration only carries its id.
          final mine = eventId != null
              ? eventId == id
              : _registrations.any((r) => r['id'] == row['id']);
          if (!mine) return;
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 500), () {
            if (mounted) _load();
          });
        },
      )
      ..subscribe();
  }

  Future<void> _load() async {
    final eventId = _eventId;
    if (eventId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (_fetching) {
      _refetch = true;
      return;
    }
    _fetching = true;
    try {
      final regsRaw = await SupabaseService.client
          .from('registrations')
          .select()
          .eq('event_id', eventId)
          .order('registered_at', ascending: false);

      String? orgName;
      final orgId = _event['organizer_id'] as String?;
      if (orgId != null && _organizerName == null) {
        final orgRow = await SupabaseService.client
            .from('organizers')
            .select('full_name')
            .eq('organizer_id', orgId)
            .maybeSingle();
        orgName = orgRow?['full_name'] as String?;
      } else {
        orgName = _organizerName;
      }

      final regs = List<Map<String, dynamic>>.from(regsRaw as List);
      final more = await Future.wait<Object?>([
        loadRegistrantProfiles(regs.map((r) => r['student_user_id'] as String?)),
        StudentCountService.activeStudents(),
      ]);

      if (!mounted) return;
      setState(() {
        _registrations = regs;
        _profiles      = more[0] as Map<String, Map<String, dynamic>>;
        _studentCount  = more[1] as int?;
        _organizerName = orgName;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    } finally {
      _fetching = false;
      if (_refetch && mounted) {
        _refetch = false;
        _load();
      }
    }
  }

  Map<String, dynamic> get _e => _event;

  String get _title    => _e['title'] as String? ?? '—';
  String get _location => _e['location'] as String? ?? '—';
  String get _type     => _e['event_type'] as String? ?? '—';
  String get _desc     => _e['description'] as String? ?? '';
  String? get _imgUrl  => _e['event_image_url'] as String?;

  // Capacity = every active student (0 until the count is known, which hides
  // the "of N" parts).
  int get _capacity   => _studentCount ?? 0;
  // Declined registrations don't count (countsAsRegistered).
  int get _registered => _registrations.isNotEmpty
      ? _registrations.where(countsAsRegistered).length
      : (_e['current_participants'] as int? ?? 0);
  int get _checkedIn =>
      _registrations.where((r) => r['status'] == 'checked_in').length;
  int get _pending => _registrations.where(
      (r) => r['status'] == 'pending' || r['status'] == 'qr_scanned').length;
  int get _remaining =>
      _capacity > 0 ? (_capacity - _registered).clamp(0, _capacity) : 0;
  double get _fillRatio => capacityFill(_registered, _capacity);
  // Of the students who registered, how many came — measuring against the
  // whole school would make a packed 40-seat seminar read 20%.
  int get _attendancePct =>
      _registered > 0 ? (_checkedIn / _registered * 100).clamp(0, 100).toInt() : 0;

  String  get _approval => approvalStatusOf(_e);
  String? get _rejectionReason => rejectionReasonOf(_e);
  bool get _datePassed {
    final w = eventWindow(_e);
    return w != null && !DateTime.now().isBefore(w.start);
  }

  String get _fmtTimeRange {
    final s  = _e['start_time'] as String?;
    final en = _e['end_time'] as String?;
    if (s == null || s.isEmpty) return '—';
    return en != null && en.isNotEmpty ? '${webFmtTime(s)} — ${webFmtTime(en)}' : webFmtTime(s);
  }

  @override
  Widget build(BuildContext context) {
    final t         = WebTk(Theme.of(context).brightness == Brightness.dark);
    final resolved  = _resolveDisplayStatus(_e);
    final sc        = checkInOpenUntil(_e) != null
        ? kCheckInOpenColor
        : webEventStatusColor(resolved);
    final statusLbl = organizerEventStatusLabel(_e);
    final typeData  = _kTypes.firstWhere(
      (tp) => tp.$1 == _type,
      orElse: () => _kTypes.last,
    );

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: t.card,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
              decoration: BoxDecoration(
                color: t.inputBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(bottom: BorderSide(color: t.border)),
              ),
              child: Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: typeData.$3.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: typeData.$3.withValues(alpha: 0.18)),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: _imgUrl != null && _imgUrl!.isNotEmpty
                      ? Image.network(_imgUrl!, fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Icon(typeData.$2, color: typeData.$3, size: 20))
                      : Icon(typeData.$2, color: typeData.$3, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_title,
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700, color: t.text),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 5),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        WebStatusBadge(label: _type, color: typeData.$3),
                        WebStatusBadge(label: statusLbl, color: sc),
                        if (eventIsArchived(_e))
                          const WebStatusBadge(label: 'Archived', color: Color(0xFF6366F1)),
                        if (_approval != 'approved')
                          WebStatusBadge(
                            label: approvalLabelFor(_e),
                            color: approvalColorFor(_e)),
                      ]),
                    ],
                  ),
                ),
                // Only a live event that ended has an attendance record.
                if (resolved == 'ended' && _approval == 'approved') ...[
                  const SizedBox(width: 8),
                  WebBtn(
                    label: 'Export',
                    icon: Icons.download_rounded,
                    small: true,
                    onTap: () => showAttendanceExportDialog(context, _e),
                  ),
                ],
                const SizedBox(width: 8),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(color: t.divider, borderRadius: BorderRadius.circular(8)),
                      child: Icon(Icons.close_rounded, size: 16, color: t.sub),
                    ),
                  ),
                ),
              ]),
            ),
            // Body
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator(color: kGold)),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_approval == 'rejected' && (_rejectionReason ?? '').isNotEmpty) ...[
                            _DialogSection(
                              icon: Icons.block_rounded,
                              iconBg: const Color(0x1AEF4444),
                              iconColor: const Color(0xFFEF4444),
                              title: 'Rejected by Admin',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_rejectionReason!,
                                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                                        color: t.text, height: 1.5)),
                                  const SizedBox(height: 6),
                                  Text(_datePassed
                                      ? 'Its date has passed — edit it with a new date to resubmit it for review.'
                                      : 'Edit and save this event to resubmit it for review.',
                                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                                        color: t.muted, fontStyle: FontStyle.italic)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                          if (eventIsCancelled(_e)) ...[
                            _DialogSection(
                              icon: Icons.event_busy_rounded,
                              iconBg: const Color(0x1AEF4444),
                              iconColor: const Color(0xFFEF4444),
                              title: 'Event cancelled',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text((_e['cancel_reason'] as String?)?.trim().isNotEmpty == true
                                          ? _e['cancel_reason'] as String
                                          : 'No reason recorded.',
                                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                                        color: t.text, height: 1.5)),
                                  const SizedBox(height: 6),
                                  Text('Registered students were notified. Registrations and '
                                      'attendance records are kept.',
                                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                                        color: t.muted, fontStyle: FontStyle.italic)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                          _buildStatsStrip(t),
                          const SizedBox(height: 14),
                          _DialogSection(
                            icon: Icons.info_outline_rounded,
                            iconBg: kGoldLight,
                            iconColor: kGold,
                            title: 'Event Information',
                            child: Column(children: [
                              _infoRow(Icons.calendar_today_rounded, const Color(0xFF2563EB), 'Date', webFmtDate(_e['event_date'] as String?), t),
                              _divider(t),
                              _infoRow(Icons.access_time_rounded, const Color(0xFF16A34A), 'Time', _fmtTimeRange, t),
                              _divider(t),
                              _infoRow(Icons.location_on_rounded, kGold, 'Venue', _location, t),
                              _divider(t),
                              _infoRow(Icons.person_rounded, const Color(0xFFEA580C), 'Organizer', _organizerName ?? '—', t),
                            ]),
                          ),
                          const SizedBox(height: 14),
                          _DialogSection(
                            icon: Icons.people_rounded,
                            iconBg: kGoldLight,
                            iconColor: kGold,
                            title: 'Registration Fill',
                            child: _buildFill(t),
                          ),
                          if (_desc.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            _DialogSection(
                              icon: Icons.notes_rounded,
                              iconBg: const Color(0x1A7C3AED),
                              iconColor: const Color(0xFF7C3AED),
                              title: 'About This Event',
                              child: Text(_desc,
                                style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.sub, height: 1.6)),
                            ),
                          ],
                          const SizedBox(height: 14),
                          _DialogSection(
                            icon: Icons.list_alt_rounded,
                            iconBg: const Color(0x1A16A34A),
                            iconColor: const Color(0xFF16A34A),
                            title: 'Recent Registrations',
                            child: _buildRegistrations(t),
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

  Widget _divider(WebTk t) => Divider(height: 16, thickness: 0.8, color: t.divider);

  Widget _infoRow(IconData icon, Color color, String label, String value, WebTk t) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, color: color, size: 15),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted)),
              const SizedBox(height: 2),
              Text(value, style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: t.text)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsStrip(WebTk t) {
    final data = [
      (value: '$_registered',     label: 'Registered', icon: Icons.confirmation_num_outlined, color: kGold),
      (value: '$_checkedIn',      label: 'Checked In',  icon: Icons.how_to_reg_rounded,        color: const Color(0xFF16A34A)),
      (value: _capacity > 0 ? '$_remaining' : '—', label: 'Remaining', icon: Icons.event_seat_rounded, color: const Color(0xFF2563EB)),
      (value: '$_attendancePct%', label: 'Attendance',  icon: Icons.bar_chart_rounded,         color: const Color(0xFF7C3AED)),
    ];
    return Row(
      children: data.asMap().entries.map((entry) {
        final d = entry.value;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(left: entry.key == 0 ? 0 : 8),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            decoration: BoxDecoration(
              color: d.color.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: d.color.withValues(alpha: 0.2)),
            ),
            child: Column(children: [
              Icon(d.icon, color: d.color, size: 17),
              const SizedBox(height: 5),
              Text(d.value, style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w800, color: d.color)),
              const SizedBox(height: 2),
              Text(d.label, style: TextStyle(fontFamily: 'Poppins', fontSize: 9, color: t.muted), textAlign: TextAlign.center),
            ]),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFill(WebTk t) {
    // One colour: capacity is the whole student body, so a fuller event is
    // just a popular one — nobody is ever turned away.
    const fillColor = kGold;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: RichText(
              text: TextSpan(style: const TextStyle(fontFamily: 'Poppins'), children: [
                TextSpan(text: '$_registered',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: fillColor)),
                if (_capacity > 0)
                  TextSpan(text: ' / $_capacity',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: t.muted)),
              ]),
            ),
          ),
          if (_capacity > 0)
            Text('${(_fillRatio * 100).toInt()}%',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w800, color: fillColor)),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: _fillRatio, minHeight: 9,
            backgroundColor: t.divider,
            valueColor: AlwaysStoppedAnimation<Color>(fillColor),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _pill('$_pending Pending', const Color(0xFFF59E0B)),
          _pill('$_checkedIn Checked In', const Color(0xFF16A34A)),
          if (_capacity > 0) _pill('$_remaining Remaining', const Color(0xFF2563EB)),
        ]),
      ],
    );
  }

  Widget _pill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600, color: color)),
  );

  Widget _buildRegistrations(WebTk t) {
    if (_registrations.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(children: [
          Icon(Icons.inbox_outlined, size: 36, color: kGold.withValues(alpha: 0.3)),
          const SizedBox(height: 10),
          Text('No registrations yet',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: t.muted)),
        ]),
      );
    }
    final total = _registrations.length;
    final canFilter = _showAllRegs && total > 5;

    // Search (name or LRN) + status filter — only once the full list is open.
    final q = _regQuery.trim().toLowerCase();
    final qDigits = q.replaceAll(RegExp(r'\D'), '');
    final filtered = !canFilter ? _registrations : _registrations.where((r) {
      final st = r['status'] as String? ?? 'pending';
      if (_regStatus != 'all' && st != _regStatus) return false;
      if (q.isEmpty) return true;
      final name = '${r['student_name'] ?? ''} ${_profileFor(r)?['full_name'] ?? ''}'.toLowerCase();
      final lrn  = (r['student_school_id'] as String? ?? '').replaceAll(RegExp(r'\D'), '');
      return name.contains(q) || (qDigits.isNotEmpty && lrn.contains(qDigits));
    }).toList();
    final shown = _showAllRegs ? filtered : _registrations.take(5).toList();

    final statuses = <String>{for (final r in _registrations) r['status'] as String? ?? 'pending'};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canFilter) ...[
          Row(children: [
            Expanded(child: SizedBox(
              height: 38,
              child: TextField(
                onChanged: (v) => setState(() => _regQuery = v),
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: t.text),
                decoration: webInputDeco('Search name or LRN…',
                    icon: Icons.search_rounded, dark: t.dark).copyWith(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9)),
              ),
            )),
            const SizedBox(width: 8),
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: t.inputBg, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.border)),
              child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                value: _regStatus,
                dropdownColor: t.card,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: t.text),
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('All statuses')),
                  for (final s in statuses)
                    DropdownMenuItem(value: s, child: Text(webStatusLabel(s))),
                ],
                onChanged: (v) => setState(() => _regStatus = v ?? 'all'),
              )),
            ),
          ]),
          const SizedBox(height: 10),
        ],
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text('No registrations match your search.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.muted)),
          ),
        for (final r in shown) _registrationRow(r, t),
        if (total > 5) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() {
                _showAllRegs = !_showAllRegs;
                if (!_showAllRegs) { _regQuery = ''; _regStatus = 'all'; }
              }),
              icon: Icon(_showAllRegs ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 18),
              label: Text(_showAllRegs ? 'Show fewer' : 'Show all $total registrations',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
              style: TextButton.styleFrom(foregroundColor: kGold),
            ),
          ),
        ],
      ],
    );
  }

  Map<String, dynamic>? _profileFor(Map<String, dynamic> r) =>
      _profiles[r['student_user_id'] as String? ?? ''];

  // One clickable registrant row → opens the Student details panel.
  Widget _registrationRow(Map<String, dynamic> r, WebTk t) {
    final p      = _profileFor(r);
    final first  = (p?['first_name'] as String? ?? '').trim();
    final last   = (p?['last_name']  as String? ?? '').trim();
    final name   = first.isNotEmpty && last.isNotEmpty
        ? '$last, $first'
        : (p?['full_name'] as String? ?? r['student_name'] as String? ?? '—');
    final lrn    = formatLrn(r['student_school_id'] as String? ?? '');
    final grade  = p?['year_level'] as int?;
    final strand = (grade == 11 || grade == 12) ? (p?['strand'] as String?) : null;
    final rstat  = r['status'] as String? ?? 'pending';
    final color  = webStatusColor(rstat);
    final meta = [
      if (lrn.isNotEmpty) lrn,
      if (grade != null) 'G$grade${strand != null ? ' $strand' : ''}',
    ].join('  ·  ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final changed = await showStudentRegistrationPanel(context,
              registration: r,
              organizerId: _e['organizer_id'] as String?,
              profile: p,
              archived: eventIsArchived(_e));
          if (changed == true && mounted) _load();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          child: Row(children: [
            StudentAvatar(name: name.contains(',')
                    ? name.split(',').reversed.join(' ')
                    : name,
                photoUrl: p?['profile_image_url'] as String?, size: 36, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                      fontWeight: FontWeight.w600, color: t.text),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(meta.isEmpty ? '—' : meta,
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            WebStatusBadge(label: webStatusLabel(rstat), color: color),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 18, color: t.muted),
          ]),
        ),
      ),
    );
  }
}

class _ErrorBar extends StatelessWidget {
  final String message;
  const _ErrorBar({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFFEF2F2),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFFCA5A5)),
    ),
    child: Row(children: [
      const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFEF4444)),
      const SizedBox(width: 8),
      Expanded(
        child: Text(message,
          style: const TextStyle(
            fontFamily: 'Poppins', fontSize: 12, color: Color(0xFFB91C1C), height: 1.4,
          )),
      ),
    ]),
  );
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'create_event_screen.dart';
import 'event_actions.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/utils/date_utils.dart' show timeAgo;
import '../../../../shared/utils/realtime_utils.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/services/student_count_service.dart';
import '../../../../core/services/supabase_service.dart';

class EventDetailsScreen extends StatefulWidget {
  final Map<String, dynamic>? eventData;
  const EventDetailsScreen({super.key, this.eventData});

  @override
  State<EventDetailsScreen> createState() => _EventDetailsScreenState();
}

class _EventDetailsScreenState extends State<EventDetailsScreen> {
  // ── State ──────────────────────────────────────────────────────────────────
  bool _loading      = true;
  bool _loadError    = false;
  bool _descExpanded = false;

  Map<String, dynamic>? _event;
  List<Map<String, dynamic>> _registrations = [];
  String? _organizerName;
  String? _organizerId;
  int?    _studentCount = StudentCountService.cached;   // = capacity
  bool _actionBusy = false;   // cancel / restore in progress

  RealtimeChannel? _channel;
  Timer?           _debounce;
  bool _fetching = false;     // a load is running…
  bool _refetch  = false;     // …and another change arrived meanwhile

  String? get _eventId =>
      widget.eventData?['id'] as String? ?? widget.eventData?['event_id'] as String?;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadData();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    super.dispose();
  }

  // ── Live updates ───────────────────────────────────────────────────────────
  // Check-ins, new registrations and changes to the event itself (approval,
  // cancellation, edits from the web) show up without pulling to refresh.

  void _subscribeRealtime() {
    final id = _eventId;
    if (id == null || id.isEmpty) return;
    final channel = Supabase.instance.client.channel('org-mobile-event-$id');
    for (final table in const ['events', 'registrations']) {
      channel.on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(event: '*', schema: 'public', table: table),
        (payload, [ref]) {
          if (_concernsThisEvent(table, payload)) _scheduleRefresh();
        },
      );
    }
    _channel = channel..subscribe();
  }

  bool _concernsThisEvent(String table, Object? payload) {
    final row = realtimeRow(payload);
    if (row == null) return false;
    if (table == 'events') return row['event_id'] == _eventId;
    final eventId = row['event_id'];
    if (eventId != null) return eventId == _eventId;
    // A deleted registration only carries its id.
    return _registrations.any((r) => r['id'] == row['id']);
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted && !_loading) _loadData(silent: true);
    });
  }

  // ── Data fetch ─────────────────────────────────────────────────────────────

  /// [silent]: refresh in place (live updates, pull-to-refresh, after an
  /// action) — no full-screen loader, and a failure keeps what's on screen.
  Future<void> _loadData({bool silent = false}) async {
    if (_fetching) { _refetch = true; return; }
    final eventId = _eventId;

    if (eventId == null || eventId.isEmpty) {
      if (mounted) setState(() { _loading = false; _loadError = true; });
      return;
    }

    _fetching = true;
    if (!silent) setState(() { _loading = true; _loadError = false; });

    try {
      final sb = Supabase.instance.client;
      _organizerId ??= await SupabaseService.getCurrentOrganizerId();
      final organizerId = _organizerId;

      var eventQuery = sb.from('events').select().eq('event_id', eventId);
      if (organizerId != null && organizerId.isNotEmpty) {
        eventQuery = eventQuery.eq('organizer_id', organizerId);
      }

      final results = await Future.wait<dynamic>([
        eventQuery.maybeSingle(),
        sb.from('registrations')
            .select()
            .eq('event_id', eventId)
            .order('registered_at', ascending: false),
        StudentCountService.activeStudents(),
      ]);

      final eventRow = results[0] as Map?;
      final regs     = results[1] as List;
      final students = results[2] as int?;

      // The organizer's name doesn't change while this screen is open.
      var orgName = _organizerName;
      final orgId = eventRow?['organizer_id'] as String?;
      if (orgName == null && orgId != null) {
        final orgRow = await sb
            .from('organizers')
            .select('full_name')
            .eq('organizer_id', orgId)
            .maybeSingle();
        orgName = orgRow?['full_name'] as String?;
      }

      if (!mounted) return;
      setState(() {
        _event         = eventRow != null ? Map<String, dynamic>.from(eventRow) : null;
        _registrations = List<Map<String, dynamic>>.from(regs);
        _organizerName = orgName;
        _studentCount  = students;
        _loading       = false;
        _loadError     = false;
      });
    } catch (e) {
      debugPrint('EventDetailsScreen load error: $e');
      if (mounted && !silent) setState(() { _loading = false; _loadError = true; });
    } finally {
      _fetching = false;
      if (_refetch && mounted) {
        _refetch = false;
        _loadData(silent: true);
      }
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────
  // The same rules as the web Events table: edit upcoming / cancelled events,
  // cancel any approved event that hasn't ended (ongoing included), restore a
  // cancelled one before it ends.

  void _openEdit() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => CreateEventScreen(existing: _d)))
        .then((_) { if (mounted) _loadData(silent: true); });
  }

  Future<void> _runAction(Future<bool> Function() action) async {
    setState(() => _actionBusy = true);
    final changed = await action();
    if (!mounted) return;
    setState(() => _actionBusy = false);
    if (changed) _loadData(silent: true);
  }

  // ── Computed accessors ─────────────────────────────────────────────────────
  // Prefer live Supabase data; fall back to passed-in eventData.

  Map<String, dynamic> get _d => _event ?? widget.eventData ?? {};

  String  get _title    => _d['title']        as String? ?? _d['name']  as String? ?? '—';
  String  get _location => _d['location']     as String? ?? _d['venue'] as String? ?? '—';
  String  get _type     => _d['event_type']   as String? ?? _d['type']  as String? ?? '—';
  String  get _desc     => _d['description']  as String? ?? '';
  String? get _imgUrl   => _d['event_image_url'] as String?;
  // From the clock (cancellation is the only stored status that counts) —
  // the stored event_status is 'upcoming' for every live event.
  String  get _status   => eventStatusValue(_d);
  // Orthogonal to _status — admin moderation gate, not the event's own
  // lifecycle. See admin_web_events.dart / Section 18 of supabase_schema.sql.
  String  get _approval => (_d['approval_status'] as String? ?? 'approved').toLowerCase();
  String? get _rejectionReason => _d['rejection_reason'] as String?;

  // Capacity = every active student (0 until the count is known, which hides
  // the "of N" parts).
  int get _capacity   => _studentCount ?? 0;
  // Use registrations count as ground truth; fall back to DB column.
  int get _registered => _registrations.isNotEmpty
      ? _registrations.length
      : (_d['current_participants'] as int? ?? _d['registered'] as int? ?? 0);
  int get _checkedIn  =>
      _registrations.where((r) => r['status'] == 'checked_in').length;
  int get _pending    =>
      _registrations.where((r) =>
          r['status'] == 'pending' || r['status'] == 'qr_scanned').length;
  int get _remaining  =>
      _capacity > 0 ? (_capacity - _registered).clamp(0, _capacity) : 0;
  double get _fillRatio => capacityFill(_registered, _capacity);
  // Of the students who registered, how many came — measuring against the
  // whole school would make a packed 40-seat seminar read 20%.
  int get _attendancePct =>
      _registered > 0 ? (_checkedIn / _registered * 100).clamp(0, 100).toInt() : 0;

  // ── Formatting ─────────────────────────────────────────────────────────────

  String get _fmtDate {
    final d = _d['event_date'] as String?;
    if (d == null) return _d['date'] as String? ?? '—';
    try {
      final dt = DateTime.parse(d);
      const m = [
        'January','February','March','April','May','June',
        'July','August','September','October','November','December',
      ];
      return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) { return d; }
  }

  String get _fmtTime {
    final s  = _d['start_time'] as String?;
    final en = _d['end_time']   as String?;
    if (s == null) return _d['time'] as String? ?? '—';
    String fmt(String t) {
      final p = t.split(':');
      if (p.length < 2) return t;
      final h = int.tryParse(p[0]) ?? 0;
      return '${h % 12 == 0 ? 12 : h % 12}:${p[1]} ${h >= 12 ? 'PM' : 'AM'}';
    }
    return en != null ? '${fmt(s)} — ${fmt(en)}' : fmt(s);
  }

  String get _fmtDeadline {
    final iso = _d['registration_deadline'] as String?;
    if (iso == null) return 'No deadline set';
    try {
      final dt = DateTime.parse(iso).toLocal();
      const m = ['Jan','Feb','Mar','Apr','May','Jun',
                  'Jul','Aug','Sep','Oct','Nov','Dec'];
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '${m[dt.month - 1]} ${dt.day}, ${dt.year}  $hh:$mm';
    } catch (_) { return iso; }
  }

  Color get _statusColor {
    if (checkInOpenUntil(_d) != null) return kCheckInOpenColor;
    switch (_status) {
      case 'ongoing':   return const Color(0xFF16A34A);
      case 'ended':     return kMuted;
      case 'cancelled': return Colors.red;
      default:          return const Color(0xFFE87A00);
    }
  }

  String get _statusDisplay => organizerEventStatusLabel(_d);

  String _regStatusLabel(String s) {
    const map = {
      'pending':         'Pending',
      'qr_scanned':      'Scanned',
      'photo_required':  'Awaiting Selfie',
      'photo_submitted': 'Photo Submitted',
      'checked_in':      'Checked In',
      'rejected':        'Rejected',
    };
    return map[s] ?? s;
  }

  Color _regStatusColor(String s) {
    switch (s) {
      case 'checked_in':      return Colors.green;
      case 'photo_submitted': return const Color(0xFF2563EB);
      case 'photo_required':  return Colors.purple;
      case 'qr_scanned':      return Colors.orange;
      case 'rejected':        return Colors.red;
      default:                return kMuted;
    }
  }

  String _initials(String name) {
    final p = name.trim().split(' ');
    if (p.length >= 2) return '${p[0][0]}${p[1][0]}'.toUpperCase();
    return p.isNotEmpty && p[0].isNotEmpty ? p[0][0].toUpperCase() : '?';
  }

  String _fmtRegDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      const m = ['Jan','Feb','Mar','Apr','May','Jun',
                  'Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${m[dt.month - 1]} ${dt.day}';
    } catch (_) { return '—'; }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final t = AppTk(Theme.of(context).brightness == Brightness.dark);
    if (_loading) {
      return Scaffold(
        backgroundColor: t.bg,
        body: const AppFullScreenLoader(message: 'Loading event details…'),
      );
    }

    if (_loadError) {
      return Scaffold(
        backgroundColor: t.bg,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(Icons.cloud_off_rounded, size: 36, color: Color(0xFFEF4444)),
                ),
                const SizedBox(height: 20),
                Text(
                  'Could not load event details',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Check your connection and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: t.sub,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                ElevatedButton.icon(
                  onPressed: _loadData,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text(
                    'Retry',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kGold,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: t.bg,
        bottomNavigationBar: _buildActionBar(t),
        body: RefreshIndicator(
          color: kGold,
          onRefresh: () => _loadData(silent: true),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── Collapsible hero ───────────────────────────────────────────
              _buildHeroSliver(),

              // ── Cancellation reason (only when cancelled) ──────────────────
              if (eventIsCancelled(_d))
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: _buildCancelledCard(t),
                  ),
                ),

              // ── Rejection reason (only when rejected) ────────────────────────
              if (_approval == 'rejected' && (_rejectionReason ?? '').isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: _buildRejectionCard(t),
                  ),
                ),

              // ── Stats strip ────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _buildStatsStrip(t),
                ),
              ),

              // ── Event information ──────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: _buildInfoCard(t),
                ),
              ),

              // ── Capacity / fill bar ────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: _buildFillCard(t),
                ),
              ),

              // ── Description ────────────────────────────────────────────────
              if (_desc.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: _buildDescCard(t),
                  ),
                ),

              // ── Recent registrations ───────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: _buildRegistrationsCard(t),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Hero SliverAppBar ──────────────────────────────────────────────────────

  Widget _buildHeroSliver() {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      stretch: true,
      backgroundColor: Colors.black,
      surfaceTintColor: Colors.black,
      leading: Padding(
        padding: const EdgeInsets.all(8),
        child: CircleAvatar(
          backgroundColor: Colors.black.withValues(alpha: 0.42),
          child: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 16,
              color: Colors.white,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      actions: const [],
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Banner image or placeholder
            _imgUrl != null && _imgUrl!.isNotEmpty
                ? Image.network(
                    _imgUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) => _heroBg(),
                  )
                : _heroBg(),

            // Gradient: transparent â†’ dark
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.78),
                  ],
                  stops: const [0.38, 1.0],
                ),
              ),
            ),

            // Title + badges pinned to banner bottom
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    children: [
                      _heroBadge(_type, kGold),
                      _heroBadge(_statusDisplay, _statusColor),
                      if (_approval != 'approved')
                        _heroBadge(approvalLabelFor(_d), approvalColorFor(_d)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _title,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.2,
                      shadows: [
                        Shadow(blurRadius: 8, color: Colors.black54),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroBg() => Container(
    color: Colors.black,
    child: Center(
      child: Icon(
        Icons.event_rounded,
        size: 72,
        color: kGold.withValues(alpha: 0.3),
      ),
    ),
  );

  Widget _heroBadge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontFamily: 'Poppins',
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),
  );

  // ── Stats strip ────────────────────────────────────────────────────────────

  Widget _buildStatsStrip(AppTk t) {
    final data = [
      (value: '$_registered',    label: 'Registered',  icon: Icons.confirmation_num_outlined, color: kGold),
      (value: '$_checkedIn',     label: 'Checked In',  icon: Icons.how_to_reg_rounded,        color: const Color(0xFF16A34A)),
      (value: _capacity > 0 ? '$_remaining' : '—', label: 'Remaining', icon: Icons.event_seat_rounded, color: const Color(0xFF2563EB)),
      (value: '$_attendancePct%',label: 'Attendance',  icon: Icons.bar_chart_rounded,         color: const Color(0xFF7C3AED)),
    ];

    return Row(
      children: data.asMap().entries.map((entry) {
        final i = entry.key;
        final d = entry.value;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(left: i == 0 ? 0 : 8),
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 6),
            decoration: BoxDecoration(
              color: d.color.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: d.color.withValues(alpha: 0.2), width: 1.5,
              ),
            ),
            child: Column(
              children: [
                Icon(d.icon, color: d.color, size: 18),
                const SizedBox(height: 5),
                Text(
                  d.value,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: d.color,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  d.label,
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 9, color: t.muted,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Event Information card ─────────────────────────────────────────────────

  Widget _buildInfoCard(AppTk t) {
    final rows = [
      (icon: Icons.calendar_today_rounded, color: const Color(0xFF2563EB), label: 'Date',                value: _fmtDate),
      (icon: Icons.access_time_rounded,    color: const Color(0xFF16A34A), label: 'Time',                value: _fmtTime),
      (icon: Icons.location_on_rounded,    color: kGold,                   label: 'Venue',               value: _location),
      (icon: Icons.category_rounded,       color: const Color(0xFF7C3AED), label: 'Event Type',          value: _type),
      (icon: Icons.person_rounded,         color: const Color(0xFFEA580C), label: 'Organizer',           value: _organizerName ?? '—'),
      (icon: Icons.lock_clock_rounded,     color: t.muted,                 label: 'Reg. Deadline',       value: _fmtDeadline),
    ];

    return _sectionCard(t,
      icon: Icons.info_outline_rounded,
      iconBg: kGoldLight,
      iconColor: kGold,
      title: 'Event Information',
      child: Column(
        children: rows.asMap().entries.map((entry) {
          final i = entry.key;
          final r = entry.value;
          return Column(
            children: [
              _infoTile(r.icon, r.color, r.label, r.value, t),
              if (i < rows.length - 1)
                Divider(
                  height: 16,
                  thickness: 0.8,
                  color: t.divider,
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ── Cancellation card ──────────────────────────────────────────────────────
  // Why and when it was cancelled — the reason registered students were shown.

  Widget _buildCancelledCard(AppTk t) {
    const red    = Color(0xFFEF4444);
    final reason = (_d['cancel_reason'] as String?)?.trim() ?? '';
    final when   = timeAgo(_d['cancelled_at'] as String? ?? _d['updated_at'] as String?);
    return _sectionCard(t,
      icon: Icons.event_busy_rounded,
      iconBg: red.withValues(alpha: 0.12),
      iconColor: red,
      title: when.isEmpty ? 'Event Cancelled' : 'Event Cancelled · $when',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(reason.isEmpty ? 'No reason recorded.' : reason,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.5,
                color: reason.isEmpty ? t.muted : t.text,
                fontStyle: reason.isEmpty ? FontStyle.italic : FontStyle.normal)),
          const SizedBox(height: 8),
          Text(
            organizerCanRestoreEvent(_d)
                ? 'Registered students were notified. Registrations and attendance '
                  'records are kept — you can restore the event before it ends.'
                : 'Registered students were notified. Registrations and attendance '
                  'records are kept.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                color: t.muted, fontStyle: FontStyle.italic, height: 1.45)),
        ],
      ),
    );
  }

  // ── Action bar ─────────────────────────────────────────────────────────────
  // Only what this event allows right now; nothing at all once it has ended.

  Widget? _buildActionBar(AppTk t) {
    if (_loading || _loadError) return null;
    final canEdit    = organizerCanEditEvent(_d);
    final canCancel  = organizerCanCancelEvent(_d);
    final canRestore = organizerCanRestoreEvent(_d);
    if (!canEdit && !canCancel && !canRestore) return null;

    Widget? secondary;
    if (canCancel || canRestore) {
      final color = canRestore ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
      secondary = OutlinedButton.icon(
        onPressed: _actionBusy
            ? null
            : () => _runAction(() => canRestore
                ? restoreEventFlow(context, _d)
                : cancelEventFlow(context, _d)),
        icon: _actionBusy
            ? SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: color))
            : Icon(canRestore ? Icons.restore_rounded : Icons.event_busy_rounded,
                size: 18, color: color),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(canRestore ? 'Restore Event' : 'Cancel Event',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                fontWeight: FontWeight.w700, color: color)),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color.withValues(alpha: 0.55), width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    }

    final edit = canEdit
        ? ElevatedButton.icon(
            onPressed: _actionBusy ? null : _openEdit,
            icon: const Icon(Icons.edit_rounded, size: 18),
            label: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('Edit Event',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                    fontWeight: FontWeight.w700)),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: kGold,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          )
        : null;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: t.card,
          boxShadow: [BoxShadow(color: t.shadow, blurRadius: 20, offset: const Offset(0, -4))],
        ),
        child: Row(children: [
          if (secondary != null) Expanded(child: secondary),
          if (secondary != null && edit != null) const SizedBox(width: 12),
          if (edit != null) Expanded(child: edit),
        ]),
      ),
    );
  }

  // ── Rejection reason card ───────────────────────────────────────────────────
  // Editing and saving this event resubmits it for review — no separate
  // "resubmit" action needed (see _saveChanges in create_event_screen.dart).

  Widget _buildRejectionCard(AppTk t) {
    return _sectionCard(t,
      icon: Icons.block_rounded,
      iconBg: const Color(0xFFEF4444).withValues(alpha: 0.12),
      iconColor: const Color(0xFFEF4444),
      title: 'Rejected by Admin',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_rejectionReason ?? '',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                  color: t.text, height: 1.5)),
            const SizedBox(height: 8),
            Text('Edit and save this event to resubmit it for review.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                  color: t.muted, fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  Widget _infoTile(IconData icon, Color color, String label, String value, AppTk t) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: color, size: 17),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 11, color: t.muted,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
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
      ],
    );
  }

  // ── Registration fill card ─────────────────────────────────────────────────

  Widget _buildFillCard(AppTk t) {
    // One colour: capacity is the whole student body, so a fuller event is
    // just a popular one — nobody is ever turned away.
    const fillColor = kGold;

    return _sectionCard(t,
      icon: Icons.people_rounded,
      iconBg: kGoldLight,
      iconColor: kGold,
      title: 'Registration Fill',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Large number + capacity
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(fontFamily: 'Poppins'),
                        children: [
                          TextSpan(
                            text: '$_registered',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: fillColor,
                              height: 1.0,
                            ),
                          ),
                          if (_capacity > 0)
                            TextSpan(
                              text: ' / $_capacity',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: t.muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'students registered',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 12, color: t.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (_capacity > 0)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${(_fillRatio * 100).toInt()}%',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: fillColor,
                        height: 1.0,
                      ),
                    ),
                    Text(
                      'capacity used',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 11, color: t.muted,
                      ),
                    ),
                  ],
                ),
            ],
          ),

          const SizedBox(height: 14),

          // Animated progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: _fillRatio),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOut,
              builder: (_, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 10,
                backgroundColor: t.divider,
                valueColor: AlwaysStoppedAnimation<Color>(fillColor),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Pill breakdown
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _pillStat('$_pending Pending',     Colors.orange),
              _pillStat('$_checkedIn Checked In', const Color(0xFF16A34A)),
              if (_capacity > 0)
                _pillStat('$_remaining Remaining', const Color(0xFF2563EB)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pillStat(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  // ── Description card ───────────────────────────────────────────────────────

  Widget _buildDescCard(AppTk t) {
    const maxLen = 200;
    final isLong  = _desc.length > maxLen;
    final display = _descExpanded || !isLong
        ? _desc
        : '${_desc.substring(0, maxLen)}…';

    return _sectionCard(t,
      icon: Icons.notes_rounded,
      iconBg: const Color(0x1A7C3AED),
      iconColor: const Color(0xFF7C3AED),
      title: 'About This Event',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            display,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: t.sub,
              height: 1.65,
            ),
          ),
          if (isLong) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => setState(() => _descExpanded = !_descExpanded),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _descExpanded ? 'Show less' : 'Read more',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: kGold,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _descExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: kGold,
                    size: 18,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Recent Registrations card ──────────────────────────────────────────────

  Widget _buildRegistrationsCard(AppTk t) {
    final preview = _registrations.take(5).toList();

    return _sectionCard(t,
      icon: Icons.list_alt_rounded,
      iconBg: const Color(0x1A16A34A),
      iconColor: const Color(0xFF16A34A),
      title: 'Recent Registrations',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: kGoldLight,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '${_registrations.length} total',
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: kGold,
          ),
        ),
      ),
      child: preview.isEmpty
          ? _buildEmptyRegs(t)
          : Column(
              children: preview.asMap().entries.map((entry) {
                final i = entry.key;
                final r = entry.value;
                return Column(
                  children: [
                    _buildRegRow(r, t),
                    if (i < preview.length - 1)
                      Divider(
                        height: 16,
                        thickness: 0.8,
                        color: t.divider,
                      ),
                  ],
                );
              }).toList(),
            ),
    );
  }

  Widget _buildEmptyRegs(AppTk t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 44,
            color: kGold.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            'No registrations yet',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: t.muted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Students who register will appear here',
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 12, color: t.muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegRow(Map<String, dynamic> r, AppTk t) {
    final name   = r['student_name']      as String? ?? '—';
    final sid    = r['student_school_id'] as String? ?? '—';
    final status = r['status']            as String? ?? 'pending';
    final date   = r['registered_at']     as String? ?? '';
    final color  = _regStatusColor(status);

    return Row(
      children: [
        // Initials avatar
        CircleAvatar(
          radius: 20,
          backgroundColor: color.withValues(alpha: 0.12),
          child: Text(
            _initials(name),
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Name + ID + date
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              Text(
                '$sid  ·  ${date.isNotEmpty ? _fmtRegDate(date) : '—'}',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 11, color: t.muted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Status badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _regStatusLabel(status),
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  // ── Shared section card helper ─────────────────────────────────────────────

  Widget _sectionCard(AppTk t, {
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: t.shadow,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, color: iconColor, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                ),
                if (trailing case final Widget w) w,
              ],
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, thickness: 1, color: t.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: child,
          ),
        ],
      ),
    );
  }
}

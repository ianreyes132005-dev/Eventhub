import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/event_registration.dart';
import '../check_in/selfie_screen.dart';
import '../../../shared/widgets/qr_code_dialog.dart';
import '../../../core/services/registration_service.dart';
import '../../../core/services/student_count_service.dart';
import '../../../core/app_colors.dart';
import '../../../shared/widgets/error_alert.dart';

class EventDetailsPage extends StatefulWidget {
  final Map<String, dynamic> event;

  /// Pass the registration row if the student is already registered.
  final Map<String, dynamic>? registration;

  const EventDetailsPage({
    required this.event,
    this.registration,
    super.key,
  });

  @override
  State<EventDetailsPage> createState() => _EventDetailsPageState();
}

class _EventDetailsPageState extends State<EventDetailsPage> {
  // Live copies: refreshed whenever the event or the student's registration
  // changes in the database, so a cancellation, a new time or venue, the
  // registered count and the check-in status show up while the page is open.
  late Map<String, dynamic> _event = widget.event;
  Map<String, dynamic>? _reg;
  bool _registering = false;
  int? _studentCount = StudentCountService.cached;   // = capacity

  RealtimeChannel? _channel;
  Timer? _debounce;
  // Upcoming → Ongoing → Ended and Register → Closed follow the clock.
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _reg = widget.registration;
    _subscribe();
    _refresh();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _debounce?.cancel();
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    super.dispose();
  }

  String get _eventId => widget.event['event_id'] as String;

  void _subscribe() {
    void soon() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), () {
        if (mounted) _refresh();
      });
    }

    // The registrations channel isn't filtered: RLS already limits it to the
    // student's own rows, and a filtered channel never hears deletes.
    _channel = Supabase.instance.client.channel('student-event-$_eventId')
      ..on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(
          event: '*',
          schema: 'public',
          table: 'events',
          filter: 'event_id=eq.$_eventId',
        ),
        (_, [_]) => soon(),
      )
      ..on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(event: '*', schema: 'public', table: 'registrations'),
        (_, [_]) => soon(),
      )
      ..subscribe();
  }

  Future<void> _refresh() async {
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      final eventFuture =
          client.from('events').select().eq('event_id', _eventId).maybeSingle();
      if (uid == null) return;
      final regFuture = client
          .from('registrations')
          .select()
          .eq('event_id', _eventId)
          .eq('student_user_id', uid)
          .maybeSingle();
      final countFuture = StudentCountService.activeStudents();
      final ev = await eventFuture;
      final Map? reg = await regFuture;
      final count = await countFuture;
      if (!mounted) return;
      setState(() {
        if (ev != null) _event = Map<String, dynamic>.from(ev);
        _reg = reg == null ? null : Map<String, dynamic>.from(reg);
        _studentCount = count ?? _studentCount;
      });
    } catch (e) {
      // Offline for a moment: keep what's on screen.
      debugPrint('EventDetailsPage refresh failed: $e');
    }
  }

  // ── Data helpers ───────────────────────────────────────────────────────────

  Map<String, dynamic> get _e => _event;

  // Theme colours — this page used fixed light-mode colours, which made
  // headings and the Date / Time / Venue values unreadable in dark mode.
  AppTk get _t => AppTk(Theme.of(context).brightness == Brightness.dark);

  String get _title => _e['title'] as String? ?? '—';
  String get _location => _e['location'] as String? ?? '—';
  String get _description => (_e['description'] as String?)?.trim() ?? '';
  String get _type => _e['event_type'] as String? ?? '';
  String get _imageUrl => _e['event_image_url'] as String? ?? '';
  int get _registered => _e['current_participants'] as int? ?? 0;
  // Capacity = every active student (0 until the count is known, which hides
  // the "of N" parts). A student who hasn't registered always has a spot.
  int get _capacity => _studentCount ?? 0;
  double get _fillRatio => capacityFill(_registered, _capacity);

  String get _statusLabel => eventStatusLabel(_e);

  Color get _statusColor {
    switch (_statusLabel) {
      case 'Ongoing':   return const Color(0xFF16A34A);
      case 'Ended':     return kSubText;
      case 'Cancelled': return Colors.red;
      default:          return const Color(0xFFE87A00);
    }
  }

  String _fmtDate() {
    final d = _e['event_date'] as String?;
    if (d == null) return '—';
    try {
      final dt = DateTime.parse(d);
      const days = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
      const months = [
        'January','February','March','April','May','June',
        'July','August','September','October','November','December',
      ];
      return '${days[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) { return d; }
  }

  String _fmtTime(String? t) {
    if (t == null) return '—';
    final p = t.split(':');
    if (p.length < 2) return t;
    final h = int.tryParse(p[0]) ?? 0;
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${p[1]} $period';
  }

  String get _timeRange {
    final s = _fmtTime(_e['start_time'] as String?);
    final e = _fmtTime(_e['end_time'] as String?);
    if (s == '—') return '—';
    return e == '—' ? s : '$s — $e';
  }

  // The deadline when one is set, otherwise 2 hours after the start
  // (registrationClosesAt — the same rule the database enforces).
  String get _closesText {
    final dt = registrationClosesAt(_e);
    if (dt == null) return '—';
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${m[dt.month - 1]} ${dt.day}, $h:$mm ${dt.hour < 12 ? 'AM' : 'PM'}';
  }

  String get _createdText {
    final iso = _e['created_at'] as String?;
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) { return iso; }
  }

  bool get _isRegistered => _reg != null;

  // Shared rule (also enforced by the server): registration closes at the
  // deadline, else 2 hours after the event starts.
  RegistrationState get _regState => registrationState(_e);

  // Not cancelled / not ended.
  bool get _canRegister => _regState != RegistrationState.cancelled &&
      _regState != RegistrationState.ended &&
      _regState != RegistrationState.notApproved;

  // Registration window closed: deadline passed, or 2 hours into the event.
  bool get _isDeadlinePassed => _regState == RegistrationState.deadlinePassed ||
      _regState == RegistrationState.started;

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _handleRegister() async {
    setState(() => _registering = true);
    try {
      final row = await RegistrationService.register(
        eventId: _e['event_id'] as String,
        eventTitle: _title,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() { _reg = row; _registering = false; });
      RegistrationSuccessPopup.show(
        context,
        eventTitle: _title,
        onComplete: _showQR,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _registering = false);
        // e.g. "Registration is closed — the deadline has passed."
        showErrorAlert(context, e, title: 'Couldn’t register');
      }
    }
  }

  void _showQR() {
    if (_reg == null) return;
    QRCodeDialog.show(
      context,
      EventRegistration(
        registrationId: _reg!['id'] as String,
        eventTitle: _title,   // current name, not the copy from sign-up
        studentId: _reg!['student_school_id'] as String? ?? '',
        studentName: _reg!['student_name'] as String? ?? '',
        registrationDate:
            DateTime.tryParse(_reg!['registered_at'] as String? ?? '') ??
                DateTime.now(),
        qrCodeData: _reg!['qr_code'] as String,
        ticketCode: _reg!['ticket_code'] as String? ?? '—',
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppTk(Theme.of(context).brightness == Brightness.dark).bg,
        extendBodyBehindAppBar: true,
        body: Stack(
          children: [
            CustomScrollView(
              slivers: [
                _buildHero(context),
                SliverToBoxAdapter(
                  child: Transform.translate(
                    offset: const Offset(0, -28),
                    child: _buildBody(),
                  ),
                ),
              ],
            ),
            // Sticky bottom action bar
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: _buildBottomBar(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Hero image (collapsible) ──────────────────────────────────────────────

  Widget _buildHero(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      stretch: true,
      backgroundColor: _t.dark ? _t.navBg : kText,
      leading: Padding(
        padding: const EdgeInsets.all(8),
        child: CircleAvatar(
          backgroundColor: Colors.black.withValues(alpha: 0.45),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Banner image
            _imageUrl.isNotEmpty
                ? Image.network(
                    _imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) => _heroBg(),
                  )
                : _heroBg(),

            // Gradient overlay bottom â†’ top
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.75),
                  ],
                  stops: const [0.45, 1.0],
                ),
              ),
            ),

            // Event type chip + status in bottom-left
            Positioned(
              bottom: 52,
              left: 20,
              right: 20,
              child: Row(
                children: [
                  if (_type.isNotEmpty)
                    _heroBadge(_type, kGold),
                  const Spacer(),
                  _heroBadge(_statusLabel, _statusColor),
                ],
              ),
            ),

            // Title at the bottom of the hero
            Positioned(
              bottom: 16,
              left: 20,
              right: 20,
              child: Text(
                _title,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.25,
                  shadows: [
                    Shadow(blurRadius: 8, color: Colors.black54),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroBg() => Container(
        color: _t.dark ? _t.navBg : kText,
        child: Center(
          child: Icon(Icons.event, size: 72, color: kGold.withValues(alpha: 0.4)),
        ),
      );

  Widget _heroBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
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
  }

  // ── Scrollable body ────────────────────────────────────────────────────────

  Widget _buildBody() {
    return Container(
      decoration: BoxDecoration(
        color: AppTk(Theme.of(context).brightness == Brightness.dark).bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _t.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Cancelled — with the organizer's reason
          if (eventIsCancelled(_e))
            Container(
              margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.25)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.event_busy_rounded, size: 20, color: Color(0xFFDC2626)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('This event was cancelled', style: TextStyle(fontFamily: 'Poppins',
                      fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFFDC2626))),
                  if ((_e['cancel_reason'] as String?)?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 3),
                    Text(_e['cancel_reason'] as String, style: TextStyle(fontFamily: 'Poppins',
                        fontSize: 12.5, height: 1.5,
                        color: AppTk(Theme.of(context).brightness == Brightness.dark).sub)),
                  ],
                ])),
              ]),
            ),

          // Quick info chips row
          _buildQuickInfoRow(),

          // Divider
          _sectionDivider(),

          // About / description
          _buildAboutSection(),

          // Divider
          _sectionDivider(),

          // Capacity
          _buildCapacitySection(),

          // Divider
          _sectionDivider(),

          // Schedule
          _buildScheduleSection(),

          // Bottom padding for sticky bar
          const SizedBox(height: 110),
        ],
      ),
    );
  }

  // ── Quick info chips row ───────────────────────────────────────────────────

  Widget _buildQuickInfoRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date
          _infoTile(
            icon: Icons.calendar_today_rounded,
            label: 'Date',
            value: _fmtDate(),
          ),
          const SizedBox(height: 14),
          // Time
          _infoTile(
            icon: Icons.access_time_rounded,
            label: 'Time',
            value: _timeRange,
          ),
          const SizedBox(height: 14),
          // Location
          _infoTile(
            icon: Icons.location_on_rounded,
            label: 'Venue',
            value: _location,
          ),
        ],
      ),
    );
  }

  Widget _infoTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: kGold.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: kGold, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: _t.sub,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _t.text,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── About ──────────────────────────────────────────────────────────────────

  Widget _buildAboutSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('About This Event'),
          const SizedBox(height: 12),
          Text(
            _description.isNotEmpty
                ? _description
                : 'No description provided for this event.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              color: _description.isNotEmpty ? _t.sub : _t.muted,
              height: 1.65,
            ),
          ),
        ],
      ),
    );
  }

  // ── Capacity ───────────────────────────────────────────────────────────────

  // Capacity is the whole student body, so a fuller event is just a popular
  // one — one colour, and never "Full".
  Widget _buildCapacitySection() {
    final pct = (_fillRatio * 100).toInt();
    final spotsLeft = _capacity > 0 ? (_capacity - _registered).clamp(0, _capacity) : null;
    const barColor = kGold;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Registration'),
          const SizedBox(height: 16),

          // Stats row
          Row(
            children: [
              _miniStat(
                icon: Icons.people_alt_rounded,
                label: 'Registered',
                value: _capacity > 0
                    ? '$_registered / $_capacity'
                    : _registered.toString(),
                color: kGold,
              ),
              const SizedBox(width: 12),
              _miniStat(
                icon: Icons.event_seat_rounded,
                label: 'Spots Left',
                value: spotsLeft != null ? '$spotsLeft' : '—',
                color: const Color(0xFF16A34A),
              ),
              const SizedBox(width: 12),
              _miniStat(
                icon: Icons.bar_chart_rounded,
                label: 'Fill Rate',
                value: _capacity > 0 ? '$pct%' : '—',
                color: barColor,
              ),
            ],
          ),

          if (_capacity > 0) ...[
            const SizedBox(height: 14),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _fillRatio,
                minHeight: 10,
                backgroundColor: _t.shimmer1,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$_registered registered',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: _t.sub,
                  ),
                ),
                Text(
                  '$pct% of students',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: barColor,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: _t.sub),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _capacity > 0
                      ? 'Every student can register — the $_capacity spots are '
                        'the school’s total number of students.'
                      : 'Every student can register.',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                      color: _t.sub, height: 1.45),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final t = AppTk(Theme.of(context).brightness == Brightness.dark);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                color: _t.sub,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Schedule ───────────────────────────────────────────────────────────────

  Widget _buildScheduleSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Schedule'),
          const SizedBox(height: 16),
          _timelineItem(
            icon: Icons.play_circle_rounded,
            color: const Color(0xFF16A34A),
            label: 'Start',
            value: _fmtTime(_e['start_time'] as String?),
            isFirst: true,
          ),
          _timelineItem(
            icon: Icons.stop_circle_rounded,
            color: Colors.red,
            label: 'End',
            value: _fmtTime(_e['end_time'] as String?),
          ),
          _timelineItem(
            icon: Icons.lock_clock,
            color: kGold,
            label: 'Registration closes',
            value: _closesText,
            isLast: true,
          ),
          const SizedBox(height: 12),
          // Created at footer
          Row(
            children: [
              Icon(Icons.info_outline, size: 13, color: _t.muted),
              const SizedBox(width: 6),
              Text(
                'Published on $_createdText',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: _t.muted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timelineItem({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline line + dot
          SizedBox(
            width: 40,
            child: Column(
              children: [
                // Top line
                if (!isFirst)
                  Expanded(
                    flex: 1,
                    child: Center(
                      child: Container(
                        width: 2,
                        color: _t.border,
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 4),

                // Icon dot
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),

                // Bottom line
                if (!isLast)
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: Container(
                        width: 2,
                        color: _t.border,
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 4),
              ],
            ),
          ),

          const SizedBox(width: 14),

          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: _t.sub,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _t.text,
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

  // ── Sticky bottom action bar ───────────────────────────────────────────────

  Widget _buildBottomBar() {
    final t = AppTk(Theme.of(context).brightness == Brightness.dark);
    return Container(
      decoration: BoxDecoration(
        color: t.card,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      child: _isRegistered
          ? _registeredAction()
          : !_canRegister
              ? _closedButton()
              : _isDeadlinePassed
                  ? _deadlinePassedButton()
                  : _registerButton(),
    );
  }

  Widget _registerButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: _registering ? null : _handleRegister,
        icon: _registering
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : const Icon(Icons.how_to_reg_rounded, size: 20),
        label: Text(
          _registering ? 'Registering…' : 'Register for this Event',
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: kGold,
          foregroundColor: Colors.white,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  // The registered student's next step, following their ticket live: show
  // the QR → take the check-in photo → wait for the organizer → checked in.
  Widget _registeredAction() {
    return switch (_reg?['status'] as String? ?? 'pending') {
      'photo_required' => _actionButton(
          icon: Icons.photo_camera_rounded,
          label: 'Take Check-in Photo',
          color: kCheckInOpenColor,
          onPressed: _openSelfie,
        ),
      'photo_submitted' => _actionButton(
          icon: Icons.hourglass_top_rounded,
          label: 'Photo sent — waiting for the organizer',
        ),
      'checked_in' => _actionButton(
          icon: Icons.check_circle_rounded,
          label: 'Checked In',
          color: const Color(0xFF15803D),
          solidWhenDisabled: true,
        ),
      'rejected' => _actionButton(
          icon: Icons.block_rounded,
          label: 'Registration Declined',
          color: const Color(0xFFB91C1C),
          solidWhenDisabled: true,
        ),
      _ => _qrButton(),
    };
  }

  void _openSelfie() {
    final id = _reg?['id'] as String?;
    if (id == null) return;
    HapticFeedback.lightImpact();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SelfieScreen(registrationId: id),
      fullscreenDialog: true,
    ));
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    Color? color,
    VoidCallback? onPressed,
    bool solidWhenDisabled = false,
  }) {
    final solid = color ?? _t.sub;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: solid,
          foregroundColor: Colors.white,
          disabledBackgroundColor:
              solidWhenDisabled ? solid : _t.shimmer2,
          disabledForegroundColor:
              solidWhenDisabled ? Colors.white : _t.sub,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  Widget _qrButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF16A34A).withValues(alpha: 0.34),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: Ink(
            height: 54,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF15803D), Color(0xFF22C55E)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                _showQR();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.qr_code_2_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 13),
                    const Expanded(
                      child: Text(
                        'View My QR Code',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.white.withValues(alpha: 0.65),
                      size: 14,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _closedButton() {
    final isCancelled = _statusLabel == 'Cancelled';
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: null,
        icon: Icon(
          isCancelled ? Icons.cancel_rounded : Icons.lock_rounded,
          size: 20,
        ),
        label: Text(
          isCancelled ? 'Event Cancelled' : 'Registration Closed',
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _t.shimmer2,
          foregroundColor: _t.sub,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  Widget _deadlinePassedButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.timer_off_rounded, size: 20),
        label: Text(
          _regState == RegistrationState.started
              ? 'Registration Closed'
              : 'Registration Deadline Passed',
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _t.shimmer2,
          foregroundColor: _t.sub,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Poppins',
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: _t.text,
      ),
    );
  }

  Widget _sectionDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      color: _t.divider,
      indent: 20,
      endIndent: 20,
    );
  }
}

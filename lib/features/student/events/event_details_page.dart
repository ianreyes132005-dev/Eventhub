import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/event_registration.dart';
import '../../../shared/widgets/qr_code_dialog.dart';
import '../../../core/services/registration_service.dart';
import '../../../core/app_colors.dart';

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
  Map<String, dynamic>? _reg;
  bool _registering = false;

  @override
  void initState() {
    super.initState();
    _reg = widget.registration;
  }

  // ── Data helpers ───────────────────────────────────────────────────────────

  Map<String, dynamic> get _e => widget.event;

  String get _title => _e['title'] as String? ?? '—';
  String get _location => _e['location'] as String? ?? '—';
  String get _description => (_e['description'] as String?)?.trim() ?? '';
  String get _type => _e['event_type'] as String? ?? '';
  String get _imageUrl => _e['event_image_url'] as String? ?? '';
  int get _registered => _e['current_participants'] as int? ?? 0;
  int get _capacity => _e['max_participants'] as int? ?? 0;
  double get _fillRatio =>
      _capacity > 0 ? (_registered / _capacity).clamp(0.0, 1.0) : 0;

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

  String get _deadlineText {
    final iso = _e['registration_deadline'] as String?;
    if (iso == null) return 'None';
    try {
      final dt = DateTime.parse(iso).toLocal();
      const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) { return iso; }
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

  bool get _isFull => _capacity > 0 && _registered >= _capacity;
  bool get _isRegistered => _reg != null;

  // Registration is only allowed for upcoming and ongoing events.
  bool get _canRegister {
    final label = _statusLabel;
    return label == 'Upcoming' || label == 'Ongoing';
  }

  // True when the event has a registration deadline that has already passed.
  bool get _isDeadlinePassed {
    final iso = _e['registration_deadline'] as String?;
    if (iso == null) return false;
    try {
      return DateTime.now().toUtc().isAfter(DateTime.parse(iso));
    } catch (_) {
      return false;
    }
  }

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showQR() {
    if (_reg == null) return;
    QRCodeDialog.show(
      context,
      EventRegistration(
        registrationId: _reg!['id'] as String,
        eventId: _reg!['event_id'] as String,
        eventTitle: _reg!['event_title'] as String? ?? _title,
        studentId: _reg!['student_school_id'] as String? ?? '',
        studentName: _reg!['student_name'] as String? ?? '',
        registrationDate:
            DateTime.tryParse(_reg!['registered_at'] as String? ?? '') ??
                DateTime.now(),
        qrCodeData: _reg!['qr_code'] as String,
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: kBackground,
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
      backgroundColor: kText,
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
        color: kText,
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
      decoration: const BoxDecoration(
        color: kBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
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
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: kSubText,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: kText,
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
              color: _description.isNotEmpty ? kSubText : Colors.grey[400],
              height: 1.65,
            ),
          ),
        ],
      ),
    );
  }

  // ── Capacity ───────────────────────────────────────────────────────────────

  Widget _buildCapacitySection() {
    final pct = (_fillRatio * 100).toInt();
    final spotsLeft = _capacity > 0 ? _capacity - _registered : null;
    final barColor = _fillRatio >= 0.9
        ? Colors.red
        : _fillRatio >= 0.7
            ? Colors.orange
            : kGold;

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
                value: spotsLeft != null
                    ? (spotsLeft <= 0 ? 'Full' : spotsLeft.toString())
                    : 'Unlimited',
                color: _isFull ? Colors.red : const Color(0xFF16A34A),
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
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$_registered registered',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: kSubText,
                  ),
                ),
                Text(
                  '$pct% full',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: barColor,
                  ),
                ),
              ],
            ),
          ],
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
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: kCard,
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
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                color: kSubText,
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
            label: 'Registration Deadline',
            value: _deadlineText,
            isLast: true,
          ),
          const SizedBox(height: 12),
          // Created at footer
          Row(
            children: [
              Icon(Icons.info_outline, size: 13, color: Colors.grey[400]),
              const SizedBox(width: 6),
              Text(
                'Published on $_createdText',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: Colors.grey[400],
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
                        color: Colors.grey[200],
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
                        color: Colors.grey[200],
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
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: kSubText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: kText,
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
    return Container(
      decoration: BoxDecoration(
        color: kCard,
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
          ? _qrButton()
          : !_canRegister
              ? _closedButton()
              : _isDeadlinePassed
                  ? _deadlinePassedButton()
                  : _isFull
                      ? _fullButton()
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

  Widget _fullButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.block_rounded, size: 20),
        label: const Text(
          'Event is Full',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey[300],
          foregroundColor: kSubText,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
          backgroundColor: Colors.grey[300],
          foregroundColor: kSubText,
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
        label: const Text(
          'Registration Deadline Passed',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey[300],
          foregroundColor: kSubText,
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
      style: const TextStyle(
        fontFamily: 'Poppins',
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: kText,
      ),
    );
  }

  Widget _sectionDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      color: Colors.grey[100],
      indent: 20,
      endIndent: 20,
    );
  }
}

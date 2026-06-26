import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../core/app_colors.dart';

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

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ── Data fetch ─────────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() { _loading = true; _loadError = false; });

    final eventId = widget.eventData?['id']       as String? ??
                    widget.eventData?['event_id']  as String?;

    if (eventId == null || eventId.isEmpty) {
      if (mounted) setState(() { _loading = false; _loadError = true; });
      return;
    }

    try {
      final sb = Supabase.instance.client;

      final results = await Future.wait([
        sb.from('events')
            .select()
            .eq('event_id', eventId)
            .maybeSingle(),
        sb.from('registrations')
            .select()
            .eq('event_id', eventId)
            .order('registered_at', ascending: false),
      ]);

      final eventRow = results[0] as Map?;
      final regs     = results[1] as List;

      String? orgName;
      final orgId = eventRow?['organizer_id'] as String?;
      if (orgId != null) {
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
        _loading       = false;
      });
    } catch (e) {
      debugPrint('EventDetailsScreen load error: $e');
      if (mounted) setState(() { _loading = false; _loadError = true; });
    }
  }

  // ── Computed accessors ─────────────────────────────────────────────────────
  // Prefer live Supabase data; fall back to passed-in eventData.

  Map<String, dynamic> get _d => _event ?? widget.eventData ?? {};

  String  get _title    => _d['title']        as String? ?? _d['name']  as String? ?? '—';
  String  get _location => _d['location']     as String? ?? _d['venue'] as String? ?? '—';
  String  get _type     => _d['event_type']   as String? ?? _d['type']  as String? ?? '—';
  String  get _desc     => _d['description']  as String? ?? '';
  String? get _imgUrl   => _d['event_image_url'] as String?;
  String  get _status   =>
      ((_d['event_status'] as String?) ?? (_d['status'] as String?) ?? 'upcoming')
          .toLowerCase();

  int get _capacity   => _d['max_participants'] as int? ?? _d['capacity']   as int? ?? 0;
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
  double get _fillRatio =>
      _capacity > 0 ? (_registered / _capacity).clamp(0.0, 1.0) : 0;
  int get _attendancePct =>
      _capacity > 0 ? (_checkedIn / _capacity * 100).clamp(0, 100).toInt() : 0;

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
    switch (_status) {
      case 'ongoing':
      case 'active':    return const Color(0xFF16A34A);
      case 'past':
      case 'completed':
      case 'ended':     return kMuted;
      case 'cancelled': return Colors.red;
      default:          return const Color(0xFFE87A00);
    }
  }

  String get _statusDisplay {
    switch (_status) {
      case 'ongoing':   return 'Ongoing';
      case 'active':    return 'Active';
      case 'completed': return 'Completed';
      case 'past':      return 'Ended';
      case 'ended':     return 'Ended';
      case 'cancelled': return 'Cancelled';
      default:          return 'Upcoming';
    }
  }

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
    if (_loading) {
      return const Scaffold(
        backgroundColor: kBackgroundAlt,
        body: AppFullScreenLoader(message: 'Loading event details…'),
      );
    }

    if (_loadError) {
      return Scaffold(
        backgroundColor: kBackgroundAlt,
        appBar: AppBar(
          backgroundColor: kText,
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
                const Text(
                  'Could not load event details',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: kText,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Check your connection and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: kSubText,
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
        backgroundColor: kBackgroundAlt,
        body: RefreshIndicator(
          color: kGold,
          onRefresh: _loadData,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── Collapsible hero ───────────────────────────────────────────
              _buildHeroSliver(),

              // ── Stats strip ────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _buildStatsStrip(),
                ),
              ),

              // ── Event information ──────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: _buildInfoCard(),
                ),
              ),

              // ── Capacity / fill bar ────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: _buildFillCard(),
                ),
              ),

              // ── Description ────────────────────────────────────────────────
              if (_desc.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: _buildDescCard(),
                  ),
                ),

              // ── Recent registrations ───────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: _buildRegistrationsCard(),
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
      backgroundColor: kText,
      surfaceTintColor: kText,
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
    color: kText,
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

  Widget _buildStatsStrip() {
    final data = [
      (value: '$_registered',    label: 'Registered',  icon: Icons.confirmation_num_outlined, color: kGold),
      (value: '$_checkedIn',     label: 'Checked In',  icon: Icons.how_to_reg_rounded,        color: const Color(0xFF16A34A)),
      (value: '$_remaining',     label: 'Remaining',   icon: Icons.event_seat_rounded,        color: const Color(0xFF2563EB)),
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
                  style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 9, color: kMuted,
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

  Widget _buildInfoCard() {
    final rows = [
      (icon: Icons.calendar_today_rounded, color: const Color(0xFF2563EB), label: 'Date',                value: _fmtDate),
      (icon: Icons.access_time_rounded,    color: const Color(0xFF16A34A), label: 'Time',                value: _fmtTime),
      (icon: Icons.location_on_rounded,    color: kGold,                   label: 'Venue',               value: _location),
      (icon: Icons.category_rounded,       color: const Color(0xFF7C3AED), label: 'Event Type',          value: _type),
      (icon: Icons.person_rounded,         color: const Color(0xFFEA580C), label: 'Organizer',           value: _organizerName ?? '—'),
      (icon: Icons.lock_clock_rounded,     color: kMuted,                  label: 'Reg. Deadline',       value: _fmtDeadline),
    ];

    return _sectionCard(
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
              _infoTile(r.icon, r.color, r.label, r.value),
              if (i < rows.length - 1)
                Divider(
                  height: 16,
                  thickness: 0.8,
                  color: Colors.grey.shade100,
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _infoTile(IconData icon, Color color, String label, String value) {
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
                style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 11, color: kMuted,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
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

  // ── Registration fill card ─────────────────────────────────────────────────

  Widget _buildFillCard() {
    final fillColor = _fillRatio >= 0.9
        ? Colors.red
        : _fillRatio >= 0.7
            ? Colors.orange
            : kGold;

    return _sectionCard(
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
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: kMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'students registered',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 12, color: kMuted,
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
                    const Text(
                      'capacity used',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 11, color: kMuted,
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
                backgroundColor: Colors.grey.shade200,
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

  Widget _buildDescCard() {
    const maxLen = 200;
    final isLong  = _desc.length > maxLen;
    final display = _descExpanded || !isLong
        ? _desc
        : '${_desc.substring(0, maxLen)}…';

    return _sectionCard(
      icon: Icons.notes_rounded,
      iconBg: const Color(0x1A7C3AED),
      iconColor: const Color(0xFF7C3AED),
      title: 'About This Event',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            display,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: kSubText,
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

  Widget _buildRegistrationsCard() {
    final preview = _registrations.take(5).toList();

    return _sectionCard(
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
          ? _buildEmptyRegs()
          : Column(
              children: preview.asMap().entries.map((entry) {
                final i = entry.key;
                final r = entry.value;
                return Column(
                  children: [
                    _buildRegRow(r),
                    if (i < preview.length - 1)
                      Divider(
                        height: 16,
                        thickness: 0.8,
                        color: Colors.grey.shade100,
                      ),
                  ],
                );
              }).toList(),
            ),
    );
  }

  Widget _buildEmptyRegs() {
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
          const Text(
            'No registrations yet',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: kMuted,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Students who register will appear here',
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 12, color: kMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegRow(Map<String, dynamic> r) {
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
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: kText,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '$sid  ·  ${date.isNotEmpty ? _fmtRegDate(date) : '—'}',
                style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 11, color: kMuted,
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

  Widget _sectionCard({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: kText,
                    ),
                  ),
                ),
                if (trailing case final t?) t,
              ],
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, thickness: 1, color: Colors.grey.shade100),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: child,
          ),
        ],
      ),
    );
  }
}

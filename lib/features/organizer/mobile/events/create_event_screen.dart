import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../../../core/app_colors.dart';

// ── Event type data ────────────────────────────────────────────────────────
const List<(String, IconData, Color)> _kTypeData = [
  ('Concert',  Icons.music_note_rounded,  Color(0xFF7C3AED)),
  ('Sports',   Icons.sports_rounded,      Color(0xFF2563EB)),
  ('Workshop', Icons.build_rounded,       Color(0xFFEA580C)),
  ('Seminar',  Icons.school_rounded,      Color(0xFF0D9488)),
  ('Other',    Icons.more_horiz_rounded,  Color(0xFF6B7280)),
];

const _kBlue  = Color(0xFF2563EB);
const _kGreen = Color(0xFF16A34A);
const _kRed   = Color(0xFFDC2626);

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key});
  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  // ── Controllers ─────────────────────────────────────────────────────────────
  final _nameCtrl      = TextEditingController();
  final _venueCtrl     = TextEditingController();
  final _descCtrl      = TextEditingController();
  final _capacityCtrl  = TextEditingController();
  final _otherTypeCtrl = TextEditingController();

  // ── State ────────────────────────────────────────────────────────────────────
  DateTime?  _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  DateTime?  _registrationDeadline;
  String     _selectedEventType = 'Concert';
  File?      _selectedBanner;
  bool       _isPublishing  = false;
  bool       _showCalendar  = false;

  double get _formProgress {
    int done = 0;
    if (_nameCtrl.text.trim().isNotEmpty) done++;
    if (_selectedDate != null)            done++;
    if (_startTime != null)               done++;
    if (_endTime != null)                 done++;
    if (_venueCtrl.text.trim().isNotEmpty) done++;
    return done / 5;
  }

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(() => setState(() {}));
    _venueCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _venueCtrl.dispose();
    _descCtrl.dispose();
    _capacityCtrl.dispose();
    _otherTypeCtrl.dispose();
    super.dispose();
  }

  // ── Validation ───────────────────────────────────────────────────────────────

  bool _validateForm() {
    if (_nameCtrl.text.trim().isEmpty)  { _snack('Event name is required', isError: true); return false; }
    if (_selectedDate == null)           { _snack('Event date is required', isError: true); return false; }
    if (_startTime == null)              { _snack('Start time is required', isError: true); return false; }
    if (_endTime == null)                { _snack('End time is required',   isError: true); return false; }
    final startMin = _startTime!.hour * 60 + _startTime!.minute;
    final endMin   = _endTime!.hour   * 60 + _endTime!.minute;
    if (endMin <= startMin) { _snack('End time must be after start time', isError: true); return false; }
    final now = DateTime.now();
    if (DateUtils.isSameDay(DateUtils.dateOnly(_selectedDate!), DateUtils.dateOnly(now))) {
      final nowMin = now.hour * 60 + now.minute;
      if (startMin < nowMin) { _snack('Start time has already passed for today\'s event', isError: true); return false; }
      if (endMin   < nowMin) { _snack('End time has already passed for today\'s event',   isError: true); return false; }
    }
    if (_registrationDeadline != null) {
      final eventDay    = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
      final deadlineDay = DateTime(_registrationDeadline!.year, _registrationDeadline!.month, _registrationDeadline!.day);
      if (deadlineDay.isAfter(eventDay)) {
        _snack('Registration deadline must be on or before the event date', isError: true);
        return false;
      }
    }
    if (_venueCtrl.text.trim().isEmpty) { _snack('Venue is required',      isError: true); return false; }
    if (_selectedEventType == 'Other' && _otherTypeCtrl.text.trim().isEmpty) {
      _snack('Please specify the event type', isError: true); return false;
    }
    return true;
  }

  // ── Pickers ──────────────────────────────────────────────────────────────────

  void _toggleCalendar() => setState(() => _showCalendar = !_showCalendar);

  Future<void> _pickStartTime() async {
    final now     = DateTime.now();
    final isToday = _selectedDate != null &&
        DateUtils.isSameDay(DateUtils.dateOnly(_selectedDate!), DateUtils.dateOnly(now));
    final t = await showModalBottomSheet<TimeOfDay>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TimePickerSheet(
        title: 'Start Time', initialTime: _startTime, accentColor: _kGreen,
        minTime: isToday ? TimeOfDay(hour: now.hour, minute: now.minute) : null,
      ),
    );
    if (t != null) setState(() => _startTime = t);
  }

  Future<void> _pickEndTime() async {
    final now     = DateTime.now();
    final isToday = _selectedDate != null &&
        DateUtils.isSameDay(DateUtils.dateOnly(_selectedDate!), DateUtils.dateOnly(now));
    final t = await showModalBottomSheet<TimeOfDay>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TimePickerSheet(
        title: 'End Time', initialTime: _endTime, accentColor: _kRed,
        minTime: isToday ? TimeOfDay(hour: now.hour, minute: now.minute) : null,
      ),
    );
    if (t != null) setState(() => _endTime = t);
  }

  Future<void> _pickDeadline() async {
    final d = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DeadlinePickerSheet(initialDeadline: _registrationDeadline),
    );
    if (d != null) setState(() => _registrationDeadline = d);
  }

  // ── Banner ───────────────────────────────────────────────────────────────────

  Future<void> _uploadBanner() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false);
      if (!mounted) return;
      if (result != null && result.files.single.path != null) {
        setState(() => _selectedBanner = File(result.files.single.path!));
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Could not select image: $e', isError: true);
    }
  }

  // ── Publish ──────────────────────────────────────────────────────────────────

  Future<void> _publishEvent() async {
    if (!_validateForm()) return;
    final supabase = Supabase.instance.client;
    final user     = supabase.auth.currentUser;
    if (user == null) { _snack('Please log in again', isError: true); return; }
    setState(() => _isPublishing = true);
    try {
      final orgData = await supabase
          .from('organizers').select('organizer_id').eq('user_id', user.id).single();
      final customOrgId = orgData['organizer_id'];
      final eventType   = _selectedEventType == 'Other'
          ? _otherTypeCtrl.text.trim() : _selectedEventType;
      String? bannerUrl;
      if (_selectedBanner != null) {
        final fileName = 'banner_${DateTime.now().millisecondsSinceEpoch}_${_selectedBanner!.path.split('/').last}';
        final bytes    = await _selectedBanner!.readAsBytes();
        await supabase.storage.from('event-banners').uploadBinary(
          fileName, bytes,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
        );
        bannerUrl = supabase.storage.from('event-banners').getPublicUrl(fileName);
      }
      final d = _selectedDate!;
      await supabase.from('events').insert({
        'organizer_id':         customOrgId,
        'title':                _nameCtrl.text.trim(),
        'description':          _descCtrl.text.trim(),
        'event_type':           eventType,
        'location':             _venueCtrl.text.trim(),
        'max_participants':     int.tryParse(_capacityCtrl.text),
        'current_participants': 0,
        'event_status':         'upcoming',
        'event_date': '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}',
        'start_time': _startTime != null
            ? '${_startTime!.hour.toString().padLeft(2,'0')}:${_startTime!.minute.toString().padLeft(2,'0')}:00' : null,
        'end_time': _endTime != null
            ? '${_endTime!.hour.toString().padLeft(2,'0')}:${_endTime!.minute.toString().padLeft(2,'0')}:00' : null,
        'registration_deadline': _registrationDeadline?.toUtc().toIso8601String(),
        'event_image_url':       bannerUrl,
      });
      if (!mounted) return;
      setState(() => _isPublishing = false);
      await AppAlert.success(context,
        title: 'Event Published!',
        message: 'Your event is now live and students can register.',
        buttonText: 'Done',
        onDismiss: () => Navigator.pop(context),
      );
    } catch (e) {
      if (!mounted) return;
      AppAlert.error(context, title: 'Publish Failed', message: e.toString());
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String _fmtDate(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _weekdayFull(int weekday) {
    const days = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    return days[(weekday - 1).clamp(0, 6)];
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:         Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
      behavior:        SnackBarBehavior.floating,
      shape:           RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin:          const EdgeInsets.all(16),
    ));
  }

  void _adjustCapacity(int delta) {
    final next = ((int.tryParse(_capacityCtrl.text) ?? 0) + delta).clamp(0, 99999);
    _capacityCtrl.text = next == 0 ? '' : '$next';
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final t = AppTk(Theme.of(context).brightness == Brightness.dark);
    return Scaffold(
      backgroundColor: t.bg,
      bottomNavigationBar: _buildBottomBar(t),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildHeader(t),
                _buildProgressBar(t),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Column(
                      children: [
                        _buildEventDetailsSection(t),
                        const SizedBox(height: 14),
                        _buildScheduleSection(t),
                        const SizedBox(height: 14),
                        _buildVenueSection(t),
                        const SizedBox(height: 14),
                        _buildBannerSection(t),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isPublishing) const AppOverlayLoader(message: 'Publishing your event…'),
        ],
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────────

  Widget _buildHeader(AppTk t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: t.shadow, blurRadius: 10, offset: const Offset(0, 3))],
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: t.text),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Create Event', style: TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w800, color: t.text, height: 1.1)),
                Text('Fill in the event details below', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.sub)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Progress bar ─────────────────────────────────────────────────────────────

  Widget _buildProgressBar(AppTk t) {
    final progress = _formProgress;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Form completion', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted)),
              Text(
                '${(progress * 100).toInt()}%',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700,
                  color: progress == 1.0 ? const Color(0xFF16A34A) : kGold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              builder: (_, value, _) => LinearProgressIndicator(
                value: value, minHeight: 5,
                backgroundColor: t.divider,
                valueColor: AlwaysStoppedAnimation<Color>(
                  value == 1.0 ? const Color(0xFF16A34A) : kGold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Event Details section ────────────────────────────────────────────────────

  Widget _buildEventDetailsSection(AppTk t) {
    return _sectionCard(
      icon: Icons.event_note_rounded, iconBg: kGoldLight, iconColor: kGold,
      title: 'Event Details',
      t: t,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _inputField(label: 'Event Name', required: true, controller: _nameCtrl,
              hint: 'e.g. Annual Science Fair 2026', icon: Icons.title_rounded, t: t),
          const SizedBox(height: 18),
          _fieldLabel('Event Type', required: true, t: t),
          const SizedBox(height: 10),
          _buildTypeChips(t),
          if (_selectedEventType == 'Other') ...[
            const SizedBox(height: 12),
            _inputField(label: 'Specify type', controller: _otherTypeCtrl,
                hint: 'e.g. Academic Quiz, Cultural Night…', icon: Icons.edit_note_rounded, t: t),
          ],
          const SizedBox(height: 18),
          _inputField(label: 'Description', controller: _descCtrl,
              hint: 'Describe what the event is about…', icon: Icons.notes_rounded, maxLines: 4, t: t),
        ],
      ),
    );
  }

  Widget _buildTypeChips(AppTk t) {
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: _kTypeData.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final (label, icon, color) = _kTypeData[i];
          final selected = _selectedEventType == label;
          return GestureDetector(
            onTap: () => setState(() => _selectedEventType = label),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 74,
              decoration: BoxDecoration(
                color: selected ? kGold : t.inputBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: selected ? kGold : t.border, width: 1.5),
                boxShadow: selected
                    ? [BoxShadow(color: kGold.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 24, color: selected ? Colors.white : color),
                  const SizedBox(height: 5),
                  Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : t.text)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Schedule section — redesigned ─────────────────────────────────────────────

  Widget _buildScheduleSection(AppTk t) {
    return _sectionCard(
      icon: Icons.schedule_rounded,
      iconBg: const Color(0x1A2563EB),
      iconColor: _kBlue,
      title: 'Schedule',
      t: t,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDateField(t),
          const SizedBox(height: 16),
          _buildTimeRow(t),
          const SizedBox(height: 14),
          _buildDeadlineField(t),
        ],
      ),
    );
  }

  // ── Date field with inline collapsible calendar ───────────────────────────────

  Widget _buildDateField(AppTk t) {
    final filled = _selectedDate != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Event Date', required: true, t: t),
        const SizedBox(height: 8),
        // Trigger card
        GestureDetector(
          onTap: _toggleCalendar,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: filled ? _kBlue.withValues(alpha: 0.04) : t.card,
              borderRadius: BorderRadius.only(
                topLeft:     const Radius.circular(14),
                topRight:    const Radius.circular(14),
                bottomLeft:  Radius.circular(_showCalendar ? 0 : 14),
                bottomRight: Radius.circular(_showCalendar ? 0 : 14),
              ),
              border: Border.all(
                color: _showCalendar
                    ? _kBlue.withValues(alpha: 0.5)
                    : filled
                    ? _kBlue.withValues(alpha: 0.3)
                    : t.border,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                // Day badge or calendar icon
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: filled ? _kBlue : t.divider,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: filled
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _weekdayFull(_selectedDate!.weekday).substring(0, 3).toUpperCase(),
                              style: const TextStyle(fontFamily: 'Poppins', fontSize: 8, fontWeight: FontWeight.w700, color: Colors.white60, letterSpacing: 0.5),
                            ),
                            Text(
                              '${_selectedDate!.day}',
                              style: const TextStyle(fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white, height: 1.1),
                            ),
                          ],
                        )
                      : Icon(Icons.calendar_month_rounded, color: t.muted, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: filled
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_fmtDate(_selectedDate!),
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700, color: t.text)),
                            const SizedBox(height: 2),
                            Text(
                              _weekdayFull(_selectedDate!.weekday),
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('Event Date', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: t.text)),
                                const Text(' *', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.red, fontWeight: FontWeight.w700)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text('Tap to open calendar', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted)),
                          ],
                        ),
                ),
                AnimatedRotation(
                  turns: _showCalendar ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: _showCalendar ? _kBlue.withValues(alpha: 0.1) : t.divider,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.keyboard_arrow_down_rounded, size: 18,
                      color: _showCalendar ? _kBlue : t.muted),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Inline calendar — AnimatedSize expand/collapse
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: _showCalendar
              ? Container(
                  decoration: BoxDecoration(
                    color: t.card,
                    borderRadius: const BorderRadius.only(
                      bottomLeft:  Radius.circular(14),
                      bottomRight: Radius.circular(14),
                    ),
                    border: Border(
                      left:   BorderSide(color: _kBlue.withValues(alpha: 0.5), width: 1.5),
                      right:  BorderSide(color: _kBlue.withValues(alpha: 0.5), width: 1.5),
                      bottom: BorderSide(color: _kBlue.withValues(alpha: 0.5), width: 1.5),
                    ),
                  ),
                  child: _InlineCalendar(
                    selectedDate:    _selectedDate,
                    firstDate:       DateTime.now(),
                    lastDate:        DateTime.now().add(const Duration(days: 730)),
                    accentColor:     _kBlue,
                    onDateSelected:  (date) => setState(() {
                      _selectedDate  = date;
                      _showCalendar  = false;
                    }),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  // ── Time row ─────────────────────────────────────────────────────────────────

  Widget _buildTimeRow(AppTk t) {
    // Duration chip
    String? durationLabel;
    bool badDuration = false;
    if (_startTime != null && _endTime != null) {
      final diff = (_endTime!.hour * 60 + _endTime!.minute) -
                   (_startTime!.hour * 60 + _startTime!.minute);
      if (diff <= 0) {
        badDuration = true;
      } else {
        final h = diff ~/ 60, m = diff % 60;
        durationLabel = h > 0 ? (m > 0 ? '${h}h ${m}m' : '${h}h') : '${m}m';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _buildTimeCard(
              label: 'Start Time', required: true,
              time: _startTime, accentColor: _kGreen,
              icon: Icons.play_circle_outline_rounded,
              onTap: _pickStartTime,
              t: t,
            )),
            const SizedBox(width: 10),
            Expanded(child: _buildTimeCard(
              label: 'End Time', required: true,
              time: _endTime, accentColor: _kRed,
              icon: Icons.stop_circle_outlined,
              onTap: _pickEndTime,
              t: t,
            )),
          ],
        ),
        if (durationLabel != null || badDuration) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: badDuration ? Colors.orange.shade50 : _kGreen.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: badDuration ? Colors.orange.shade200 : _kGreen.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  badDuration ? Icons.warning_amber_rounded : Icons.timer_outlined,
                  size: 14,
                  color: badDuration ? Colors.orange.shade700 : _kGreen,
                ),
                const SizedBox(width: 6),
                Text(
                  badDuration ? 'End time must be after start time' : 'Duration: $durationLabel',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600,
                    color: badDuration ? Colors.orange.shade700 : _kGreen,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTimeCard({
    required String    label,
    required bool      required,
    required TimeOfDay? time,
    required Color     accentColor,
    required IconData  icon,
    required VoidCallback onTap,
    required AppTk t,
  }) {
    final filled = time != null;
    String fmt12(TimeOfDay tod) {
      final h = tod.hour % 12 == 0 ? 12 : tod.hour % 12;
      return '$h:${tod.minute.toString().padLeft(2,'0')}';
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          color: filled ? accentColor.withValues(alpha: 0.05) : t.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: filled ? accentColor.withValues(alpha: 0.35) : t.border,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 12, color: filled ? accentColor : t.muted),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(label, style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w600,
                    color: filled ? accentColor : t.muted)),
                ),
                if (required && !filled)
                  const Text('*', style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: Colors.red, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            if (filled) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(fmt12(time), style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 28, fontWeight: FontWeight.w800,
                    color: accentColor, height: 1.0)),
                  const SizedBox(width: 5),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(time.hour >= 12 ? 'PM' : 'AM',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w800, color: accentColor)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text('Tap to edit', style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: accentColor.withValues(alpha: 0.6))),
            ] else ...[
              Text('--:--', style: TextStyle(fontFamily: 'Poppins', fontSize: 28, fontWeight: FontWeight.w800, color: t.muted, height: 1.0)),
              const SizedBox(height: 3),
              Text('Tap to set', style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: t.muted)),
            ],
          ],
        ),
      ),
    );
  }

  // ── Deadline field ────────────────────────────────────────────────────────────

  Widget _buildDeadlineField(AppTk t) {
    final filled = _registrationDeadline != null;
    final d      = _registrationDeadline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _fieldLabel('Registration Deadline', t: t),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: t.divider, borderRadius: BorderRadius.circular(4)),
              child: Text('optional', style: TextStyle(fontFamily: 'Poppins', fontSize: 9, color: t.muted, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickDeadline,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: filled ? kGold.withValues(alpha: 0.04) : t.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: filled ? kGold.withValues(alpha: 0.4) : t.border,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: filled ? kGold.withValues(alpha: 0.12) : t.border,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(Icons.event_busy_rounded, size: 20, color: filled ? kGold : t.muted),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: filled && d != null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_fmtDate(d), style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700, color: t.text)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: kGold.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')} ${d.hour >= 12 ? 'PM' : 'AM'}',
                                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: kGold),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('No deadline set', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: t.text)),
                            const SizedBox(height: 2),
                            Text('Tap to add a registration deadline',
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted)),
                          ],
                        ),
                ),
                if (filled)
                  GestureDetector(
                    onTap: () => setState(() => _registrationDeadline = null),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Container(
                        width: 24, height: 24,
                        decoration: BoxDecoration(color: t.divider, shape: BoxShape.circle),
                        child: Icon(Icons.close_rounded, size: 14, color: t.muted),
                      ),
                    ),
                  )
                else
                  Icon(Icons.add_circle_outline_rounded, color: kGold.withValues(alpha: 0.5), size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Venue & Capacity section ─────────────────────────────────────────────────

  Widget _buildVenueSection(AppTk t) {
    return _sectionCard(
      icon: Icons.place_rounded, iconBg: const Color(0x1A16A34A), iconColor: const Color(0xFF16A34A),
      title: 'Venue & Capacity',
      t: t,
      child: Column(
        children: [
          _inputField(label: 'Venue / Location', required: true, controller: _venueCtrl,
              hint: 'e.g. School Gymnasium', icon: Icons.location_on_outlined, t: t),
          const SizedBox(height: 18),
          _buildCapacityField(t),
        ],
      ),
    );
  }

  Widget _buildCapacityField(AppTk t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Max Participants', optional: true, t: t),
        const SizedBox(height: 8),
        Row(
          children: [
            _stepBtn(Icons.remove_rounded, () => _adjustCapacity(-10)),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _capacityCtrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700, color: t.text),
                decoration: InputDecoration(
                  hintText: '—',
                  hintStyle: TextStyle(fontFamily: 'Poppins', fontSize: 16, color: t.muted),
                  filled: true, fillColor: t.inputBg,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border:        OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kGold, width: 2)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _stepBtn(Icons.add_rounded, () => _adjustCapacity(10)),
          ],
        ),
        const SizedBox(height: 6),
        Text('Leave blank for unlimited participants',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted)),
      ],
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 44, height: 48,
      decoration: BoxDecoration(
        color: kGoldLight, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kGold.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Icon(icon, color: kGold, size: 20),
    ),
  );

  // ── Banner section ────────────────────────────────────────────────────────────

  Widget _buildBannerSection(AppTk t) {
    return _sectionCard(
      icon: Icons.image_rounded, iconBg: const Color(0x1A7C3AED), iconColor: const Color(0xFF7C3AED),
      title: 'Event Banner',
      t: t,
      child: _selectedBanner != null ? _buildBannerPreview(t) : _buildBannerDropZone(t),
    );
  }

  Widget _buildBannerDropZone(AppTk t) {
    return GestureDetector(
      onTap: _uploadBanner,
      child: Container(
        width: double.infinity, height: 160,
        decoration: BoxDecoration(
          color: t.inputBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.border, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(color: const Color(0x1A7C3AED), borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.add_photo_alternate_rounded, size: 26, color: Color(0xFF7C3AED)),
            ),
            const SizedBox(height: 12),
            Text('Tap to upload banner image', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: t.text)),
            const SizedBox(height: 4),
            Text('Recommended: 16 : 9  ·  JPG or PNG', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted)),
          ],
        ),
      ),
    );
  }

  Widget _buildBannerPreview(AppTk t) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          SizedBox(width: double.infinity, height: 180, child: Image.file(_selectedBanner!, fit: BoxFit.cover)),
          Positioned(bottom: 0, left: 0, right: 0,
            child: Container(height: 60, decoration: BoxDecoration(gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6)],
            )))),
          Positioned(bottom: 12, left: 12,
            child: GestureDetector(
              onTap: _uploadBanner,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.swap_horiz_rounded, size: 14, color: t.text),
                  const SizedBox(width: 5),
                  Text('Change', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: t.text)),
                ]),
              ),
            )),
          Positioned(top: 10, right: 10,
            child: GestureDetector(
              onTap: () => setState(() => _selectedBanner = null),
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
              ),
            )),
        ],
      ),
    );
  }

  // ── Bottom bar ────────────────────────────────────────────────────────────────

  Widget _buildBottomBar(AppTk t) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: t.card,
          boxShadow: [BoxShadow(color: t.shadow, blurRadius: 20, offset: const Offset(0, -4))],
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: _isPublishing ? null : kGoldGradient,
            color:    _isPublishing ? t.border : null,
            borderRadius: BorderRadius.circular(14),
            boxShadow: _isPublishing ? null : [BoxShadow(color: kGold.withValues(alpha: 0.40), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: ElevatedButton.icon(
            onPressed: _isPublishing ? null : _publishEvent,
            icon: _isPublishing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.publish_rounded, size: 18),
            label: Text(_isPublishing ? 'Publishing…' : 'Publish Event',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent, foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.transparent, disabledForegroundColor: Colors.white70,
              elevation: 0, shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ),
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────────

  Widget _sectionCard({
    required IconData icon, required Color iconBg, required Color iconColor,
    required String title, required Widget child, required AppTk t,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: t.card, borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: t.shadow, blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Container(width: 32, height: 32,
                  decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(9)),
                  child: Icon(icon, color: iconColor, size: 16)),
                const SizedBox(width: 10),
                Text(title, style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700, color: t.text)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, thickness: 1, color: t.divider),
          Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 18), child: child),
        ],
      ),
    );
  }

  Widget _inputField({
    required String label, required TextEditingController controller,
    required AppTk t,
    String? hint, IconData? icon, int maxLines = 1,
    bool required = false, TextInputType? keyboard,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label, required: required, t: t),
        const SizedBox(height: 7),
        TextFormField(
          controller: controller, maxLines: maxLines, keyboardType: keyboard,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.text),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.muted),
            prefixIcon: icon != null ? Icon(icon, color: kGold, size: 18) : null,
            filled: true, fillColor: t.inputBg,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border:        OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kGold, width: 2)),
          ),
        ),
      ],
    );
  }

  Widget _fieldLabel(String label, {bool required = false, bool optional = false, required AppTk t}) {
    return Row(
      children: [
        Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: t.text)),
        if (required) const Text('  *', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.red, fontWeight: FontWeight.w700)),
        if (optional) Text('  (optional)', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Inline Calendar Widget
// ─────────────────────────────────────────────────────────────────────────────

class _InlineCalendar extends StatefulWidget {
  final DateTime?             selectedDate;
  final DateTime              firstDate;
  final DateTime              lastDate;
  final Color                 accentColor;
  final ValueChanged<DateTime> onDateSelected;

  const _InlineCalendar({
    required this.selectedDate,
    required this.firstDate,
    required this.lastDate,
    required this.accentColor,
    required this.onDateSelected,
  });

  @override
  State<_InlineCalendar> createState() => _InlineCalendarState();
}

class _InlineCalendarState extends State<_InlineCalendar> {
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
  void _next() => setState(() { if (_month == 12) { _month = 1;  _year++; } else { _month++; } });

  List<DateTime?> _cells() {
    final first  = DateTime(_year, _month, 1);
    final offset = first.weekday % 7; // Sun=0 Mon=1 … Sat=6
    final days   = DateUtils.getDaysInMonth(_year, _month);
    final list   = <DateTime?>[];
    for (var i = 0; i < offset; i++) { list.add(null); }
    for (var d = 1; d <= days; d++) { list.add(DateTime(_year, _month, d)); }
    while (list.length % 7 != 0) { list.add(null); }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final t     = AppTk(Theme.of(context).brightness == Brightness.dark);
    final today = DateUtils.dateOnly(DateTime.now());
    final cells = _cells();
    final accent = widget.accentColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
      child: Column(
        children: [
          // Month / year navigation
          Row(
            children: [
              _CalNavBtn(icon: Icons.chevron_left_rounded,  onTap: _prev, color: accent),
              Expanded(
                child: Text(
                  '${_months[_month - 1]} $_year',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700, color: t.text),
                ),
              ),
              _CalNavBtn(icon: Icons.chevron_right_rounded, onTap: _next, color: accent),
            ],
          ),
          const SizedBox(height: 14),
          // Weekday header
          Row(
            children: _weekdays.map((d) => Expanded(
              child: Text(d,
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700,
                  color: d == 'Su' || d == 'Sa' ? accent.withValues(alpha: 0.55) : t.muted)),
            )).toList(),
          ),
          const SizedBox(height: 8),
          // Day grid
          ...List.generate(cells.length ~/ 7, (week) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: List.generate(7, (col) {
                  final date = cells[week * 7 + col];
                  if (date == null) return const Expanded(child: SizedBox(height: 42));

                  final isSel      = widget.selectedDate != null && DateUtils.isSameDay(date, widget.selectedDate);
                  final isToday    = DateUtils.isSameDay(date, today);
                  final isPast     = date.isBefore(widget.firstDate);
                  final isFuture   = date.isAfter(widget.lastDate);
                  final disabled   = isPast || isFuture;

                  return Expanded(
                    child: GestureDetector(
                      onTap: disabled ? null : () => widget.onDateSelected(date),
                      child: Container(
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color:  isSel ? accent : Colors.transparent,
                          shape:  BoxShape.circle,
                          border: isToday && !isSel ? Border.all(color: accent, width: 1.5) : null,
                        ),
                        child: Text(
                          '${date.day}',
                          style: TextStyle(
                            fontFamily:  'Poppins',
                            fontSize:    13,
                            fontWeight:  isSel || isToday ? FontWeight.w700 : FontWeight.w500,
                            color: isSel ? Colors.white
                                : disabled ? t.muted
                                : isToday  ? accent
                                : t.text,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _CalNavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  const _CalNavBtn({required this.icon, required this.onTap, required this.color});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 34, height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, size: 20, color: color),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Time Picker Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _TimePickerSheet extends StatefulWidget {
  final String     title;
  final TimeOfDay? initialTime;
  final Color      accentColor;
  final TimeOfDay? minTime;

  const _TimePickerSheet({required this.title, this.initialTime, required this.accentColor, this.minTime});

  @override
  State<_TimePickerSheet> createState() => _TimePickerSheetState();
}

class _TimePickerSheetState extends State<_TimePickerSheet> {
  late FixedExtentScrollController _hourCtrl;
  late FixedExtentScrollController _minCtrl;
  late bool _isAm;
  bool _pastError = false;

  @override
  void initState() {
    super.initState();
    final t  = widget.initialTime ?? TimeOfDay.now();
    _isAm    = t.hour < 12;
    final h  = t.hour % 12 == 0 ? 12 : t.hour % 12;
    // Start controllers mid-range so both scroll directions work
    _hourCtrl = FixedExtentScrollController(initialItem: 600 + (h - 1));
    _minCtrl  = FixedExtentScrollController(initialItem: 600 + t.minute);
  }

  @override
  void dispose() { _hourCtrl.dispose(); _minCtrl.dispose(); super.dispose(); }

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
    final t      = AppTk(Theme.of(context).brightness == Brightness.dark);
    final accent = widget.accentColor;
    final bottom = MediaQuery.of(context).padding.bottom;
    const itemH  = 54.0;

    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: t.border, borderRadius: BorderRadius.circular(2))),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
            child: Row(children: [
              Container(width: 38, height: 38,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(11)),
                child: Icon(Icons.access_time_rounded, color: accent, size: 20)),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.title, style: TextStyle(fontFamily: 'Poppins', fontSize: 17, fontWeight: FontWeight.w700, color: t.text)),
                Text(
                  widget.minTime != null
                      ? 'Today\'s event — from ${_fmtMinTime(widget.minTime!)} onwards'
                      : 'Scroll to set hour, minute & period',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted),
                ),
              ]),
            ]),
          ),
          const SizedBox(height: 24),
          // Drums + AM/PM
          SizedBox(
            height: itemH * 5,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  // Hour drum
                  Expanded(child: _drum(
                    ctrl: _hourCtrl, count: 12,
                    label: (i) => '${i + 1}'.padLeft(2, '0'),
                    accent: accent, itemH: itemH, t: t,
                  )),
                  // Colon
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(width: 6, height: 6, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
                      const SizedBox(height: 10),
                      Container(width: 6, height: 6, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
                    ]),
                  ),
                  // Minute drum
                  Expanded(child: _drum(
                    ctrl: _minCtrl, count: 60,
                    label: (i) => '$i'.padLeft(2, '0'),
                    accent: accent, itemH: itemH, t: t,
                  )),
                  const SizedBox(width: 14),
                  // AM/PM
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: ['AM', 'PM'].map((p) {
                      final sel = (p == 'AM') == _isAm;
                      return GestureDetector(
                        onTap: () => setState(() { _isAm = p == 'AM'; _pastError = false; }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 58, height: itemH * 1.1,
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: sel ? accent : t.inputBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: sel ? accent : t.border, width: 1.5),
                          ),
                          child: Center(child: Text(p,
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700,
                              color: sel ? Colors.white : t.muted))),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Past-time error (shown when user tries to confirm a time before minTime)
          if (_pastError)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.schedule_rounded, color: Colors.red.shade700, size: 15),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This time has already passed. Please pick a later time.',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                            fontWeight: FontWeight.w500, color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Set button
          Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, bottom + 20),
            child: SizedBox(
              width: double.infinity, height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: accent, borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6))],
                ),
                child: ElevatedButton.icon(
                  onPressed: () {
                    final res = _result();
                    if (widget.minTime != null) {
                      final selMin = res.hour * 60 + res.minute;
                      final minMin = widget.minTime!.hour * 60 + widget.minTime!.minute;
                      if (selMin < minMin) { setState(() => _pastError = true); return; }
                    }
                    Navigator.pop(context, res);
                  },
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text('Set ${widget.title}',
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent, foregroundColor: Colors.white,
                    elevation: 0, shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
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
    required double itemH,
    required AppTk t,
  }) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Selection highlight bar
        Container(
          height: itemH,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.22)),
          ),
        ),
        // Scroll wheel
        ListWheelScrollView.useDelegate(
          controller: ctrl,
          itemExtent: itemH,
          diameterRatio: 1.8,
          perspective: 0.003,
          physics: const FixedExtentScrollPhysics(),
          onSelectedItemChanged: (_) => setState(() => _pastError = false),
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: count * 1000,
            builder: (_, i) {
              final idx  = i % count;
              final isSel = ctrl.hasClients && ctrl.selectedItem % count == idx;
              return Center(
                child: Text(label(idx),
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize:   isSel ? 30 : 20,
                    fontWeight: isSel ? FontWeight.w800 : FontWeight.w400,
                    color:      isSel ? accent : t.muted,
                  )),
              );
            },
          ),
        ),
        // Top fade
        Positioned(top: 0, left: 0, right: 0,
          child: IgnorePointer(child: Container(
            height: itemH * 2,
            decoration: BoxDecoration(gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [t.card, t.card.withValues(alpha: 0)],
            )),
          ))),
        // Bottom fade
        Positioned(bottom: 0, left: 0, right: 0,
          child: IgnorePointer(child: Container(
            height: itemH * 2,
            decoration: BoxDecoration(gradient: LinearGradient(
              begin: Alignment.bottomCenter, end: Alignment.topCenter,
              colors: [t.card, t.card.withValues(alpha: 0)],
            )),
          ))),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Deadline Picker Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _DeadlinePickerSheet extends StatefulWidget {
  final DateTime? initialDeadline;
  const _DeadlinePickerSheet({this.initialDeadline});

  @override
  State<_DeadlinePickerSheet> createState() => _DeadlinePickerSheetState();
}

class _DeadlinePickerSheetState extends State<_DeadlinePickerSheet> {
  DateTime? _selDate;
  late int  _viewMonth, _viewYear;
  late FixedExtentScrollController _hourCtrl, _minCtrl;
  late bool _isAm;

  static const _months   = ['January','February','March','April','May','June','July','August','September','October','November','December'];
  static const _weekdays = ['Su','Mo','Tu','We','Th','Fr','Sa'];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final d   = widget.initialDeadline?.toLocal();
    _selDate   = d != null ? DateUtils.dateOnly(d) : null;
    _viewMonth = _selDate?.month ?? now.month;
    _viewYear  = _selDate?.year  ?? now.year;
    final h = d?.hour ?? now.hour, m = d?.minute ?? now.minute;
    _isAm     = h < 12;
    _hourCtrl = FixedExtentScrollController(initialItem: 600 + ((h % 12 == 0 ? 12 : h % 12) - 1));
    _minCtrl  = FixedExtentScrollController(initialItem: 600 + m);
  }

  @override
  void dispose() { _hourCtrl.dispose(); _minCtrl.dispose(); super.dispose(); }

  void _prev() => setState(() { if (_viewMonth == 1) { _viewMonth = 12; _viewYear--; } else { _viewMonth--; } });
  void _next() => setState(() { if (_viewMonth == 12) { _viewMonth = 1; _viewYear++; } else { _viewMonth++; } });

  List<DateTime?> _cells() {
    final first  = DateTime(_viewYear, _viewMonth, 1);
    final offset = first.weekday % 7;
    final days   = DateUtils.getDaysInMonth(_viewYear, _viewMonth);
    final list   = <DateTime?>[];
    for (var i = 0; i < offset; i++) { list.add(null); }
    for (var d = 1; d <= days;  d++) { list.add(DateTime(_viewYear, _viewMonth, d)); }
    while (list.length % 7 != 0) { list.add(null); }
    return list;
  }

  DateTime? _buildResult() {
    if (_selDate == null) return null;
    final h12 = (_hourCtrl.selectedItem % 12) + 1;
    final min  = _minCtrl.selectedItem % 60;
    final h24  = _isAm ? (h12 == 12 ? 0 : h12) : (h12 == 12 ? 12 : h12 + 12);
    return DateTime(_selDate!.year, _selDate!.month, _selDate!.day, h24, min);
  }

  @override
  Widget build(BuildContext context) {
    final t      = AppTk(Theme.of(context).brightness == Brightness.dark);
    final today  = DateUtils.dateOnly(DateTime.now());
    final cells  = _cells();
    final bottom = MediaQuery.of(context).padding.bottom;
    const itemH  = 44.0;

    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: t.border, borderRadius: BorderRadius.circular(2))),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Row(children: [
                Container(width: 38, height: 38,
                  decoration: BoxDecoration(color: kGoldLight, borderRadius: BorderRadius.circular(11)),
                  child: const Icon(Icons.event_busy_rounded, color: kGold, size: 20)),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Registration Deadline', style: TextStyle(fontFamily: 'Poppins', fontSize: 17, fontWeight: FontWeight.w700, color: t.text)),
                  Text('Last day students can sign up', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted)),
                ]),
              ]),
            ),
            const SizedBox(height: 16),
            Divider(color: t.divider, height: 1),
            // ── Mini calendar ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                children: [
                  Row(children: [
                    _CalNavBtn(icon: Icons.chevron_left_rounded,  onTap: _prev, color: kGold),
                    Expanded(child: Text('${_months[_viewMonth - 1]} $_viewYear',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700, color: t.text))),
                    _CalNavBtn(icon: Icons.chevron_right_rounded, onTap: _next, color: kGold),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: _weekdays.map((d) => Expanded(
                    child: Text(d, textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700,
                        color: d == 'Su' || d == 'Sa' ? kGold.withValues(alpha: 0.6) : t.muted)),
                  )).toList()),
                  const SizedBox(height: 6),
                  ...List.generate(cells.length ~/ 7, (week) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(children: List.generate(7, (col) {
                      final date = cells[week * 7 + col];
                      if (date == null) return const Expanded(child: SizedBox(height: 38));
                      final isSel   = _selDate != null && DateUtils.isSameDay(date, _selDate);
                      final isToday = DateUtils.isSameDay(date, today);
                      final isPast  = date.isBefore(today);
                      return Expanded(
                        child: GestureDetector(
                          onTap: isPast ? null : () => setState(() => _selDate = date),
                          child: Container(
                            height: 38, alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color:  isSel ? kGold : Colors.transparent,
                              shape:  BoxShape.circle,
                              border: isToday && !isSel ? Border.all(color: kGold, width: 1.5) : null,
                            ),
                            child: Text('${date.day}', style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 12,
                              fontWeight: isSel || isToday ? FontWeight.w700 : FontWeight.w500,
                              color: isSel ? Colors.white : isPast ? t.muted : isToday ? kGold : t.text,
                            )),
                          ),
                        ),
                      );
                    })),
                  )),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Divider(color: t.divider, height: 1),
            // ── Time drums ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Hour
                  _deadlineDrum(ctrl: _hourCtrl, count: 12, label: (i) => '${i+1}'.padLeft(2,'0'), header: 'Hour', itemH: itemH, t: t),
                  // Colon
                  Padding(padding: const EdgeInsets.fromLTRB(6, 0, 6, 20),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(width: 5, height: 5, decoration: const BoxDecoration(color: kGold, shape: BoxShape.circle)),
                      const SizedBox(height: 6),
                      Container(width: 5, height: 5, decoration: const BoxDecoration(color: kGold, shape: BoxShape.circle)),
                    ])),
                  // Minute
                  _deadlineDrum(ctrl: _minCtrl, count: 60, label: (i) => '$i'.padLeft(2,'0'), header: 'Min', itemH: itemH, t: t),
                  const SizedBox(width: 16),
                  // AM/PM
                  Column(children: [
                    ...['AM','PM'].map((p) {
                      final sel = (p == 'AM') == _isAm;
                      return GestureDetector(
                        onTap: () => setState(() => _isAm = p == 'AM'),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 58, height: itemH, margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: sel ? kGold : t.inputBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: sel ? kGold : t.border, width: 1.5),
                          ),
                          child: Center(child: Text(p, style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700,
                            color: sel ? Colors.white : t.muted))),
                        ),
                      );
                    }),
                    Text('Period', style: TextStyle(fontFamily: 'Poppins', fontSize: 9, color: t.muted)),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Buttons
            Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, bottom + 20),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: t.muted,
                      side: BorderSide(color: t.border),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: _selDate != null ? kGold : t.border,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: _selDate != null
                          ? [BoxShadow(color: kGold.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 5))]
                          : null,
                    ),
                    child: ElevatedButton(
                      onPressed: _selDate == null ? null : () => Navigator.pop(context, _buildResult()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent, foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.transparent, disabledForegroundColor: Colors.white60,
                        elevation: 0, shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Set Deadline', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deadlineDrum({
    required FixedExtentScrollController ctrl,
    required int count,
    required String Function(int) label,
    required String header,
    required double itemH,
    required AppTk t,
  }) {
    return Column(children: [
      SizedBox(
        height: itemH * 4, width: 72,
        child: Stack(alignment: Alignment.center, children: [
          Container(height: itemH, decoration: BoxDecoration(
            color: kGold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kGold.withValues(alpha: 0.25)),
          )),
          ListWheelScrollView.useDelegate(
            controller: ctrl, itemExtent: itemH,
            diameterRatio: 1.6, perspective: 0.003,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: (_) => setState(() {}),
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: count * 1000,
              builder: (_, i) {
                final idx  = i % count;
                final isSel = ctrl.hasClients && ctrl.selectedItem % count == idx;
                return Center(child: Text(label(idx), style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize:   isSel ? 26 : 18,
                  fontWeight: isSel ? FontWeight.w800 : FontWeight.w400,
                  color:      isSel ? kGold : t.muted,
                )));
              },
            ),
          ),
          Positioned(top: 0, left: 0, right: 0, child: IgnorePointer(child: Container(
            height: itemH * 1.5, decoration: BoxDecoration(gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [t.card, t.card.withValues(alpha: 0)],
            ))))),
          Positioned(bottom: 0, left: 0, right: 0, child: IgnorePointer(child: Container(
            height: itemH * 1.5, decoration: BoxDecoration(gradient: LinearGradient(
              begin: Alignment.bottomCenter, end: Alignment.topCenter,
              colors: [t.card, t.card.withValues(alpha: 0)],
            ))))),
        ]),
      ),
      const SizedBox(height: 5),
      Text(header, style: TextStyle(fontFamily: 'Poppins', fontSize: 9, color: t.muted)),
    ]);
  }
}

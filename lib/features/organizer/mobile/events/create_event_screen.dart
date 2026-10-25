import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/services/audit_service.dart';
import '../../../../core/services/event_cancellation_service.dart';
import '../../../../core/services/event_change_request_service.dart';
import '../../../../core/services/student_count_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../shared/utils/date_utils.dart' show genUuid;
import '../../../../shared/utils/event_form_validation.dart';
import '../../../../shared/widgets/form_errors.dart';
import '../../../../shared/widgets/stepped_wheel.dart';
import '../../../../shared/widgets/web/swal.dart';
import '../../../../shared/widgets/error_alert.dart';
import '../../../../core/friendly_error.dart';

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
const _kEnd   = Color(0xFF4F46E5); // end time — not red: red means an error here

// ── Banner upload constraints ─────────────────────────────────────────────
const _kAllowedBannerExts = {'jpg', 'jpeg', 'png', 'webp'};
const _kMaxBannerBytes    = 10 * 1024 * 1024; // 10 MB — matches the web upload flow

String _bannerContentType(String ext) {
  switch (ext) {
    case 'jpg':
    case 'jpeg': return 'image/jpeg';
    case 'png':  return 'image/png';
    case 'webp': return 'image/webp';
    default:     return 'application/octet-stream';
  }
}

// Stands in for a newly picked banner while comparing changes — the file is
// only uploaded once the organizer confirms.
const _kNewBanner = '\u0000new-banner';

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

/// Create an event, or edit [existing] — one form for both, like the web
/// event dialog. Edits to an approved event go to the admin as a change
/// request; pending / rejected events are updated directly (saving a rejected
/// event resubmits it). Pops `true` after a successful save.
class CreateEventScreen extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const CreateEventScreen({super.key, this.existing});
  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  // ── Controllers ─────────────────────────────────────────────────────────────
  final _nameCtrl      = TextEditingController();
  final _venueCtrl     = TextEditingController();
  final _descCtrl      = TextEditingController();
  final _otherTypeCtrl = TextEditingController();

  // ── State ────────────────────────────────────────────────────────────────────
  DateTime?  _selectedDate;
  DateTime?  _selectedEndDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  String     _selectedEventType = 'Concert';
  File?      _selectedBanner;
  bool       _isPublishing  = false;
  bool       _showCalendar  = false;
  bool       _showEndCalendar = false;
  // Capacity isn't entered — it's every active student.
  int?       _studentCount = StudentCountService.cached;

  // ── Edit mode ────────────────────────────────────────────────────────────────
  bool get _isEdit => widget.existing != null;
  // Approved events are live, so edits need the admin's approval first.
  bool get _isLive => _isEdit && EventChangeRequestService.needsApproval(widget.existing!);
  bool get _isRejected => widget.existing?['approval_status'] == 'rejected';
  String? _existingBannerUrl;            // current banner, or the one already proposed
  Map<String, dynamic>? _revision;       // latest change request (approved events)
  bool _loadingRevision = false;
  // The admin's answer to that request shows while the form is open.
  RealtimeChannel? _revisionChannel;

  // Field problems show only after the first Publish attempt, then update
  // live as the organizer fixes them.
  bool _submitted = false;
  final _fieldKeys = {for (final f in EventFormField.values) f: GlobalKey()};
  final _summaryKey = GlobalKey();

  static const _fieldLabels = {
    EventFormField.title:     'Event name',
    EventFormField.otherType: 'Event type',
    EventFormField.startDate: 'Start date',
    EventFormField.endDate:   'End date',
    EventFormField.startTime: 'Start time',
    EventFormField.endTime:   'End time',
    EventFormField.location:  'Venue',
  };

  Map<EventFormField, String> _validate() => validateEventForm(
        title: _nameCtrl.text, needsOtherType: _selectedEventType == 'Other',
        otherType: _otherTypeCtrl.text,
        startDate: _selectedDate, endDate: _selectedEndDate,
        startTime: _startTime, endTime: _endTime,
        location: _venueCtrl.text);

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

  double get _formProgress {
    int done = 0;
    if (_nameCtrl.text.trim().isNotEmpty) done++;
    if (_selectedDate != null)            done++;
    if (_selectedEndDate != null)         done++;
    if (_startTime != null)               done++;
    if (_endTime != null)                 done++;
    if (_venueCtrl.text.trim().isNotEmpty) done++;
    return done / 6;
  }

  @override
  void initState() {
    super.initState();
    if (_isEdit) _prefill(widget.existing!);
    if (_isLive) {
      _loadingRevision = true;
      _loadChangeRequest();
      _watchChangeRequest();
    }
    _nameCtrl.addListener(() => setState(() {}));
    _venueCtrl.addListener(() => setState(() {}));
    // Keep field errors live once they're showing.
    _otherTypeCtrl.addListener(() { if (_submitted) setState(() {}); });
    StudentCountService.activeStudents().then((n) {
      if (mounted && n != _studentCount) setState(() => _studentCount = n);
    });
  }

  @override
  void dispose() {
    if (_revisionChannel != null) {
      Supabase.instance.client.removeChannel(_revisionChannel!);
    }
    _nameCtrl.dispose();
    _venueCtrl.dispose();
    _descCtrl.dispose();
    _otherTypeCtrl.dispose();
    super.dispose();
  }

  // ── Edit mode: fill the form ─────────────────────────────────────────────────

  void _prefill(Map<String, dynamic> e) {
    _nameCtrl.text  = e['title'] as String? ?? '';
    _descCtrl.text  = e['description'] as String? ?? '';
    _venueCtrl.text = e['location'] as String? ?? '';
    // Custom types (saved via "Other") select Other with the value filled in.
    final type   = e['event_type'] as String? ?? 'Concert';
    final preset = type != 'Other' && _kTypeData.any((t) => t.$1 == type);
    _selectedEventType  = preset ? type : 'Other';
    _otherTypeCtrl.text = preset ? '' : type;
    _selectedDate    = _parseDate(e['event_date']);
    _selectedEndDate = _parseDate(e['end_date']) ?? _selectedDate;
    _startTime = _parseTime(e['start_time']);
    _endTime   = _parseTime(e['end_time']);
    final img = e['event_image_url'] as String?;
    _existingBannerUrl = img != null && img.isNotEmpty ? img : null;
  }

  // Changes still waiting for the admin are filled in, so saving again keeps
  // them (the request is replaced as a whole, so they'd be lost otherwise).
  Future<void> _loadChangeRequest() async {
    final id = widget.existing!['event_id'] as String? ?? '';
    final r  = id.isEmpty ? null : (await EventChangeRequestService.latestFor([id]))[id];
    if (!mounted) return;
    if (r != null && r['status'] == 'pending') {
      _prefill({
        ...widget.existing!,
        ...Map<String, dynamic>.from(r['changes'] as Map? ?? const {}),
      });
    }
    setState(() { _revision = r; _loadingRevision = false; });
  }

  // Live: an approval or rejection of the request updates the notice at
  // the top. Only the notice — what the organizer is typing stays as it is.
  void _watchChangeRequest() {
    final id = widget.existing!['event_id'] as String? ?? '';
    if (id.isEmpty) return;
    _revisionChannel = Supabase.instance.client.channel('org-form-revision-$id')
      ..on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(
          event: '*',
          schema: 'public',
          table: 'event_revisions',
          filter: 'event_id=eq.$id',
        ),
        (_, [_]) async {
          final r = (await EventChangeRequestService.latestFor([id]))[id];
          if (mounted) setState(() => _revision = r);
        },
      )
      ..subscribe();
  }

  static DateTime? _parseDate(Object? v) {
    final d = DateTime.tryParse(v as String? ?? '');
    return d == null ? null : DateUtils.dateOnly(d);
  }

  static TimeOfDay? _parseTime(Object? v) {
    final p = (v as String? ?? '').split(':');
    final h = int.tryParse(p[0]);
    final m = p.length > 1 ? int.tryParse(p[1]) : null;
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  static String _isoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String? _isoTime(TimeOfDay? t) => t == null
      ? null
      : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  /// The form in events-table columns (the banner is handled separately).
  /// No capacity — it's the number of active students.
  Map<String, dynamic> _formValues() {
    final start = _selectedDate!;
    return {
      'title':            _nameCtrl.text.trim(),
      'description':      _descCtrl.text.trim(),
      'event_type':       _selectedEventType == 'Other'
          ? _otherTypeCtrl.text.trim() : _selectedEventType,
      'location':         _venueCtrl.text.trim(),
      'event_date':       _isoDate(start),
      'end_date':         _isoDate(_selectedEndDate ?? start),
      'start_time':       _isoTime(_startTime),
      'end_time':         _isoTime(_endTime),
    };
  }

  // ── Validation ───────────────────────────────────────────────────────────────

  bool _validateForm() {
    final problems = _validate();
    if (problems.isEmpty) return true;
    // Mark every problem on the form and jump to the first one.
    HapticFeedback.mediumImpact();
    setState(() => _submitted = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealFirstProblem(problems.keys.first));
    return false;
  }

  // ── Pickers ──────────────────────────────────────────────────────────────────

  void _toggleCalendar() => setState(() => _showCalendar = !_showCalendar);
  void _toggleEndCalendar() => setState(() => _showEndCalendar = !_showEndCalendar);

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
    // Only an event that ENDS today can't end earlier than now.
    final endDay  = _selectedEndDate ?? _selectedDate;
    final isToday = endDay != null && DateUtils.isSameDay(endDay, now);
    final t = await showModalBottomSheet<TimeOfDay>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TimePickerSheet(
        title: 'End Time',
        initialTime: _endTime ?? _suggestedEndTime(),
        accentColor: _kEnd,
        minTime: isToday ? TimeOfDay(hour: now.hour, minute: now.minute) : null,
      ),
    );
    if (t != null) setState(() => _endTime = t);
  }

  TimeOfDay _suggestedEndTime() {
    final start = _startTime;
    if (start == null) return const TimeOfDay(hour: 17, minute: 0);
    return TimeOfDay(hour: (start.hour + 1) % 24, minute: start.minute);
  }

  // ── Banner ───────────────────────────────────────────────────────────────────

  // Uploads the picked banner under a unique name (like the web) → public URL.
  Future<String> _uploadSelectedBanner(SupabaseClient supabase) async {
    final ext   = _selectedBanner!.path.split('.').last.toLowerCase();
    final path  = 'banner_${DateTime.now().millisecondsSinceEpoch}_${genUuid()}.$ext';
    final bytes = await _selectedBanner!.readAsBytes();
    await supabase.storage.from('event-banners').uploadBinary(
      path, bytes,
      fileOptions: FileOptions(
        contentType: _bannerContentType(ext),
        cacheControl: '3600',
        upsert: false,
      ),
    );
    return supabase.storage.from('event-banners').getPublicUrl(path);
  }

  // Removes a banner file by its public URL. Best effort — a leftover file
  // must never fail the save.
  Future<void> _removeBannerFile(SupabaseClient supabase, String? url) async {
    if (url == null || url.isEmpty) return;
    try {
      final segments = Uri.parse(url).pathSegments;
      final i = segments.indexOf('event-banners');
      if (i >= 0 && i < segments.length - 1) {
        await supabase.storage.from('event-banners').remove([segments.sublist(i + 1).join('/')]);
      }
    } catch (e) {
      debugPrint('Banner cleanup skipped: $e');
    }
  }

  Future<void> _pickBanner() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false);
      if (!mounted || result == null) return;
      final picked = result.files.single;
      if (picked.path == null) return;

      final ext = (picked.extension ?? '').toLowerCase();
      if (!_kAllowedBannerExts.contains(ext)) {
        _snack('Banner must be a JPG, PNG, or WEBP image.', isError: true);
        return;
      }
      if (picked.size > _kMaxBannerBytes) {
        _snack('Image must be 10 MB or smaller.', isError: true);
        return;
      }

      setState(() => _selectedBanner = File(picked.path!));
    } catch (e) {
      if (!mounted) return;
      showErrorAlert(context, e,
          title: 'Couldn’t open the image',
          fallback: 'Please choose a different image and try again.');
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
      final bannerUrl = _selectedBanner != null ? await _uploadSelectedBanner(supabase) : null;
      await supabase.from('events').insert({
        ..._formValues(),
        'organizer_id':         customOrgId,
        'current_participants': 0,
        'event_status':         'upcoming',
        'event_image_url':      bannerUrl,
      });
      AuditService.logEvent(
        action: 'created',
        eventTitle: _nameCtrl.text.trim(),
        organizerId: customOrgId as String?,
        details: 'New event created',
      );
      if (!mounted) return;
      setState(() => _isPublishing = false);
      await AppAlert.success(context,
        title: 'Event Submitted!',
        message: 'Your event has been sent to the admin for approval and '
            'will go live once reviewed.',
        buttonText: 'Done',
        onDismiss: () => Navigator.pop(context, true),
      );
    } catch (e) {
      if (!mounted) return;
      showErrorAlert(context, e, title: 'Couldn’t submit the event');
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  // ── Save (edit mode) ─────────────────────────────────────────────────────────

  Future<void> _saveChanges() async {
    if (_loadingRevision || !_validateForm()) return;
    final event    = widget.existing!;
    final eventId  = event['event_id'] as String? ?? '';
    final supabase = Supabase.instance.client;
    setState(() => _isPublishing = true);
    String? uploaded;   // a banner this save uploaded and hasn't used yet
    try {
      final orgId = event['organizer_id'] as String? ??
          await SupabaseService.getCurrentOrganizerId();
      if (orgId == null || orgId.isEmpty) {
        throw Exception('Your organizer profile could not be found.');
      }
      final values = _formValues();

      // Approved event → change request. It keeps its current details (and
      // banner) until an admin approves.
      if (_isLive) {
        final changes = EventChangeRequestService.diff(event, {
          ...values,
          'event_image_url': _selectedBanner != null ? _kNewBanner : _existingBannerUrl,
        });
        if (changes.isEmpty) {
          setState(() => _isPublishing = false);
          _snack('Nothing has changed.', isError: true);
          return;
        }
        final count = EventChangeRequestService.touchesSchedule(changes)
            ? await EventCancellationService.registrationCount(eventId)
            : 0;
        if (!mounted) return;
        setState(() => _isPublishing = false);   // the alert shows its own loader

        // SweetAlert2 confirm: the request is sent behind its loader, and a
        // failure shows inside the alert so the organizer can simply retry.
        final r = await Swal.fire(context,
          icon: SwalIcon.question,
          title: 'Submit for approval?',
          text: 'This event is approved, so an admin needs to approve your '
              'changes. It keeps its current details until then.'
              '${count > 0 ? '\n\n$count registered student${count == 1 ? '' : 's'} will be '
                  'notified of the new date, time or venue once it’s approved.' : ''}',
          showCancelButton: true,
          confirmButtonText: 'Yes, submit it',
          cancelButtonText: 'Keep editing',
          confirmButtonColor: kSwalGold,
          reverseButtons: true,
          buttonTextStyle: const TextStyle(fontFamily: 'Poppins',
              fontSize: 14, fontWeight: FontWeight.w700),
          preConfirm: (_) async {
            try {
              if (_selectedBanner != null) {
                uploaded = await _uploadSelectedBanner(supabase);
                changes['event_image_url'] = uploaded;
              }
              await EventChangeRequestService.submit(
                eventId: eventId,
                organizerId: orgId,
                eventTitle: event['title'] as String? ?? _nameCtrl.text.trim(),
                changes: changes,
              );
              uploaded = null;   // part of the request now
              return null;
            } catch (e) {
              if (uploaded != null) await _removeBannerFile(supabase, uploaded);
              uploaded = null;
              return friendlyError(e);
            }
          },
        );
        if (!r.isConfirmed || !mounted) return;
        await Swal.fire(context,
          icon: SwalIcon.success,
          title: 'Submitted!',
          text: 'An admin will review your changes. Students keep seeing the '
              'current details until they’re approved.',
          confirmButtonColor: kSwalGold,
          timer: const Duration(seconds: 3),
          timerProgressBar: true,
        );
        if (mounted) Navigator.pop(context, true);
        return;
      }

      // Not live yet (pending / rejected) → update directly. Asking for
      // 'pending' is how a rejected event is resubmitted — without it the
      // database quietly keeps it Rejected and the admin never sees it again.
      if (_selectedBanner != null) uploaded = await _uploadSelectedBanner(supabase);
      final updated = await supabase.from('events').update({
        ...values,
        'event_image_url': uploaded ?? _existingBannerUrl,
        if (_isRejected) 'approval_status': 'pending',
      }).eq('event_id', eventId).eq('organizer_id', orgId)
          .select('event_id, approval_status');
      if ((updated as List).isEmpty) {
        throw Exception('The event wasn’t updated — it may have been removed, '
            'or you don’t have permission to change it.');
      }
      // The event now points at the new banner — retire the old one.
      if (uploaded != null) {
        await _removeBannerFile(supabase, event['event_image_url'] as String?);
        uploaded = null;
      }
      if (_isRejected && (updated.first as Map)['approval_status'] != 'pending') {
        throw Exception('Your changes were saved, but the event couldn’t be sent '
            'back for review. Please try again.');
      }
      AuditService.logEvent(
        action: 'updated',
        eventTitle: _nameCtrl.text.trim(),
        eventId: eventId,
        organizerId: orgId,
        details: _isRejected
            ? 'Event edited and resubmitted for review'
            : 'Event details updated',
      );
      if (!mounted) return;
      setState(() => _isPublishing = false);
      if (_isRejected) {
        // Back in the admin's queue → SweetAlert2 success, like the web.
        await Swal.fire(context,
          icon: SwalIcon.success,
          title: 'Resubmitted!',
          text: 'Your changes were saved and the event is back in the admin’s '
              'review queue. You’ll see it as Pending review until they decide.',
          confirmButtonColor: kSwalGold,
          timer: const Duration(seconds: 4),
          timerProgressBar: true,
        );
        if (mounted) Navigator.pop(context, true);
        return;
      }
      await AppAlert.success(context,
        title: 'Event Updated',
        message: 'Your changes were saved. The event is still waiting for admin approval.',
        buttonText: 'Done',
        onDismiss: () => Navigator.pop(context, true),
      );
    } catch (e) {
      // Don't leave an upload behind that nothing points to.
      if (uploaded != null) await _removeBannerFile(supabase, uploaded);
      if (!mounted) return;
      showErrorAlert(context, e, title: 'Couldn’t save your changes');
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
                // An edit starts complete — the bar would only ever say 100%.
                if (!_isEdit) _buildProgressBar(t),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Column(
                      children: [
                        if (_isEdit) ..._buildEditNotices(t),
                        if (_errors.isNotEmpty) ...[
                          FormErrorSummary<EventFormField>(
                            key: _summaryKey,
                            errors: _errors, labels: _fieldLabels, onTap: _scrollTo,
                            dark: t.dark, textColor: t.text),
                          const SizedBox(height: 14),
                        ],
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
          if (_loadingRevision) const AppOverlayLoader(message: 'Loading event…'),
          if (_isPublishing)
            AppOverlayLoader(message: _isEdit ? 'Saving your changes…' : 'Publishing your event…'),
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
                Text(_isEdit ? 'Edit Event' : 'Create Event', style: TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w800, color: t.text, height: 1.1)),
                Text(
                  _isEdit
                      ? (widget.existing!['title'] as String? ?? 'Update the event details below')
                      : 'Fill in the event details below',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.sub),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (_isEdit) ...[
            const SizedBox(width: 10),
            _buildStatusChip(),
          ],
        ],
      ),
    );
  }

  // Where the event stands now: its review state until approved, then its status.
  Widget _buildStatusChip() {
    final e     = widget.existing!;
    final label = _isLive ? eventStatusLabel(e) : approvalLabelFor(e);
    final color = _isLive ? eventStatusColor(label) : approvalColorFor(e);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7, height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
              fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  // ── Edit-mode notices ────────────────────────────────────────────────────────

  List<Widget> _buildEditNotices(AppTk t) {
    const amber = Color(0xFFF59E0B);
    final red   = formErrorColor(t.dark);
    final notices = <Widget>[];
    final reason  = (widget.existing!['rejection_reason'] as String?)?.trim() ?? '';
    if (_isRejected) {
      final w = eventWindow(widget.existing!);
      final datePassed = w != null && !DateTime.now().isBefore(w.start);
      notices.add(_notice(t, color: red, icon: Icons.block_rounded,
        title: 'Rejected by admin',
        message: '${reason.isNotEmpty ? '$reason\n' : ''}'
            '${datePassed ? 'Its date has passed, so pick a new one. ' : ''}'
            'Saving your changes sends the event back for review.'));
    }
    if (_isLive) {
      final status = _revision?['status'];
      final revReason = (_revision?['rejection_reason'] as String?)?.trim() ?? '';
      if (status == 'pending') {
        notices.add(_notice(t, color: amber, icon: Icons.hourglass_top_rounded,
          title: 'Changes waiting for approval',
          message: 'Your earlier changes are filled in below. Saving again updates '
              'that request — students still see the current details.'));
      } else {
        if (status == 'rejected') {
          notices.add(_notice(t, color: red, icon: Icons.block_rounded,
            title: 'Your last changes were rejected',
            message: revReason.isNotEmpty ? revReason : 'No reason was given.'));
        }
        notices.add(_notice(t, color: _kBlue, icon: Icons.fact_check_outlined,
          title: 'Changes need admin approval',
          message: 'This event is approved, so what you save here goes to the admin '
              'first. Students keep seeing the current details until then.'));
      }
    }
    return [
      for (final n in notices) ...[n, const SizedBox(height: 14)],
    ];
  }

  Widget _notice(AppTk t, {
    required Color color, required IconData icon,
    required String title, required String message,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
              fontWeight: FontWeight.w700, color: t.text)),
          const SizedBox(height: 3),
          Text(message, style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
              color: t.sub, height: 1.45)),
        ])),
      ]),
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
    final errs = _errors;
    return _sectionCard(
      icon: Icons.event_note_rounded, iconBg: kGoldLight, iconColor: kGold,
      title: 'Event Details',
      errorCount: [EventFormField.title, EventFormField.otherType].where(errs.containsKey).length,
      t: t,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _inputField(label: 'Event Name', required: true, controller: _nameCtrl,
              hint: 'e.g. Annual Science Fair 2026', icon: Icons.title_rounded, t: t,
              fieldKey: _fieldKeys[EventFormField.title], error: errs[EventFormField.title]),
          const SizedBox(height: 18),
          _fieldLabel('Event Type', required: true, t: t),
          const SizedBox(height: 10),
          _buildTypeChips(t),
          if (_selectedEventType == 'Other') ...[
            const SizedBox(height: 12),
            _inputField(label: 'Specify type', required: true, controller: _otherTypeCtrl,
                hint: 'e.g. Academic Quiz, Cultural Night…', icon: Icons.edit_note_rounded, t: t,
                fieldKey: _fieldKeys[EventFormField.otherType], error: errs[EventFormField.otherType]),
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
    final errs = _errors;
    return _sectionCard(
      icon: Icons.schedule_rounded,
      iconBg: const Color(0x1A2563EB),
      iconColor: _kBlue,
      title: 'Schedule',
      errorCount: [EventFormField.startDate, EventFormField.endDate,
          EventFormField.startTime, EventFormField.endTime].where(errs.containsKey).length,
      t: t,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDateField(t, label: 'Start Date', required: true,
              fieldKey: _fieldKeys[EventFormField.startDate], error: errs[EventFormField.startDate],
              selectedDate: _selectedDate, showCalendar: _showCalendar, onTap: _toggleCalendar, onDateSelected: (date) { setState(() { _selectedDate = date; _showCalendar = false; if (_selectedEndDate == null || _selectedEndDate!.isBefore(date)) _selectedEndDate = date; }); }),
          const SizedBox(height: 16),
          _buildDateField(t, label: 'End Date', required: true,
              fieldKey: _fieldKeys[EventFormField.endDate], error: errs[EventFormField.endDate],
              selectedDate: _selectedEndDate, showCalendar: _showEndCalendar, onTap: _toggleEndCalendar, onDateSelected: (date) => setState(() { _selectedEndDate = date; _showEndCalendar = false; })),
          const SizedBox(height: 16),
          _buildTimeRow(t),
        ],
      ),
    );
  }

  // ── Date field with inline collapsible calendar ───────────────────────────────

  Widget _buildDateField(
    AppTk t, {
    required String label,
    required bool required,
    required DateTime? selectedDate,
    required bool showCalendar,
    required VoidCallback onTap,
    required ValueChanged<DateTime> onDateSelected,
    Key? fieldKey,
    String? error,
  }) {
    final filled = selectedDate != null;
    return Column(
      key: fieldKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label, required: required, t: t),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: filled ? _kBlue.withValues(alpha: 0.04) : t.card,
              borderRadius: BorderRadius.only(
                topLeft:     const Radius.circular(14),
                topRight:    const Radius.circular(14),
                bottomLeft:  Radius.circular(showCalendar ? 0 : 14),
                bottomRight: Radius.circular(showCalendar ? 0 : 14),
              ),
              border: Border.all(
                color: error != null
                    ? formErrorColor(t.dark)
                    : showCalendar
                    ? _kBlue.withValues(alpha: 0.5)
                    : filled
                    ? _kBlue.withValues(alpha: 0.3)
                    : t.border,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
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
                              _weekdayFull(selectedDate.weekday).substring(0, 3).toUpperCase(),
                              style: const TextStyle(fontFamily: 'Poppins', fontSize: 8, fontWeight: FontWeight.w700, color: Colors.white60, letterSpacing: 0.5),
                            ),
                            Text(
                              '${selectedDate.day}',
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
                            Text(_fmtDate(selectedDate),
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700, color: t.text)),
                            const SizedBox(height: 2),
                            Text(
                              _weekdayFull(selectedDate.weekday),
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: t.text)),
                                if (required) const Text(' *', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.red, fontWeight: FontWeight.w700)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text('Tap to open calendar', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted)),
                          ],
                        ),
                ),
                AnimatedRotation(
                  turns: showCalendar ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: showCalendar ? _kBlue.withValues(alpha: 0.1) : t.divider,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.keyboard_arrow_down_rounded, size: 18,
                      color: showCalendar ? _kBlue : t.muted),
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: showCalendar
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
                    selectedDate:    selectedDate,
                    firstDate:       DateUtils.dateOnly(DateTime.now()),
                    lastDate:        DateUtils.dateOnly(
                      DateTime.now().add(const Duration(days: 730)),
                    ),
                    accentColor:     _kBlue,
                    onDateSelected:  onDateSelected,
                  ),
                )
              : const SizedBox.shrink(),
        ),
        if (error != null) FormFieldError(error, dark: t.dark),
      ],
    );
  }

  // ── Time row ─────────────────────────────────────────────────────────────────

  Widget _buildTimeRow(AppTk t) {
    final errs = _errors;
    // Duration chip — across dates, so multi-day events aren't flagged.
    String? durationLabel;
    bool badDuration = false;
    if (_selectedDate != null && _startTime != null && _endTime != null) {
      final s = _selectedDate!, e = _selectedEndDate ?? _selectedDate!;
      final diff = DateTime(e.year, e.month, e.day, _endTime!.hour, _endTime!.minute)
          .difference(DateTime(s.year, s.month, s.day, _startTime!.hour, _startTime!.minute))
          .inMinutes;
      if (diff <= 0) {
        // Once errors show, the message under the time says it.
        badDuration = !errs.containsKey(EventFormField.endTime);
      } else {
        final d = diff ~/ 1440, h = (diff % 1440) ~/ 60, m = diff % 60;
        durationLabel = [if (d > 0) '${d}d', if (h > 0) '${h}h', if (m > 0) '${m}m'].join(' ');
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(key: _fieldKeys[EventFormField.startTime], child: _buildTimeCard(
              label: 'Start Time', required: true,
              time: _startTime, accentColor: _kGreen,
              icon: Icons.play_circle_outline_rounded,
              onTap: _pickStartTime,
              hasError: errs.containsKey(EventFormField.startTime),
              t: t,
            )),
            const SizedBox(width: 10),
            Expanded(key: _fieldKeys[EventFormField.endTime], child: _buildTimeCard(
              label: 'End Time', required: true,
              time: _endTime, accentColor: _kEnd,
              icon: Icons.stop_circle_outlined,
              onTap: _pickEndTime,
              hasError: errs.containsKey(EventFormField.endTime),
              t: t,
            )),
          ],
        ),
        for (final f in const [EventFormField.startTime, EventFormField.endTime])
          if (errs[f] != null) FormFieldError(errs[f]!, dark: t.dark),
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
                  color: badDuration ? Colors.orange.shade800 : _kGreen,
                ),
                const SizedBox(width: 6),
                Text(
                  badDuration ? 'The end must be after the start' : 'Duration: $durationLabel',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600,
                    color: badDuration ? Colors.orange.shade800 : _kGreen,
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
    bool hasError = false,
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
            color: hasError
                ? formErrorColor(t.dark)
                : filled ? accentColor.withValues(alpha: 0.35) : t.border,
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

  // ── Venue & Capacity section ─────────────────────────────────────────────────

  // Registration closes 2 hours after the event starts — tell organizers up front.
  Widget _buildRegistrationNote(AppTk t) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(Icons.info_outline_rounded, size: 15, color: t.muted),
      const SizedBox(width: 8),
      Expanded(
        child: Text('Registration closes 2 hours after the event starts.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: t.muted, height: 1.4)),
      ),
    ],
  );

  Widget _buildVenueSection(AppTk t) {
    final errs = _errors;
    return _sectionCard(
      icon: Icons.place_rounded, iconBg: const Color(0x1A16A34A), iconColor: const Color(0xFF16A34A),
      title: 'Venue & Capacity',
      errorCount: errs.containsKey(EventFormField.location) ? 1 : 0,
      t: t,
      child: Column(
        children: [
          _inputField(label: 'Venue / Location', required: true, controller: _venueCtrl,
              hint: 'e.g. School Gymnasium', icon: Icons.location_on_outlined, t: t,
              fieldKey: _fieldKeys[EventFormField.location], error: errs[EventFormField.location]),
          const SizedBox(height: 18),
          _buildCapacityInfo(t),
          const SizedBox(height: 12),
          _buildRegistrationNote(t),
        ],
      ),
    );
  }

  // Capacity is fixed to the student body: every active student can register,
  // and it grows as students are added — so it's shown, not entered.
  Widget _buildCapacityInfo(AppTk t) {
    final n = _studentCount;
    final registered = (widget.existing?['current_participants'] as num?)?.toInt() ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Capacity', t: t),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: t.inputBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.border, width: 1.2),
          ),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: kGold.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.groups_rounded, color: kGold, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n != null ? '$n students' : 'All students',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                      fontWeight: FontWeight.w700, color: t.text)),
                const SizedBox(height: 2),
                Text(
                  registered > 0
                      ? 'Every student can register · $registered registered so far'
                      : 'Every student can register',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: t.sub)),
              ]),
            ),
            const SizedBox(width: 8),
            Icon(Icons.lock_outline_rounded, size: 14, color: t.muted),
          ]),
        ),
        const SizedBox(height: 6),
        Text('Set automatically — it grows as students are added.',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted)),
      ],
    );
  }

  // ── Banner section ────────────────────────────────────────────────────────────

  Widget _buildBannerSection(AppTk t) {
    return _sectionCard(
      icon: Icons.image_rounded, iconBg: const Color(0x1A7C3AED), iconColor: const Color(0xFF7C3AED),
      title: 'Event Banner',
      t: t,
      child: _selectedBanner != null || _existingBannerUrl != null
          ? _buildBannerPreview(t)
          : _buildBannerDropZone(t),
    );
  }

  Widget _buildBannerDropZone(AppTk t) {
    return GestureDetector(
      onTap: _pickBanner,
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

  // A newly picked file, else (editing) the event's current banner.
  Widget _buildBannerPreview(AppTk t) {
    final picked = _selectedBanner != null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          SizedBox(
            width: double.infinity, height: 180,
            child: picked
                ? Image.file(_selectedBanner!, fit: BoxFit.cover)
                : Image.network(_existingBannerUrl!, fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: t.inputBg,
                      child: Icon(Icons.broken_image_outlined, size: 32, color: t.muted),
                    )),
          ),
          Positioned(bottom: 0, left: 0, right: 0,
            child: Container(height: 60, decoration: BoxDecoration(gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6)],
            )))),
          Positioned(bottom: 12, left: 12,
            child: GestureDetector(
              onTap: _pickBanner,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(10)),
                // Dark text in both themes — the chip is always white.
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.swap_horiz_rounded, size: 14, color: kText),
                  SizedBox(width: 5),
                  Text('Change', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: kText)),
                ]),
              ),
            )),
          // Undo a new pick (editing: back to the current banner).
          if (picked)
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
    final busy = _isPublishing || _loadingRevision;
    // Says what saving will do: publish, ask the admin, resubmit, or just save.
    final label = _isPublishing
        ? (_isEdit ? 'Saving…' : 'Publishing…')
        : !_isEdit ? 'Publish Event'
        : _isLive ? 'Submit for Approval'
        : _isRejected ? 'Save & Resubmit'
        : 'Save Changes';
    final icon = !_isEdit
        ? Icons.publish_rounded
        : _isLive ? Icons.fact_check_outlined : Icons.save_rounded;
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
            gradient: busy ? null : kGoldGradient,
            color:    busy ? t.border : null,
            borderRadius: BorderRadius.circular(14),
            boxShadow: busy ? null : [BoxShadow(color: kGold.withValues(alpha: 0.40), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: ElevatedButton.icon(
            onPressed: busy ? null : (_isEdit ? _saveChanges : _publishEvent),
            icon: _isPublishing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Icon(icon, size: 18),
            label: Text(label,
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
    int errorCount = 0,   // > 0 shows a "N to fix" tag in the header
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
                if (errorCount > 0) ...[
                  const Spacer(),
                  FormSectionErrorPill(count: errorCount, dark: t.dark),
                ],
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
    Key? fieldKey, String? error,
  }) {
    final errSide = BorderSide(color: formErrorColor(t.dark), width: 1.5);
    return Column(
      key: fieldKey,
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
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: error != null ? errSide : BorderSide(color: t.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: error != null ? errSide.copyWith(width: 2) : const BorderSide(color: kGold, width: 2)),
          ),
        ),
        if (error != null) FormFieldError(error, dark: t.dark),
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
        // Scroll wheel — one number per swipe / wheel notch.
        SteppedWheel(
          controller: ctrl,
          itemExtent: itemH,
          childCount: count * 1000,
          onSelectedItemChanged: (_) => setState(() => _pastError = false),
          itemBuilder: (_, i) {
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

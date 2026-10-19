// ─────────────────────────────────────────────────────────────────────────────
// Organizer web — "Student details" side panel.
//
// Opened from a registration row (Events → Event details, and the
// Registrations tab). Slides in from the right so the list stays visible and
// the organizer can click through students one after another.
//
//   • Profile   photo, name, LRN (copy), grade · strand · section
//   • This event check-in progress (Registered → … → Checked in / Rejected)
//   • Identity  profile photo next to the check-in selfie
//   • History   registrations & attendance with THIS organizer's events only
//   • Action    the next step for the current status (request selfie /
//               check in / reject with reason) via RegistrationService
//
// Profile fields come from the `event_registrant_profiles` view, which only
// returns students registered for the calling organizer's own events. If the
// view isn't installed yet, the panel still works from the registration row.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/app_colors.dart';
import '../../../core/services/registration_service.dart';
import '../../../core/services/supabase_service.dart';
import 'web_shared.dart';

const _kGreen = Color(0xFF16A34A);
const _kRed   = Color(0xFFEF4444);

/// Registrant profiles keyed by student `user_id`. Returns an empty map (and
/// logs) when the view is missing, so callers degrade to registration data.
Future<Map<String, Map<String, dynamic>>> loadRegistrantProfiles(
    Iterable<String?> userIds) async {
  final ids = userIds.whereType<String>().toSet().toList();
  if (ids.isEmpty) return {};
  try {
    final rows = await SupabaseService.client
        .from('event_registrant_profiles')
        .select()
        .in_('user_id', ids);
    return {
      for (final r in rows as List)
        (r['user_id'] as String): Map<String, dynamic>.from(r as Map),
    };
  } catch (e) {
    debugPrint('loadRegistrantProfiles failed (is the view installed?): $e');
    return {};
  }
}

/// Opens the panel. Resolves to `true` when the registration's status was
/// changed from inside it, so the caller can refresh its list.
Future<bool?> showStudentRegistrationPanel(
  BuildContext context, {
  required Map<String, dynamic> registration,
  String? organizerId,
  Map<String, dynamic>? profile,
}) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close student details',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, _, _) => Align(
      alignment: Alignment.centerRight,
      child: StudentRegistrationPanel(
        registration: registration, organizerId: organizerId, profile: profile),
    ),
    transitionBuilder: (_, anim, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

class StudentRegistrationPanel extends StatefulWidget {
  final Map<String, dynamic>  registration;
  final String?               organizerId;
  final Map<String, dynamic>? profile;
  const StudentRegistrationPanel({
    super.key, required this.registration, this.organizerId, this.profile});

  @override
  State<StudentRegistrationPanel> createState() => _StudentRegistrationPanelState();
}

class _StudentRegistrationPanelState extends State<StudentRegistrationPanel> {
  late Map<String, dynamic> _reg;
  Map<String, dynamic>? _profile;
  String? _selfieUrl;
  bool _selfieLoading = false;
  List<Map<String, dynamic>>? _history;   // null = loading
  bool _busy = false;
  bool _changed = false;

  String? get _uid    => _reg['student_user_id'] as String?;
  String  get _status => _reg['status'] as String? ?? 'pending';

  @override
  void initState() {
    super.initState();
    _reg     = Map<String, dynamic>.from(widget.registration);
    _profile = widget.profile;
    if (_profile == null && _uid != null) _loadProfile();
    _loadSelfie();
    _loadHistory();
  }

  Future<void> _loadProfile() async {
    final p = await loadRegistrantProfiles([_uid]);
    if (mounted && p[_uid] != null) setState(() => _profile = p[_uid]);
  }

  Future<void> _loadSelfie() async {
    final path = _reg['selfie_url'] as String?;
    if (path == null || path.isEmpty) return;
    setState(() => _selfieLoading = true);
    try {
      final url = await RegistrationService.getSelfieSignedUrl(path);
      if (mounted) setState(() { _selfieUrl = url; _selfieLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _selfieLoading = false);
    }
  }

  // Only this organizer's events — never other organizers' registrations.
  Future<void> _loadHistory() async {
    if (_uid == null || widget.organizerId == null) {
      setState(() => _history = const []);
      return;
    }
    try {
      final rows = await SupabaseService.client
          .from('registrations')
          .select('id, status, registered_at, checked_in_at, rejection_reason, event_title, '
              'events!inner(title, event_date, organizer_id)')
          .eq('student_user_id', _uid!)
          .eq('events.organizer_id', widget.organizerId!)
          .order('registered_at', ascending: false);
      if (mounted) setState(() => _history = List<Map<String, dynamic>>.from(rows as List));
    } catch (e) {
      debugPrint('Student history load failed: $e');
      if (mounted) setState(() => _history = const []);
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _setStatus(String status, {String? reason}) async {
    setState(() => _busy = true);
    try {
      await RegistrationService.updateStatus(_reg['id'] as String, status,
          rejectionReason: reason);
      if (!mounted) return;
      setState(() {
        _reg['status'] = status;
        if (status == 'checked_in') _reg['checked_in_at'] = DateTime.now().toIso8601String();
        if (status == 'rejected')   _reg['rejection_reason'] = reason;
        _busy = false;
        _changed = true;
      });
      _loadHistory();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorAlert(context, e, title: 'Couldn’t update the status');
    }
  }

  Future<void> _reject() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _RejectReasonDialog(name: _displayName),
    );
    if (reason != null && reason.trim().isNotEmpty) {
      await _setStatus('rejected', reason: reason.trim());
    }
  }

  void _close() => Navigator.of(context).pop(_changed);

  // ── Derived display values ─────────────────────────────────────────────────

  String get _displayName {
    final p = _profile;
    final first = (p?['first_name'] as String? ?? '').trim();
    final last  = (p?['last_name']  as String? ?? '').trim();
    if (first.isNotEmpty && last.isNotEmpty) return '$first $last';
    return (p?['full_name'] as String?)?.trim().isNotEmpty == true
        ? p!['full_name'] as String
        : _reg['student_name'] as String? ?? 'Student';
  }

  String get _lrn => formatLrn(
      (_profile?['lrn'] ?? _reg['student_school_id']) as String? ?? '');

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final h = MediaQuery.of(context).size.height;
    return Material(
      color: t.card,
      elevation: 16,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      child: SizedBox(
        width: 420,
        height: h,
        child: Column(children: [
          // Title bar
          Container(
            height: kWebTopH,
            padding: const EdgeInsets.fromLTRB(20, 0, 10, 0),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.border))),
            child: Row(children: [
              Text('Student details', style: TextStyle(fontFamily: 'Poppins',
                  fontSize: 15, fontWeight: FontWeight.w700, color: t.text)),
              const Spacer(),
              IconButton(
                tooltip: 'Close',
                onPressed: _close,
                icon: Icon(Icons.close_rounded, size: 20, color: t.sub),
              ),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              children: [
                _buildProfile(t),
                const SizedBox(height: 22),
                _section('THIS EVENT', t),
                _buildEventProgress(t),
                if (_showIdentity) ...[
                  const SizedBox(height: 22),
                  _section('IDENTITY CHECK', t),
                  _buildIdentity(t),
                ],
                const SizedBox(height: 22),
                _section('WITH YOUR EVENTS', t),
                _buildHistory(t),
              ],
            ),
          ),
          _buildFooter(t),
        ]),
      ),
    );
  }

  Widget _section(String text, WebTk t) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text, style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5,
        fontWeight: FontWeight.w700, letterSpacing: 0.9, color: t.muted)),
  );

  // ── Profile ────────────────────────────────────────────────────────────────

  Widget _buildProfile(WebTk t) {
    final p      = _profile;
    final grade  = p?['year_level'] as int?;
    final strand = (grade == 11 || grade == 12) ? (p?['strand'] as String?) : null;
    final section = (p?['section'] as String?)?.trim();
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      StudentAvatar(name: _displayName, photoUrl: p?['profile_image_url'] as String?,
          size: 64, color: webStatusColor(_status)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_displayName, style: TextStyle(fontFamily: 'Poppins', fontSize: 17,
            fontWeight: FontWeight.w800, color: t.text), maxLines: 2,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Row(children: [
          Flexible(child: Text(_lrn.isEmpty ? '—' : _lrn,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: t.sub,
                fontFeatures: const [FontFeature.tabularFigures()]))),
          if (_lrn.isNotEmpty)
            IconButton(
              tooltip: 'Copy LRN',
              visualDensity: VisualDensity.compact,
              iconSize: 14,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _lrn.replaceAll(RegExp(r'\D'), '')));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('LRN copied', style: TextStyle(fontFamily: 'Poppins')),
                  duration: Duration(seconds: 2)));
              },
              icon: Icon(Icons.copy_rounded, color: t.muted),
            ),
        ]),
        const SizedBox(height: 6),
        if (p == null)
          Text('Profile details unavailable — showing registration info.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted,
                fontStyle: FontStyle.italic))
        else
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (grade != null) _chip('Grade $grade', t),
            if (strand != null) _chip(strand, t, highlight: true),
            if (section != null && section.isNotEmpty) _chip(section, t),
          ]),
      ])),
    ]);
  }

  Widget _chip(String label, WebTk t, {bool highlight = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: highlight ? kGold.withValues(alpha: 0.12) : t.inputBg,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: highlight ? kGold.withValues(alpha: 0.35) : t.border),
    ),
    child: Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
        fontWeight: FontWeight.w600,
        color: highlight ? const Color(0xFFB8861C) : t.sub)),
  );

  // ── This event: check-in progress ──────────────────────────────────────────

  static const _steps = [
    ('pending',         'Registered'),
    ('qr_scanned',      'QR scanned'),
    ('photo_required',  'Selfie requested'),
    ('photo_submitted', 'Selfie submitted'),
    ('checked_in',      'Checked in'),
  ];

  Widget _buildEventProgress(WebTk t) {
    final rejected = _status == 'rejected';
    // A rejection happens after a selfie was submitted.
    final current = rejected
        ? 3
        : _steps.indexWhere((s) => s.$1 == _status).clamp(0, _steps.length - 1);
    final done = _status == 'checked_in';

    String? timeFor(String step) => switch (step) {
      'pending'    => _fmtDateTime(_reg['registered_at'] as String?),
      'checked_in' => _fmtDateTime(_reg['checked_in_at'] as String?),
      _            => null,
    };

    final items = <Widget>[];
    for (var i = 0; i < _steps.length; i++) {
      if (rejected && i == _steps.length - 1) break;
      final (key, label) = _steps[i];
      final state = i < current || (i == current && (done || rejected))
          ? _StepState.done
          : i == current ? _StepState.current : _StepState.upcoming;
      items.add(_StepRow(
        label: label,
        time: timeFor(key),
        state: state,
        hint: state == _StepState.current && _status == 'photo_submitted'
            ? 'waiting for you' : null,
        isLast: !rejected && i == _steps.length - 1,
      ));
    }
    if (rejected) {
      items.add(_StepRow(
        label: 'Rejected', state: _StepState.rejected, isLast: true,
        hint: (_reg['rejection_reason'] as String?)?.trim().isNotEmpty == true
            ? '“${_reg['rejection_reason']}”' : null,
      ));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: t.inputBg, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(_reg['event_title'] as String? ?? 'This event',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                fontWeight: FontWeight.w700, color: t.text),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          WebStatusBadge(label: webStatusLabel(_status), color: webStatusColor(_status)),
        ]),
        const SizedBox(height: 12),
        ...items,
      ]),
    );
  }

  // ── Identity check ─────────────────────────────────────────────────────────

  bool get _showIdentity =>
      const {'photo_required', 'photo_submitted', 'checked_in', 'rejected'}.contains(_status) ||
      (_reg['selfie_url'] as String?)?.isNotEmpty == true;

  Widget _buildIdentity(WebTk t) {
    final photo = _profile?['profile_image_url'] as String?;
    return Row(children: [
      Expanded(child: _PhotoTile(
        label: 'Profile photo', sub: 'On file',
        url: photo, emptyText: 'No profile photo',
        name: _displayName)),
      const SizedBox(width: 10),
      Expanded(child: _PhotoTile(
        label: 'Check-in selfie',
        sub: _selfieUrl != null ? 'Submitted' : null,
        url: _selfieUrl, loading: _selfieLoading,
        emptyText: _status == 'photo_required' ? 'Waiting for selfie' : 'No selfie',
        name: _displayName)),
    ]);
  }

  // ── History with this organizer's events ───────────────────────────────────

  Widget _buildHistory(WebTk t) {
    final h = _history;
    if (h == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: SizedBox(width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: kGold))));
    }
    if (h.isEmpty) {
      return Text('No other registrations with your events.',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.muted));
    }
    final attended = h.where((r) => r['status'] == 'checked_in').length;
    final pct = (attended / h.length * 100).round();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text.rich(TextSpan(
        style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: t.sub),
        children: [
          TextSpan(text: '${h.length}', style: TextStyle(fontWeight: FontWeight.w800, color: t.text)),
          TextSpan(text: ' registered  ·  '),
          TextSpan(text: '$attended', style: TextStyle(fontWeight: FontWeight.w800, color: t.text)),
          TextSpan(text: ' attended ($pct%)'),
        ],
      )),
      const SizedBox(height: 8),
      for (final r in h.take(6)) _historyRow(r, t),
      if (h.length > 6)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('+ ${h.length - 6} more',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: t.muted)),
        ),
    ]);
  }

  Widget _historyRow(Map<String, dynamic> r, WebTk t) {
    final ev      = r['events'] as Map<String, dynamic>?;
    final title   = ev?['title'] as String? ?? r['event_title'] as String? ?? '—';
    final status  = r['status'] as String? ?? 'pending';
    final isThis  = r['id'] == _reg['id'];
    final reason  = (r['rejection_reason'] as String?)?.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 7, height: 7, margin: const EdgeInsets.only(top: 6, right: 10),
          decoration: BoxDecoration(color: webStatusColor(status), shape: BoxShape.circle)),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: title, style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                fontWeight: FontWeight.w600, color: t.text)),
            if (isThis)
              TextSpan(text: '  · this event', style: TextStyle(fontFamily: 'Poppins',
                  fontSize: 11, color: t.muted)),
          ]), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            [webFmtDate(ev?['event_date'] as String?), webStatusLabel(status)]
                .where((s) => s.isNotEmpty && s != '—').join('  ·  ') +
                (status == 'rejected' && reason != null && reason.isNotEmpty
                    ? ' — “$reason”' : ''),
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),
      ]),
    );
  }

  // ── Footer: the next action for this status ────────────────────────────────

  Widget _buildFooter(WebTk t) {
    Widget info(IconData icon, String text, Color c) => Row(children: [
      Icon(icon, size: 16, color: c),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(fontFamily: 'Poppins',
          fontSize: 12, color: t.sub, height: 1.4))),
    ]);

    final Widget content = switch (_status) {
      'pending' => info(Icons.qr_code_scanner_rounded,
          'Scan the student’s QR code at the venue to start check-in.', t.muted),
      'qr_scanned' => Row(children: [
          Expanded(child: info(Icons.check_circle_outline_rounded,
              'QR scanned. Ask for a selfie to verify identity.', webStatusColor('qr_scanned'))),
          const SizedBox(width: 10),
          _primaryBtn('Request selfie', Icons.photo_camera_outlined, kGold,
              () => _setStatus('photo_required')),
        ]),
      'photo_required' => info(Icons.hourglass_top_rounded,
          'Waiting for the student to send a selfie.', webStatusColor('photo_required')),
      'photo_submitted' => Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: _busy ? null : _reject,
            icon: const Icon(Icons.close_rounded, size: 16, color: _kRed),
            label: const Text('Reject', style: TextStyle(fontFamily: 'Poppins',
                fontWeight: FontWeight.w700, color: _kRed)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _kRed),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 13)),
          )),
          const SizedBox(width: 10),
          Expanded(child: _primaryBtn('Check in', Icons.check_rounded, _kGreen,
              () => _setStatus('checked_in'))),
        ]),
      'checked_in' => info(Icons.verified_rounded,
          'Checked in ${_fmtDateTime(_reg['checked_in_at'] as String?) ?? ''}'.trim(), _kGreen),
      'rejected' => info(Icons.cancel_outlined,
          'Check-in was rejected. The student was notified with the reason.', _kRed),
      _ => const SizedBox.shrink(),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: t.border))),
      child: _busy && _status != 'photo_submitted'
          ? const Center(child: SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: kGold)))
          : content,
    );
  }

  Widget _primaryBtn(String label, IconData icon, Color c, VoidCallback onTap) =>
      ElevatedButton.icon(
        onPressed: _busy ? null : onTap,
        icon: _busy
            ? const SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontFamily: 'Poppins',
            fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: c, foregroundColor: Colors.white, elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16)),
      );
}

String? _fmtDateTime(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return null;
  const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  final h  = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ap = d.hour < 12 ? 'AM' : 'PM';
  return '${mo[d.month - 1]} ${d.day}, $h:${d.minute.toString().padLeft(2, '0')} $ap';
}

// ═════════════════════════════════════════════════════════════════════════════
// Pieces
// ═════════════════════════════════════════════════════════════════════════════

/// Round student avatar: profile photo, or initials tinted by [color].
class StudentAvatar extends StatelessWidget {
  final String  name;
  final String? photoUrl;
  final double  size;
  final Color   color;
  const StudentAvatar({super.key, required this.name, required this.photoUrl,
      required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final initials = parts.isEmpty ? '?'
        : parts.length == 1 ? parts.first[0].toUpperCase()
        : '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    final fallback = Container(
      width: size, height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(initials, style: TextStyle(fontFamily: 'Poppins',
          fontSize: size * 0.32, fontWeight: FontWeight.w700, color: color)),
    );
    if (photoUrl == null || photoUrl!.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(photoUrl!, width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback),
    );
  }
}

enum _StepState { done, current, upcoming, rejected }

class _StepRow extends StatelessWidget {
  final String label;
  final String? time, hint;
  final _StepState state;
  final bool isLast;
  const _StepRow({required this.label, required this.state, required this.isLast,
      this.time, this.hint});

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final (Color c, IconData icon) = switch (state) {
      _StepState.done     => (_kGreen, Icons.check_rounded),
      _StepState.current  => (kGold, Icons.circle),
      _StepState.upcoming => (t.muted, Icons.circle_outlined),
      _StepState.rejected => (_kRed, Icons.close_rounded),
    };
    final filled = state == _StepState.done || state == _StepState.rejected;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 20,
          child: Column(children: [
            Container(
              width: 18, height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? c : Colors.transparent,
                border: Border.all(color: c, width: 1.5),
              ),
              child: Icon(icon, size: state == _StepState.current ? 8 : 12,
                  color: filled ? Colors.white : c),
            ),
            if (!isLast)
              Expanded(child: Container(width: 1.5,
                  color: state == _StepState.done ? _kGreen.withValues(alpha: 0.5) : t.border)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(child: Padding(
          padding: EdgeInsets.only(bottom: isLast ? 4 : 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(label, style: TextStyle(fontFamily: 'Poppins',
                  fontSize: 12.5,
                  fontWeight: state == _StepState.upcoming ? FontWeight.w400 : FontWeight.w600,
                  color: state == _StepState.upcoming ? t.muted
                      : state == _StepState.rejected ? _kRed : t.text))),
              if (time != null)
                Text(time!, style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted)),
            ]),
            if (hint != null)
              Text(hint!, style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: state == _StepState.rejected ? _kRed : kGold)),
          ]),
        )),
      ]),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final String label, emptyText, name;
  final String? sub, url;
  final bool loading;
  const _PhotoTile({required this.label, required this.url, required this.emptyText,
      required this.name, this.sub, this.loading = false});

  void _open(BuildContext context) => showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(40),
      child: Stack(children: [
        InteractiveViewer(child: Image.network(url!, fit: BoxFit.contain)),
        Positioned(top: 8, right: 8, child: IconButton(
          onPressed: () => Navigator.pop(ctx),
          icon: const Icon(Icons.close_rounded, color: Colors.white))),
        Positioned(left: 14, bottom: 12, child: Text('$label · $name',
          style: const TextStyle(fontFamily: 'Poppins', color: Colors.white70, fontSize: 12))),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final has = url != null && url!.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AspectRatio(
        aspectRatio: 1,
        child: Material(
          color: t.inputBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: t.border)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: has ? () => _open(context) : null,
            child: loading
                ? const Center(child: SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: kGold)))
                : has
                    ? Image.network(url!, fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _empty(t, 'Couldn’t load image'))
                    : _empty(t, emptyText),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
          fontWeight: FontWeight.w600, color: t.text)),
      if (sub != null)
        Text(has ? '$sub · click to enlarge' : sub!,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5, color: t.muted)),
    ]);
  }

  Widget _empty(WebTk t, String text) => Center(child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.image_not_supported_outlined, size: 22, color: t.muted),
      const SizedBox(height: 6),
      Text(text, textAlign: TextAlign.center,
        style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted)),
    ],
  ));
}

class _RejectReasonDialog extends StatefulWidget {
  final String name;
  const _RejectReasonDialog({required this.name});
  @override
  State<_RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<_RejectReasonDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final ok = _ctrl.text.trim().isNotEmpty;
    return AlertDialog(
      backgroundColor: t.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Reject check-in?', style: TextStyle(fontFamily: 'Poppins',
          fontSize: 16, fontWeight: FontWeight.w800, color: t.text)),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.name} will see this reason.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: t.sub)),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              autofocus: true,
              maxLines: 3,
              maxLength: 200,
              onChanged: (_) => setState(() {}),
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.text),
              decoration: webInputDeco('e.g. Selfie doesn’t match the profile photo',
                  dark: t.dark),
            ),
          ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(fontFamily: 'Poppins', color: t.sub)),
        ),
        ElevatedButton(
          onPressed: ok ? () => Navigator.pop(context, _ctrl.text) : null,
          style: ElevatedButton.styleFrom(backgroundColor: _kRed,
              foregroundColor: Colors.white, elevation: 0),
          child: const Text('Reject', style: TextStyle(fontFamily: 'Poppins',
              fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

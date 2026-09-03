import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/services/audit_service.dart';
import '../../../../core/services/supabase_service.dart';


// ── Static lookup tables ───────────────────────────────────────────────────
const List<(String, IconData, Color)> _kTypeData = [
  ('Concert',  Icons.music_note_rounded,  Color(0xFF7C3AED)),
  ('Sports',   Icons.sports_rounded,      Color(0xFF2563EB)),
  ('Workshop', Icons.build_rounded,       Color(0xFFEA580C)),
  ('Seminar',  Icons.school_rounded,      Color(0xFF0D9488)),
  ('Other',    Icons.more_horiz_rounded,  Color(0xFF6B7280)),
];

const List<(String, String, IconData, Color)> _kStatusData = [
  ('upcoming',  'Upcoming',  Icons.schedule_rounded,     Color(0xFFE87A00)),
  ('ongoing',   'Ongoing',   Icons.play_circle_rounded,  Color(0xFF16A34A)),
  ('completed', 'Completed', Icons.check_circle_rounded, Color(0xFF6B7280)),
  ('cancelled', 'Cancelled', Icons.cancel_rounded,       Colors.red),
];

class ManageEventScreen extends StatefulWidget {
  final Map<String, dynamic> eventData;
  const ManageEventScreen({super.key, required this.eventData});

  @override
  State<ManageEventScreen> createState() => _ManageEventScreenState();
}

class _ManageEventScreenState extends State<ManageEventScreen> {
  // ── Controllers ────────────────────────────────────────────────────────────
  late final TextEditingController _nameCtrl;
  late final TextEditingController _venueCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _capacityCtrl;
  late final TextEditingController _otherTypeCtrl;

  // ── State ──────────────────────────────────────────────────────────────────
  String _selectedType   = 'Concert';
  String _currentStatus  = 'upcoming';
  bool   _isSaving       = false;

  // ── Derived from eventData ─────────────────────────────────────────────────
  String get _eventId =>
      (widget.eventData['event_id'] as String?) ??
      (widget.eventData['id']       as String?) ?? '';
  int get _registered  => widget.eventData['registered']          as int? ?? 0;
  int get _capacity    => int.tryParse(_capacityCtrl.text)        ?? 0;
  String get _approval => (widget.eventData['approval_status'] as String? ?? 'approved').toLowerCase();
  String? get _rejectionReason => widget.eventData['rejection_reason'] as String?;

  // ── Date / time formatting ─────────────────────────────────────────────────
  String get _displayDate {
    final iso = widget.eventData['event_date'] as String?;
    if (iso == null) return widget.eventData['date'] as String? ?? '—';
    try {
      final dt = DateTime.parse(iso);
      const m = ['JAN','FEB','MAR','APR','MAY','JUN',
                  'JUL','AUG','SEP','OCT','NOV','DEC'];
      return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) { return iso; }
  }

  String get _displayTime {
    final s  = widget.eventData['start_time'] as String?;
    final en = widget.eventData['end_time']   as String?;
    if (s == null) return widget.eventData['time'] as String? ?? '—';
    String fmt(String t) {
      final p = t.split(':');
      if (p.length < 2) return t;
      final h = int.tryParse(p[0]) ?? 0;
      return '${h % 12 == 0 ? 12 : h % 12}:${p[1]} ${h >= 12 ? 'PM' : 'AM'}';
    }
    return en != null ? '${fmt(s)} - ${fmt(en)}' : fmt(s);
  }

  @override
  void initState() {
    super.initState();
    final d = widget.eventData;
    // Accept both the raw Supabase column names and the legacy short keys.
    _nameCtrl     = TextEditingController(
      text: (d['title']    as String?) ?? (d['name']  as String?) ?? '');
    _venueCtrl    = TextEditingController(
      text: (d['location'] as String?) ?? (d['venue'] as String?) ?? '');
    _descCtrl     = TextEditingController(text: d['description'] as String? ?? '');
    _capacityCtrl = TextEditingController(
      text: d['max_participants'] != null
          ? '${d['max_participants']}'
          : d['capacity'] != null ? '${d['capacity']}' : '',
    );
    _otherTypeCtrl = TextEditingController();

    // Resolve type — if it doesn't match a known type, fall back to 'Other'
    final rawType = (d['event_type'] as String?) ?? (d['type'] as String?) ?? 'Concert';
    _selectedType = _kTypeData.any((t) => t.$1 == rawType) ? rawType : 'Other';
    if (_selectedType == 'Other') _otherTypeCtrl.text = rawType;

    // Resolve status
    _currentStatus = ((d['event_status'] as String?) ??
        (d['status'] as String?) ?? 'upcoming').toLowerCase();
    if (!_kStatusData.any((s) => s.$1 == _currentStatus)) {
      _currentStatus = 'upcoming';
    }
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

  // ── Save to Supabase ───────────────────────────────────────────────────────

  Future<void> _saveChanges() async {
    if (_nameCtrl.text.trim().isEmpty) {
      _snack('Event name is required', isError: true);
      return;
    }
    if (_venueCtrl.text.trim().isEmpty) {
      _snack('Venue is required', isError: true);
      return;
    }
    if (_selectedType == 'Other' && _otherTypeCtrl.text.trim().isEmpty) {
      _snack('Please specify the event type', isError: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final organizerId = await SupabaseService.getCurrentOrganizerId();
      if (organizerId == null || organizerId.isEmpty) {
        throw Exception('Your organizer profile could not be found.');
      }

      final eventType = _selectedType == 'Other'
          ? _otherTypeCtrl.text.trim()
          : _selectedType;

      await Supabase.instance.client.from('events').update({
        'title':            _nameCtrl.text.trim(),
        'location':         _venueCtrl.text.trim(),
        'description':      _descCtrl.text.trim(),
        'event_type':       eventType,
        'max_participants': int.tryParse(_capacityCtrl.text),
        'event_status':     _currentStatus,
      }).eq('event_id', _eventId).eq('organizer_id', organizerId);

      AuditService.logEvent(
        action: 'updated',
        eventTitle: _nameCtrl.text.trim(),
        eventId: _eventId,
        organizerId: widget.eventData['organizer_id'] as String?,
        details: 'Event details updated',
      );

      if (!mounted) return;
      setState(() => _isSaving = false);
      await AppAlert.success(
        context,
        title: 'Event Updated',
        message: 'Your changes have been saved successfully.',
        buttonText: 'Done',
        onDismiss: () => Navigator.pop(context, true),
      );
      return;
    } catch (e) {
      if (!mounted) return;
      AppAlert.error(context, title: 'Save Failed', message: e.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmCancelEvent() async {
    bool confirmed = false;
    await AppAlert.confirm(
      context,
      title: 'Cancel This Event?',
      message: 'Marking this event as cancelled will disable new registrations. '
          'This action can be reversed by changing the status again.',
      confirmText: 'Cancel Event',
      cancelText: 'Keep Event',
      confirmColor: Colors.red.shade600,
      onConfirm: () => confirmed = true,
    );
    if (confirmed && mounted) {
      setState(() => _currentStatus = 'cancelled');
      _snack('Status set to Cancelled — save to apply');
    }
  }

  void _adjustCapacity(int delta) {
    final current = int.tryParse(_capacityCtrl.text) ?? 0;
    final next    = (current + delta).clamp(0, 99999);
    setState(() => _capacityCtrl.text = next == 0 ? '' : '$next');
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ── Status helpers ─────────────────────────────────────────────────────────

  Color _statusColor(String status) {
    for (final s in _kStatusData) {
      if (s.$1 == status) return s.$4;
    }
    return kGold;
  }

  String _statusDisplay(String status) {
    for (final s in _kStatusData) {
      if (s.$1 == status) return s.$2;
    }
    return 'Upcoming';
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

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
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      children: [
                        if (_approval == 'rejected' && (_rejectionReason ?? '').isNotEmpty) ...[
                          _buildRejectionBanner(t),
                          const SizedBox(height: 14),
                        ],
                        _buildEventInfoSection(t),
                        const SizedBox(height: 14),
                        _buildScheduleSection(t),
                        const SizedBox(height: 14),
                        _buildDetailsSection(t),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isSaving) const AppOverlayLoader(message: 'Saving changes…'),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(AppTk t) {
    final statusColor = _statusColor(_currentStatus);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 8),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.pop(context),
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

          // Title + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Manage Event',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: t.text,
                    height: 1.1,
                  ),
                ),
                Text(
                  _nameCtrl.text.isNotEmpty
                      ? _nameCtrl.text
                      : 'Edit event details',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: t.sub,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Current status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: statusColor.withValues(alpha: 0.35), width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  _statusDisplay(_currentStatus),
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Rejection banner ───────────────────────────────────────────────────────
  // Saving any change here resubmits the event for review automatically
  // (server-side trigger flips approval_status rejected → pending) — no
  // separate "resubmit" button needed.

  Widget _buildRejectionBanner(AppTk t) {
    const color = Color(0xFFEF4444);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.block_rounded, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Rejected by admin',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                fontWeight: FontWeight.w700, color: t.text)),
          const SizedBox(height: 3),
          Text(_rejectionReason ?? '',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                color: t.sub, height: 1.4)),
          const SizedBox(height: 6),
          Text('Saving your changes below will resubmit this event for review.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                color: t.muted, fontStyle: FontStyle.italic)),
        ])),
      ]),
    );
  }

  // ── Section: Event Info ────────────────────────────────────────────────────

  Widget _buildEventInfoSection(AppTk t) {
    return _sectionCard(
      icon: Icons.event_note_rounded,
      iconBg: kGoldLight,
      iconColor: kGold,
      title: 'Event Info',
      t: t,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _inputField(
            label: 'Event Name',
            required: true,
            controller: _nameCtrl,
            icon: Icons.title_rounded,
            t: t,
          ),
          const SizedBox(height: 18),
          _fieldLabel('Event Type', required: true, t: t),
          const SizedBox(height: 10),
          _buildTypeChips(t),
          if (_selectedType == 'Other') ...[
            const SizedBox(height: 12),
            _inputField(
              label: 'Specify type',
              controller: _otherTypeCtrl,
              hint: 'e.g.  Cultural Night, Quiz Bee…',
              icon: Icons.edit_note_rounded,
              t: t,
            ),
          ],
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
          final selected = _selectedType == label;
          return GestureDetector(
            onTap: () => setState(() => _selectedType = label),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 74,
              decoration: BoxDecoration(
                color: selected ? kGold : t.inputBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected ? kGold : t.border,
                  width: 1.5,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: kGold.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 24, color: selected ? Colors.white : color),
                  const SizedBox(height: 5),
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : t.text,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Section: Schedule ──────────────────────────────────────────────────────

  Widget _buildScheduleSection(AppTk t) {
    return _sectionCard(
      icon: Icons.schedule_rounded,
      iconBg: const Color(0x1A2563EB),
      iconColor: const Color(0xFF2563EB),
      title: 'Schedule',
      t: t,
      child: Column(
        children: [
          // Date read-only
          _readOnlyTile(
            icon: Icons.calendar_today_rounded,
            label: 'Event Date',
            value: _displayDate,
            t: t,
          ),
          const SizedBox(height: 10),
          // Time read-only
          _readOnlyTile(
            icon: Icons.access_time_rounded,
            label: 'Time',
            value: _displayTime,
            t: t,
          ),
          const SizedBox(height: 14),
          // Venue editable
          _inputField(
            label: 'Venue / Location',
            required: true,
            controller: _venueCtrl,
            icon: Icons.location_on_outlined,
            t: t,
          ),
        ],
      ),
    );
  }

  Widget _readOnlyTile({
    required IconData icon,
    required String label,
    required String value,
    required AppTk t,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: t.inputBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.border, width: 1.2),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: t.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 10, color: t.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.sub,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.lock_outline_rounded, size: 14, color: t.muted),
        ],
      ),
    );
  }

  // ── Section: Description & Capacity ───────────────────────────────────────

  Widget _buildDetailsSection(AppTk t) {
    return _sectionCard(
      icon: Icons.tune_rounded,
      iconBg: const Color(0x1A16A34A),
      iconColor: const Color(0xFF16A34A),
      title: 'Details',
      t: t,
      child: Column(
        children: [
          _inputField(
            label: 'Description',
            controller: _descCtrl,
            hint: 'Describe what this event is about…',
            icon: Icons.notes_rounded,
            maxLines: 4,
            t: t,
          ),
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
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: t.text,
                ),
                decoration: InputDecoration(
                  hintText: '—',
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins', fontSize: 16, color: t.muted,
                  ),
                  filled: true,
                  fillColor: t.inputBg,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: t.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: t.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: kGold, width: 2),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _stepBtn(Icons.add_rounded, () => _adjustCapacity(10)),
          ],
        ),
        const SizedBox(height: 6),
        // Registered / capacity bar
        if (_capacity > 0 && _registered > 0) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (_registered / _capacity).clamp(0.0, 1.0),
                    minHeight: 5,
                    backgroundColor: t.divider,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _registered >= _capacity ? Colors.red : kGold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$_registered / $_capacity',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: t.sub,
                ),
              ),
            ],
          ),
        ] else
          Text(
            'Leave blank for unlimited participants',
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 11, color: t.muted,
            ),
          ),
      ],
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 48,
        decoration: BoxDecoration(
          color: kGoldLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: kGold.withValues(alpha: 0.3), width: 1.5,
          ),
        ),
        child: Icon(icon, color: kGold, size: 20),
      ),
    );
  }

  // ── Bottom action bar ──────────────────────────────────────────────────────

  Widget _buildBottomBar(AppTk t) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: t.card,
          boxShadow: [
            BoxShadow(
              color: t.shadow,
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Cancel event (danger)
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                onPressed: _isSaving ? null : _confirmCancelEvent,
                icon: Icon(Icons.cancel_outlined, size: 16, color: Colors.red.shade500),
                label: Text(
                  'Cancel',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.red.shade500,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.red.shade300, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Save changes — gradient when idle, muted when saving
            Expanded(
              flex: 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: _isSaving ? null : kGoldGradient,
                  color:    _isSaving ? t.border : null,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: _isSaving
                      ? null
                      : [
                          BoxShadow(
                            color:  kGold.withValues(alpha: 0.40),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                ),
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveChanges,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text(
                    _isSaving ? 'Saving…' : 'Save Changes',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:         Colors.transparent,
                    foregroundColor:         Colors.white,
                    disabledBackgroundColor: Colors.transparent,
                    disabledForegroundColor: Colors.white70,
                    elevation:   0,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared widget helpers ──────────────────────────────────────────────────

  Widget _sectionCard({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required Widget child,
    required AppTk t,
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
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
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

  Widget _inputField({
    required String label,
    required TextEditingController controller,
    required AppTk t,
    String? hint,
    IconData? icon,
    int maxLines  = 1,
    bool required = false,
    TextInputType? keyboard,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label, required: required, t: t),
        const SizedBox(height: 7),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboard,
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 13, color: t.text,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontFamily: 'Poppins', fontSize: 13, color: t.muted,
            ),
            prefixIcon: icon != null
                ? Icon(icon, color: kGold, size: 18)
                : null,
            filled: true,
            fillColor: t.inputBg,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: t.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: t.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kGold, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fieldLabel(
    String label, {
    bool required = false,
    bool optional = false,
    required AppTk t,
  }) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: t.text,
          ),
        ),
        if (required)
          const Text(
            '  *',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: Colors.red,
              fontWeight: FontWeight.w700,
            ),
          ),
        if (optional)
          Text(
            '  (optional)',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              color: t.muted,
            ),
          ),
      ],
    );
  }
}

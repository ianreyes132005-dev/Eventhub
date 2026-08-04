import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/app_colors.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/audit_service.dart';
import 'web_shared.dart';

// ── Banner upload constraints ─────────────────────────────────────────────
const _kAllowedBannerExts = {'jpg', 'jpeg', 'png', 'webp'};

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
  final db = (event['event_status'] as String? ?? '').toLowerCase();
  if (db != 'upcoming' && db != 'ongoing') return db;

  final dStr = event['event_date'] as String?;
  if (dStr == null) return db;

  try {
    final now  = DateTime.now();
    final d    = DateTime.parse(dStr);
    final eDay = DateTime(d.year, d.month, d.day);
    final nDay = DateTime(now.year, now.month, now.day);

    if (nDay.isAfter(eDay)) return 'ended';

    if (nDay == eDay) {
      final eStr = event['end_time'] as String?;
      if (eStr != null && eStr.isNotEmpty) {
        final p = eStr.split(':');
        final h = int.tryParse(p[0]) ?? 0;
        final m = p.length > 1 ? (int.tryParse(p[1]) ?? 0) : 0;
        if (now.isAfter(DateTime(d.year, d.month, d.day, h, m))) return 'ended';
      }
    }
  } catch (_) {}
  return db;
}

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
  final  _search  = TextEditingController();
  List<Map<String, dynamic>> _events    = [];
  List<Map<String, dynamic>> _displayed = [];

  final _filters = ['All', 'Upcoming', 'Ongoing', 'Ended', 'Cancelled'];

  String? _hoveredTab;

  late final AnimationController _staggerCtrl;
  RealtimeChannel? _channel;
  Timer?           _debounce;

  @override
  void initState() {
    super.initState();
    _staggerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _search.addListener(_applyFilter);
    _load();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_channel != null) SupabaseService.client.removeChannel(_channel!);
    _staggerCtrl.dispose();
    _search.dispose();
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
      if (!mounted) return;
      _events = List<Map<String, dynamic>>.from(rows as List);
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
        final status = e['event_status'] as String? ?? '';
        final title  = (e['title'] as String? ?? '').toLowerCase();
        final loc    = (e['location'] as String? ?? '').toLowerCase();
        final type   = (e['event_type'] as String? ?? '').toLowerCase();
        final matchFilter = _filter == 'All' ||
            (_filter == 'Ended'
                ? (_resolveDisplayStatus(e) == 'ended')
                : status == _filter.toLowerCase());
        final matchSearch = q.isEmpty ||
            title.contains(q) || loc.contains(q) || type.contains(q);
        return matchFilter && matchSearch;
      }).toList();
    });
  }

  Future<void> _openDialog({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EventDialog(
        orgId:    widget.orgId,
        existing: existing,
      ),
    );
    if (!mounted) return;
    if (result == true) {
      _load();
      final wasRejected = isEdit && (existing['approval_status'] as String? ?? '') == 'rejected';
      await WebAlert.success(
        context: context,
        title:   isEdit ? 'Event Updated!' : 'Event Submitted!',
        message: !isEdit
          ? 'Your new event has been sent to the admin for approval and will go live once reviewed.'
          : wasRejected
            ? 'Your changes have been saved and resubmitted for admin approval.'
            : 'Your changes have been saved successfully.',
      );
    }
  }

  void _openDetails(Map<String, dynamic> e) {
    showDialog(
      context: context,
      builder: (_) => _EventDetailsDialog(event: e),
    );
  }

  Future<void> _delete(Map<String, dynamic> e) async {
    final id = e['event_id'] as String?;
    if (id == null) return;
    final ok = await WebAlert.confirm(
      context:      context,
      title:        'Delete Event?',
      message:      'Are you sure you want to delete "${e['title'] ?? 'this event'}"? All registrations for this event will also be permanently removed. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (ok != true) return;
    try {
      // Snapshot registrations first so they can be restored (compensating
      // rollback) if the event deletion fails after registrations are gone.
      final regsRaw  = await SupabaseService.client
          .from('registrations')
          .select()
          .eq('event_id', id);
      final savedRegs = List<Map<String, dynamic>>.from(regsRaw as List);

      await SupabaseService.client
          .from('registrations')
          .delete()
          .eq('event_id', id);

      try {
        await SupabaseService.client
            .from('events')
            .delete()
            .eq('event_id', id);
      } catch (eventErr) {
        // Event deletion failed — re-insert the registrations we just deleted
        // to restore a consistent state.
        if (savedRegs.isNotEmpty) {
          await SupabaseService.client.from('registrations').insert(savedRegs);
        }
        rethrow;
      }

      AuditService.logEvent(
        action: 'deleted',
        eventTitle: e['title'] as String? ?? 'Unknown event',
        eventId: id,
        organizerId: widget.orgId,
        details: savedRegs.isEmpty
            ? 'Event deleted (no registrations)'
            : 'Event deleted · ${savedRegs.length} registration${savedRegs.length == 1 ? '' : 's'} removed',
      );

      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Failed to delete event: ${e.toString().replaceAll('Exception:', '').trim()}',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
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
                  WebEmptyState(
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
    final counts = <String, int>{
      'All':       _events.length,
      'Upcoming':  _events.where((e) => _resolveDisplayStatus(e) == 'upcoming').length,
      'Ongoing':   _events.where((e) => _resolveDisplayStatus(e) == 'ongoing').length,
      'Ended': _events.where((e) {
        final r = _resolveDisplayStatus(e);
        return r == 'completed' || r == 'ended';
      }).length,
      'Cancelled': _events.where((e) => e['event_status'] == 'cancelled').length,
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _filters.map((f) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _filterTab(f, counts[f] ?? 0),
              )).toList(),
            ),
          ),
        ),
        const SizedBox(width: 16),
        WebSearchField(
          controller: _search,
          hint: 'Search events…',
          onChanged: (_) {},
        ),
      ],
    );
  }

  Widget _filterTab(String f, int count) {
    final t        = WebTk(Theme.of(context).brightness == Brightness.dark);
    final selected = _filter == f;
    final hovered  = _hoveredTab == f;
    final accent   = f == 'All' ? kGold : webEventStatusColor(f.toLowerCase());

    return MouseRegion(
      cursor:  SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoveredTab = f),
      onExit:  (_) => setState(() => _hoveredTab = null),
      child: GestureDetector(
        onTap: () {
          setState(() { _filter = f; _hoveredTab = null; });
          _applyFilter();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve:    Curves.easeOut,
          padding:  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.08)
                : hovered
                    ? t.divider
                    : t.inputBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.35)
                  : t.border,
              width: selected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status dot — visible only when selected
              if (selected) ...[
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    color: accent, shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                f,
                style: TextStyle(
                  fontFamily:    'Poppins',
                  fontSize:      12,
                  fontWeight:    selected ? FontWeight.w700 : FontWeight.w500,
                  color:         selected ? accent : t.sub,
                  letterSpacing: selected ? 0.1 : 0,
                ),
              ),
              const SizedBox(width: 7),
              // Live count badge
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: selected
                      ? accent.withValues(alpha: 0.15)
                      : t.divider,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize:   10,
                    fontWeight: FontWeight.w700,
                    color:      selected ? accent : t.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTable() {
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
            child: const Row(
              children: [
                Expanded(flex: 4, child: WebColHeader('EVENT')),
                Expanded(flex: 2, child: WebColHeader('DATE')),
                Expanded(flex: 2, child: WebColHeader('LOCATION')),
                Expanded(flex: 2, child: WebColHeader('REGISTRATIONS')),
                Expanded(flex: 2, child: WebColHeader('STATUS')),
                SizedBox(width: 112, child: WebColHeader('ACTIONS')),
              ],
            ),
          ),
          start: 0.48, end: 0.68,
        ),
        ...(_displayed.asMap().entries.map((entry) {
          final i      = entry.key;
          final e      = entry.value;
          final isLast = i == _displayed.length - 1;
          final status   = e['event_status'] as String?;
          final approval = (e['approval_status'] as String? ?? 'approved').toLowerCase();
          final resolved = _resolveDisplayStatus(e);
          final isEnded  = resolved == 'ended';
          final sc       = isEnded ? const Color(0xFF6B7280) : webEventStatusColor(status);
          final type   = e['event_type'] as String?;
          final typeData = _kTypes.firstWhere(
            (t) => t.$1 == type,
            orElse: () => _kTypes.last,
          );
          final current = e['current_participants'] as int? ?? 0;
          final max     = e['max_participants'] as int? ?? 0;
          final isFull  = max > 0 && current >= max;
          final s       = 0.55 + (i * 0.07).clamp(0.0, 0.27);

          return _stagger(
            _HoverRow(
              isLast: isLast,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Row(
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
                                ),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
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
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_rounded, size: 12, color: t.muted),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(webFmtDate(e['event_date'] as String?),
                            style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 12.5, color: t.text,
                            )),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        Icon(Icons.location_on_rounded, size: 12, color: t.muted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(e['location'] as String? ?? '—',
                            style: TextStyle(
                              fontFamily: 'Poppins', fontSize: 12.5, color: t.sub,
                            ),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(children: [
                          Text('$current',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isFull ? const Color(0xFFEF4444) : t.text,
                            )),
                          Text(max > 0 ? ' / $max' : ' / âˆž',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: t.muted,
                            )),
                        ]),
                        if (max > 0) ...[
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: (current / max).clamp(0.0, 1.0),
                              minHeight: 3,
                              backgroundColor: t.border,
                              color: isFull
                                ? const Color(0xFFEF4444)
                                : const Color(0xFF3B82F6),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        WebStatusBadge(
                          label: isEnded ? 'Ended' : webEventStatusLabel(status),
                          color: sc,
                        ),
                        // Only shown while it needs attention — Approved is
                        // the normal/expected state and would just be noise.
                        if (approval != 'approved') ...[
                          const SizedBox(height: 4),
                          WebStatusBadge(
                            label: approvalStatusLabel(approval),
                            color: approvalStatusColor(approval),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 112,
                    child: Row(
                      children: [
                        _IconBtn(
                          icon: Icons.edit_rounded,
                          color: const Color(0xFF3B82F6),
                          tooltip: 'Edit',
                          onTap: () => _openDialog(existing: e),
                        ),
                        const SizedBox(width: 6),
                        _IconBtn(
                          icon: Icons.visibility_outlined,
                          color: kGold,
                          tooltip: 'Details',
                          onTap: () => _openDetails(e),
                        ),
                        const SizedBox(width: 6),
                        _IconBtn(
                          icon: Icons.delete_outline_rounded,
                          color: const Color(0xFFEF4444),
                          tooltip: 'Delete',
                          onTap: () => _delete(e),
                        ),
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
  const _EventDialog({this.orgId, this.existing});

  @override
  State<_EventDialog> createState() => _EventDialogState();
}

class _EventDialogState extends State<_EventDialog> {
  final _titleCtrl     = TextEditingController();
  final _descCtrl      = TextEditingController();
  final _locationCtrl  = TextEditingController();
  final _capacityCtrl  = TextEditingController();
  final _otherTypeCtrl = TextEditingController();

  String    _type         = 'Concert';
  String    _status       = 'upcoming';
  DateTime? _date;
  TimeOfDay?_startTime;
  TimeOfDay?_endTime;
  bool      _showCalendar     = false;
  bool      _showStartPicker  = false;
  bool      _showEndPicker    = false;

  String?    _existingBannerUrl;
  Uint8List? _bannerBytes;
  String?    _bannerName;
  bool       _saving = false;
  String?    _error;

  bool get _isEdit => widget.existing != null;

  // Tracks the 5 most important required fields so the progress bar animates
  // as the organizer fills in the form.  Each field counts as 1/5 = 20%.
  double get _formProgress {
    int done = 0;
    if (_titleCtrl.text.trim().isNotEmpty) done++;
    if (_date != null)                     done++;
    if (_startTime != null)                done++;
    if (_endTime != null)                  done++;
    if (_locationCtrl.text.trim().isNotEmpty) done++;
    return done / 5;
  }

  @override
  void initState() {
    super.initState();
    // Rebuild whenever the user edits a text field that feeds _formProgress.
    _titleCtrl.addListener(() { if (mounted) setState(() {}); });
    _locationCtrl.addListener(() { if (mounted) setState(() {}); });
    final e = widget.existing;
    if (e != null) {
      _titleCtrl.text    = e['title'] as String? ?? '';
      _descCtrl.text     = e['description'] as String? ?? '';
      _locationCtrl.text = e['location'] as String? ?? '';
      _capacityCtrl.text = (e['max_participants'] ?? '').toString();
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
    _capacityCtrl.dispose();
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



  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Event title is required.');
      return;
    }
    if (_date == null) {
      setState(() => _error = 'Please select an event date.');
      return;
    }
    if (_locationCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Location is required.');
      return;
    }
    if (_type == 'Other' && _otherTypeCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please specify the event type.');
      return;
    }
    // Only validate "time in the past" when creating — editors must be able
    // to update details of events that are already in progress or completed.
    if (!_isEdit) {
      final now = DateTime.now();
      if (DateUtils.isSameDay(DateUtils.dateOnly(_date!), DateUtils.dateOnly(now))) {
        final nowMin = now.hour * 60 + now.minute;
        if (_startTime != null && _startTime!.hour * 60 + _startTime!.minute < nowMin) {
          setState(() => _error = "Start time has already passed for today's event.");
          return;
        }
        if (_endTime != null && _endTime!.hour * 60 + _endTime!.minute < nowMin) {
          setState(() => _error = "End time has already passed for today's event.");
          return;
        }
      }
    }
    if (_startTime != null && _endTime != null) {
      final startMin = _startTime!.hour * 60 + _startTime!.minute;
      final endMin   = _endTime!.hour   * 60 + _endTime!.minute;
      if (endMin <= startMin) {
        setState(() => _error = 'End time must be after start time.');
        return;
      }
    }
    if (widget.orgId == null) return;

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

      final dateStr  = _date!.toIso8601String().split('T').first;
      final startStr = _startTime != null
        ? '${_startTime!.hour.toString().padLeft(2,'0')}:${_startTime!.minute.toString().padLeft(2,'0')}:00'
        : null;
      final endStr   = _endTime != null
        ? '${_endTime!.hour.toString().padLeft(2,'0')}:${_endTime!.minute.toString().padLeft(2,'0')}:00'
        : null;

      final payload = {
        'title':              _titleCtrl.text.trim(),
        'description':        _descCtrl.text.trim(),
        'location':           _locationCtrl.text.trim(),
        'event_type':         _type == 'Other'
            ? _otherTypeCtrl.text.trim()
            : _type,
        'event_status':       _status,
        'event_date':         dateStr,
        'start_time':      ?startStr,
        'end_time':        ?endStr,
        'event_image_url': ?imageUrl,
        'max_participants':
            int.tryParse(_capacityCtrl.text.trim()) ?? 0,
      };

      if (_isEdit) {
        final eventId = widget.existing!['event_id'] as String;
        await client.from('events').update(payload).eq('event_id', eventId);
        AuditService.logEvent(
          action: 'updated',
          eventTitle: _titleCtrl.text.trim(),
          eventId: eventId,
          organizerId: widget.orgId,
          details: 'Event details updated',
        );
      } else {
        await client.from('events')
            .insert({...payload, 'organizer_id': widget.orgId!});
        final cap = int.tryParse(_capacityCtrl.text.trim()) ?? 0;
        AuditService.logEvent(
          action: 'created',
          eventTitle: _titleCtrl.text.trim(),
          organizerId: widget.orgId,
          details: cap > 0
              ? 'New event created · max $cap participants'
              : 'New event created',
        );
      }

      if (mounted) { Navigator.of(context).pop(true); }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error  = e.toString().replaceAll('Exception:', '').trim();
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
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
                    // ── Event Details ─────────────────────────────────────────
                    _DialogSection(
                      icon: Icons.event_note_rounded,
                      iconBg: kGoldLight,
                      iconColor: kGold,
                      title: 'Event Details',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Event Title  *'),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _titleCtrl,
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 13.5, color: t.text),
                            decoration: webInputDeco('e.g. Annual Science Fair', dark: t.dark),
                          ),
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
                            _label('Specify type'),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _otherTypeCtrl,
                              maxLength: 40,
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 13.5,
                                  color: t.text),
                              decoration: webInputDeco(
                                'e.g. Quiz Bee, Sports Fest, Job Fair',
                                icon: Icons.edit_rounded,
                                dark: t.dark,
                              ).copyWith(
                                counterStyle: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 10,
                                    color: t.muted),
                              ),
                            ),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildDateTrigger(),
                          _buildInlineCalendar(),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(child: _buildTimeCard(
                              label: 'Start Time', isRequired: true,
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
                            Expanded(child: _buildTimeCard(
                              label: 'End Time', isRequired: true,
                              time: _endTime,
                              accentColor: const Color(0xFFEF4444),
                              icon: Icons.stop_circle_outlined,
                              isActive: _showEndPicker,
                              onTap: () => setState(() {
                                _showEndPicker   = !_showEndPicker;
                                _showStartPicker = false;
                              }),
                            )),
                          ]),
                          _buildInlineTimePicker(),
                          Builder(builder: (ctx) {
                            if (_startTime == null || _endTime == null) return const SizedBox.shrink();
                            final diff = (_endTime!.hour * 60 + _endTime!.minute) -
                                         (_startTime!.hour * 60 + _startTime!.minute);
                            final bad = diff <= 0;
                            final h = diff ~/ 60; final m = diff % 60;
                            final lbl = h > 0 ? (m > 0 ? '${h}h ${m}m' : '${h}h') : '${m}m';
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
                                    size: 13, color: bad ? const Color(0xFFF59E0B) : const Color(0xFF16A34A)),
                                  const SizedBox(width: 6),
                                  Text(bad ? 'End time must be after start time' : 'Duration: $lbl',
                                    style: TextStyle(
                                      fontFamily: 'Poppins', fontSize: 10.5, fontWeight: FontWeight.w600,
                                      color: bad ? const Color(0xFFF59E0B) : const Color(0xFF16A34A),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _label('Location  *'),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _locationCtrl,
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.text),
                            decoration: webInputDeco('Venue or room name', icon: Icons.location_on_rounded, dark: t.dark),
                          ),
                          const SizedBox(height: 14),
                          _label('Max Capacity'),
                          const SizedBox(height: 6),
                          Row(children: [
                            _dialogStepBtn(Icons.remove_rounded, () {
                              final v = (int.tryParse(_capacityCtrl.text) ?? 0) - 10;
                              setState(() => _capacityCtrl.text = v <= 0 ? '' : '$v');
                            }),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _capacityCtrl,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700, color: t.text),
                                decoration: InputDecoration(
                                  hintText: '—',
                                  hintStyle: TextStyle(fontFamily: 'Poppins', fontSize: 16, color: t.muted),
                                  filled: true, fillColor: t.inputBg,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: t.border)),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: t.border)),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(color: kGold, width: 2)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _dialogStepBtn(Icons.add_rounded, () {
                              final v = (int.tryParse(_capacityCtrl.text) ?? 0) + 10;
                              setState(() => _capacityCtrl.text = '$v');
                            }),
                          ]),
                          const SizedBox(height: 5),
                          Text('Leave blank for unlimited participants',
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
                    onPressed: (_saving || _titleCtrl.text.trim().isEmpty || _date == null) ? null : _save,
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
                      : Text(_isEdit ? 'Save Changes' : 'Create Event',
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
              color: isActive
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

  Widget _dialogStepBtn(IconData icon, VoidCallback onTap) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 46,
        decoration: BoxDecoration(
          color: kGoldLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kGold.withValues(alpha: 0.30), width: 1.5),
        ),
        child: Icon(icon, color: kGold, size: 18),
      ),
    ),
  );

  void _toggleCalendar() => setState(() => _showCalendar = !_showCalendar);

  String _weekdayAbbr(int w) {
    const d = ['MON','TUE','WED','THU','FRI','SAT','SUN'];
    return d[(w - 1).clamp(0, 6)];
  }

  String _weekdayFull(int w) {
    const d = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    return d[(w - 1).clamp(0, 6)];
  }

  Widget _buildDateTrigger() {
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
              color: _showCalendar
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

  Widget _buildInlineTimePicker() {
    final showStart = _showStartPicker;
    final showEnd   = _showEndPicker;
    if (!showStart && !showEnd) return const SizedBox.shrink();
    final wtk         = WebTk(Theme.of(context).brightness == Brightness.dark);
    final accentColor = showStart ? const Color(0xFF16A34A) : const Color(0xFFEF4444);
    final label       = showStart ? 'Start Time' : 'End Time';
    final initTime    = showStart ? _startTime   : _endTime;
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
  const _DialogSection({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.child,
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
  const _HoverRow({required this.child, required this.isLast});

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return MouseRegion(
    onEnter: (_) => setState(() => _h = true),
    onExit:  (_) => setState(() => _h = false),
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
        ListWheelScrollView.useDelegate(
          controller: ctrl,
          itemExtent: _itemH,
          diameterRatio: 1.8,
          perspective: 0.003,
          physics: const FixedExtentScrollPhysics(),
          onSelectedItemChanged: (_) => setState(() => _pastError = false),
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: count * 1000,
            builder: (_, i) {
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
  List<Map<String, dynamic>> _registrations = [];
  String? _organizerName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final eventId = widget.event['event_id'] as String?;
    if (eventId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final regsRaw = await SupabaseService.client
          .from('registrations')
          .select()
          .eq('event_id', eventId)
          .order('registered_at', ascending: false);

      String? orgName;
      final orgId = widget.event['organizer_id'] as String?;
      if (orgId != null) {
        final orgRow = await SupabaseService.client
            .from('organizers')
            .select('full_name')
            .eq('organizer_id', orgId)
            .maybeSingle();
        orgName = orgRow?['full_name'] as String?;
      }

      if (!mounted) return;
      setState(() {
        _registrations = List<Map<String, dynamic>>.from(regsRaw as List);
        _organizerName = orgName;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> get _e => widget.event;

  String get _title    => _e['title'] as String? ?? '—';
  String get _location => _e['location'] as String? ?? '—';
  String get _type     => _e['event_type'] as String? ?? '—';
  String get _desc     => _e['description'] as String? ?? '';
  String? get _imgUrl  => _e['event_image_url'] as String?;

  int get _capacity   => _e['max_participants'] as int? ?? 0;
  int get _registered => _registrations.isNotEmpty
      ? _registrations.length
      : (_e['current_participants'] as int? ?? 0);
  int get _checkedIn =>
      _registrations.where((r) => r['status'] == 'checked_in').length;
  int get _pending => _registrations.where(
      (r) => r['status'] == 'pending' || r['status'] == 'qr_scanned').length;
  int get _remaining =>
      _capacity > 0 ? (_capacity - _registered).clamp(0, _capacity) : 0;
  double get _fillRatio =>
      _capacity > 0 ? (_registered / _capacity).clamp(0.0, 1.0) : 0.0;
  int get _attendancePct =>
      _capacity > 0 ? (_checkedIn / _capacity * 100).clamp(0, 100).toInt() : 0;

  String  get _approval => (_e['approval_status'] as String? ?? 'approved').toLowerCase();
  String? get _rejectionReason => _e['rejection_reason'] as String?;

  String get _fmtTimeRange {
    final s  = _e['start_time'] as String?;
    final en = _e['end_time'] as String?;
    if (s == null || s.isEmpty) return '—';
    return en != null && en.isNotEmpty ? '${webFmtTime(s)} — ${webFmtTime(en)}' : webFmtTime(s);
  }

  String _initials(String name) {
    final p = name.trim().split(' ');
    if (p.length >= 2) return '${p[0][0]}${p[1][0]}'.toUpperCase();
    return p.isNotEmpty && p[0].isNotEmpty ? p[0][0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final t         = WebTk(Theme.of(context).brightness == Brightness.dark);
    final status    = _e['event_status'] as String?;
    final resolved  = _resolveDisplayStatus(_e);
    final isEnded   = resolved == 'ended';
    final sc        = isEnded ? const Color(0xFF6B7280) : webEventStatusColor(status);
    final statusLbl = isEnded ? 'Ended' : webEventStatusLabel(status);
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
                        if (_approval != 'approved')
                          WebStatusBadge(
                            label: approvalStatusLabel(_approval),
                            color: approvalStatusColor(_approval)),
                      ]),
                    ],
                  ),
                ),
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
                                  Text('Edit and save this event to resubmit it for review.',
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
      (value: '$_remaining',      label: 'Remaining',   icon: Icons.event_seat_rounded,        color: const Color(0xFF2563EB)),
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
    final fillColor = _fillRatio >= 0.9 ? const Color(0xFFEF4444)
        : _fillRatio >= 0.7 ? const Color(0xFFF59E0B) : kGold;
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
    final preview = _registrations.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...preview.asMap().entries.map((entry) {
          final r      = entry.value;
          final name   = r['student_name'] as String? ?? '—';
          final sid    = r['student_school_id'] as String? ?? '—';
          final rstat  = r['status'] as String? ?? 'pending';
          final regAt  = r['registered_at'] as String?;
          final color  = webStatusColor(rstat);
          return Padding(
            padding: EdgeInsets.only(bottom: entry.key < preview.length - 1 ? 12 : 0),
            child: Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Text(_initials(name),
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: t.text),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('$sid  ·  ${regAt != null ? webFmtDate(regAt) : '—'}',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted)),
                  ],
                ),
              ),
              WebStatusBadge(label: webStatusLabel(rstat), color: color),
            ]),
          );
        }),
        if (_registrations.length > 5) ...[
          const SizedBox(height: 12),
          Text('+ ${_registrations.length - 5} more registration${_registrations.length - 5 == 1 ? '' : 's'}',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, fontWeight: FontWeight.w600, color: t.muted)),
        ],
      ],
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

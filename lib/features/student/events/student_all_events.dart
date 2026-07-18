import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'event_details_page.dart';
import '../../../shared/widgets/app_loader.dart';
import '../../../shared/widgets/app_alert.dart';
import 'my_registered_events_page.dart';
import '../../../models/event_registration.dart';
import '../../../shared/widgets/qr_code_dialog.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/registration_service.dart';
import '../../../core/app_colors.dart';


// ══════════════════════════════════════════════════════════════════════════════
// Page
// ══════════════════════════════════════════════════════════════════════════════

class StudentAllEventsPage extends StatefulWidget {
  final bool showAsEmbedded;
  const StudentAllEventsPage({this.showAsEmbedded = false, super.key});

  @override
  State<StudentAllEventsPage> createState() => _StudentAllEventsPageState();
}

class _StudentAllEventsPageState extends State<StudentAllEventsPage> {
  String _filter      = 'All';
  String _searchQuery = '';
  bool   _loading     = true;
  bool   _hasError    = false;

  final TextEditingController _searchCtrl     = TextEditingController();
  final List<String>          _filterOptions  = ['All', 'Upcoming', 'Ongoing', 'Ended'];

  List<Map<String, dynamic>>          _events       = [];
  final Map<String, Map<String, dynamic>> _regByEventId = {};
  String? _registeringId;

  RealtimeChannel? _channel;
  Timer?           _debounce;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

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
    _searchCtrl.dispose();
    super.dispose();
  }

  void _subscribeRealtime() {
    _channel = Supabase.instance.client.channel('student-all-events');
    for (final table in ['events', 'registrations']) {
      _channel!.on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(event: '*', schema: 'public', table: table),
        (_, [a]) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 600), () {
            if (mounted && !_loading) _loadData(silent: true);
          });
        },
      );
    }
    _channel!.subscribe();
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _loadData({bool silent = false}) async {
    if (mounted) setState(() { if (!silent) _loading = true; _hasError = false; });
    try {
      final results = await Future.wait([
        SupabaseService.getEvents(),
        RegistrationService.getMyRegistrations(),
      ]);

      final events = results[0];
      final regs   = results[1];

      final regMap = <String, Map<String, dynamic>>{};
      for (final r in regs) {
        final eid = r['event_id'] as String?;
        if (eid != null) regMap[eid] = r;
      }

      if (mounted) {
        setState(() {
          _events = events;
          _regByEventId
            ..clear()
            ..addAll(regMap);
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('StudentAllEventsPage load error: $e');
      if (mounted) setState(() { _loading = false; _hasError = true; });
    }
  }

  Future<void> _handleRegister(Map<String, dynamic> event) async {
    final eventId    = event['event_id'] as String;
    final eventTitle = event['title']    as String? ?? '';

    setState(() => _registeringId = eventId);
    try {
      final row = await RegistrationService.register(
        eventId: eventId, eventTitle: eventTitle,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() { _regByEventId[eventId] = row; _registeringId = null; });
      RegistrationSuccessPopup.show(
        context,
        eventTitle: eventTitle,
        onComplete: () => _showQR(event),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _registeringId = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: const Color(0xFFEF4444),
        ));
      }
    }
  }

  void _showQR(Map<String, dynamic> event) {
    final eventId = event['event_id'] as String;
    final reg     = _regByEventId[eventId];
    if (reg == null) return;
    QRCodeDialog.show(context, EventRegistration(
      registrationId:   reg['id']                as String,
      eventId:          eventId,
      eventTitle:       reg['event_title']        as String? ?? event['title'] ?? '',
      studentId:        reg['student_school_id']  as String? ?? '',
      studentName:      reg['student_name']       as String? ?? '',
      registrationDate: DateTime.tryParse(reg['registered_at'] as String? ?? '') ?? DateTime.now(),
      qrCodeData:       reg['qr_code']            as String,
    ));
  }

  void _confirmRegister(Map<String, dynamic> event) {
    AppAlert.confirm(
      context,
      title:        'Confirm Registration',
      message:      'Register for "${event['title']}"?\nYour QR ticket will be generated immediately.',
      confirmText:  'Register',
      cancelText:   'Cancel',
      confirmColor: kGold,
      icon:         Icons.how_to_reg_rounded,
      iconColor:    kGold,
      onConfirm:    () => _handleRegister(event),
    );
  }

  // ── Filter logic ──────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get _filtered {
    final list = _events.where((e) {
      final label = eventStatusLabel(e);
      final matchesFilter = _filter == 'All' ||
          label == _filter ||
          (_filter == 'Ended' && label == 'Cancelled');
      final q     = _searchQuery.toLowerCase();
      final matchesSearch = q.isEmpty ||
          (e['title']      as String? ?? '').toLowerCase().contains(q) ||
          (e['location']   as String? ?? '').toLowerCase().contains(q) ||
          (e['event_type'] as String? ?? '').toLowerCase().contains(q);
      return matchesFilter && matchesSearch;
    }).toList();

    int statusOrder(String label) {
      if (label == 'Upcoming') return 0;
      if (label == 'Ongoing')  return 1;
      return 2; // Past, Cancelled
    }

    list.sort((a, b) {
      final po = statusOrder(eventStatusLabel(a))
          .compareTo(statusOrder(eventStatusLabel(b)));
      if (po != 0) return po;
      final da = a['event_date'] as String? ?? '';
      final db = b['event_date'] as String? ?? '';
      return da.compareTo(db);
    });

    return list;
  }

  int _countFor(String filter) {
    if (filter == 'All') return _events.length;
    return _events.where((e) => eventStatusLabel(e) == filter).length;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool   _isFull(Map<String, dynamic> e) {
    final max = e['max_participants']    as int?;
    final cur = e['current_participants'] as int?;
    if (max == null || max == 0) return false;
    return (cur ?? 0) >= max;
  }

  double _fill(Map<String, dynamic> e) {
    final max = e['max_participants']    as int?;
    final cur = e['current_participants'] as int?;
    if (max == null || max == 0) return 0.0;
    return ((cur ?? 0) / max).clamp(0.0, 1.0);
  }

  String _capacityText(Map<String, dynamic> e) {
    final max = e['max_participants']    as int?;
    final cur = e['current_participants'] as int?;
    if (max == null) return 'Unlimited';
    if (_isFull(e))  return 'Full · $max spots';
    return '${cur ?? 0} / $max registered';
  }

  String _fmtDate(Map<String, dynamic> e) {
    final d = e['event_date'] as String?;
    if (d == null) return '—';
    try {
      final dt = DateTime.parse(d);
      const m  = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
      return '${m[dt.month - 1]} ${dt.day}';
    } catch (_) { return d; }
  }

  String _fmtTime(Map<String, dynamic> e) {
    final s  = e['start_time'] as String?;
    final en = e['end_time']   as String?;
    if (s == null) return '—';
    String fmt(String t) {
      final p = t.split(':');
      if (p.length < 2) return t;
      final h = int.tryParse(p[0]) ?? 0;
      return '${h % 12 == 0 ? 12 : h % 12}:${p[1]} ${h >= 12 ? 'PM' : 'AM'}';
    }
    return en != null ? '${fmt(s)} — ${fmt(en)}' : fmt(s);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final t      = AppTk(Theme.of(context).brightness == Brightness.dark);
    final events = _filtered;

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: _loading
            ? _buildLoading(t)
            : _hasError
                ? _buildError(t)
                : RefreshIndicator(
                    color: kGold,
                    backgroundColor: t.card,
                    onRefresh: _loadData,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(child: _buildHeader(t)),
                        SliverToBoxAdapter(child: _buildSearchBar(t)),
                        SliverToBoxAdapter(child: _buildRegisteredShortcut(t)),
                        SliverToBoxAdapter(child: _buildFilterRow(t)),
                        events.isEmpty
                            ? SliverFillRemaining(
                                hasScrollBody: false,
                                child: _buildEmpty(t),
                              )
                            : SliverPadding(
                                padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
                                sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (_, i) => _buildCard(events[i], t),
                                    childCount: events.length,
                                  ),
                                ),
                              ),
                      ],
                    ),
                  ),
      ),
    );
  }

  // ── Loading ───────────────────────────────────────────────────────────────

  Widget _buildLoading(AppTk t) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        children: [
          _buildHeader(t),
          _buildSearchBar(t),
          const SizedBox(height: 8),
          const AppShimmerList(itemCount: 4, hasAvatar: false, hasImage: true),
        ],
      ),
    );
  }

  // ── Error ─────────────────────────────────────────────────────────────────

  Widget _buildError(AppTk t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68, height: 68,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.22)),
              ),
              child: const Icon(Icons.wifi_off_rounded, size: 32, color: Color(0xFFEF4444)),
            ),
            const SizedBox(height: 20),
            Text('Could not load events',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700, color: t.text)),
            const SizedBox(height: 8),
            Text('Check your connection and try again.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.muted),
              textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: kGold,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(AppTk t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 3, height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFC49230), kGold, Color(0xFFEAB866)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 14),
          Text('Events',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 26, fontWeight: FontWeight.w800, color: t.text, height: 1.15)),
        ],
      ),
    );
  }

  // ── Search bar ────────────────────────────────────────────────────────────

  Widget _buildSearchBar(AppTk t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Container(
        decoration: BoxDecoration(
          color: t.inputBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.border),
          boxShadow: [BoxShadow(color: t.shadow, blurRadius: 12, offset: const Offset(0, 3))],
        ),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _searchQuery = v),
          style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: t.text),
          decoration: InputDecoration(
            hintText: 'Search events, venues, type…',
            hintStyle: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.muted),
            prefixIcon: const Icon(Icons.search_rounded, color: kGold, size: 22),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.cancel_rounded, color: t.muted, size: 20),
                    onPressed: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); },
                  )
                : null,
            filled: false,
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            border:        OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: kGold, width: 1.8)),
          ),
        ),
      ),
    );
  }

  // ── My Registered shortcut ────────────────────────────────────────────────

  Widget _buildRegisteredShortcut(AppTk t) {
    final count = _regByEventId.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.push(context,
            MaterialPageRoute(builder: (_) => const MyRegisteredEventsPage()),
          ).then((_) => _loadData());
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFC49230), kGold, Color(0xFFE8C26C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: kGold.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 6)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.confirmation_num_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('My Registered Events',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white)),
                    const SizedBox(height: 2),
                    Text(
                      count == 0
                          ? 'No registrations yet'
                          : '$count event${count == 1 ? '' : 's'} registered',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: Colors.white.withValues(alpha: 0.82)),
                    ),
                  ],
                ),
              ),
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Filter row ────────────────────────────────────────────────────────────

  Widget _buildFilterRow(AppTk t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SizedBox(
        height: 38,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: _filterOptions.length,
          itemBuilder: (_, i) {
            final f        = _filterOptions[i];
            final selected = _filter == f;
            final count    = _countFor(f);

            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _filter = f);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  gradient: selected ? kGoldGradient : null,
                  color:    selected ? null : t.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected ? const Color(0xFFC49230) : t.border,
                    width: 1.5,
                  ),
                  boxShadow: selected
                      ? [BoxShadow(color: kGold.withValues(alpha: 0.28), blurRadius: 8, offset: const Offset(0, 3))]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(f,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : t.sub,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.white.withValues(alpha: 0.25)
                            : t.divider,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('$count',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: selected ? Colors.white : t.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────

  Widget _buildEmpty(AppTk t) {
    final isFiltered = _filter != 'All' || _searchQuery.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 70, height: 70,
            decoration: BoxDecoration(
              color: kGold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kGold.withValues(alpha: 0.18)),
            ),
            child: Icon(
              isFiltered ? Icons.search_off_rounded : Icons.event_busy_rounded,
              size: 32, color: kGold.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isFiltered ? 'No results found' : 'No events yet',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700, color: t.text),
          ),
          const SizedBox(height: 6),
          Text(
            isFiltered
                ? 'Try a different search or filter.'
                : 'Check back soon — events will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: t.muted, height: 1.6),
          ),
          if (isFiltered) ...[
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () {
                _searchCtrl.clear();
                setState(() { _searchQuery = ''; _filter = 'All'; });
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: kGold,
                side: const BorderSide(color: kGold, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Clear filters',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700, color: kGold)),
            ),
          ],
        ],
      ),
    );
  }

  // ── Event card ────────────────────────────────────────────────────────────

  Widget _buildCard(Map<String, dynamic> event, AppTk t) {
    final eventId      = event['event_id'] as String;
    final statusLabel  = eventStatusLabel(event);
    final isRegistered = _regByEventId.containsKey(eventId);
    final full         = _isFull(event);
    final isRegistering = _registeringId == eventId;
    final imageUrl     = event['event_image_url'] as String?;
    final hasImage     = imageUrl != null && imageUrl.isNotEmpty;
    final eventType    = event['event_type'] as String?;
    final sc           = eventStatusColor(statusLabel);
    final fill         = _fill(event);
    final isPast       = statusLabel == 'Ended' || statusLabel == 'Cancelled';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.border),
        boxShadow: [BoxShadow(color: t.shadow, blurRadius: 14, offset: const Offset(0, 5))],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Image ──────────────────────────────────────────────────
                  _CardImage(
                    imageUrl: hasImage ? imageUrl : null,
                    statusLabel: statusLabel,
                    sc: sc,
                    isRegistered: isRegistered,
                    dateLabel: _fmtDate(event),
                    t: t,
                    onTap: () => _openDetails(event, eventId),
                  ),
                  // ── Body ───────────────────────────────────────────────────
                  GestureDetector(
                    onTap: () => _openDetails(event, eventId),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (eventType != null && eventType.isNotEmpty) ...[
                            _TypeChip(label: eventType),
                            const SizedBox(height: 8),
                          ],
                          Text(
                            event['title'] as String? ?? '—',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 15.5, fontWeight: FontWeight.w700, color: t.text, height: 1.25),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 10),
                          _MetaRow(icon: Icons.access_time_rounded, text: _fmtTime(event), t: t),
                          const SizedBox(height: 4),
                          _MetaRow(icon: Icons.location_on_rounded,  text: event['location'] as String? ?? '—', t: t),
                          const SizedBox(height: 12),
                          _CapacityBar(
                            fill:    fill,
                            label:   _capacityText(event),
                            isFull:  full,
                            maxSet:  event['max_participants'] != null,
                            t:       t,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // ── Action row ─────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Row(
                      children: [
                        // Details text button
                        GestureDetector(
                          onTap: () => _openDetails(event, eventId),
                          child: Text(
                            'View Details',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, fontWeight: FontWeight.w700, color: t.muted,
                                decoration: TextDecoration.underline, decorationColor: t.muted),
                          ),
                        ),
                        const Spacer(),
                        // Primary action button
                        if (isPast)
                          const SizedBox.shrink()
                        else if (isRegistered)
                          _PrimaryBtn(
                            label: 'My QR',
                            icon:  Icons.qr_code_2_rounded,
                            color: const Color(0xFF16A34A),
                            onTap: () => _showQR(event),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF15803D), Color(0xFF22C55E)],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                          )
                        else if (full)
                          _PrimaryBtn(
                            label: 'Full',
                            icon:  Icons.block_rounded,
                            color: t.muted,
                            onTap: null,
                            ghost: true,
                          )
                        else
                          _PrimaryBtn(
                            label:   isRegistering ? 'Registering…' : 'Register',
                            icon:    isRegistering ? null : Icons.how_to_reg_rounded,
                            color:   kGold,
                            onTap:   isRegistering ? null : () => _confirmRegister(event),
                            loading: isRegistering,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetails(Map<String, dynamic> event, String eventId) {
    Navigator.push(context,
      MaterialPageRoute(
        builder: (_) => EventDetailsPage(
          event: event,
          registration: _regByEventId[eventId],
        ),
      ),
    ).then((_) => _loadData());
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Sub-widgets
// ══════════════════════════════════════════════════════════════════════════════

// ── Card image with overlays ──────────────────────────────────────────────────

class _CardImage extends StatelessWidget {
  final String?    imageUrl;
  final String     statusLabel;
  final Color      sc;
  final bool       isRegistered;
  final String     dateLabel;
  final AppTk        t;
  final VoidCallback onTap;

  const _CardImage({
    required this.imageUrl,
    required this.statusLabel,
    required this.sc,
    required this.isRegistered,
    required this.dateLabel,
    required this.t,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: 162,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background
            imageUrl != null
                ? Image.network(imageUrl!, fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _placeholder())
                : _placeholder(),
            // Bottom scrim
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Color(0xAA000000)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.45, 1.0],
                ),
              ),
            ),
            // Status chip — top left
            Positioned(
              top: 12, left: 12,
              child: _StatusChip(label: statusLabel, color: sc),
            ),
            // Registered badge — top right
            if (isRegistered)
              Positioned(
                top: 12, right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16A34A),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 6)],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_rounded, size: 10, color: Colors.white),
                      SizedBox(width: 4),
                      Text('Registered',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            // Date pill — bottom right
            Positioned(
              bottom: 10, right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: kGold,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 6)],
                ),
                child: Text(dateLabel,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, size: 32, color: t.muted),
          const SizedBox(height: 4),
          Text('No image', style: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: t.muted)),
        ],
      ),
    );
  }
}

// ── Animated status chip ──────────────────────────────────────────────────────

class _StatusChip extends StatefulWidget {
  final String label;
  final Color  color;
  const _StatusChip({required this.label, required this.color});

  @override
  State<_StatusChip> createState() => _StatusChipState();
}

class _StatusChipState extends State<_StatusChip>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;
  Animation<double>?   _fade;

  @override
  void initState() {
    super.initState();
    if (widget.label == 'Ongoing') {
      _ctrl = AnimationController(
          vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat(reverse: true);
      _fade = Tween<double>(begin: 0.25, end: 1.0)
          .animate(CurvedAnimation(parent: _ctrl!, curve: Curves.easeInOut));
    }
  }

  @override
  void dispose() { _ctrl?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.42), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.label == 'Ongoing' && _fade != null) ...[
            FadeTransition(
              opacity: _fade!,
              child: Container(
                width: 6, height: 6,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(widget.label,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.white)),
        ],
      ),
    );
  }
}

// ── Event type chip ───────────────────────────────────────────────────────────

class _TypeChip extends StatelessWidget {
  final String label;
  const _TypeChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: kGold.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kGold.withValues(alpha: 0.25)),
      ),
      child: Text(label,
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, color: kGold)),
    );
  }
}

// ── Metadata row ──────────────────────────────────────────────────────────────

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String   text;
  final AppTk      t;
  const _MetaRow({required this.icon, required this.text, required this.t});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: t.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: t.sub),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

// ── Capacity progress bar ─────────────────────────────────────────────────────

class _CapacityBar extends StatelessWidget {
  final double fill;
  final String label;
  final bool   isFull;
  final bool   maxSet;
  final AppTk    t;

  const _CapacityBar({
    required this.fill,
    required this.label,
    required this.isFull,
    required this.maxSet,
    required this.t,
  });

  Color get _barColor => isFull
      ? const Color(0xFFEF4444)
      : fill > 0.80
          ? const Color(0xFFF97316)
          : const Color(0xFF10B981);

  @override
  Widget build(BuildContext context) {
    if (!maxSet) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.people_rounded, size: 13,
                color: isFull ? const Color(0xFFEF4444) : t.muted),
            const SizedBox(width: 5),
            Expanded(
              child: Text(label,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                    color: isFull ? const Color(0xFFEF4444) : t.sub,
                    fontWeight: isFull ? FontWeight.w600 : FontWeight.w400)),
            ),
            Text('${(fill * 100).round()}%',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, color: _barColor)),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fill,
            minHeight: 4,
            backgroundColor: t.divider,
            valueColor: AlwaysStoppedAnimation<Color>(_barColor),
          ),
        ),
      ],
    );
  }
}

// ── Primary action button ─────────────────────────────────────────────────────

class _PrimaryBtn extends StatelessWidget {
  final String        label;
  final IconData?     icon;
  final Color         color;
  final VoidCallback? onTap;
  final bool          ghost;
  final bool          loading;
  final Gradient?     gradient;

  const _PrimaryBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.ghost    = false,
    this.loading  = false,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final disabled     = onTap == null && !loading;
    final useGradient  = gradient != null && !ghost && !disabled;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          gradient: useGradient ? gradient : null,
          color: useGradient
              ? null
              : ghost
                  ? Colors.transparent
                  : disabled
                      ? color.withValues(alpha: 0.45)
                      : color,
          borderRadius: BorderRadius.circular(12),
          border: ghost ? Border.all(color: color, width: 1.5) : null,
          boxShadow: ghost || disabled
              ? null
              : [BoxShadow(color: color.withValues(alpha: 0.30), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: loading
            ? SizedBox(
                width: 15, height: 15,
                child: CircularProgressIndicator(color: ghost ? color : Colors.white, strokeWidth: 2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 14, color: ghost ? color : Colors.white),
                    const SizedBox(width: 6),
                  ],
                  Text(label,
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, fontWeight: FontWeight.w700,
                        color: ghost ? color : Colors.white)),
                ],
              ),
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/widgets/app_loader.dart';
import '../../../models/event_registration.dart';
import '../../../shared/widgets/qr_code_dialog.dart';
import '../../../core/services/registration_service.dart';
import '../../../core/app_colors.dart';
import '../check_in/selfie_screen.dart';


// ══════════════════════════════════════════════════════════════════════════════
// Page
// ══════════════════════════════════════════════════════════════════════════════

class MyRegisteredEventsPage extends StatefulWidget {
  const MyRegisteredEventsPage({super.key});

  @override
  State<MyRegisteredEventsPage> createState() => _MyRegisteredEventsPageState();
}

class _MyRegisteredEventsPageState extends State<MyRegisteredEventsPage> {
  String _filter      = 'All';
  String _searchQuery = '';
  bool   _loading     = true;
  bool   _hasError    = false;

  final TextEditingController _searchCtrl    = TextEditingController();
  final List<String>          _filterOptions = ['All', 'Upcoming', 'Ongoing', 'Ended'];

  List<Map<String, dynamic>> _registrations = [];

  RealtimeChannel? _channel;
  Timer?           _debounce;
  // Upcoming → Ongoing → Ended follow the clock.
  Timer?           _clock;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeRealtime();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _debounce?.cancel();
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _subscribeRealtime() {
    _channel = Supabase.instance.client.channel('student-my-regs');
    for (final table in ['registrations', 'events']) {
      _channel!.on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(event: '*', schema: 'public', table: table),
        (_, [a]) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 600), () {
            if (mounted && !_loading) _load(silent: true);
          });
        },
      );
    }
    _channel!.subscribe();
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _load({bool silent = false}) async {
    if (mounted) setState(() { if (!silent) _loading = true; _hasError = false; });
    try {
      final rows = await RegistrationService.getMyRegistrationsWithEvents();
      if (mounted) setState(() { _registrations = rows; _loading = false; });
    } catch (e) {
      debugPrint('MyRegisteredEventsPage load error: $e');
      if (mounted) setState(() { _loading = false; _hasError = true; });
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  // The event's current name — the registration keeps the one from sign-up,
  // which goes stale when an organizer renames the event.
  String _titleOf(Map<String, dynamic> reg) {
    final current = ((reg['events'] as Map?)?['title'] as String?)?.trim();
    if (current != null && current.isNotEmpty) return current;
    return reg['event_title'] as String? ?? '—';
  }

  bool _isCheckedIn(Map<String, dynamic> reg) =>
      (reg['status'] as String? ?? '') == 'checked_in';

  String _fmtDate(Map<String, dynamic> reg) {
    final ev = reg['events'] as Map?;
    final d  = ev?['event_date'] as String?;
    if (d == null) return '—';
    try {
      final dt = DateTime.parse(d);
      const m  = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
      return '${m[dt.month - 1]} ${dt.day}';
    } catch (_) { return d; }
  }

  String _fmtTime(Map<String, dynamic> reg) {
    final ev = reg['events'] as Map?;
    final s  = ev?['start_time'] as String?;
    final e  = ev?['end_time']   as String?;
    if (s == null) return '—';
    String fmt(String t) {
      final p = t.split(':');
      if (p.length < 2) return t;
      final h = int.tryParse(p[0]) ?? 0;
      return '${h % 12 == 0 ? 12 : h % 12}:${p[1]} ${h >= 12 ? 'PM' : 'AM'}';
    }
    return e != null ? '${fmt(s)} — ${fmt(e)}' : fmt(s);
  }

  String _fmtRegisteredAt(Map<String, dynamic> reg) {
    final iso = reg['registered_at'] as String?;
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      const m  = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) { return iso; }
  }

  // ── Filtering ─────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get _filtered {
    final list = _registrations.where((reg) {
      final label = eventStatusLabel(reg['events'] as Map<String, dynamic>? ?? {});
      final matchesFilter = _filter == 'All' || label == _filter;
      final q     = _searchQuery.toLowerCase();
      final title = _titleOf(reg).toLowerCase();
      final ev    = reg['events'] as Map?;
      final loc   = (ev?['location'] as String? ?? '').toLowerCase();
      final matchesSearch = q.isEmpty || title.contains(q) || loc.contains(q);
      return matchesFilter && matchesSearch;
    }).toList();

    int statusOrder(String label) {
      if (label == 'Upcoming') return 0;
      if (label == 'Ongoing')  return 1;
      return 2; // Past, Cancelled
    }

    list.sort((a, b) {
      final la = eventStatusLabel(a['events'] as Map<String, dynamic>? ?? {});
      final lb = eventStatusLabel(b['events'] as Map<String, dynamic>? ?? {});
      final po = statusOrder(la).compareTo(statusOrder(lb));
      if (po != 0) return po;
      final da = (a['events'] as Map?)?['event_date'] as String? ?? '';
      final db = (b['events'] as Map?)?['event_date'] as String? ?? '';
      return da.compareTo(db);
    });

    return list;
  }

  int _countFor(String f) {
    if (f == 'All') return _registrations.length;
    return _registrations.where((r) => eventStatusLabel(r['events'] as Map<String, dynamic>? ?? {}) == f).length;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final t     = AppTk(Theme.of(context).brightness == Brightness.dark);
    final items = _filtered;

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
                    onRefresh: _load,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(child: _buildHeader(t)),
                        SliverToBoxAdapter(child: _buildSearchBar(t)),
                        SliverToBoxAdapter(child: _buildFilterRow(t)),
                        items.isEmpty
                            ? SliverFillRemaining(
                                hasScrollBody: false,
                                child: _buildEmpty(t),
                              )
                            : SliverPadding(
                                padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
                                sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (_, i) => _buildTicket(items[i], t),
                                    childCount: items.length,
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
          const SizedBox(height: 8),
          const AppShimmerList(itemCount: 4, hasAvatar: false, hasImage: false),
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
            Text('Could not load registrations',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700, color: t.text)),
            const SizedBox(height: 8),
            Text('Check your connection and try again.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.muted),
              textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _load,
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
          GestureDetector(
            onTap: () { HapticFeedback.lightImpact(); Navigator.pop(context); },
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: t.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.border),
                boxShadow: [BoxShadow(color: t.shadow, blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: t.text),
            ),
          ),
          const SizedBox(width: 14),
          Container(
            width: 3, height: 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFC49230), kGold, Color(0xFFEAB866)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('My Registrations',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 24, fontWeight: FontWeight.w800, color: t.text, height: 1.15)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Search bar ────────────────────────────────────────────────────────────

  Widget _buildSearchBar(AppTk t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
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
            hintText: 'Search your registrations…',
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
              onTap: () { HapticFeedback.selectionClick(); setState(() => _filter = f); },
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
                        color: selected ? Colors.white.withValues(alpha: 0.25) : t.divider,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('$count',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: selected ? Colors.white : t.muted,
                        )),
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
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: kGold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kGold.withValues(alpha: 0.18)),
            ),
            child: Icon(
              isFiltered ? Icons.search_off_rounded : Icons.confirmation_num_outlined,
              size: 34, color: kGold.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isFiltered ? 'No results found' : 'No registrations yet',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700, color: t.text),
          ),
          const SizedBox(height: 6),
          Text(
            isFiltered
                ? 'Try a different search or filter.'
                : 'Browse upcoming events and register\nto see your tickets here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: t.muted, height: 1.6),
          ),
          const SizedBox(height: 24),
          isFiltered
              ? OutlinedButton(
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
                )
              : ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kGold,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
                  ),
                  child: const Text('Browse Events',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700)),
                ),
        ],
      ),
    );
  }

  // ── Ticket card ───────────────────────────────────────────────────────────

  Widget _buildTicket(Map<String, dynamic> reg, AppTk t) {
    final ev          = reg['events'] as Map?;
    final title       = _titleOf(reg);
    final imageUrl    = ev?['event_image_url'] as String?;
    final hasImage    = imageUrl != null && imageUrl.isNotEmpty;
    final statusLabel = eventStatusLabel(reg['events'] as Map<String, dynamic>? ?? {});
    final status      = reg['status'] as String? ?? 'pending';
    final checkedIn   = _isCheckedIn(reg);
    // Declined by the organizer: the ticket can't be used, so no QR.
    final isDeclined  = status == 'rejected';
    final declineReason = (reg['rejection_reason'] as String?)?.trim() ?? '';
    final needsPhoto  = status == 'photo_required';
    final location    = ev?['location'] as String? ?? '—';
    final sc          = eventStatusColor(statusLabel);

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.border),
        boxShadow: [BoxShadow(color: t.shadow, blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Banner ──────────────────────────────────────────────────────────
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: SizedBox(
              height: 152,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  hasImage
                      ? Image.network(imageUrl, fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _placeholder(t))
                      : _placeholder(t),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Color(0x88000000)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.45, 1.0],
                      ),
                    ),
                  ),
                  Positioned(top: 12, left: 12, child: _StatusChip(label: statusLabel, color: sc)),
                  Positioned(top: 12, right: 12, child: _CheckInBadge(status: status)),
                  Positioned(
                    bottom: 10, right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: kGold,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 6)],
                      ),
                      child: Text(_fmtDate(reg),
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Event info ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700, color: t.text, height: 1.25),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 10),
                _MetaRow(icon: Icons.calendar_today_rounded, text: '${_fmtDate(reg)}  ·  ${_fmtTime(reg)}', t: t),
                const SizedBox(height: 5),
                _MetaRow(icon: Icons.location_on_rounded,    text: location,                               t: t),
                const SizedBox(height: 5),
                _MetaRow(icon: Icons.bookmark_added_rounded, text: 'Registered ${_fmtRegisteredAt(reg)}', t: t),
              ],
            ),
          ),

          // ── Ticket divider ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: _TicketDivider(dividerColor: t.divider),
          ),

          // ── QR button ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: isDeclined
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.35)),
                    ),
                    child: Column(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.block_rounded, size: 16, color: Color(0xFFDC2626)),
                            SizedBox(width: 8),
                            Text(
                              'Registration declined',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFB91C1C),
                              ),
                            ),
                          ],
                        ),
                        if (declineReason.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Reason: $declineReason',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: Color(0xFFB91C1C),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                : needsPhoto
                    ? _buildUploadPhotoButton(reg)
                    : Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: (checkedIn ? const Color(0xFF16A34A) : kGold)
                              .withValues(alpha: 0.34),
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
                          decoration: BoxDecoration(
                            gradient: checkedIn
                                ? const LinearGradient(
                                    colors: [Color(0xFF15803D), Color(0xFF22C55E)],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  )
                                : kGoldGradient,
                          ),
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              _showQR(reg);
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
                  ),
          ),
        ],
      ),
    );
  }

  // ── Persistent "Upload Attendance Photo" CTA ─────────────────────────────────
  //
  // Shown whenever a registration's status is 'photo_required' — i.e. the
  // organizer has confirmed attendance and requested proof. This card lives
  // in the ticket itself (not a one-shot popup), so backing out of the
  // camera screen or closing the app never strands the student: it's still
  // here next time they open this list, no organizer re-scan needed.
  Widget _buildUploadPhotoButton(Map<String, dynamic> reg) {
    final regId = reg['id'] as String;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9333EA).withValues(alpha: 0.34),
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
                colors: [Color(0xFF7E22CE), Color(0xFF9333EA)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                _openSelfieScreen(regId);
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
                        Icons.camera_alt_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 13),
                    const Expanded(
                      child: Text(
                        'Upload Attendance Photo',
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

  void _openSelfieScreen(String registrationId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SelfieScreen(registrationId: registrationId),
        fullscreenDialog: true,
      ),
    );
  }

  Widget _placeholder(AppTk t) {
    return Container(
      color: t.border,
      child: Center(
        child: Icon(Icons.image_outlined, size: 36, color: t.muted),
      ),
    );
  }

  // ── QR ────────────────────────────────────────────────────────────────────

  void _showQR(Map<String, dynamic> reg) {
    QRCodeDialog.show(context, EventRegistration(
      registrationId:   reg['id']                as String,
      eventTitle:       _titleOf(reg),
      studentId:        reg['student_school_id']  as String? ?? '',
      studentName:      reg['student_name']       as String? ?? '',
      registrationDate: DateTime.tryParse(reg['registered_at'] as String? ?? '') ?? DateTime.now(),
      qrCodeData:       reg['qr_code']            as String,
      ticketCode:       reg['ticket_code']        as String? ?? '—',
    ));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Sub-widgets
// ══════════════════════════════════════════════════════════════════════════════

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
        boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.40), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.label == 'Ongoing' && _fade != null) ...[
            FadeTransition(
              opacity: _fade!,
              child: Container(width: 6, height: 6,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
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

// ── Check-in badge ────────────────────────────────────────────────────────────

/// The badge on a ticket for its registration status: where check-in
/// stands. A new registration is simply "Registered". The colours keep white
/// text at 5:1 or better (the Home card's ticket chip uses the same ones).
({String label, IconData icon, Color color}) ticketStatusBadge(String? status) =>
    switch (status) {
      'qr_scanned' => (label: 'Scanned', icon: Icons.qr_code_scanner_rounded,
          color: const Color(0xFF0369A1)),
      'photo_required' => (label: 'Selfie needed', icon: Icons.photo_camera_rounded,
          color: kCheckInOpenColor),
      'photo_submitted' => (label: 'Under review', icon: Icons.hourglass_top_rounded,
          color: const Color(0xFF6D28D9)),
      'checked_in' => (label: 'Checked In', icon: Icons.check_circle_rounded,
          color: const Color(0xFF15803D)),
      'rejected' => (label: 'Declined', icon: Icons.block_rounded,
          color: const Color(0xFFB91C1C)),
      _ => (label: 'Registered', icon: Icons.confirmation_num_rounded,
          color: const Color(0xFF2563EB)),
    };

class _CheckInBadge extends StatelessWidget {
  final String? status;
  const _CheckInBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final badge = ticketStatusBadge(status);
    final color = badge.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.38), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badge.icon, color: Colors.white, size: 10),
          const SizedBox(width: 4),
          Text(
            badge.label,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

// ── Meta row ──────────────────────────────────────────────────────────────────

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
        const SizedBox(width: 7),
        Expanded(
          child: Text(text,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.sub),
            overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

// ── Ticket divider ────────────────────────────────────────────────────────────

class _TicketDivider extends StatelessWidget {
  final Color dividerColor;
  const _TicketDivider({required this.dividerColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _DashedLine(color: dividerColor)),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: kGold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: kGold.withValues(alpha: 0.22)),
          ),
          child: Text('TICKET',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 7.5, fontWeight: FontWeight.w800,
                color: kGold.withValues(alpha: 0.68), letterSpacing: 1.5)),
        ),
        Expanded(child: _DashedLine(color: dividerColor)),
      ],
    );
  }
}

// ── Dashed line via CustomPainter ─────────────────────────────────────────────

class _DashedLine extends StatelessWidget {
  final Color color;
  const _DashedLine({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1.5,
      child: CustomPaint(painter: _DashPainter(color)),
    );
  }
}

class _DashPainter extends CustomPainter {
  final Color color;
  const _DashPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color      = color
      ..strokeWidth = 1.5
      ..style      = PaintingStyle.stroke;
    double x = 0;
    while (x < size.width) {
      final end = (x + 5.0).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, 0), Offset(end, 0), paint);
      x += 9.0;
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter old) => old.color != color;
}

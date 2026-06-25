import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'create_event_screen.dart';
import 'manage_event_screen.dart';
import 'event_details.dart';
import '../../../../shared/widgets/app_loader.dart';
import '../../../../core/app_colors.dart';


class OrganizerEventsScreen extends StatefulWidget {
  final bool showAsEmbedded;
  const OrganizerEventsScreen({this.showAsEmbedded = false, super.key});

  @override
  State<OrganizerEventsScreen> createState() => _OrganizerEventsScreenState();
}

class _OrganizerEventsScreenState extends State<OrganizerEventsScreen> {
  String  _filter    = 'All';
  bool    _loading   = true;
  bool    _loadError = false;
  String? _organizerId;

  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _events    = [];
  List<Map<String, dynamic>> _filtered  = [];
  // event_id â†’ checked-in count (loaded alongside events)
  final Map<String, int> _checkedInMap = {};

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // â”€â”€ Data loading â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _loadData() async {
    setState(() { _loading = true; _loadError = false; });
    try {
      final client = Supabase.instance.client;
      final user   = client.auth.currentUser;
      if (user == null) return;

      final orgRow = await client
          .from('organizers')
          .select('organizer_id')
          .eq('user_id', user.id)
          .maybeSingle();

      if (orgRow == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      _organizerId = orgRow['organizer_id'] as String;

      final rows = await client
          .from('events')
          .select()
          .eq('organizer_id', _organizerId!)
          .order('created_at', ascending: false);

      final events = List<Map<String, dynamic>>.from(rows as List);

      // Load checked-in counts for all events in a single query
      final checkedIn = <String, int>{};
      if (events.isNotEmpty) {
        final eventIds = events.map((e) => e['event_id'] as String).toList();
        final regRows  = await client
            .from('registrations')
            .select('event_id')
            .in_('event_id', eventIds)
            .eq('status', 'checked_in');
        for (final r in (regRows as List)) {
          final eid = r['event_id'] as String;
          checkedIn[eid] = (checkedIn[eid] ?? 0) + 1;
        }
      }

      if (mounted) {
        setState(() {
          _events        = events;
          _checkedInMap
            ..clear()
            ..addAll(checkedIn);
          _loading = false;
          _applyFilter();
        });
      }
    } catch (e) {
      debugPrint('OrganizerEventsScreen load error: $e');
      if (mounted) setState(() { _loading = false; _loadError = true; });
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.toLowerCase();
    _filtered = _events.where((e) {
      final label     = _statusLabel(e);
      final matchFilter  = _filter == 'All' || label == _filter;
      final title        = (e['title']      as String? ?? '').toLowerCase();
      final location     = (e['location']   as String? ?? '').toLowerCase();
      final type         = (e['event_type'] as String? ?? '').toLowerCase();
      final matchSearch  = q.isEmpty ||
          title.contains(q) || location.contains(q) || type.contains(q);
      return matchFilter && matchSearch;
    }).toList();
    setState(() {});
  }

  // â”€â”€ Status helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  String _statusLabel(Map<String, dynamic> e) {
    final s = (e['event_status'] as String? ?? '').toLowerCase();
    if (s == 'ongoing' || s == 'active')                    return 'Ongoing';
    if (s == 'completed' || s == 'past' || s == 'ended')    return 'Past';
    if (s == 'cancelled')                                    return 'Cancelled';
    if (s == 'draft'    || s == 'pending')                   return 'Draft';
    final dateStr = e['event_date'] as String?;
    if (dateStr != null) {
      try {
        final date  = DateTime.parse(dateStr);
        final today = DateTime.now();
        if (date.isBefore(DateTime(today.year, today.month, today.day))) {
          return 'Past';
        }
      } catch (_) {}
    }
    return 'Upcoming';
  }

  Color _statusColor(String label) {
    switch (label) {
      case 'Ongoing':   return const Color(0xFF16A34A);
      case 'Past':      return const Color(0xFF6B7280);
      case 'Cancelled': return Colors.red;
      case 'Draft':     return const Color(0xFF9333EA);
      default:          return const Color(0xFFE87A00);
    }
  }

  String _formatDate(Map<String, dynamic> e) {
    final d = e['event_date'] as String?;
    if (d == null) return 'â€”';
    try {
      final dt = DateTime.parse(d);
      const m = ['JAN','FEB','MAR','APR','MAY','JUN',
                  'JUL','AUG','SEP','OCT','NOV','DEC'];
      return '${m[dt.month - 1]} ${dt.day}';
    } catch (_) { return d; }
  }

  String _formatTime(Map<String, dynamic> e) {
    final s  = e['start_time'] as String?;
    final en = e['end_time']   as String?;
    if (s == null) return 'â€”';
    String fmt(String t) {
      final p = t.split(':');
      if (p.length < 2) return t;
      final h = int.tryParse(p[0]) ?? 0;
      return '${h % 12 == 0 ? 12 : h % 12}:${p[1]} ${h >= 12 ? 'PM' : 'AM'}';
    }
    return en != null ? '${fmt(s)} - ${fmt(en)}' : fmt(s);
  }

  // â”€â”€ Computed counts â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  int get _total         => _events.length;
  int get _upcomingCount => _events.where((e) => _statusLabel(e) == 'Upcoming').length;
  int get _ongoingCount  => _events.where((e) => _statusLabel(e) == 'Ongoing').length;
  int get _pastCount     => _events.where((e) => _statusLabel(e) == 'Past').length;

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // BUILD
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          widget.showAsEmbedded ? Colors.transparent : kBackground,
      body: SafeArea(
        child: Column(
          children: [
            if (!widget.showAsEmbedded) _buildTopBar(),
            Expanded(
              child: _loading
                  ? _buildLoadingState()
                  : _loadError
                      ? _buildErrorState()
                      : RefreshIndicator(
                      color: kGold,
                      onRefresh: _loadData,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(child: _buildPageHeader()),
                          SliverToBoxAdapter(child: _buildSummaryStrip()),
                          SliverToBoxAdapter(child: _buildCreateButton()),
                          SliverToBoxAdapter(child: _buildFilterRow()),
                          SliverToBoxAdapter(child: _buildSearchBar()),
                          SliverToBoxAdapter(child: _buildResultCount()),
                          if (_filtered.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: _buildEmptyState(),
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (_, i) => Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: _buildEventCard(_filtered[i]),
                                  ),
                                  childCount: _filtered.length,
                                ),
                              ),
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

  // â”€â”€ Loading state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildLoadingState() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildPageHeader(),
          const AppShimmerList(itemCount: 5, hasAvatar: false, hasImage: true),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
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
              'Could not load events',
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
    );
  }

  // â”€â”€ Standalone top bar (non-embedded mode) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 18,
                color: kText,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'My Events',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: kText,
                    height: 1.1,
                  ),
                ),
                Text(
                  '$_total event${_total == 1 ? '' : 's'} total',
                  style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 12, color: kSubText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // â”€â”€ Inline page header (embedded mode) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildPageHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Eyebrow label
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: kGold,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    const Text(
                      'ORGANIZER',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: kGold,
                        letterSpacing: 1.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),

                // Title
                const Text(
                  'My Events',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: kText,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 7),

                // Gold accent underline
                Container(
                  width: 38,
                  height: 3,
                  decoration: BoxDecoration(
                    gradient: kGoldGradient,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 10),

                // Subtitle with icon
                Row(
                  children: [
                    Icon(Icons.schedule_rounded,
                        size: 13,
                        color: kSubText.withValues(alpha: 0.8)),
                    const SizedBox(width: 5),
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          color: kSubText,
                        ),
                        children: [
                          TextSpan(
                            text: '$_upcomingCount',
                            style: const TextStyle(
                              color: kGold,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const TextSpan(text: ' upcoming'),
                          TextSpan(
                            text: '  Â·  $_total',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: kText,
                            ),
                          ),
                          const TextSpan(text: ' total'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Decorative icon badge
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              gradient: kGoldGradient,
              borderRadius: BorderRadius.circular(17),
              boxShadow: [
                BoxShadow(
                  color: kGold.withValues(alpha: 0.32),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.event_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
        ],
      ),
    );
  }

  // â”€â”€ Summary stat strip â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildSummaryStrip() {
    final tiles = [
      (value: '$_total',        label: 'Total',    icon: Icons.event_rounded,         color: kGold),
      (value: '$_upcomingCount',label: 'Upcoming', icon: Icons.schedule_rounded,      color: const Color(0xFFE87A00)),
      (value: '$_ongoingCount', label: 'Ongoing',  icon: Icons.play_circle_rounded,   color: const Color(0xFF16A34A)),
      (value: '$_pastCount',    label: 'Past',     icon: Icons.history_rounded,       color: const Color(0xFF6B7280)),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: tiles.asMap().entries.map((entry) {
          final i = entry.key;
          final t = entry.value;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(left: i == 0 ? 0 : 8),
              padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 6),
              decoration: BoxDecoration(
                color: t.color.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: t.color.withValues(alpha: 0.2), width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  Icon(t.icon, color: t.color, size: 18),
                  const SizedBox(height: 5),
                  Text(
                    t.value,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: t.color,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    t.label,
                    style: const TextStyle(
                      fontFamily: 'Poppins', fontSize: 9, color: kMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // â”€â”€ Create new event (gradient card button) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildCreateButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateEventScreen()),
          ).then((_) => _loadData()),
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFC49230), kGold, Color(0xFFEAB866)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: kGold.withValues(alpha: 0.38),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Create New Event',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Publish a school event for students',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.white,
                      size: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // â”€â”€ Filter pill row (horizontal scroll) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildFilterRow() {
    const filters = ['All', 'Upcoming', 'Ongoing', 'Past', 'Draft'];
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: SizedBox(
        height: 42,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: filters.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (ctx, i) {
            final f        = filters[i];
            final selected = _filter == f;
            return GestureDetector(
              onTap: () => setState(() { _filter = f; _applyFilter(); }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                decoration: BoxDecoration(
                  gradient: selected ? kGoldGradient : null,
                  color: selected ? null : Colors.white,
                  borderRadius: BorderRadius.circular(21),
                  border: Border.all(
                    color: selected ? const Color(0xFFC49230) : Colors.grey.shade300,
                    width: 1.5,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: kGold.withValues(alpha: 0.32),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    f,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : kSubText,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // â”€â”€ Search bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: kText.withValues(alpha: 0.07),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (_) => _applyFilter(),
          style: const TextStyle(
            fontFamily: 'Poppins', fontSize: 14, color: kText,
          ),
          decoration: InputDecoration(
            hintText: 'Search events, venue, or typeâ€¦',
            hintStyle: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: kMuted.withValues(alpha: 0.8),
            ),
            prefixIcon: const Icon(
              Icons.search_rounded, color: kGold, size: 22,
            ),
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: Icon(
                      Icons.cancel_rounded,
                      color: kMuted.withValues(alpha: 0.6),
                      size: 20,
                    ),
                    onPressed: () {
                      _searchCtrl.clear();
                      _applyFilter();
                    },
                  )
                : null,
            filled: false,
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: kGold, width: 2),
            ),
          ),
        ),
      ),
    );
  }

  // â”€â”€ Result count label â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildResultCount() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Text(
        '${_filtered.length} event${_filtered.length == 1 ? '' : 's'} found',
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: kSubText,
        ),
      ),
    );
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // Event card â€” kept exactly as shown in screenshot
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  Widget _buildEventCard(Map<String, dynamic> e) {
    final eventId     = e['event_id'] as String;
    final title       = e['title']    as String? ?? 'â€”';
    final location    = e['location'] as String? ?? 'â€”';
    final type        = e['event_type'] as String? ?? 'â€”';
    final imageUrl    = e['event_image_url'] as String?;
    final registered  = e['current_participants'] as int? ?? 0;
    final capacity    = e['max_participants']     as int? ?? 0;
    final checkedIn   = _checkedInMap[eventId]   ?? 0;
    final statusLabel = _statusLabel(e);
    final statusColor = _statusColor(statusLabel);
    final fillPercent   = capacity > 0 ? (registered / capacity).clamp(0.0, 1.0) : 0.0;
    final attendancePct = registered > 0 ? ((checkedIn / registered) * 100).toInt() : 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: kText.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner image
          Stack(
            children: [
              SizedBox(
                width: double.infinity,
                height: 160,
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, stack) => _imagePlaceholder(),
                      )
                    : _imagePlaceholder(),
              ),
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.35),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 10, right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    statusLabel,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title + type badge
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: kText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: kGold.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        type,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: kGold,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Location / date / time block
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: kBackground.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 13,
                            color: kGold,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              location,
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: kText,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(
                            Icons.calendar_today_outlined,
                            size: 12,
                            color: kSubText,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _formatDate(e),
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              color: kSubText,
                            ),
                          ),
                          const Text(
                            ' Â· ',
                            style: TextStyle(color: kSubText),
                          ),
                          const Icon(
                            Icons.access_time_outlined,
                            size: 12,
                            color: kSubText,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              _formatTime(e),
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                color: kSubText,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // Stats row
                Row(
                  children: [
                    Expanded(
                      child: _statItem(
                        '$registered${capacity > 0 ? '/$capacity' : ''}',
                        'Registered',
                        kGold,
                      ),
                    ),
                    Container(
                      width: 1, height: 32,
                      color: Colors.grey.withValues(alpha: 0.2),
                    ),
                    Expanded(
                      child: _statItem('$checkedIn', 'Checked In', const Color(0xFF1A9E6E)),
                    ),
                    Container(
                      width: 1, height: 32,
                      color: Colors.grey.withValues(alpha: 0.2),
                    ),
                    Expanded(
                      child: _statItem(
                        '$attendancePct%', 'Attendance', const Color(0xFF2979C8),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Fill progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: fillPercent,
                    minHeight: 5,
                    backgroundColor: Colors.grey.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  ),
                ),

                const SizedBox(height: 12),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: _actionBtn('Manage', kGold, false, () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ManageEventScreen(
                              eventData: {
                                // Pass raw event row so ManageEventScreen can
                                // format dates itself and never loses precision.
                                ...e,
                                'registered': registered,
                                'checkedIn':  checkedIn,
                              },
                            ),
                          ),
                        ).then((_) => _loadData());
                      }),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _actionBtn('Details', kGold, true, () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            // EventDetailsScreen re-fetches from Supabase using
                            // event_id, so only the id key is strictly needed.
                            builder: (_) => EventDetailsScreen(eventData: e),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // â”€â”€ Card helpers (unchanged) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _statItem(String value, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 10, color: kSubText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(
    String label,
    Color color,
    bool secondary,
    VoidCallback onTap,
  ) {
    // Secondary (outlined) variant â€” e.g. "Details"
    if (secondary) {
      return ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: color,
          elevation: 0,
          side: BorderSide(color: color.withValues(alpha: 0.4), width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    // Primary variant â€” gradient matching the AI Assistant button
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: kGoldGradient,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: kGold.withValues(alpha: 0.38),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          side: BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      color: kBackground,
      child: Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 48,
          color: kGold.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  // â”€â”€ Empty state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildEmptyState() {
    final isFiltered =
        _filter != 'All' || _searchCtrl.text.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: kGold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Icon(
              isFiltered
                  ? Icons.search_off_rounded
                  : Icons.event_busy_rounded,
              size: 42,
              color: kGold.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            isFiltered ? 'No events found' : 'No events yet',
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: kText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isFiltered
                ? 'Try adjusting your search or filter'
                : 'Create your first event to get started',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: kMuted,
              height: 1.6,
            ),
          ),
          if (isFiltered) ...[
            const SizedBox(height: 28),
            GestureDetector(
              onTap: () {
                _searchCtrl.clear();
                setState(() { _filter = 'All'; });
                _applyFilter();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28, vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: kGold,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: kGold.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Text(
                  'Clear filters',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

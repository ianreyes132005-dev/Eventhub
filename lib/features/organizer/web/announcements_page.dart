import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/app_colors.dart';
import '../../../core/services/supabase_service.dart';
import 'web_shared.dart';

class WebAnnouncementsPage extends StatefulWidget {
  const WebAnnouncementsPage({super.key});

  @override
  State<WebAnnouncementsPage> createState() => _WebAnnouncementsPageState();
}

class _WebAnnouncementsPageState extends State<WebAnnouncementsPage> with SingleTickerProviderStateMixin {
  final _titleCtrl = TextEditingController();
  final _msgCtrl   = TextEditingController();

  bool    _posting  = false;
  bool    _loading  = true;
  String? _error;
  int     _titleLen = 0;
  int     _msgLen   = 0;

  List<Map<String, dynamic>> _announcements = [];

  late final AnimationController _staggerCtrl;
  RealtimeChannel? _channel;
  Timer?           _debounce;

  @override
  void initState() {
    super.initState();
    _staggerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _titleCtrl.addListener(_updateLengths);
    _msgCtrl.addListener(_updateLengths);
    _load();
    SupabaseService.announcementsVersion.addListener(_load);
    _subscribeRealtime();
  }

  void _updateLengths() {
    if (mounted) {
      setState(() {
        _titleLen = _titleCtrl.text.length;
        _msgLen   = _msgCtrl.text.length;
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_channel != null) SupabaseService.client.removeChannel(_channel!);
    _staggerCtrl.dispose();
    _titleCtrl.dispose();
    _msgCtrl.dispose();
    SupabaseService.announcementsVersion.removeListener(_load);
    super.dispose();
  }

  void _subscribeRealtime() {
    _channel = SupabaseService.client.channel('org-announcements');
    _channel!.on(
      RealtimeListenTypes.postgresChanges,
      ChannelFilter(event: '*', schema: 'public', table: 'announcements'),
      (_, [a]) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 600), () {
          if (mounted) _load();
        });
      },
    );
    _channel!.subscribe();
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

  Future<void> _load() async {
    try {
      final rows = await SupabaseService.getAnnouncements();
      if (mounted) {
        setState(() { _announcements = rows; _loading = false; });
        _staggerCtrl.forward(from: 0);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        _staggerCtrl.forward(from: 0);
      }
    }
  }

  Future<void> _post() async {
    final title = _titleCtrl.text.trim();
    final msg   = _msgCtrl.text.trim();
    if (title.isEmpty || msg.isEmpty) {
      setState(() => _error = 'Both title and message are required.');
      return;
    }
    setState(() { _posting = true; _error = null; });
    try {
      await SupabaseService.createAnnouncement(title: title, message: msg);
      _titleCtrl.clear();
      _msgCtrl.clear();
      await _load();
      if (mounted) {
        await WebAlert.success(
          context: context,
          title:   'Announcement Posted!',
          message: 'Your message is now visible to all registered students.',
        );
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception:', '').trim());
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _delete(int id) async {
    final ok = await WebAlert.confirm(
      context:      context,
      title:        'Delete Announcement?',
      message:      'This announcement will be removed for all students. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (ok != true) return;
    try {
      await SupabaseService.deleteAnnouncement(id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Failed to delete announcement: ${e.toString().replaceAll('Exception:', '').trim()}',
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kGold));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(kWebPad),
      child: LayoutBuilder(builder: (_, c) {
        final wide = c.maxWidth > 720;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _stagger(_buildPageHeader(), start: 0.00, end: 0.38),
            const SizedBox(height: 24),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 340, child: _stagger(_buildForm(), start: 0.18, end: 0.58)),
                  const SizedBox(width: 20),
                  Expanded(child: _buildList()),
                ],
              )
            else ...[
              _stagger(_buildForm(), start: 0.18, end: 0.58),
              const SizedBox(height: 20),
              _buildList(),
            ],
          ],
        );
      }),
    );
  }

  // ── Page header ───────────────────────────────────────────────────────────────

  Widget _buildPageHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Announcements',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: kText,
                height: 1.1,
              )),
            SizedBox(height: 3),
            Text('Broadcast messages to all registered students',
              style: TextStyle(
                fontFamily: 'Poppins', fontSize: 12, color: kSubText,
              )),
          ],
        ),
        const Spacer(),
        // Stat pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: kGold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kGold.withValues(alpha: 0.22)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('${_announcements.length}',
              style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 14,
                fontWeight: FontWeight.w800, color: kGold,
              )),
            const SizedBox(width: 6),
            const Text('Posted',
              style: TextStyle(
                fontFamily: 'Poppins', fontSize: 11,
                fontWeight: FontWeight.w500, color: kSubText,
              )),
          ]),
        ),
      ],
    );
  }

  // ── Compose form ──────────────────────────────────────────────────────────────

  Widget _buildForm() => WebCard(
    padding: const EdgeInsets.all(22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Card header
        Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              gradient: kGoldGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.campaign_rounded, color: Colors.white, size: 21),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('New Announcement',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 15,
                    fontWeight: FontWeight.w800, color: kText,
                  )),
                SizedBox(height: 3),
                Text('Visible to all students',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 11, color: kSubText,
                  )),
              ],
            ),
          ),
          // Audience badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.people_alt_rounded, size: 11, color: Color(0xFF3B82F6)),
              SizedBox(width: 4),
              Text('All Students',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 10,
                  fontWeight: FontWeight.w600, color: Color(0xFF1D4ED8),
                )),
            ]),
          ),
        ]),

        const SizedBox(height: 20),
        const Divider(color: kCardBorder),
        const SizedBox(height: 18),

        // Title field
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _FieldLabel('Announcement Title'),
            Text('$_titleLen / 100',
              style: TextStyle(
                fontFamily: 'Poppins', fontSize: 11,
                color: _titleLen >= 90 ? const Color(0xFFEF4444) : kMuted,
                fontWeight: _titleLen >= 90
                    ? FontWeight.w600 : FontWeight.w400,
              )),
          ],
        ),
        const SizedBox(height: 7),
        TextField(
          controller: _titleCtrl,
          maxLength: 100,
          buildCounter: (_, {required currentLength,
                              required isFocused, maxLength}) => null,
          style: const TextStyle(
            fontFamily: 'Poppins', fontSize: 13.5, color: kText),
          decoration: webInputDeco('e.g. Event Schedule Update'),
          onSubmitted: (_) => _post(),
        ),
        const SizedBox(height: 16),

        // Message field
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _FieldLabel('Message'),
            Text('$_msgLen / 1000',
              style: TextStyle(
                fontFamily: 'Poppins', fontSize: 11,
                color: _msgLen >= 900 ? const Color(0xFFEF4444) : kMuted,
                fontWeight: _msgLen >= 900
                    ? FontWeight.w600 : FontWeight.w400,
              )),
          ],
        ),
        const SizedBox(height: 7),
        TextField(
          controller: _msgCtrl,
          maxLength: 1000,
          maxLines: 6,
          buildCounter: (_, {required currentLength,
                              required isFocused, maxLength}) => null,
          style: const TextStyle(
            fontFamily: 'Poppins', fontSize: 13, color: kText, height: 1.55),
          decoration: webInputDeco('Write your announcement here…'),
        ),

        // Error
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline_rounded,
                size: 15, color: Color(0xFFEF4444)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_error!,
                  style: const TextStyle(
                    fontFamily: 'Poppins', fontSize: 12,
                    color: Color(0xFFB91C1C),
                  )),
              ),
            ]),
          ),
        ],

        const SizedBox(height: 20),

        // Post button
        SizedBox(
          width: double.infinity, height: 46,
          child: ElevatedButton.icon(
            onPressed: _posting ? null : _post,
            icon: _posting
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.send_rounded, size: 16),
            label: Text(_posting ? 'Sending…' : 'Post Announcement',
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              )),
            style: ElevatedButton.styleFrom(
              backgroundColor: kGold,
              foregroundColor: Colors.white,
              disabledBackgroundColor: kGold.withValues(alpha: 0.55),
              disabledForegroundColor: Colors.white70,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    ),
  );

  // ── Posted announcements list ─────────────────────────────────────────────────

  Widget _buildList() => WebCard(
    padding: const EdgeInsets.all(22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Section header
        Row(children: [
          Container(
            width: 3, height: 18,
            decoration: BoxDecoration(
              color: kGold, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          const Text('Posted Announcements',
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 15,
              fontWeight: FontWeight.w800, color: kText,
            )),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: kGold.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kGold.withValues(alpha: 0.22)),
            ),
            child: Text('${_announcements.length}',
              style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 11,
                fontWeight: FontWeight.w700, color: kGold,
              )),
          ),
        ]),

        const SizedBox(height: 18),

        if (_announcements.isEmpty)
          const WebEmptyState(
            icon: Icons.campaign_outlined,
            title: 'No announcements yet',
            subtitle: 'Post your first announcement using the compose form.',
          )
        else
          ..._announcements.asMap().entries.map((entry) {
            final i = entry.key;
            final a = entry.value;
            final s = 0.35 + (i * 0.08).clamp(0.0, 0.35);
            return _stagger(
              Padding(
                padding: EdgeInsets.only(top: i > 0 ? 12 : 0),
                child: _AnnouncementCard(
                  announcement: a,
                  onDelete: () => _delete(a['id'] as int),
                ),
              ),
              start: s, end: (s + 0.22).clamp(0.0, 1.0),
            );
          }),
      ],
    ),
  );
}

// ── Announcement card ─────────────────────────────────────────────────────────

class _AnnouncementCard extends StatefulWidget {
  final Map<String, dynamic> announcement;
  final VoidCallback         onDelete;
  const _AnnouncementCard({required this.announcement, required this.onDelete});

  @override
  State<_AnnouncementCard> createState() => _AnnouncementCardState();
}

class _AnnouncementCardState extends State<_AnnouncementCard> {
  bool _expanded = false;
  bool _hovered  = false;

  @override
  Widget build(BuildContext context) {
    final a       = widget.announcement;
    final title   = a['title']      as String? ?? '—';
    final message = a['message']    as String? ?? '';
    final created = a['created_at'] as String?;
    final isLong  = message.length > 180;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _hovered ? const Color(0xFFFFFDF5) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _hovered
              ? kGold.withValues(alpha: 0.40)
              : kCardBorder,
          ),
          boxShadow: [
            BoxShadow(
              color: _hovered
                ? kGold.withValues(alpha: 0.10)
                : Colors.black.withValues(alpha: 0.03),
              blurRadius: _hovered ? 14 : 4,
              offset: Offset(0, _hovered ? 4 : 1),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Gold left accent bar
              Container(
                width: 4,
                decoration: const BoxDecoration(
                  color: kGold,
                  borderRadius: BorderRadius.only(
                    topLeft:    Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                  ),
                ),
              ),

              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // Header row: icon + title/time + delete
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 34, height: 34,
                            decoration: BoxDecoration(
                              color: kGold.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.campaign_rounded, size: 17, color: kGold),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title,
                                  style: const TextStyle(
                                    fontFamily: 'Poppins', fontSize: 13.5,
                                    fontWeight: FontWeight.w700, color: kText,
                                  )),
                                const SizedBox(height: 3),
                                Row(children: [
                                  const Icon(Icons.access_time_rounded,
                                    size: 10, color: kMuted),
                                  const SizedBox(width: 3),
                                  Text(webTimeAgo(created),
                                    style: const TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 10.5, color: kMuted,
                                    )),
                                ]),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _DeleteBtn(onTap: widget.onDelete),
                        ],
                      ),

                      const SizedBox(height: 11),
                      const Divider(height: 1, color: kCardBorder),
                      const SizedBox(height: 11),

                      // Message body with AnimatedSize
                      AnimatedSize(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeInOut,
                        child: Text(
                          isLong && !_expanded
                            ? '${message.substring(0, 180)}…'
                            : message,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12.5,
                            color: kSubText,
                            height: 1.65,
                          ),
                        ),
                      ),

                      // Read more / Show less
                      if (isLong) ...[
                        const SizedBox(height: 9),
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => setState(() => _expanded = !_expanded),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(
                                _expanded ? 'Show less' : 'Read more',
                                style: const TextStyle(
                                  fontFamily: 'Poppins', fontSize: 11.5,
                                  fontWeight: FontWeight.w600, color: kGold,
                                )),
                              const SizedBox(width: 2),
                              Icon(
                                _expanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                                size: 15, color: kGold,
                              ),
                            ]),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Delete button with hover ───────────────────────────────────────────────────

class _DeleteBtn extends StatefulWidget {
  final VoidCallback onTap;
  const _DeleteBtn({required this.onTap});

  @override
  State<_DeleteBtn> createState() => _DeleteBtnState();
}

class _DeleteBtnState extends State<_DeleteBtn> {
  bool _h = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _h = true),
    onExit:  (_) => setState(() => _h = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: Tooltip(
        message: 'Delete announcement',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          width: 30, height: 30,
          decoration: BoxDecoration(
            color: _h
              ? const Color(0xFFEF4444).withValues(alpha: 0.12)
              : const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _h
                ? const Color(0xFFEF4444).withValues(alpha: 0.35)
                : Colors.transparent,
            ),
          ),
          child: const Icon(Icons.delete_outline_rounded,
            size: 14, color: Color(0xFFEF4444)),
        ),
      ),
    ),
  );
}

// ── Field label ───────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
    style: const TextStyle(
      fontFamily: 'Poppins',
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      color: kText,
    ));
}

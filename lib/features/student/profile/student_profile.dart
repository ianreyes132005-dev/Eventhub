import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:eventhub/core/services/supabase_service.dart';
import 'package:eventhub/shared/widgets/app_loader.dart';
import '../../../core/app_colors.dart';
import '../../../core/theme_store.dart';
import '../../../shared/widgets/error_alert.dart';
import '../../../shared/widgets/web/swal.dart';
import '../../../core/services/app_lang_prefs.dart';
import '../../../core/services/student_notif_prefs.dart';


// ══════════════════════════════════════════════════════════════════════════════
// ProfileBody — embedded inside StudentDashboard's IndexedStack
// ══════════════════════════════════════════════════════════════════════════════

class ProfileBody extends StatefulWidget {
  const ProfileBody({super.key});

  @override
  State<ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends State<ProfileBody> {
  bool    _loading        = true;
  bool    _uploadingPhoto = false;
  String  fullName        = '';
  String  studentId       = '';
  String  gradeSection    = '';
  int?    _year;                 // 7–12
  String? _strand;               // 'STEM' | 'HUMSS' | 'GAS' (Senior High only)
  String? _section;              // e.g. "Sampaguita" (from the registrar import)

  static const _strandNames = {
    'STEM':  'Science, Technology, Engineering & Mathematics',
    'HUMSS': 'Humanities & Social Sciences',
    'GAS':   'General Academic Strand',
  };

  bool get _isShs => _year == 11 || _year == 12;

  String get _levelName => _year == null
      ? ''
      : _isShs ? 'Senior High' : (_year! >= 7 && _year! <= 10 ? 'Junior High' : '');
  String  memberSince     = '';
  String? profilePhotoUrl;
  /// The student's registrations with their events — the stats card counts
  /// them as it builds, so the clock can move events into "finished".
  List<Map<String, dynamic>> _regs = [];
  int get registeredEvents => _regs.length;
  int get checkedIn => _regs.where((r) => r['status'] == 'checked_in').length;

  String _langCode = AppLangPrefs.english;
  /// From the installed build (pubspec version), not typed by hand.
  String _version = '';

  // Live: registering, every check-in step, an admin editing the student's
  // name, grade or section, and event changes all refresh the tab.
  RealtimeChannel? _channel;
  Timer? _debounce;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _subscribe();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _clock?.cancel();
    _debounce?.cancel();
    if (_channel != null) SupabaseService.client.removeChannel(_channel!);
    super.dispose();
  }

  void _subscribe() {
    final uid = SupabaseService.currentUser?.id;
    if (uid == null) return;
    void soon() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 600), () {
        if (mounted) _loadProfile();
      });
    }

    // registrations and events aren't filtered: RLS limits them to what the
    // student can see, and a filtered channel never hears deletes.
    _channel = SupabaseService.client.channel('student-profile-$uid')
      ..on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(event: '*', schema: 'public', table: 'registrations'),
        (_, [_]) => soon(),
      )
      ..on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(event: '*', schema: 'public', table: 'events'),
        (_, [_]) => soon(),
      )
      ..on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(
          event: 'UPDATE',
          schema: 'public',
          table: 'students',
          filter: 'user_id=eq.$uid',
        ),
        (_, [_]) => soon(),
      )
      ..subscribe();
  }

  Future<void> _loadProfile() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) { setState(() => _loading = false); return; }

      final studentRow = await SupabaseService.getProfile();

      final regs = await SupabaseService.client
          .from('registrations')
          .select('status, events(*)')
          .eq('student_user_id', user.id);

      final langCode = await AppLangPrefs.code(user.id);

      if (!mounted) return;
      final fn      = studentRow?['full_name'] as String? ?? '';
      final yr      = studentRow?['year_level'] as int?;
      final created = studentRow?['created_at'] as String?;
      final dt      = created != null ? DateTime.tryParse(created) : null;
      const mos     = ['Jan','Feb','Mar','Apr','May','Jun',
                       'Jul','Aug','Sep','Oct','Nov','Dec'];

      setState(() {
        _langCode = langCode;
        fullName         = fn.isNotEmpty ? fn : 'Student';
        studentId        = studentRow?['lrn'] as String? ?? '—';
        gradeSection     = yr != null ? 'Grade $yr' : '—';
        _year            = yr;
        final st         = studentRow?['strand'];
        _strand          = st is String && _strandNames.containsKey(st) ? st : null;
        final sec        = (studentRow?['section'] as String?)?.trim();
        _section         = sec == null || sec.isEmpty ? null : sec;
        memberSince      = dt != null ? '${mos[dt.month - 1]} ${dt.year}' : '—';
        profilePhotoUrl  = studentRow?['profile_image_url'] as String?;
        _regs            = List<Map<String, dynamic>>.from(regs as List);
        _loading = false;
      });
    } catch (e) {
      debugPrint('Student profile load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = AppTk(Theme.of(context).brightness == Brightness.dark);
    if (_loading) {
      return const AppFullScreenLoader(message: 'Loading your profile…');
    }
    return SafeArea(
      child: RefreshIndicator(
        color: kGold,
        backgroundColor: t.card,
        onRefresh: _loadProfile,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildTitle(t),
                  const SizedBox(height: 18),
                  _buildIdentityCard(t),
                  const SizedBox(height: 14),
                  _buildStatsCard(t),
                  const SizedBox(height: 24),
                  _buildSectionHeader('Account', t),
                  const SizedBox(height: 8),
                  _buildAccountInfoRow(t),
                  const SizedBox(height: 8),
                  _buildNotificationsTile(t),
                  const SizedBox(height: 8),
                  _buildLanguageTile(t),
                  const SizedBox(height: 24),
                  _buildSectionHeader('Preferences', t),
                  const SizedBox(height: 8),
                  _buildThemeTile(t),
                  const SizedBox(height: 8),
                  _buildAboutTile(t),
                  const SizedBox(height: 24),
                  _buildSectionHeader('Session', t),
                  const SizedBox(height: 8),
                  _buildLogoutButton(t),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Photo upload ──────────────────────────────────────────────────────────

  Future<void> _pickAndUploadPhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image, allowMultiple: false, withData: true,
    );
    if (!mounted || result == null) return;

    final file  = result.files.single;
    final bytes = file.bytes ??
        (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (bytes == null || !mounted) return;

    final ext = (file.extension ?? '').toLowerCase();
    const allowed = {'jpg', 'jpeg', 'png', 'webp'};
    if (!allowed.contains(ext)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unsupported image format. Use JPG, PNG, or WebP.'),
          backgroundColor: Color(0xFFEF4444)),
      );
      return;
    }
    if (bytes.length > 3 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Image is too large. Please choose a photo under 3 MB.'),
          backgroundColor: Color(0xFFEF4444)),
      );
      return;
    }

    setState(() => _uploadingPhoto = true);
    try {
      final user = SupabaseService.currentUser!;
      final path = '${user.id}/profile.$ext';

      await SupabaseService.client.storage
          .from('profile-photos')
          .uploadBinary(path, bytes,
              fileOptions: const FileOptions(upsert: true, cacheControl: '3600'));

      // Cache-buster: re-uploading to the same path keeps the same URL, so
      // image caches would keep showing the old photo until app restart.
      final url =
          '${SupabaseService.client.storage.from('profile-photos').getPublicUrl(path)}'
          '?v=${DateTime.now().millisecondsSinceEpoch}';

      await SupabaseService.client
          .from('students')
          .update({'profile_image_url': url})
          .eq('user_id', user.id);

      if (mounted) setState(() { profilePhotoUrl = url; _uploadingPhoto = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingPhoto = false);
        showErrorAlert(context, e, title: 'Couldn’t update your photo');
      }
    }
  }

  // ── Title + identity ───────────────────────────────────────────────────────

  Widget _buildTitle(AppTk t) => Center(
    child: Text('Profile',
      style: TextStyle(fontFamily: 'Poppins', fontSize: 17,
          fontWeight: FontWeight.w800, color: t.text)),
  );

  Widget _buildIdentityCard(AppTk t) {
    return _card(
      t: t,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          GestureDetector(
            onTap: _pickAndUploadPhoto,
            child: Stack(children: [
              Container(
                width: 58, height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, color: kGoldLight,
                  border: Border.all(color: kGold, width: 2),
                ),
                clipBehavior: Clip.antiAliasWithSaveLayer,
                child: _uploadingPhoto
                    ? const Center(
                        child: SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              color: kGold, strokeWidth: 2.5),
                        ),
                      )
                    : (profilePhotoUrl != null && profilePhotoUrl!.isNotEmpty
                        ? Image.network(profilePhotoUrl!, fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Icon(
                                Icons.person_rounded, size: 30, color: kGold))
                        : const Icon(Icons.person_rounded,
                            size: 30, color: kGold)),
              ),
              Positioned(
                bottom: 0, right: 0,
                child: Container(
                  width: 20, height: 20,
                  decoration: BoxDecoration(
                    color: kGold, shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                      size: 10, color: Colors.white),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fullName,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 15,
                      fontWeight: FontWeight.w700, color: t.text),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
                // LRN under the name — it's what students log in with. The
                // login email is an internal @gmail.com address, not shown.
                if (studentId.isNotEmpty && studentId != '—') ...[
                  const SizedBox(height: 2),
                  Text('LRN ${formatLrn(studentId)}',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                        color: t.muted,
                        fontFeatures: const [FontFeature.tabularFigures()]),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
                // Grade + strand at a glance, e.g. [Grade 11] [STEM]
                if (_year != null) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    _identityChip('Grade $_year', t),
                    if (_isShs && _strand != null)
                      _identityChip(_strand!, t, highlight: true),
                    if (_section != null) _identityChip(_section!, t),
                  ]),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _identityChip(String label, AppTk t, {bool highlight = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: highlight ? kGold.withValues(alpha: 0.12) : t.shimmer1,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
          color: highlight ? kGold.withValues(alpha: 0.35) : t.border),
    ),
    child: Text(label,
      style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: highlight ? 0.4 : 0,
          color: highlight ? const Color(0xFFB8861C) : t.sub)),
  );

  // ── Stats card ────────────────────────────────────────────────────────────

  Widget _buildStatsCard(AppTk t) {
    if (registeredEvents == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: t.border),
          boxShadow: [BoxShadow(color: t.shadow, blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: t.border,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.event_busy_rounded, size: 24, color: t.muted),
            ),
            const SizedBox(height: 14),
            Text('No events yet',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                  fontWeight: FontWeight.w700, color: t.text)),
            const SizedBox(height: 4),
            Text('Register for an event to start\ntracking your activity',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                  color: t.muted, height: 1.55)),
          ],
        ),
      );
    }

    // Same as Home: attended ÷ events that are over (check-in closed, not
    // cancelled) — an event still ahead can't have been attended yet.
    final now      = DateTime.now();
    final finished = _regs.where((r) => registrationIsFinished(r, now: now)).toList();
    final attendancePct = finished.isEmpty
        ? null
        : (finished.where((r) => r['status'] == 'checked_in').length /
                finished.length * 100)
            .round();
    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.border),
        boxShadow: [BoxShadow(color: t.shadow, blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          _statTile(Icons.event_rounded,        registeredEvents.toString(), 'Registered', kGold,                    t),
          _vertDivider(t),
          _statTile(Icons.check_circle_rounded, checkedIn.toString(),        'Attended',   const Color(0xFF10B981), t),
          _vertDivider(t),
          _statTile(Icons.insights_rounded,     attendancePct == null ? '—' : '$attendancePct%',           'Attendance', const Color(0xFF3B82F6), t),
        ],
      ),
    );
  }

  Widget _vertDivider(AppTk t) => Container(width: 1, height: 60, color: t.divider);

  Widget _statTile(IconData icon, String value, String label, Color color, AppTk t) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(height: 9),
            Text(value,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 20,
                  fontWeight: FontWeight.w800, color: t.text)),
            const SizedBox(height: 2),
            Text(label,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 9.5,
                  fontWeight: FontWeight.w500, color: t.muted, letterSpacing: 0.2)),
          ],
        ),
      ),
    );
  }

  // ── Section header ────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title, AppTk t) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(title,
        style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
            fontWeight: FontWeight.w600, color: t.muted)),
    );
  }

  // ── Account information ───────────────────────────────────────────────────

  Widget _buildAccountInfoRow(AppTk t) => _prefTile(t,
      icon:  Icons.badge_rounded,
      title: 'Account Information',
      onTap: _showAccountInfoSheet);

  void _showAccountInfoSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final t = AppTk(Theme.of(ctx).brightness == Brightness.dark);
        return _sheetShell(ctx, t,
          icon:     Icons.badge_rounded,
          title:    'Account Information',
          subtitle: 'Managed by your administrator',
          children: [
            const SizedBox(height: 4),
            _infoTile(Icons.badge_rounded, 'Student ID (LRN)',
                formatLrn(studentId), t: t, isId: true, onTap: _copyLrn),
            _divider(t),
            _infoTile(Icons.school_rounded, 'Grade Level',
                _levelName.isEmpty ? gradeSection : '$gradeSection · $_levelName', t: t),
            _divider(t),
            if (_isShs) ...[
              _infoTile(Icons.auto_stories_rounded, 'Strand',
                  _strand != null
                      ? '$_strand — ${_strandNames[_strand]}'
                      : 'Not assigned yet — contact your administrator',
                  t: t, muted: _strand == null),
              _divider(t),
            ],
            if (_section != null) ...[
              _infoTile(Icons.groups_rounded, 'Section', _section!, t: t),
              _divider(t),
            ],
            _infoTile(Icons.calendar_month_rounded, 'Member Since',
                memberSince, t: t),
            const SizedBox(height: 6),
          ],
        );
      },
    );
  }

  void _copyLrn() {
    Clipboard.setData(ClipboardData(text: studentId));
    HapticFeedback.lightImpact();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Row(children: [
        Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
        SizedBox(width: 8),
        Text('LRN copied to clipboard',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
      ]),
      backgroundColor: const Color(0xFF16A34A),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      duration: const Duration(seconds: 2),
    ));
  }

  Widget _infoTile(IconData icon, String label, String value, {
    required AppTk t, bool isId = false, bool muted = false, VoidCallback? onTap,
  }) {
    Widget tile = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: kGold.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: kGold, size: 17),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5, color: t.muted)),
                const SizedBox(height: 3),
                if (isId)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: kGold.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(value,
                          style: const TextStyle(
                            fontFamily: 'Courier', fontSize: 12,
                            fontWeight: FontWeight.w700, color: Color(0xFFB8861C))),
                      ),
                      if (onTap != null) ...[
                        const SizedBox(width: 7),
                        Icon(Icons.copy_rounded, size: 12, color: t.muted),
                      ],
                    ],
                  )
                else
                  Text(value,
                    style: TextStyle(fontFamily: 'Poppins',
                        fontSize: muted ? 12 : 13,
                        fontWeight: muted ? FontWeight.w400 : FontWeight.w600,
                        fontStyle: muted ? FontStyle.italic : FontStyle.normal,
                        color: muted ? t.muted : t.text),
                    // Long strand names wrap instead of being cut off.
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: tile,
        ),
      );
    }
    return tile;
  }

  // ── Dark mode tile ────────────────────────────────────────────────────────

  Widget _prefTile(AppTk t, {
    required IconData icon,
    required String title,
    String? trailing,
    required VoidCallback onTap,
  }) {
    return _card(
      t: t,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: kGold.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: kGold, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(title,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                      fontWeight: FontWeight.w600, color: t.text)),
              ),
              if (trailing != null) ...[
                Text(trailing,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                      fontWeight: FontWeight.w500, color: t.muted)),
                const SizedBox(width: 6),
              ],
              Icon(Icons.chevron_right_rounded, color: t.muted, size: 20),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _sheetShell(BuildContext ctx, AppTk t, {
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).padding.bottom + 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42, height: 4,
            decoration: BoxDecoration(
              color: t.muted.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: kGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 19, color: kGold),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 15,
                          fontWeight: FontWeight.w700, color: t.text)),
                    Text(subtitle,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                          color: t.muted)),
                  ],
                ),
              ),
            ]),
          ),
          Divider(height: 1, color: t.divider),
          ...children,
        ],
      ),
    );
  }

  Widget _sheetNote(AppTk t, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 12, color: t.muted.withValues(alpha: 0.7)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                  color: t.muted.withValues(alpha: 0.8), height: 1.5)),
          ),
        ],
      ),
    );
  }

  // ── Notifications tile + preferences ───────────────────────────────────────

  Widget _buildNotificationsTile(AppTk t) => _prefTile(t,
      icon:  Icons.notifications_rounded,
      title: 'Notifications',
      onTap: _showNotifPrefsSheet);

  Future<void> _showNotifPrefsSheet() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    final disabled = await StudentNotifPrefs.disabled(user.id);
    if (!mounted) return;

    final enabled = {
      StudentNotifPrefs.announcements:
          !disabled.contains(StudentNotifPrefs.announcements),
      StudentNotifPrefs.checkins:
          !disabled.contains(StudentNotifPrefs.checkins),
    };

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final t = AppTk(Theme.of(ctx).brightness == Brightness.dark);
        return StatefulBuilder(builder: (ctx, setSheet) {
          Widget toggle({
            required String cat,
            required IconData icon,
            required Color color,
            required String title,
            required String subtitle,
          }) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                            fontWeight: FontWeight.w600, color: t.text)),
                      Text(subtitle,
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5,
                            color: t.muted)),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: enabled[cat]!,
                  activeThumbColor: kGold,
                  activeTrackColor: kGold.withValues(alpha: 0.35),
                  onChanged: (v) {
                    setSheet(() => enabled[cat] = v);
                    StudentNotifPrefs.setEnabled(user.id, cat, v);
                  },
                ),
              ]),
            );
          }

          return _sheetShell(ctx, t,
            icon:     Icons.notifications_rounded,
            title:    'Notification Preferences',
            subtitle: 'Choose what appears in your inbox',
            children: [
              const SizedBox(height: 8),
              toggle(
                cat:      StudentNotifPrefs.announcements,
                icon:     Icons.campaign_rounded,
                color:    const Color(0xFF8B5CF6),
                title:    'Announcements',
                subtitle: 'School updates from organizers',
              ),
              toggle(
                cat:      StudentNotifPrefs.checkins,
                icon:     Icons.how_to_reg_rounded,
                color:    const Color(0xFF10B981),
                title:    'Check-in confirmations',
                subtitle: 'When your attendance is recorded',
              ),
              // Verification can never be silenced — organizers rely on it.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                child: Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.photo_camera_front_rounded,
                        size: 18, color: Color(0xFF3B82F6)),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Verification requests',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                              fontWeight: FontWeight.w600, color: t.text)),
                        Text('Selfie requests to confirm attendance',
                          style: TextStyle(fontFamily: 'Poppins',
                              fontSize: 10.5, color: t.muted)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: t.divider,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.lock_rounded, size: 10, color: t.muted),
                      const SizedBox(width: 4),
                      Text('Required',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                            fontWeight: FontWeight.w700, color: t.muted)),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              _sheetNote(t,
                  'Applies to your notification bell and inbox. Verification '
                  'requests can\'t be turned off — organizers need them to '
                  'confirm your attendance.'),
            ],
          );
        });
      },
    );
  }

  // ── Language tile + picker ─────────────────────────────────────────────────

  Widget _buildLanguageTile(AppTk t) => _prefTile(t,
      icon:     Icons.translate_rounded,
      title:    'Language',
      trailing: AppLangPrefs.label(_langCode),
      onTap:    _showLanguageSheet);

  Future<void> _showLanguageSheet() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final t = AppTk(Theme.of(ctx).brightness == Brightness.dark);

        Widget langRow({
          required String badge,
          required String name,
          required String subtitle,
          bool selected   = false,
          bool comingSoon = false,
          VoidCallback? onTap,
        }) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: selected
                        ? kGold.withValues(alpha: 0.06)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? kGold.withValues(alpha: 0.30)
                          : t.border,
                    ),
                  ),
                  child: Row(children: [
                    Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: selected
                            ? kGold.withValues(alpha: 0.14)
                            : t.divider,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Center(
                        child: Text(badge,
                          style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: selected
                                ? const Color(0xFFB8861C)
                                : t.muted,
                          )),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                            style: TextStyle(fontFamily: 'Poppins',
                                fontSize: 13.5, fontWeight: FontWeight.w600,
                                color: comingSoon ? t.muted : t.text)),
                          Text(subtitle,
                            style: TextStyle(fontFamily: 'Poppins',
                                fontSize: 10.5, color: t.muted)),
                        ],
                      ),
                    ),
                    if (comingSoon)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: const Color(0xFFF59E0B)
                                  .withValues(alpha: 0.30)),
                        ),
                        child: const Text('Soon',
                          style: TextStyle(fontFamily: 'Poppins',
                              fontSize: 10, fontWeight: FontWeight.w700,
                              color: Color(0xFFD97706))),
                      )
                    else if (selected)
                      const Icon(Icons.check_circle_rounded,
                          color: kGold, size: 22)
                    else
                      Icon(Icons.radio_button_unchecked_rounded,
                          color: t.muted, size: 22),
                  ]),
                ),
              ),
            ),
          );
        }

        return _sheetShell(ctx, t,
          icon:     Icons.translate_rounded,
          title:    'Language',
          subtitle: 'Choose your preferred app language',
          children: [
            const SizedBox(height: 12),
            langRow(
              badge:    'EN',
              name:     'English',
              subtitle: 'Default',
              selected: _langCode == AppLangPrefs.english,
              onTap: () {
                AppLangPrefs.setCode(user.id, AppLangPrefs.english);
                setState(() => _langCode = AppLangPrefs.english);
                Navigator.pop(ctx);
              },
            ),
            langRow(
              badge:      'FIL',
              name:       'Filipino',
              subtitle:   'Tagalog',
              comingSoon: true,
              onTap: () {
                HapticFeedback.selectionClick();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Filipino (Tagalog) is coming soon.'),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _sheetNote(t,
                'More languages are on the way. Your choice is saved and '
                'will apply across the app once available.'),
          ],
        );
      },
    );
  }

  // ── Theme tile + picker ────────────────────────────────────────────────────

  Widget _buildThemeTile(AppTk t) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeStore.notifier,
      builder: (_, mode, _) => _prefTile(t,
          icon:     Icons.palette_rounded,
          title:    'Theme',
          trailing: mode == ThemeMode.dark ? 'Dark' : 'Light',
          onTap:    _showThemeSheet),
    );
  }

  void _showThemeSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: ThemeStore.notifier,
          builder: (_, mode, _) {
            final t = AppTk(mode == ThemeMode.dark);

            Widget modeCard({
              required ThemeMode value,
              required String label,
              required String subtitle,
              required IconData icon,
            }) {
              final selected = mode == value;
              final pvDark   = value == ThemeMode.dark;
              final pvBg     = pvDark ? const Color(0xFF18140F) : const Color(0xFFFBF6EA);
              final pvCard   = pvDark ? const Color(0xFF231E17) : Colors.white;
              final pvBorder = pvDark ? const Color(0xFF352D20) : const Color(0xFFF0E8D8);
              final pvLine   = pvDark ? const Color(0xFFF2EAD8) : const Color(0xFF111827);
              final pvSub    = pvDark ? const Color(0xFF7A6E55) : const Color(0xFF9CA3AF);

              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    ThemeStore.set(value);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: selected
                          ? kGold.withValues(alpha: 0.06)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected
                            ? kGold.withValues(alpha: 0.40)
                            : t.border,
                        width: selected ? 1.6 : 1,
                      ),
                    ),
                    child: Column(children: [
                      Container(
                        height: 78,
                        width: double.infinity,
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: pvBg,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: pvBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Container(
                                width: 7, height: 7,
                                decoration: const BoxDecoration(
                                    color: kGold, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 5),
                              Container(
                                width: 42, height: 4,
                                decoration: BoxDecoration(
                                  color: pvLine.withValues(alpha: 0.75),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ]),
                            const SizedBox(height: 8),
                            Expanded(
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: pvCard,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: pvBorder),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 64, height: 4,
                                      decoration: BoxDecoration(
                                        color: pvLine.withValues(alpha: 0.85),
                                        borderRadius:
                                            BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Container(
                                      width: 40, height: 3.5,
                                      decoration: BoxDecoration(
                                        color: pvSub,
                                        borderRadius:
                                            BorderRadius.circular(2),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        Icon(icon, size: 15,
                            color: selected ? kGold : t.muted),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(label,
                                style: TextStyle(fontFamily: 'Poppins',
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: t.text)),
                              Text(subtitle,
                                style: TextStyle(fontFamily: 'Poppins',
                                    fontSize: 9.5, color: t.muted)),
                            ],
                          ),
                        ),
                        selected
                            ? const Icon(Icons.check_circle_rounded,
                                color: kGold, size: 20)
                            : Icon(Icons.radio_button_unchecked_rounded,
                                color: t.muted, size: 20),
                      ]),
                    ]),
                  ),
                ),
              );
            }

            return _sheetShell(ctx, t,
              icon:     Icons.palette_rounded,
              title:    'Theme',
              subtitle: 'Choose how EventHub looks',
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Row(children: [
                    modeCard(
                      value:    ThemeMode.light,
                      label:    'Light',
                      subtitle: 'Bright and clean',
                      icon:     Icons.light_mode_rounded,
                    ),
                    const SizedBox(width: 12),
                    modeCard(
                      value:    ThemeMode.dark,
                      label:    'Dark',
                      subtitle: 'Easy on the eyes',
                      icon:     Icons.dark_mode_rounded,
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                _sheetNote(t,
                    'Applies instantly and is saved to your account on '
                    'this device.'),
              ],
            );
          },
        );
      },
    );
  }

  // ── About tile ────────────────────────────────────────────────────────────

  Widget _buildAboutTile(AppTk t) => _prefTile(t,
      icon:     Icons.info_rounded,
      title:    'About EventHub',
      trailing: _version.isEmpty ? null : 'v$_version',
      onTap:    _showAboutDialog);

  // ── Logout button ─────────────────────────────────────────────────────────

  Widget _buildLogoutButton(AppTk t) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _showLogoutDialog,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFEF4444).withValues(alpha: 0.25), width: 1.5),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 17),
                SizedBox(width: 8),
                Text('Log Out',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                      fontWeight: FontWeight.w700, color: Color(0xFFEF4444))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Shared card helper ────────────────────────────────────────────────────

  Widget _card({required Widget child, required AppTk t}) {
    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.border),
        boxShadow: [BoxShadow(color: t.shadow, blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: child,
    );
  }

  Widget _divider(AppTk t) => Divider(
    height: 1, thickness: 0.8, indent: 66, endIndent: 16, color: t.divider,
  );

  // ── Dialogs ───────────────────────────────────────────────────────────────

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        final t = AppTk(Theme.of(ctx).brightness == Brightness.dark);
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    gradient: kGoldGradient,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: kGold.withValues(alpha: 0.40), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: const Icon(Icons.event_rounded, color: Colors.white, size: 36),
                ),
                const SizedBox(height: 16),
                Text('EventHub',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w800, color: t.text)),
                const SizedBox(height: 4),
                if (_version.isNotEmpty)
                  Text('Version $_version',
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, color: kGold, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Text(
                  'J-Jireh Learning Center\'s official event management platform. Browse and register for school events, track your attendance, and scan in with your personal QR code — all in one place.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, height: 1.6, color: t.muted),
                ),
                const SizedBox(height: 16),
                Divider(color: t.divider),
                const SizedBox(height: 12),
                _aboutInfoRow(Icons.school_rounded,         'School',   'J-Jireh Learning Center', t),
                const SizedBox(height: 10),
                _aboutInfoRow(Icons.build_rounded,          'Build',    'Flutter · Supabase',       t),
                const SizedBox(height: 10),
                _aboutInfoRow(Icons.devices_rounded,        'Platform', 'Android',                  t),
                const SizedBox(height: 10),
                _aboutInfoRow(Icons.support_agent_rounded,  'Contact',  'See school admin',         t),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close',
                      style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14, color: kGold)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _aboutInfoRow(IconData icon, String label, String value, AppTk t) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Row(
      children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: kGold.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: kGold),
        ),
        const SizedBox(width: 12),
        Text('$label  ',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, fontWeight: FontWeight.w600, color: t.text)),
        Text(value,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: t.muted)),
      ],
    ),
  );

  void _showLogoutDialog() {
    Swal.fire(
      context,
      icon: SwalIcon.warning,
      title: 'Log out?',
      text: 'Are you sure you want to sign out of your account?',
      showCancelButton: true,
      confirmButtonText: 'Log Out',
      confirmButtonColor: const Color(0xFFDC3741),
      cancelButtonText: 'Stay',
      reverseButtons: true,
    ).then((result) {
      if (result.isConfirmed) _performLogout();
    });
  }

  Future<void> _performLogout() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: kGold)),
    );
    try {
      await SupabaseService.signOut();
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        showErrorAlert(context, e, title: 'Couldn’t sign out');
      }
      return;
    }
    if (mounted) {
      Navigator.of(context).pop();
      await Swal.fire(
        context,
        icon: SwalIcon.success,
        title: 'Signed out',
        text: 'You have been signed out successfully.',
        showConfirmButton: false,
        timer: const Duration(milliseconds: 1200),
        timerProgressBar: true,
        allowOutsideClick: false,
      );
    }
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
    }
  }
}

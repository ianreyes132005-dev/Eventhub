import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../shared/widgets/app_loader.dart';
import 'package:eventhub/core/services/supabase_service.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/theme_store.dart';
import '../../../../core/services/org_notif_prefs.dart';
import '../../../../core/services/app_lang_prefs.dart';


// ══════════════════════════════════════════════════════════════════════════════
// OrganizerProfileScreen
// ══════════════════════════════════════════════════════════════════════════════

class OrganizerProfileScreen extends StatefulWidget {
  const OrganizerProfileScreen({super.key});

  @override
  State<OrganizerProfileScreen> createState() => _OrganizerProfileScreenState();
}

class _OrganizerProfileScreenState extends State<OrganizerProfileScreen> {
  bool _loading        = true;
  bool _uploadingPhoto = false;

  String _langCode = AppLangPrefs.english;

  Map<String, dynamic> _organizer = {
    'id': '—',
    'fullName': '',
    'email': '',
    'organization': 'J-Jireh',
    'memberSince': '—',
    'profileImage': null,
    'managedEvents': 0,
    'activeEvents': 0,
    'registeredParticipants': 0,
    'status': 'Active',
  };

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) { setState(() => _loading = false); return; }

      final orgRow = await SupabaseService.client
          .from('organizers')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      if (orgRow == null) { setState(() => _loading = false); return; }

      final orgId = orgRow['organizer_id'] as String;

      final events = await SupabaseService.client
          .from('events')
          .select('event_id, event_status, current_participants')
          .eq('organizer_id', orgId);

      final eventList      = events as List;
      final activeStatuses = {'upcoming', 'ongoing', 'active'};
      final activeCount    = eventList
          .where((e) => activeStatuses.contains(
              (e['event_status'] as String? ?? '').toLowerCase()))
          .length;
      final totalParticipants = eventList.fold<int>(
        0,
        (sum, e) => sum + (e['current_participants'] as int? ?? 0),
      );

      final fn       = orgRow['full_name'] as String? ?? '';
      final created  = orgRow['created_at'] as String?;
      final langCode = await AppLangPrefs.code(user.id);

      if (!mounted) return;
      setState(() {
        _organizer = {
          'id': orgId,
          'fullName': fn.isNotEmpty ? fn : 'Organizer',
          'email': user.email ?? '—',
          'organization': orgRow['organization'] as String? ?? 'J-Jireh',
          'memberSince': () {
            if (created == null) return '—';
            final dt = DateTime.tryParse(created);
            if (dt == null) return '—';
            const mos = ['Jan','Feb','Mar','Apr','May','Jun',
                         'Jul','Aug','Sep','Oct','Nov','Dec'];
            return '${mos[dt.month - 1]} ${dt.year}';
          }(),
          'profileImage': orgRow['profile_image_url'],
          'managedEvents': eventList.length,
          'activeEvents': activeCount,
          'registeredParticipants': totalParticipants,
          'status': orgRow['is_active'] == true ? 'Active' : 'Inactive',
        };
        _langCode = langCode;
        _loading  = false;
      });
    } catch (e) {
      debugPrint('Organizer profile load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = AppTk(Theme.of(context).brightness == Brightness.dark);
    if (_loading) {
      return Scaffold(
        backgroundColor: t.bg,
        body: const AppFullScreenLoader(message: 'Loading your profile…'),
      );
    }
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: kGold,
          backgroundColor: t.card,
          onRefresh: _loadProfile,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.only(top: 14, bottom: 36),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildTitle(t),
                    const SizedBox(height: 18),
                    _buildIdentityCard(t),
                    const SizedBox(height: 14),
                    _buildStatsCard(t),
                    const SizedBox(height: 24),
                    _listLabel('Account', t),
                    const SizedBox(height: 8),
                    _buildAccountInfoRow(t),
                    const SizedBox(height: 8),
                    _buildNotificationsTile(t),
                    const SizedBox(height: 8),
                    _buildLanguageTile(t),
                    const SizedBox(height: 24),
                    _listLabel('Preferences', t),
                    const SizedBox(height: 8),
                    _buildThemeTile(t),
                    const SizedBox(height: 8),
                    _buildAboutTile(t),
                    const SizedBox(height: 24),
                    _listLabel('Session', t),
                    const SizedBox(height: 8),
                    _buildLogoutTile(),
                  ]),
                ),
              ),
            ],
          ),
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

      // Delete old file if the extension changed — upsert only matches the same path
      final oldUrl = _organizer['profileImage'] as String?;
      if (oldUrl != null && oldUrl.isNotEmpty) {
        const marker = '/profile-photos/';
        final idx    = oldUrl.indexOf(marker);
        if (idx >= 0) {
          final oldPath = oldUrl.substring(idx + marker.length).split('?').first;
          if (oldPath != path) {
            try {
              await SupabaseService.client.storage
                  .from('profile-photos')
                  .remove([oldPath]);
            } catch (_) {} // non-critical
          }
        }
      }

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
          .from('organizers')
          .update({'profile_image_url': url})
          .eq('user_id', user.id);

      if (mounted) {
        setState(() {
          _organizer = Map.from(_organizer)..['profileImage'] = url;
          _uploadingPhoto = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingPhoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'),
              backgroundColor: const Color(0xFFEF4444)),
        );
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
    final photoUrl = _organizer['profileImage'] as String?;
    final name     = _organizer['fullName'] as String? ?? 'Organizer';
    final email    = _organizer['email']    as String? ?? '—';
    return _card(
      t: t,
      margin: const EdgeInsets.symmetric(horizontal: 20),
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
                    : (photoUrl != null && photoUrl.isNotEmpty
                        ? Image.network(photoUrl, fit: BoxFit.cover,
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
                Text(name,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 15,
                      fontWeight: FontWeight.w700, color: t.text),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(email,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                      color: t.muted),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ── List section label + settings row ──────────────────────────────────────

  Widget _listLabel(String title, AppTk t) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Text(title,
      style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
          fontWeight: FontWeight.w600, color: t.muted)),
  );

  Widget _settingsRow(AppTk t, {
    required IconData icon,
    required String title,
    String? trailing,
    required VoidCallback onTap,
  }) {
    return _card(
      t: t,
      margin: const EdgeInsets.symmetric(horizontal: 20),
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

  Widget _pill(String label, Color bg, Color fg, {IconData? icon}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: fg.withValues(alpha: 0.25)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 11, color: fg), const SizedBox(width: 4)],
        Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
      ],
    ),
  );

  // ── Stats card ────────────────────────────────────────────────────────────

  Widget _buildStatsCard(AppTk t) {
    final total      = _organizer['managedEvents']         as int? ?? 0;
    final active     = _organizer['activeEvents']          as int? ?? 0;
    final registered = _organizer['registeredParticipants'] as int? ?? 0;

    if (total == 0) {
      return _card(
        t: t,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(color: t.border, shape: BoxShape.circle),
                child: Icon(Icons.event_busy_rounded, size: 24, color: t.muted),
              ),
              const SizedBox(height: 14),
              Text('No events yet',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                    fontWeight: FontWeight.w700, color: t.text)),
              const SizedBox(height: 4),
              Text('Create your first event to\nstart tracking your activity',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                    color: t.muted, height: 1.55)),
            ],
          ),
        ),
      );
    }

    return _card(
      t: t,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _statTile(Icons.event_rounded,  '$total',      'Total Events', kGold,                   t),
          _vertDivider(t),
          _statTile(Icons.bolt_rounded,   '$active',     'Active',       const Color(0xFF10B981), t),
          _vertDivider(t),
          _statTile(Icons.people_rounded, '$registered', 'Registered',   const Color(0xFF3B82F6), t),
        ],
      ),
    );
  }

  Widget _vertDivider(AppTk t) =>
      Container(width: 1, height: 60, color: t.divider);

  Widget _statTile(IconData icon, String value, String label, Color color, AppTk t) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 17, color: color),
            ),
            const SizedBox(height: 8),
            Text(value,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 20,
                  fontWeight: FontWeight.w800, color: t.text, height: 1.0)),
            const SizedBox(height: 3),
            Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 9.5,
                  color: t.muted, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // ── Account information ────────────────────────────────────────────────────

  Widget _buildAccountInfoRow(AppTk t) => _settingsRow(t,
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
        final isActive    = _organizer['status'] == 'Active';
        final statusColor = isActive
            ? const Color(0xFF16A34A)
            : const Color(0xFF6B7280);
        return Container(
          decoration: BoxDecoration(
            color: t.card,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).padding.bottom + 14),
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
                    child: const Icon(Icons.badge_rounded,
                        size: 19, color: kGold),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Account Information',
                          style: TextStyle(fontFamily: 'Poppins',
                              fontSize: 15, fontWeight: FontWeight.w700,
                              color: t.text)),
                        Text('Managed by your administrator',
                          style: TextStyle(fontFamily: 'Poppins',
                              fontSize: 11, color: t.muted)),
                      ],
                    ),
                  ),
                  _pill(
                    isActive ? 'Active' : 'Inactive',
                    statusColor.withValues(alpha: 0.10),
                    statusColor,
                    icon: isActive
                        ? Icons.check_circle_rounded
                        : Icons.pause_circle_rounded,
                  ),
                ]),
              ),
              Divider(height: 1, color: t.divider),
              const SizedBox(height: 4),
              _infoTile(Icons.email_outlined, 'Email Address',
                  _organizer['email'] as String? ?? '—', t: t),
              _divider(t),
              _infoTile(Icons.business_rounded, 'Organization',
                  _organizer['organization'] as String? ?? '—', t: t),
              _divider(t),
              _infoTile(Icons.badge_rounded, 'Organizer ID',
                  _organizer['id'] as String? ?? '—', t: t, isId: true),
              _divider(t),
              _infoTile(Icons.calendar_month_rounded, 'Member Since',
                  '${_organizer['memberSince']}', t: t),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }

  Widget _infoTile(IconData icon, String label, String value, {
    required AppTk t, bool isId = false,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
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
                isId
                    ? GestureDetector(
                        onLongPress: () {
                          HapticFeedback.selectionClick();
                          Clipboard.setData(ClipboardData(text: value));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Organizer ID copied'),
                              behavior: SnackBarBehavior.floating,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: kGold.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(value,
                            style: const TextStyle(fontFamily: 'Courier', fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFB8861C))),
                        ),
                      )
                    : Text(value,
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: t.text),
                        overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Notifications ──────────────────────────────────────────────────────────

  Future<void> _showNotifPrefsSheet() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    final disabled = await OrgNotifPrefs.disabled(user.id);
    if (!mounted) return;

    final enabled = {
      OrgNotifPrefs.signups:  !disabled.contains(OrgNotifPrefs.signups),
      OrgNotifPrefs.live:     !disabled.contains(OrgNotifPrefs.live),
      OrgNotifPrefs.today:    !disabled.contains(OrgNotifPrefs.today),
      OrgNotifPrefs.tomorrow: !disabled.contains(OrgNotifPrefs.tomorrow),
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
                    OrgNotifPrefs.setEnabled(user.id, cat, v);
                  },
                ),
              ]),
            );
          }

          return Container(
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).padding.bottom + 14),
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
                      child: const Icon(Icons.notifications_rounded,
                          size: 19, color: kGold),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Notification Preferences',
                            style: TextStyle(fontFamily: 'Poppins',
                                fontSize: 15, fontWeight: FontWeight.w700,
                                color: t.text)),
                          Text('Choose what appears in your dashboard bell',
                            style: TextStyle(fontFamily: 'Poppins',
                                fontSize: 11, color: t.muted)),
                        ],
                      ),
                    ),
                  ]),
                ),
                Divider(height: 1, color: t.divider),
                const SizedBox(height: 8),
                toggle(
                  cat:      OrgNotifPrefs.signups,
                  icon:     Icons.how_to_reg_rounded,
                  color:    const Color(0xFF8B5CF6),
                  title:    'New sign-ups',
                  subtitle: 'When students register for your events',
                ),
                toggle(
                  cat:      OrgNotifPrefs.live,
                  icon:     Icons.radio_button_checked_rounded,
                  color:    const Color(0xFF10B981),
                  title:    'Live events',
                  subtitle: 'When one of your events is ongoing',
                ),
                toggle(
                  cat:      OrgNotifPrefs.today,
                  icon:     Icons.today_rounded,
                  color:    const Color(0xFF3B82F6),
                  title:    'Starting today',
                  subtitle: 'Events scheduled for today',
                ),
                toggle(
                  cat:      OrgNotifPrefs.tomorrow,
                  icon:     Icons.calendar_month_rounded,
                  color:    const Color(0xFFF59E0B),
                  title:    'Starting tomorrow',
                  subtitle: 'A heads-up one day before',
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 12, color: t.muted.withValues(alpha: 0.7)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Applies to the notification bell on your dashboard. '
                          'Changes take effect the next time it refreshes.',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                              color: t.muted.withValues(alpha: 0.8),
                              height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  Widget _buildNotificationsTile(AppTk t) => _settingsRow(t,
      icon:  Icons.notifications_rounded,
      title: 'Notifications',
      onTap: _showNotifPrefsSheet);

  // ── Language ───────────────────────────────────────────────────────────────

  Widget _buildLanguageTile(AppTk t) => _settingsRow(t,
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
                            color: selected ? const Color(0xFFB8861C) : t.muted,
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
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: const Color(0xFFF59E0B)
                                  .withValues(alpha: 0.30)),
                        ),
                        child: const Text('Soon',
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                              fontWeight: FontWeight.w700,
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

        return Container(
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).padding.bottom + 14),
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
                    child: const Icon(Icons.translate_rounded,
                        size: 19, color: kGold),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Language',
                          style: TextStyle(fontFamily: 'Poppins',
                              fontSize: 15, fontWeight: FontWeight.w700,
                              color: t.text)),
                        Text('Choose your preferred app language',
                          style: TextStyle(fontFamily: 'Poppins',
                              fontSize: 11, color: t.muted)),
                      ],
                    ),
                  ),
                ]),
              ),
              Divider(height: 1, color: t.divider),
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 12, color: t.muted.withValues(alpha: 0.7)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'More languages are on the way. Your choice is saved '
                        'and will apply across the app once available.',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                            color: t.muted.withValues(alpha: 0.8),
                            height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Theme ──────────────────────────────────────────────────────────────────

  Widget _buildThemeTile(AppTk t) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeStore.notifier,
      builder: (_, mode, _) => _settingsRow(t,
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
                      // Miniature UI preview in this mode's real colors
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 64, height: 4,
                                      decoration: BoxDecoration(
                                        color: pvLine.withValues(alpha: 0.85),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Container(
                                      width: 40, height: 3.5,
                                      decoration: BoxDecoration(
                                        color: pvSub,
                                        borderRadius: BorderRadius.circular(2),
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

            return Container(
              decoration: BoxDecoration(
                color: t.card,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).padding.bottom + 14),
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
                        child: const Icon(Icons.palette_rounded,
                            size: 19, color: kGold),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Theme',
                              style: TextStyle(fontFamily: 'Poppins',
                                  fontSize: 15, fontWeight: FontWeight.w700,
                                  color: t.text)),
                            Text('Choose how EventHub looks',
                              style: TextStyle(fontFamily: 'Poppins',
                                  fontSize: 11, color: t.muted)),
                          ],
                        ),
                      ),
                    ]),
                  ),
                  Divider(height: 1, color: t.divider),
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 12, color: t.muted.withValues(alpha: 0.7)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Applies instantly and is saved to your account '
                            'on this device.',
                            style: TextStyle(fontFamily: 'Poppins',
                                fontSize: 10,
                                color: t.muted.withValues(alpha: 0.8),
                                height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── About ──────────────────────────────────────────────────────────────────

  Widget _buildAboutTile(AppTk t) => _settingsRow(t,
      icon:     Icons.info_rounded,
      title:    'About EventHub',
      trailing: 'v1.0.0',
      onTap:    _showAboutDialog);

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
                const Text('Version 1.0.0',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: kGold, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Text(
                  'J-Jireh Learning Center\'s official event management platform. Create and manage school events, publish announcements, and track registrations and check-ins — all in one place.',
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

  // ── Logout ─────────────────────────────────────────────────────────────────

  Widget _buildLogoutTile() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _confirmLogout,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFEF4444).withValues(alpha: 0.25), width: 1.5,
              ),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 18),
                  SizedBox(width: 8),
                  Text('Log Out',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFEF4444))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Shared card helpers ────────────────────────────────────────────────────

  Widget _card({required Widget child, required AppTk t, EdgeInsets? margin}) {
    return Container(
      margin: margin,
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

  // ── Dialogs ────────────────────────────────────────────────────────────────

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Log out?',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to sign out of your account?',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Poppins')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _performLogout();
            },
            child: const Text('Log Out',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
  }

  Future<void> _performLogout() async {
    showDialog(
      context: context, barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: kGold)),
    );
    try {
      await SupabaseService.signOut();
    } catch (e) {
      debugPrint('Organizer sign-out error: $e');
    }
    if (mounted) {
      Navigator.of(context).pop(); // dismiss loader
      Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
    }
  }

}

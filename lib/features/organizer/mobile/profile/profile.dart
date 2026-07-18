import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../shared/widgets/app_loader.dart';
import 'package:eventhub/core/services/supabase_service.dart';
import '../../../../core/app_colors.dart';


// ══════════════════════════════════════════════════════════════════════════════
// OrganizerProfileScreen
// ══════════════════════════════════════════════════════════════════════════════

class OrganizerProfileScreen extends StatefulWidget {
  final bool showAsEmbedded;
  const OrganizerProfileScreen({this.showAsEmbedded = false, super.key});

  @override
  State<OrganizerProfileScreen> createState() => _OrganizerProfileScreenState();
}

class _OrganizerProfileScreenState extends State<OrganizerProfileScreen> {
  bool _loading        = true;
  bool _uploadingPhoto = false;

  Map<String, dynamic> _organizer = {
    'id': '—',
    'fullName': '',
    'email': '',
    'username': '',
    'role': 'Event Organizer',
    'organization': 'J-Jireh',
    'memberSince': '—',
    'profileImage': null,
    'managedEvents': 0,
    'activeEvents': 0,
    'registeredParticipants': 0,
    'checkedInToday': 0,
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

      int checkedInToday = 0;
      if (eventList.isNotEmpty) {
        final today      = DateTime.now();
        final startOfDay = DateTime(today.year, today.month, today.day)
            .toUtc()
            .toIso8601String();
        final eventIds = eventList.map((e) => e['event_id']).toList();
        final checkins = await SupabaseService.client
            .from('registrations')
            .select('id')
            .eq('status', 'checked_in')
            .gte('checked_in_at', startOfDay)
            .filter('event_id', 'in', '(${eventIds.join(',')})');
        checkedInToday = (checkins as List).length;
      }

      final fn      = orgRow['full_name'] as String? ?? '';
      final created = orgRow['created_at'] as String?;

      if (!mounted) return;
      setState(() {
        _organizer = {
          'id': orgId,
          'fullName': fn.isNotEmpty ? fn : 'Organizer',
          'email': user.email ?? '—',
          'username': fn.toLowerCase().replaceAll(' ', '_'),
          'role': 'Event Organizer',
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
          'checkedInToday': checkedInToday,
          'status': orgRow['is_active'] == true ? 'Active' : 'Inactive',
        };
        _loading = false;
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
              SliverToBoxAdapter(child: _buildBanner(t)),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              SliverPadding(
                padding: const EdgeInsets.only(bottom: 36),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildNameSection(t),
                    const SizedBox(height: 20),
                    _buildStatsCard(t),
                    const SizedBox(height: 16),
                    _buildAccountCard(t),
                    const SizedBox(height: 12),
                    _buildAboutTile(t),
                    const SizedBox(height: 12),
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
    if (bytes == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      final user = SupabaseService.currentUser!;
      final ext  = (file.extension ?? 'jpg').toLowerCase();
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

      final url = SupabaseService.client.storage
          .from('profile-photos')
          .getPublicUrl(path);

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

  // ── Banner + Avatar ────────────────────────────────────────────────────────

  Widget _buildBanner(AppTk t) {
    final photoUrl = _organizer['profileImage'] as String?;
    return SizedBox(
      height: 194,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: 148,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFC49230), kGold, Color(0xFFEAB866)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(children: [
                Positioned(top: -38, right: -30,  child: _circle(150, Colors.white.withValues(alpha: 0.10))),
                Positioned(bottom: -24, left: -32, child: _circle(110, Colors.white.withValues(alpha: 0.07))),
                Positioned(top: 24, left: 70,      child: _circle(56,  Colors.white.withValues(alpha: 0.06))),
              ]),
            ),
          ),
          Positioned(
            bottom: 0,
            child: GestureDetector(
              onTap: _pickAndUploadPhoto,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: kGold.withValues(alpha: 0.28), blurRadius: 18, offset: const Offset(0, 5))],
                ),
                child: Stack(children: [
                  Container(
                    width: 88, height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle, color: kGoldLight,
                      border: Border.all(color: kGold, width: 2.5),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _uploadingPhoto
                        ? const Center(child: CircularProgressIndicator(color: kGold, strokeWidth: 2.5))
                        : (photoUrl != null && photoUrl.isNotEmpty
                            ? Image.network(photoUrl, fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Icon(Icons.person_rounded, size: 44, color: kGold))
                            : const Icon(Icons.person_rounded, size: 44, color: kGold)),
                  ),
                  Positioned(
                    bottom: 0, right: 0,
                    child: Container(
                      width: 26, height: 26,
                      decoration: BoxDecoration(
                        color: kGold, shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.camera_alt_rounded, size: 13, color: Colors.white),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circle(double size, Color color) => Container(
    width: size, height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );

  // ── Name + badges ──────────────────────────────────────────────────────────

  Widget _buildNameSection(AppTk t) {
    final isActive = _organizer['status'] == 'Active';
    final statusColor = isActive
        ? const Color(0xFF16A34A)
        : const Color(0xFF6B7280);

    return Column(
      children: [
        Text(
          _organizer['fullName'] as String? ?? 'Organizer',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w800, color: t.text),
        ),
        const SizedBox(height: 3),
        Text(
          _organizer['organization'] as String? ?? 'J-Jireh',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.sub),
        ),
        const SizedBox(height: 10),
        _pill(
          isActive ? 'Active' : 'Inactive',
          statusColor.withValues(alpha: 0.10),
          statusColor,
          icon: isActive ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
        ),
        const SizedBox(height: 6),
        Text(
          'Member since ${_organizer['memberSince']}',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted),
        ),
      ],
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

  // ── Account card ───────────────────────────────────────────────────────────

  Widget _buildAccountCard(AppTk t) {
    return _card(
      t: t,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Account Information', t),
          _infoTile(Icons.email_outlined,  'Email Address', _organizer['email'] as String? ?? '—',        t: t),
          _divider(t),
          _infoTile(Icons.business_rounded,'Organization',  _organizer['organization'] as String? ?? '—', t: t),
          _divider(t),
          _infoTile(Icons.badge_rounded,   'Organizer ID',  _organizer['id'] as String? ?? '—',           t: t, isId: true),
          const SizedBox(height: 4),
        ],
      ),
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
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: kGold.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(value,
                          style: const TextStyle(fontFamily: 'Courier', fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFB8861C))),
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

  // ── About ──────────────────────────────────────────────────────────────────

  Widget _buildAboutTile(AppTk t) {
    return _card(
      t: t,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: _showAboutDialog,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: kGold.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.info_rounded, color: kGold, size: 18),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('About EventHub',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
                            fontWeight: FontWeight.w600, color: t.text)),
                      Text('Version 1.0.0 · J-Jireh Learning Center',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5, color: t.muted)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: t.muted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

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

  Widget _sectionLabel(String title, AppTk t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          Container(
            width: 3, height: 14,
            decoration: BoxDecoration(color: kGold, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 8),
          Text(title,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, fontWeight: FontWeight.w700, color: t.text, letterSpacing: 0.2)),
        ],
      ),
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

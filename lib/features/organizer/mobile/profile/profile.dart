import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../shared/widgets/app_loader.dart';
import 'package:eventhub/core/services/supabase_service.dart';
import 'edit_organizer_profile_screen.dart';
import '../../../../core/app_colors.dart';


// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// OrganizerProfileScreen
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

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
    'id': 'â€”',
    'fullName': '',
    'email': '',
    'username': '',
    'role': 'Event Organizer',
    'organization': 'J-Jireh',
    'memberSince': 'â€”',
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
          'email': user.email ?? 'â€”',
          'username': fn.toLowerCase().replaceAll(' ', '_'),
          'role': 'Event Organizer',
          'organization': orgRow['organization'] as String? ?? 'J-Jireh',
          'memberSince': created != null
              ? (DateTime.tryParse(created)?.year.toString() ?? 'â€”')
              : 'â€”',
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

  // â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  Widget build(BuildContext context) {
    final t = AppTk(Theme.of(context).brightness == Brightness.dark);
    if (_loading) {
      return Scaffold(
        backgroundColor: t.bg,
        body: const AppFullScreenLoader(message: 'Loading your profileâ€¦'),
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
                    _buildEditButton(t),
                    const SizedBox(height: 16),
                    _buildAccountCard(t),
                    const SizedBox(height: 12),
                    _buildSecurityCard(t),
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

  // â”€â”€ Photo upload â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

      // Delete old file if the extension changed â€” upsert only matches the same path
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

  // â”€â”€ Banner + Avatar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

  // â”€â”€ Name + badges â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildNameSection(AppTk t) {
    final isActive = _organizer['status'] == 'Active';
    final statusColor = isActive
        ? const Color(0xFF16A34A)
        : const Color(0xFF6B7280);

    return Column(
      children: [
        Text(
          _organizer['fullName'] as String? ?? 'Organizer',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w800, color: t.text),
        ),
        const SizedBox(height: 3),
        Text(
          _organizer['organization'] as String? ?? 'J-Jireh',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.sub),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6, runSpacing: 4, alignment: WrapAlignment.center,
          children: [
            _pill(_organizer['role'] as String? ?? 'Event Organizer', kGold.withValues(alpha: 0.12), kGold),
            _pill(
              isActive ? 'Active' : 'Inactive',
              statusColor.withValues(alpha: 0.10),
              statusColor,
              icon: isActive ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
            ),
          ],
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

  // â”€â”€ Edit button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildEditButton(AppTk t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: kGoldGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: kGold.withValues(alpha: 0.38), blurRadius: 14, offset: const Offset(0, 5))],
        ),
        child: SizedBox(
          width: double.infinity, height: 48,
          child: ElevatedButton.icon(
            onPressed: () async {
              final result = await Navigator.of(context).push<bool?>(
                MaterialPageRoute(
                  builder: (_) => EditOrganizerProfileScreen(
                    fullName:     _organizer['fullName'] as String?,
                    organization: _organizer['organization'] as String?,
                    email:        _organizer['email'] as String?,
                    username:     _organizer['username'] as String?,
                  ),
                ),
              );
              if (result == true) _loadProfile();
            },
            icon: const Icon(Icons.edit_rounded, size: 17),
            label: const Text('Edit Profile',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent, foregroundColor: Colors.white,
              elevation: 0, shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ),
    );
  }

  // â”€â”€ Account card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildAccountCard(AppTk t) {
    return _card(
      t: t,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Account Information', t),
          _infoTile(Icons.person_rounded,          'Full Name',     _organizer['fullName'] as String? ?? 'â€”',       t: t),
          _divider(t),
          _infoTile(Icons.email_outlined,          'Email Address', _organizer['email'] as String? ?? 'â€”',          t: t),
          _divider(t),
          _infoTile(Icons.alternate_email_rounded, 'Username',      '@${_organizer['username'] as String? ?? 'â€”'}', t: t),
          _divider(t),
          _infoTile(Icons.business_rounded,        'Organization',  _organizer['organization'] as String? ?? 'â€”',   t: t),
          _divider(t),
          _infoTile(Icons.badge_rounded,           'Organizer ID',  _organizer['id'] as String? ?? 'â€”',             t: t, isId: true),
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

  // â”€â”€ Security card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildSecurityCard(AppTk t) {
    return _card(
      t: t,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Security', t),
          _actionTile(
            icon: Icons.lock_rounded,
            title: 'Change Password',
            subtitle: 'Update your account password',
            onTap: _showChangePasswordDialog,
            t: t,
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required AppTk t,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20),
      ),
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
              child: Icon(icon, color: kGold, size: 17),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: t.text)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: t.muted, size: 20),
          ],
        ),
      ),
    );
  }

  // â”€â”€ Logout â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

  // â”€â”€ Shared card helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

  // â”€â”€ Dialogs â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

  void _showChangePasswordDialog() {
    final newCtrl     = TextEditingController();
    final confirmCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        bool saving = false;
        return StatefulBuilder(
          builder: (ctx, setDialog) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Change Password',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _pwField(newCtrl, 'New Password'),
                const SizedBox(height: 12),
                _pwField(confirmCtrl, 'Confirm New Password'),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(fontFamily: 'Poppins')),
              ),
              ElevatedButton(
                onPressed: saving ? null : () async {
                  final nw = newCtrl.text.trim();
                  final cf = confirmCtrl.text.trim();
                  if (nw.isEmpty || cf.isEmpty) { _snack('Please fill in all fields', const Color(0xFFEF4444)); return; }
                  if (nw != cf) { _snack('Passwords do not match', const Color(0xFFEF4444)); return; }
                  if (nw.length < 6) { _snack('Password must be at least 6 characters', const Color(0xFFEF4444)); return; }
                  setDialog(() => saving = true);
                  try {
                    await SupabaseService.client.auth.updateUser(UserAttributes(password: nw));
                    if (ctx.mounted) Navigator.pop(ctx);
                    _snack('Password updated successfully', const Color(0xFF16A34A));
                  } catch (e) {
                    setDialog(() => saving = false);
                    _snack('Update failed: ${e.toString()}', const Color(0xFFEF4444));
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGold, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: saving
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Update', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pwField(TextEditingController ctrl, String label) => TextField(
    controller: ctrl,
    obscureText: true,
    style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
      filled: true,
      fillColor: kGold.withValues(alpha: 0.04),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: kGold.withValues(alpha: 0.30), width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kGold, width: 1.8),
      ),
    ),
  );

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }
}

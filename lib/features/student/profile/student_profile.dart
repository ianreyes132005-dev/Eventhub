import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:eventhub/core/services/supabase_service.dart';
import 'package:eventhub/shared/widgets/app_loader.dart';
import '../../../core/app_colors.dart';


// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// ProfileBody â€” embedded inside StudentDashboard's IndexedStack
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

class ProfileBody extends StatefulWidget {
  final bool showAsEmbedded;
  const ProfileBody({this.showAsEmbedded = false, super.key});

  @override
  State<ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends State<ProfileBody> {
  bool   _loading        = true;
  bool   _uploadingPhoto = false;
  String fullName        = '';
  String username        = '';
  String studentId       = '';
  String gradeSection    = '';
  String role            = 'Student';
  String email           = '';
  String memberSince     = '';
  String? profilePhotoUrl;
  int    registeredEvents = 0;
  int    checkedIn        = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) { setState(() => _loading = false); return; }

      final studentRow = await SupabaseService.getProfile();

      final regs = await SupabaseService.client
          .from('registrations')
          .select('status')
          .eq('student_user_id', user.id);

      if (!mounted) return;
      final fn    = studentRow?['full_name'] as String? ?? '';
      final parts = fn.toLowerCase().split(' ');
      final uname = parts.length >= 2
          ? '${parts.first}_${parts.last}'
          : (parts.isNotEmpty ? parts.first : 'student');

      final yr      = studentRow?['year_level'] as int?;
      final created = studentRow?['created_at'] as String?;

      setState(() {
        fullName         = fn.isNotEmpty ? fn : 'Student';
        username         = uname;
        studentId        = studentRow?['lrn'] as String? ?? 'â€”';
        gradeSection     = yr != null ? 'Year Level $yr' : 'â€”';
        email            = user.email ?? 'â€”';
        memberSince      = created != null
            ? DateTime.tryParse(created)?.year.toString() ?? 'â€”'
            : 'â€”';
        profilePhotoUrl  = studentRow?['profile_image_url'] as String?;
        registeredEvents = regs.length;
        checkedIn        = (regs as List)
            .where((r) => r['status'] == 'checked_in')
            .length;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Student profile load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  Widget build(BuildContext context) {
    final t = AppTk(Theme.of(context).brightness == Brightness.dark);
    if (_loading) {
      return const AppFullScreenLoader(message: 'Loading your profileâ€¦');
    }
    return SafeArea(
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
                  _buildLogoutTile(t),
                ]),
              ),
            ),
          ],
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

      await SupabaseService.client.storage
          .from('profile-photos')
          .uploadBinary(path, bytes,
              fileOptions: const FileOptions(upsert: true, cacheControl: '3600'));

      final url = SupabaseService.client.storage
          .from('profile-photos')
          .getPublicUrl(path);

      await SupabaseService.client
          .from('students')
          .update({'profile_image_url': url})
          .eq('user_id', user.id);

      if (mounted) setState(() { profilePhotoUrl = url; _uploadingPhoto = false; });
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

  // â”€â”€ Banner + Avatar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildBanner(AppTk t) {
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
                Positioned(top: -38, right: -30,   child: _circle(150, Colors.white.withValues(alpha: 0.10))),
                Positioned(bottom: -24, left: -32,  child: _circle(110, Colors.white.withValues(alpha: 0.07))),
                Positioned(top: 24, left: 70,       child: _circle(56,  Colors.white.withValues(alpha: 0.06))),
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
                      shape: BoxShape.circle,
                      color: kGoldLight,
                      border: Border.all(color: kGold, width: 2.5),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _uploadingPhoto
                        ? const Center(child: CircularProgressIndicator(color: kGold, strokeWidth: 2.5))
                        : (profilePhotoUrl != null && profilePhotoUrl!.isNotEmpty
                            ? Image.network(profilePhotoUrl!, fit: BoxFit.cover,
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

  // â”€â”€ Name + badges â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildNameSection(AppTk t) {
    return Column(
      children: [
        Text(fullName,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w800, color: t.text)),
        const SizedBox(height: 3),
        Text('@$username',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.sub)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6, runSpacing: 4, alignment: WrapAlignment.center,
          children: [
            _pill(role, kGold.withValues(alpha: 0.12), kGold),
            _pill(gradeSection, const Color(0xFF3B82F6).withValues(alpha: 0.10), const Color(0xFF3B82F6)),
          ],
        ),
        const SizedBox(height: 6),
        Text('Member since $memberSince',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted)),
      ],
    );
  }

  Widget _pill(String label, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: fg.withValues(alpha: 0.25)),
    ),
    child: Text(label,
      style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
  );

  // â”€â”€ Edit button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
                  builder: (_) => EditProfileInfoScreen(
                    fullName: fullName, gradeSection: gradeSection,
                    studentId: studentId, email: email,
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

  // â”€â”€ Account card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildAccountCard(AppTk t) {
    return _card(
      t: t,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Account Information', t),
          _infoTile(Icons.person_rounded,          'Full Name',        fullName,     t: t),
          _divider(t),
          _infoTile(Icons.email_outlined,          'Email Address',    email,        t: t),
          _divider(t),
          _infoTile(Icons.badge_rounded,           'Student ID (LRN)', studentId,    t: t, isId: true),
          _divider(t),
          _infoTile(Icons.school_rounded,          'Grade / Section',  gradeSection, t: t),
          _divider(t),
          _infoTile(Icons.manage_accounts_rounded, 'Role',             role,         t: t),
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

  // â”€â”€ Security card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

  // â”€â”€ Logout â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildLogoutTile(AppTk t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showLogoutDialog,
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

  // â”€â”€ Shared card helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
            decoration: BoxDecoration(
              color: kGold, borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(title,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, fontWeight: FontWeight.w700, color: t.text, letterSpacing: 0.2)),
        ],
      ),
    );
  }

  Widget _divider(AppTk t) => Divider(
    height: 1, thickness: 0.8,
    indent: 66, endIndent: 16,
    color: t.divider,
  );

  // â”€â”€ Dialogs â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _showLogoutDialog() {
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
            onPressed: () async {
              Navigator.pop(ctx);
              showDialog(
                context: context, barrierDismissible: false,
                builder: (_) => const Center(child: CircularProgressIndicator(color: kGold)),
              );
              try { await SupabaseService.signOut(); } catch (e) { debugPrint('Sign out error: $e'); }
              if (mounted) {
                Navigator.of(context).pop();
                Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
              }
            },
            child: const Text('Log Out',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
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

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// ProfileScreen â€” full-screen standalone wrapper (kept for compat)
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppTk(Theme.of(context).brightness == Brightness.dark);
    return Scaffold(
      backgroundColor: t.bg,
      body: const ProfileBody(),
    );
  }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// EditProfileInfoScreen
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

class EditProfileInfoScreen extends StatefulWidget {
  final String? fullName;
  final String? gradeSection;
  final String? studentId;
  final String? contactNumber;
  final String? email;
  final bool    showAsEmbedded;

  const EditProfileInfoScreen({
    super.key,
    this.fullName,
    this.gradeSection,
    this.studentId,
    this.contactNumber,
    this.email,
    this.showAsEmbedded = false,
  });

  @override
  State<EditProfileInfoScreen> createState() => _EditProfileInfoScreenState();
}

class _EditProfileInfoScreenState extends State<EditProfileInfoScreen> {
  late final TextEditingController _nameCtrl;
  bool _saving     = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.fullName ?? '');
    _nameCtrl.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    final changed = _nameCtrl.text != (widget.fullName ?? '');
    if (changed != _hasChanges) setState(() => _hasChanges = changed);
  }

  String _initials(String name) {
    final t = name.trim();
    if (t.isEmpty) return 'S';
    final parts = t.split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return t[0].toUpperCase();
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasChanges) return true;
    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        title: const Text('Discard changes?',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 17)),
        content: const Text('You have unsaved changes. Are you sure you want to leave?',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 13, height: 1.55)),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: OutlinedButton.styleFrom(
              foregroundColor: kGold, side: const BorderSide(color: kGold),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('Keep Editing',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.10),
              foregroundColor: const Color(0xFFEF4444),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('Discard',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _save() async {
    if (!_hasChanges || _saving) return;
    if (_nameCtrl.text.trim().isEmpty) {
      _snack('Full name cannot be empty.', isError: true);
      return;
    }
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    try {
      final ok = await SupabaseService.updateProfile({'full_name': _nameCtrl.text.trim()});
      if (!mounted) return;
      if (ok) {
        _snack('Profile updated!', isError: false);
        Navigator.of(context).pop(true);
      } else {
        _snack('Failed to update profile.', isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Update failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(isError ? Icons.error_rounded : Icons.check_circle_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13))),
      ]),
      backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF16A34A),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      duration: const Duration(seconds: 3),
    ));
  }

  // â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  Widget build(BuildContext context) {
    final t = AppTk(Theme.of(context).brightness == Brightness.dark);
    return PopScope(
      canPop: !_hasChanges && !_saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final ok = await _confirmDiscard();
        if (ok && mounted) nav.pop();
      },
      child: Scaffold(
        backgroundColor: t.bg,
        body: SingleChildScrollView(
          child: Column(children: [_buildHero(), _buildBody(t)]),
        ),
        bottomNavigationBar: _buildSaveBar(t),
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1C1814), Color(0xFF2D2318), Color(0xFF3A2F1E)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(top: -30, right: -20, child: _decCircle(160, Colors.white.withValues(alpha: 0.04))),
          Positioned(bottom: 10, left: -40, child: _decCircle(110, Colors.white.withValues(alpha: 0.03))),
          Positioned(top: 50, left: 60,    child: _decCircle(60,  kGold.withValues(alpha: 0.07))),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 68),
              child: Column(children: [
                Row(children: [
                  _backBtn(),
                  const Spacer(),
                  AnimatedOpacity(
                    opacity: _hasChanges ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: _unsavedBadge(),
                  ),
                ]),
                const SizedBox(height: 18),
                const Text('Edit Profile',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white, height: 1.1)),
                const SizedBox(height: 4),
                const Text('Update your personal information',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: Colors.white60)),
              ]),
            ),
          ),
          Positioned(
            bottom: -48, left: 0, right: 0,
            child: Center(
              child: ListenableBuilder(
                listenable: _nameCtrl,
                builder: (_, _) => _avatarCircle(_initials(_nameCtrl.text)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarCircle(String initials) => Container(
    width: 96, height: 96,
    decoration: BoxDecoration(
      shape: BoxShape.circle, gradient: kGoldGradient,
      border: Border.all(color: Colors.white, width: 3.5),
      boxShadow: [BoxShadow(color: kGold.withValues(alpha: 0.45), blurRadius: 22, offset: const Offset(0, 8))],
    ),
    child: Center(child: Text(initials,
      style: const TextStyle(fontFamily: 'Poppins', fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white))),
  );

  Widget _buildBody(AppTk t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 64, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionLabel('Editable', Icons.edit_rounded, kGold, t),
        const SizedBox(height: 10),
        _formCard(t: t, children: [
          _editField(ctrl: _nameCtrl, label: 'Full Name', hint: 'e.g. Maria Santos',
              icon: Icons.badge_outlined, maxLength: 60, isFirst: true, isLast: true, t: t),
        ]),
        const SizedBox(height: 20),
        _sectionLabel('Set by Administrator', Icons.admin_panel_settings_rounded, t.muted, t),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: kGold.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kGold.withValues(alpha: 0.20)),
          ),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_rounded, size: 16, color: kGold),
            SizedBox(width: 10),
            Expanded(child: Text(
              'These fields are provisioned by your school administrator and cannot be changed through the app.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11, height: 1.55),
            )),
          ]),
        ),
        _formCard(t: t, children: [
          _lockedField(label: 'Grade / Section', value: widget.gradeSection ?? 'â€”', icon: Icons.school_outlined, isFirst: true, t: t),
          _cardDivider(t),
          _lockedField(label: 'Email Address',   value: widget.email ?? 'â€”',         icon: Icons.email_outlined, t: t),
          _cardDivider(t),
          _lockedField(label: 'Student ID (LRN)', value: widget.studentId ?? 'â€”',    icon: Icons.badge_outlined, isId: true, isLast: true, t: t),
        ]),
        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _buildSaveBar(AppTk t) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: t.card,
          boxShadow: [BoxShadow(color: t.shadow, blurRadius: 16, offset: const Offset(0, -4))],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(scale: Tween<double>(begin: 0.97, end: 1.0).animate(anim), child: child),
          ),
          child: _hasChanges
              ? _saveBtn(key: const ValueKey('save'))
              : _noChangeBtn(key: const ValueKey('noop'), t: t),
        ),
      ),
    );
  }

  Widget _saveBtn({Key? key}) => DecoratedBox(
    key: key,
    decoration: BoxDecoration(
      gradient: kGoldGradient, borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: kGold.withValues(alpha: 0.40), blurRadius: 16, offset: const Offset(0, 6))],
    ),
    child: SizedBox(
      width: double.infinity, height: 52,
      child: ElevatedButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.0))
            : const Icon(Icons.check_rounded, size: 20),
        label: Text(_saving ? 'Savingâ€¦' : 'Save Changes',
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent, foregroundColor: Colors.white,
          elevation: 0, shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    ),
  );

  Widget _noChangeBtn({Key? key, required AppTk t}) => SizedBox(
    key: key, width: double.infinity, height: 52,
    child: OutlinedButton.icon(
      onPressed: () => Navigator.of(context).pop(),
      icon: const Icon(Icons.arrow_back_rounded, size: 18),
      label: const Text('Go Back',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        foregroundColor: t.muted,
        side: BorderSide(color: t.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );

  // â”€â”€ Field widgets â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _editField({
    required TextEditingController ctrl,
    required String label,
    required String hint,
    required IconData icon,
    required AppTk t,
    int?  maxLength,
    TextInputType keyboard = TextInputType.text,
    bool isFirst = false,
    bool isLast  = false,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(14, isFirst ? 14 : 6, 14, isLast ? 14 : 6),
      child: TextFormField(
        controller: ctrl, keyboardType: keyboard, maxLength: maxLength,
        style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: t.text, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          labelText: label, hintText: hint,
          labelStyle: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.sub),
          hintStyle: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.muted),
          prefixIcon: Icon(icon, color: kGold, size: 20),
          counterStyle: TextStyle(fontFamily: 'Poppins', fontSize: 10, color: t.muted),
          filled: true, fillColor: t.inputBg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: BorderSide(color: kGold.withValues(alpha: 0.25), width: 1.2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: kGold, width: 2),
          ),
        ),
      ),
    );
  }

  Widget _lockedField({
    required String label, required String value, required IconData icon, required AppTk t,
    bool isId = false, bool isFirst = false, bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(14, isFirst ? 14 : 10, 14, isLast ? 14 : 10),
      child: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(color: t.border, borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, color: t.muted, size: 17),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5, color: t.muted)),
          const SizedBox(height: 3),
          isId
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: kGold.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(value, style: const TextStyle(fontFamily: 'Courier', fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFB8861C))),
                )
              : Text(value, style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w500, color: t.sub)),
        ])),
        Icon(Icons.lock_rounded, size: 13, color: t.border),
      ]),
    );
  }

  Widget _cardDivider(AppTk t) => Divider(
    height: 1, thickness: 0.8, indent: 60, endIndent: 14, color: t.divider,
  );

  Widget _formCard({required List<Widget> children, required AppTk t}) => Container(
    decoration: BoxDecoration(
      color: t.card, borderRadius: BorderRadius.circular(18),
      border: Border.all(color: t.border),
      boxShadow: [BoxShadow(color: t.shadow, blurRadius: 12, offset: const Offset(0, 4))],
    ),
    child: Column(children: children),
  );

  Widget _sectionLabel(String title, IconData icon, Color color, AppTk t) => Row(children: [
    Container(
      width: 26, height: 26,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(7)),
      child: Icon(icon, size: 13, color: color),
    ),
    const SizedBox(width: 8),
    Text(title.toUpperCase(),
      style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: color)),
    const SizedBox(width: 8),
    Expanded(child: Divider(height: 1, color: color.withValues(alpha: 0.15))),
  ]);

  Widget _backBtn() => GestureDetector(
    onTap: () async {
      final nav = Navigator.of(context);
      final ok = await _confirmDiscard();
      if (ok && mounted) nav.pop();
    },
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12), shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: Colors.white),
    ),
  );

  Widget _unsavedBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: kGold.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20),
      border: Border.all(color: kGold.withValues(alpha: 0.40)),
    ),
    child: const Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.edit_rounded, size: 10, color: kGold),
      SizedBox(width: 5),
      Text('Unsaved changes',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w600, color: kGold)),
    ]),
  );

  Widget _decCircle(double size, Color color) => Container(
    width: size, height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

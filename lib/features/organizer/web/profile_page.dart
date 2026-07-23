import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/app_colors.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/org_notif_prefs.dart';
import '../../../core/services/app_lang_prefs.dart';
import '../../../core/theme_store.dart';
import 'web_shared.dart';

class WebProfilePage extends StatefulWidget {
  final String?  orgId;
  final String?  name;
  final String?  email;
  final String?  organization;
  final void Function(String url)? onPhotoUpdated;
  final void Function(OrganizerPage)? onNavigate;

  const WebProfilePage({
    super.key,
    this.orgId,
    this.name,
    this.email,
    this.organization,
    this.onPhotoUpdated,
    this.onNavigate,
  });

  @override
  State<WebProfilePage> createState() => _WebProfilePageState();
}

class _WebProfilePageState extends State<WebProfilePage> {
  bool _uploadingPhoto = false;

  String? _photoUrl;
  bool    _isActive    = true;
  String  _memberSince = '—';

  String _langCode = AppLangPrefs.english;

  @override
  void initState() {
    super.initState();
    _loadExtras();
    _loadLangPref();
  }

  Future<void> _loadLangPref() async {
    final uid = SupabaseService.currentUser?.id;
    if (uid == null) return;
    final code = await AppLangPrefs.code(uid);
    if (mounted) setState(() => _langCode = code);
  }

  // ── Actions ───────────────────────────────────────────────────────────────────

  Future<void> _loadExtras() async {
    if (widget.orgId == null) return;
    try {
      final row = await SupabaseService.client
          .from('organizers')
          .select('profile_image_url, is_active, created_at')
          .eq('organizer_id', widget.orgId!)
          .maybeSingle();
      if (!mounted || row == null) return;

      setState(() {
        _photoUrl = row['profile_image_url'] as String?;
        _isActive = row['is_active'] == true;
        final created = row['created_at'] as String?;
        final dt = created != null ? DateTime.tryParse(created) : null;
        if (dt != null) {
          const mos = ['Jan','Feb','Mar','Apr','May','Jun',
                       'Jul','Aug','Sep','Oct','Nov','Dec'];
          _memberSince = '${mos[dt.month - 1]} ${dt.year}';
        }
      });
    } catch (_) {}
  }

  Future<void> _pickAndUploadPhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image, allowMultiple: false, withData: true,
    );
    if (!mounted || result == null) return;
    final bytes = result.files.single.bytes;
    if (bytes == null) return;

    final ext = (result.files.single.extension ?? '').toLowerCase();
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
      final oldUrl = _photoUrl;
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
        setState(() { _photoUrl = url; _uploadingPhoto = false; });
        widget.onPhotoUpdated?.call(url);
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

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(kWebPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Profile',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: t.text,
              height: 1.1,
            )),
          const SizedBox(height: 3),
          Text('Manage your account, preferences, and activity',
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 12, color: t.sub)),
          const SizedBox(height: 20),
          _buildBanner(t),
          const SizedBox(height: 24),
          _buildSettingsGrid(t),
        ],
      ),
    );
  }

  // ── Settings grid — "Account Settings" + "Preferences" ────────────────────────

  void _openAccountInfo() {
    showDialog(
      context: context,
      builder: (_) => _AccountInfoDialog(
        email:        widget.email ?? '—',
        organization: widget.organization,
        orgId:        widget.orgId ?? '—',
        memberSince:  _memberSince,
        isActive:     _isActive,
      ),
    );
  }

  void _openNotifPrefs() {
    final uid = SupabaseService.currentUser?.id;
    if (uid == null) return;
    showDialog(context: context, builder: (_) => _NotifPrefsDialog(userId: uid));
  }

  void _openLanguageDialog() {
    final uid = SupabaseService.currentUser?.id;
    if (uid == null) return;
    showDialog(
      context: context,
      builder: (_) => _LanguageDialog(
        userId:      uid,
        initialCode: _langCode,
        onChanged:   (code) => setState(() => _langCode = code),
      ),
    );
  }

  void _openAbout() {
    showDialog(context: context, builder: (_) => const _AboutDialog());
  }

  Widget _sectionLabel(String text, WebTk t) => Padding(
    padding: const EdgeInsets.only(bottom: 12, left: 2),
    child: Text(text,
      style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
          fontWeight: FontWeight.w700, color: t.sub, letterSpacing: 0.2)),
  );

  Widget _buildSettingsGrid(WebTk t) {
    final accountSettings = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Account Settings', t),
        _SettingTile(
          t: t, icon: Icons.badge_outlined, color: kGold,
          title: 'Account Information',
          subtitle: 'Email, organization, and status',
          onTap: _openAccountInfo,
        ),
        const SizedBox(height: 12),
        _SettingTile(
          t: t, icon: Icons.notifications_rounded, color: const Color(0xFF8B5CF6),
          title: 'Notifications',
          subtitle: 'Manage your dashboard alerts',
          trailing: 'Preferences',
          onTap: _openNotifPrefs,
        ),
        const SizedBox(height: 12),
        _SettingTile(
          t: t, icon: Icons.translate_rounded, color: const Color(0xFF3B82F6),
          title: 'Language',
          subtitle: 'Dashboard display language',
          trailing: AppLangPrefs.label(_langCode),
          trailingIcon: Icons.expand_more_rounded,
          onTap: _openLanguageDialog,
        ),
      ],
    );

    final preferences = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Preferences', t),
        _ThemeInlineCard(t: t),
        const SizedBox(height: 12),
        _SettingTile(
          t: t, icon: Icons.info_outline_rounded, color: const Color(0xFF10B981),
          title: 'About EventHub',
          subtitle: 'Version, build, and support info',
          trailing: 'v1.0.0',
          onTap: _openAbout,
        ),
      ],
    );

    return LayoutBuilder(builder: (_, c) {
      if (c.maxWidth > 760) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: accountSettings),
          const SizedBox(width: 20),
          Expanded(child: preferences),
        ]);
      }
      return Column(children: [
        accountSettings,
        const SizedBox(height: 22),
        preferences,
      ]);
    });
  }

  // ── Profile identity card ──────────────────────────────────────────────────────

  Widget _buildBanner(WebTk t) {
    final name = widget.name ?? 'Organizer';
    final email = widget.email ?? '—';
    final org  = widget.organization;
    final orgId = widget.orgId ?? '—';
    final initials = name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase())
        .take(2)
        .join();
    final statusColor = _isActive ? kGold : t.muted;

    return WebCard(
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(builder: (_, c) {
        final wide = c.maxWidth > 480;
        final avatar = MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _uploadingPhoto ? null : _pickAndUploadPhoto,
            child: Tooltip(
              message: 'Change photo',
              waitDuration: const Duration(milliseconds: 600),
              child: Stack(children: [
                Container(
                  width: 76, height: 76,
                  decoration: BoxDecoration(
                    gradient: kGoldGradient,
                    shape: BoxShape.circle,
                    border: Border.all(color: t.card, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: kGold.withValues(alpha: 0.30),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAliasWithSaveLayer,
                  child: _uploadingPhoto
                      ? const Center(
                          child: SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.4),
                          ),
                        )
                      : (_photoUrl != null && _photoUrl!.isNotEmpty)
                          ? Image.network(_photoUrl!, fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Center(
                                child: Text(initials,
                                  style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  )),
                              ))
                          : Center(
                              child: Text(initials,
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                )),
                            ),
                ),
                Positioned(
                  bottom: 0, right: 0,
                  child: Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      color: kGold,
                      shape: BoxShape.circle,
                      border: Border.all(color: t.card, width: 2),
                    ),
                    child: const Icon(Icons.camera_alt_rounded,
                        size: 12, color: Colors.white),
                  ),
                ),
              ]),
            ),
          ),
        );

        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('ORGANIZER PROFILE',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5,
                            fontWeight: FontWeight.w700, letterSpacing: 1.2,
                            color: kGold)),
                      const SizedBox(height: 3),
                      Text(name,
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 21,
                            fontWeight: FontWeight.w800, color: t.text, height: 1.1)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withValues(alpha: 0.30)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_isActive ? Icons.verified_rounded : Icons.pause_circle_rounded,
                        size: 13, color: statusColor),
                    const SizedBox(width: 5),
                    Text(_isActive ? 'Active Organizer' : 'Inactive Organizer',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                          fontWeight: FontWeight.w700, color: statusColor)),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (org != null && org.isNotEmpty) ...[
              Row(children: [
                Icon(Icons.business_rounded, size: 13, color: t.muted),
                const SizedBox(width: 6),
                Text(org,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                      fontWeight: FontWeight.w600, color: t.sub)),
              ]),
              const SizedBox(height: 6),
            ],
            Row(children: [
              Icon(Icons.mail_outline_rounded, size: 13, color: t.muted),
              const SizedBox(width: 6),
              Text(email,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: t.sub)),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 6, children: [
              _InfoChip(
                icon:  Icons.badge_rounded,
                label: orgId,
                color: kGold,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: orgId));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Organizer ID copied'),
                      behavior: SnackBarBehavior.floating,
                      width: 240,
                    ),
                  );
                },
              ),
              _InfoChip(
                icon:  Icons.calendar_month_rounded,
                label: 'Member since $_memberSince',
                color: const Color(0xFF3B82F6),
              ),
            ]),
          ],
        );

        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [avatar, const SizedBox(height: 16), details],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            avatar,
            const SizedBox(width: 20),
            Expanded(child: details),
          ],
        );
      }),
    );
  }

}


// ── Info chip (banner) ────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  final VoidCallback? onTap;
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(label,
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 11,
            fontWeight: FontWeight.w600, color: color,
          )),
        if (onTap != null) ...[
          const SizedBox(width: 5),
          Icon(Icons.copy_rounded, size: 10,
              color: color.withValues(alpha: 0.70)),
        ],
      ]),
    );
    if (onTap == null) return chip;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Tooltip(message: 'Copy', child: chip),
      ),
    );
  }
}

// ── Individual setting tile (each is its own card) ────────────────────────────

class _SettingTile extends StatefulWidget {
  final WebTk        t;
  final IconData      icon;
  final Color         color;
  final String        title;
  final String        subtitle;
  final String?       trailing;
  final IconData      trailingIcon;
  final VoidCallback  onTap;
  const _SettingTile({
    required this.t,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.trailingIcon = Icons.chevron_right_rounded,
    required this.onTap,
  });

  @override
  State<_SettingTile> createState() => _SettingTileState();
}

class _SettingTileState extends State<_SettingTile> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _h ? widget.color.withValues(alpha: 0.35) : t.border,
            ),
            boxShadow: [
              BoxShadow(
                color: t.shadow,
                blurRadius: _h ? 16 : 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(widget.icon, size: 19, color: widget.color),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13.5,
                        fontWeight: FontWeight.w700, color: t.text)),
                  const SizedBox(height: 2),
                  Text(widget.subtitle,
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                        color: t.muted),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (widget.trailing != null) ...[
              Text(widget.trailing!,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                    fontWeight: FontWeight.w600, color: t.sub)),
              const SizedBox(width: 4),
            ],
            Icon(widget.trailingIcon, size: 18, color: t.muted),
          ]),
        ),
      ),
    );
  }
}

// ── Shared preference-dialog frame ────────────────────────────────────────────
// Web-native modal chrome (icon badge + title/subtitle + close, divider,
// scrollable body) — deliberately NOT a mobile bottom sheet, matching this
// app's existing web dialog language (see WebAlert / admin's _dialogShell).

class _PrefDialogFrame extends StatelessWidget {
  final IconData icon;
  final Color    iconColor;
  final String   title;
  final String   subtitle;
  final Widget   child;
  final double   maxWidth;
  const _PrefDialogFrame({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.child,
    this.maxWidth = 440,
  });

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(20),
            border: t.dark ? Border.all(color: t.border) : null,
            boxShadow: [
              BoxShadow(color: t.shadow, blurRadius: 40, offset: const Offset(0, 16)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 20, 18),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: iconColor, size: 20),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 16,
                              fontWeight: FontWeight.w800, color: t.text)),
                        const SizedBox(height: 2),
                        Text(subtitle,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5,
                              color: t.sub)),
                      ],
                    ),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Icon(Icons.close_rounded, size: 20, color: t.muted),
                    ),
                  ),
                ]),
              ),
              Divider(height: 1, color: t.border),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _prefNote(WebTk t, String text) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(Icons.info_outline_rounded, size: 13, color: t.muted.withValues(alpha: 0.7)),
      const SizedBox(width: 7),
      Expanded(
        child: Text(text,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5,
              color: t.muted.withValues(alpha: 0.85), height: 1.5)),
      ),
    ],
  );
}

// ── Notification preferences dialog ───────────────────────────────────────────

class _NotifPrefsDialog extends StatefulWidget {
  final String userId;
  const _NotifPrefsDialog({required this.userId});

  @override
  State<_NotifPrefsDialog> createState() => _NotifPrefsDialogState();
}

class _NotifPrefsDialogState extends State<_NotifPrefsDialog> {
  Map<String, bool> _enabled = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final disabled = await OrgNotifPrefs.disabled(widget.userId);
    if (!mounted) return;
    setState(() {
      _enabled = {
        OrgNotifPrefs.signups:  !disabled.contains(OrgNotifPrefs.signups),
        OrgNotifPrefs.live:     !disabled.contains(OrgNotifPrefs.live),
        OrgNotifPrefs.today:    !disabled.contains(OrgNotifPrefs.today),
        OrgNotifPrefs.tomorrow: !disabled.contains(OrgNotifPrefs.tomorrow),
      };
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return _PrefDialogFrame(
      icon:     Icons.notifications_rounded,
      iconColor: kGold,
      title:    'Notification Preferences',
      subtitle: 'Choose what appears in your dashboard bell',
      child: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(color: kGold, strokeWidth: 2.4)),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _toggle(t, OrgNotifPrefs.signups, Icons.how_to_reg_rounded,
                    const Color(0xFF8B5CF6), 'New sign-ups',
                    'When students register for your events'),
                const SizedBox(height: 14),
                _toggle(t, OrgNotifPrefs.live, Icons.radio_button_checked_rounded,
                    const Color(0xFF10B981), 'Live events',
                    'When one of your events is ongoing'),
                const SizedBox(height: 14),
                _toggle(t, OrgNotifPrefs.today, Icons.today_rounded,
                    const Color(0xFF3B82F6), 'Starting today',
                    'Events scheduled for today'),
                const SizedBox(height: 14),
                _toggle(t, OrgNotifPrefs.tomorrow, Icons.calendar_month_rounded,
                    const Color(0xFFF59E0B), 'Starting tomorrow',
                    'A heads-up one day before'),
                const SizedBox(height: 18),
                _prefNote(t,
                    'Applies to the notification bell on your dashboard.'),
              ],
            ),
    );
  }

  Widget _toggle(WebTk t, String cat, IconData icon, Color color,
      String title, String subtitle) {
    return Row(children: [
      Container(
        width: 38, height: 38,
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
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted)),
          ],
        ),
      ),
      Switch.adaptive(
        value: _enabled[cat] ?? true,
        activeThumbColor: kGold,
        activeTrackColor: kGold.withValues(alpha: 0.35),
        onChanged: (v) {
          setState(() => _enabled[cat] = v);
          OrgNotifPrefs.setEnabled(widget.userId, cat, v);
        },
      ),
    ]);
  }
}

// ── Language dialog ────────────────────────────────────────────────────────────

class _LanguageDialog extends StatefulWidget {
  final String userId;
  final String initialCode;
  final ValueChanged<String> onChanged;
  const _LanguageDialog({
    required this.userId,
    required this.initialCode,
    required this.onChanged,
  });

  @override
  State<_LanguageDialog> createState() => _LanguageDialogState();
}

class _LanguageDialogState extends State<_LanguageDialog> {
  late String _code = widget.initialCode;

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return _PrefDialogFrame(
      icon:     Icons.translate_rounded,
      iconColor: kGold,
      title:    'Language',
      subtitle: 'Choose your preferred dashboard language',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _langCard(t, code: AppLangPrefs.english, badge: 'EN',
              name: 'English', desc: 'Default'),
          const SizedBox(height: 10),
          _langCard(t, code: AppLangPrefs.filipino, badge: 'FIL',
              name: 'Filipino', desc: 'Tagalog', comingSoon: true),
          const SizedBox(height: 18),
          _prefNote(t,
              'More languages are on the way. Your choice is saved and will '
              'apply across the dashboard once available.'),
        ],
      ),
    );
  }

  Widget _langCard(WebTk t, {
    required String code,
    required String badge,
    required String name,
    required String desc,
    bool comingSoon = false,
  }) {
    final selected = _code == code;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: comingSoon
            ? () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Filipino (Tagalog) is coming soon.'),
                  behavior: SnackBarBehavior.floating,
                ))
            : () {
                setState(() => _code = code);
                AppLangPrefs.setCode(widget.userId, code);
                widget.onChanged(code);
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? kGold.withValues(alpha: 0.06) : t.inputBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? kGold.withValues(alpha: 0.40) : t.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: selected ? kGold.withValues(alpha: 0.15) : t.divider,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Center(
                child: Text(badge,
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                      color: selected ? const Color(0xFFB8861C) : t.muted)),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: comingSoon ? t.muted : t.text)),
                  Text(desc,
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted)),
                ],
              ),
            ),
            if (comingSoon)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.30)),
                ),
                child: const Text('Soon',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5,
                      fontWeight: FontWeight.w700, color: Color(0xFFD97706))),
              )
            else if (selected)
              const Icon(Icons.check_circle_rounded, color: kGold, size: 22)
            else
              Icon(Icons.radio_button_unchecked_rounded, color: t.muted, size: 22),
          ]),
        ),
      ),
    );
  }
}

// ── Theme — inline toggle card (no dialog; choice is visible immediately) ─────

class _ThemeInlineCard extends StatelessWidget {
  final WebTk t;
  const _ThemeInlineCard({required this.t});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeStore.notifier,
      builder: (_, mode, _) {
        final isDark = mode == ThemeMode.dark;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.border),
            boxShadow: [
              BoxShadow(color: t.shadow, blurRadius: 8, offset: const Offset(0, 3)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                    size: 19, color: const Color(0xFFF59E0B)),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Theme',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 13.5,
                            fontWeight: FontWeight.w700, color: t.text)),
                      const SizedBox(height: 2),
                      Text('Choose your preferred theme.',
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                            color: t.muted)),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: _pill(label: 'Light', icon: Icons.wb_sunny_rounded,
                      selected: !isDark, onTap: () => ThemeStore.set(ThemeMode.light)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _pill(label: 'Dark', icon: Icons.nightlight_round,
                      selected: isDark, onTap: () => ThemeStore.set(ThemeMode.dark)),
                ),
              ]),
            ],
          ),
        );
      },
    );
  }

  Widget _pill({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? kGold.withValues(alpha: 0.10) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? kGold.withValues(alpha: 0.55) : t.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 15, color: selected ? kGold : t.muted),
            const SizedBox(width: 6),
            Text(label,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                  fontWeight: FontWeight.w700, color: selected ? kGold : t.sub)),
          ]),
        ),
      ),
    );
  }
}

// ── Account information dialog (view-only — admin-managed) ────────────────────

class _AccountInfoDialog extends StatelessWidget {
  final String  email;
  final String? organization;
  final String  orgId;
  final String  memberSince;
  final bool    isActive;
  const _AccountInfoDialog({
    required this.email,
    this.organization,
    required this.orgId,
    required this.memberSince,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return _PrefDialogFrame(
      icon:     Icons.badge_rounded,
      iconColor: kGold,
      title:    'Account Information',
      subtitle: 'Managed by your school administrator',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(t, Icons.mail_outline_rounded, 'Email Address', email),
          _divider(t),
          _row(t, Icons.business_rounded, 'Organization',
              (organization != null && organization!.isNotEmpty) ? organization! : '—'),
          _divider(t),
          _row(t, Icons.badge_rounded, 'Organizer ID', orgId, mono: true,
              onCopy: () {
                Clipboard.setData(ClipboardData(text: orgId));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Organizer ID copied'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }),
          _divider(t),
          _row(t, Icons.calendar_month_rounded, 'Member Since', memberSince),
          _divider(t),
          _row(t, isActive ? Icons.verified_rounded : Icons.pause_circle_rounded,
              'Status', isActive ? 'Active' : 'Inactive'),
          const SizedBox(height: 18),
          _prefNote(t, 'Contact your school administrator to update these details.'),
        ],
      ),
    );
  }

  Widget _divider(WebTk t) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Divider(height: 1, color: t.border),
  );

  Widget _row(WebTk t, IconData icon, String label, String value,
      {bool mono = false, VoidCallback? onCopy}) {
    return Row(children: [
      Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: kGold.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 16, color: kGold),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5, color: t.muted)),
            const SizedBox(height: 2),
            Text(value,
              style: TextStyle(
                  fontFamily: mono ? 'Courier' : 'Poppins', fontSize: 13.5,
                  fontWeight: FontWeight.w600, color: t.text),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
      if (onCopy != null)
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onCopy,
            child: Icon(Icons.copy_rounded, size: 15, color: t.muted),
          ),
        ),
    ]);
  }
}

// ── About dialog ───────────────────────────────────────────────────────────────

class _AboutDialog extends StatelessWidget {
  const _AboutDialog();

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return _PrefDialogFrame(
      icon:     Icons.celebration_rounded,
      iconColor: kGold,
      title:    'About EventHub',
      subtitle: 'Version 1.0.0',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'J-Jireh Learning Center\'s official event management platform. '
            'Create and manage school events, publish announcements, and '
            'track registrations and check-ins — all in one place.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                color: t.sub, height: 1.6),
          ),
          const SizedBox(height: 18),
          Divider(height: 1, color: t.border),
          const SizedBox(height: 16),
          _row(t, Icons.school_rounded, 'School', 'J-Jireh Learning Center'),
          const SizedBox(height: 12),
          _row(t, Icons.build_rounded, 'Build', 'Flutter · Supabase'),
          const SizedBox(height: 12),
          _row(t, Icons.language_rounded, 'Platform', 'Web'),
          const SizedBox(height: 12),
          _row(t, Icons.support_agent_rounded, 'Contact', 'See school admin'),
        ],
      ),
    );
  }

  Widget _row(WebTk t, IconData icon, String label, String value) {
    return Row(children: [
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
        style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
            fontWeight: FontWeight.w600, color: t.text)),
      Expanded(
        child: Text(value,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.muted)),
      ),
    ]);
  }
}


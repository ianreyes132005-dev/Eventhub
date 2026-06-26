import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/app_colors.dart';
import '../../../core/services/supabase_service.dart';
import 'web_shared.dart';

class WebProfilePage extends StatefulWidget {
  final String?  orgId;
  final String?  name;
  final String?  email;
  final String?  organization;
  final void Function(String? name, String? org) onProfileUpdated;

  const WebProfilePage({
    super.key,
    this.orgId,
    this.name,
    this.email,
    this.organization,
    required this.onProfileUpdated,
  });

  @override
  State<WebProfilePage> createState() => _WebProfilePageState();
}

class _WebProfilePageState extends State<WebProfilePage> {
  late final _nameCtrl = TextEditingController(text: widget.name ?? '');
  late final _orgCtrl  = TextEditingController(text: widget.organization ?? '');

  final _curPwCtrl  = TextEditingController();
  final _newPwCtrl  = TextEditingController();
  final _confPwCtrl = TextEditingController();

  bool _savingProfile = false;
  bool _savingPw      = false;
  bool _obscureCur    = true;
  bool _obscureNew    = true;
  bool _obscureConf   = true;

  String? _profileMsg;
  bool    _profileSuccess = false;
  String? _pwMsg;
  bool    _pwSuccess      = false;

  @override
  void didUpdateWidget(WebProfilePage old) {
    super.didUpdateWidget(old);
    if (old.name         != widget.name)         _nameCtrl.text = widget.name         ?? '';
    if (old.organization != widget.organization) _orgCtrl.text  = widget.organization ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _orgCtrl.dispose();
    _curPwCtrl.dispose();
    _newPwCtrl.dispose();
    _confPwCtrl.dispose();
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────────────

  Future<void> _saveProfile() async {
    final name = _nameCtrl.text.trim();
    final org  = _orgCtrl.text.trim();
    if (name.isEmpty) {
      setState(() { _profileMsg = 'Name cannot be empty.'; _profileSuccess = false; });
      return;
    }
    if (widget.orgId == null) return;
    setState(() { _savingProfile = true; _profileMsg = null; });
    try {
      await SupabaseService.client
          .from('organizers')
          .update({'full_name': name, 'organization': org})
          .eq('organizer_id', widget.orgId!);
      widget.onProfileUpdated(name, org.isEmpty ? null : org);
      if (mounted) {
        setState(() {
          _profileMsg     = 'Profile updated successfully.';
          _profileSuccess = true;
          _savingProfile  = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _profileMsg     = e.toString().replaceAll('Exception:', '').trim();
          _profileSuccess = false;
          _savingProfile  = false;
        });
      }
    }
  }

  Future<void> _changePassword() async {
    final cur  = _curPwCtrl.text;
    final nw   = _newPwCtrl.text;
    final conf = _confPwCtrl.text;

    if (cur.isEmpty || nw.isEmpty || conf.isEmpty) {
      setState(() { _pwMsg = 'All password fields are required.'; _pwSuccess = false; });
      return;
    }
    if (nw.length < 6) {
      setState(() { _pwMsg = 'New password must be at least 6 characters.'; _pwSuccess = false; });
      return;
    }
    if (nw != conf) {
      setState(() { _pwMsg = 'Passwords do not match.'; _pwSuccess = false; });
      return;
    }

    setState(() { _savingPw = true; _pwMsg = null; });
    try {
      final email = widget.email ?? SupabaseService.currentUser?.email ?? '';
      await SupabaseService.client.auth
          .signInWithPassword(email: email, password: cur);
      await SupabaseService.client.auth.updateUser(UserAttributes(password: nw));
      _curPwCtrl.clear();
      _newPwCtrl.clear();
      _confPwCtrl.clear();
      if (mounted) {
        setState(() {
          _pwMsg     = 'Password changed successfully.';
          _pwSuccess = true;
          _savingPw  = false;
        });
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _pwMsg     = e.message.contains('Invalid')
              ? 'Current password is incorrect.'
              : e.message;
          _pwSuccess = false;
          _savingPw  = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pwMsg     = e.toString().replaceAll('Exception:', '').trim();
          _pwSuccess = false;
          _savingPw  = false;
        });
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(kWebPad),
      child: LayoutBuilder(builder: (_, c) {
        final wide = c.maxWidth > 700;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPageHeader(),
            const SizedBox(height: 24),
            _buildBanner(),
            const SizedBox(height: 24),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildProfileCard()),
                  const SizedBox(width: 20),
                  Expanded(child: _buildPasswordCard()),
                ],
              )
            else
              Column(children: [
                _buildProfileCard(),
                const SizedBox(height: 20),
                _buildPasswordCard(),
              ]),
          ],
        );
      }),
    );
  }

  // ── Page header ───────────────────────────────────────────────────────────────

  Widget _buildPageHeader() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Profile',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: kText,
            height: 1.1,
          )),
        SizedBox(height: 3),
        Text('Manage your account details and security preferences',
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 12, color: kSubText,
          )),
      ],
    );
  }

  // ── Profile banner ────────────────────────────────────────────────────────────

  Widget _buildBanner() {
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

    return WebCard(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Banner strip ──
          Stack(
            children: [
              Container(
                height: 120,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF1C1814),
                      Color(0xFF2C2016),
                      Color(0xFF3A2F1E),
                    ],
                    begin: Alignment.centerLeft,
                    end:   Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
              ),
              // Decorative circles
              Positioned(
                right: -24, top: -36,
                child: Container(
                  width: 160, height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kGold.withValues(alpha: 0.06),
                  ),
                ),
              ),
              Positioned(
                right: 80, bottom: -30,
                child: Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kGold.withValues(alpha: 0.04),
                  ),
                ),
              ),
              Positioned(
                left: 180, top: -20,
                child: Container(
                  width: 70, height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kGold.withValues(alpha: 0.03),
                  ),
                ),
              ),
              // Watermark
              Positioned(
                right: 24, bottom: 16,
                child: Text('J-Jireh EventHub',
                  style: TextStyle(
                    fontFamily: 'Playball',
                    fontSize: 20,
                    color: kGold.withValues(alpha: 0.40),
                  )),
              ),
            ],
          ),

          // ── Avatar + info row ──
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Avatar overlapping the banner
                Transform.translate(
                  offset: const Offset(0, -30),
                  child: Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      gradient: kGoldGradient,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: kGold.withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(initials,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        )),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Name + meta info
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(name,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: kText,
                            height: 1.1,
                          )),
                        const SizedBox(height: 4),
                        // Email row
                        Row(children: [
                          const Icon(Icons.mail_outline_rounded,
                            size: 12, color: kMuted),
                          const SizedBox(width: 5),
                          Text(email,
                            style: const TextStyle(
                              fontFamily: 'Poppins', fontSize: 12,
                              color: kSubText,
                            )),
                        ]),
                        if (org != null && org.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Row(children: [
                            const Icon(Icons.business_rounded,
                              size: 12, color: kMuted),
                            const SizedBox(width: 5),
                            Text(org,
                              style: const TextStyle(
                                fontFamily: 'Poppins', fontSize: 12,
                                color: kSubText,
                              )),
                          ]),
                        ],
                        const SizedBox(height: 8),
                        // Info chips row
                        Wrap(spacing: 8, runSpacing: 6, children: [
                          _InfoChip(
                            icon:  Icons.badge_rounded,
                            label: orgId,
                            color: kGold,
                          ),
                          const _InfoChip(
                            icon:  Icons.verified_user_rounded,
                            label: 'Active',
                            color: Color(0xFF10B981),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),

                // Organizer role badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        kGold.withValues(alpha: 0.12),
                        kGold.withValues(alpha: 0.06),
                      ],
                      begin: Alignment.topLeft,
                      end:   Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: kGold.withValues(alpha: 0.30)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_rounded, size: 14, color: kGold),
                      SizedBox(width: 6),
                      Text('Organizer',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: kGold,
                        )),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Edit profile card ─────────────────────────────────────────────────────────

  Widget _buildProfileCard() => WebCard(
    padding: const EdgeInsets.all(22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _CardHeader(
          icon:     Icons.person_outline_rounded,
          title:    'Edit Profile',
          subtitle: 'Update your display name and organization',
          color:    kGold,
        ),
        const SizedBox(height: 20),
        const Divider(color: kCardBorder),
        const SizedBox(height: 18),

        // Full Name
        const _FieldLabel('Full Name'),
        const SizedBox(height: 7),
        TextField(
          controller: _nameCtrl,
          style: const TextStyle(
            fontFamily: 'Poppins', fontSize: 13.5, color: kText),
          decoration: webInputDeco('Your full name',
            icon: Icons.person_outline_rounded),
        ),
        const SizedBox(height: 16),

        // Organization
        const _FieldLabel('Organization'),
        const SizedBox(height: 7),
        TextField(
          controller: _orgCtrl,
          style: const TextStyle(
            fontFamily: 'Poppins', fontSize: 13.5, color: kText),
          decoration: webInputDeco('School or organization name',
            icon: Icons.business_rounded),
        ),
        const SizedBox(height: 16),

        // Email — read-only display (no controller, no memory leak)
        const _FieldLabel('Email Address'),
        const SizedBox(height: 7),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F2F5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kCardBorder),
          ),
          child: Row(children: [
            const Icon(Icons.mail_outline_rounded, size: 16, color: kMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(widget.email ?? '—',
                style: const TextStyle(
                  fontFamily: 'Poppins', fontSize: 13.5, color: kMuted,
                )),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.lock_outline_rounded, size: 11, color: kSubText),
                SizedBox(width: 4),
                Text('Locked',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 10,
                    fontWeight: FontWeight.w600, color: kSubText,
                  )),
              ]),
            ),
          ]),
        ),

        if (_profileMsg != null) ...[
          const SizedBox(height: 14),
          _MsgBar(message: _profileMsg!, success: _profileSuccess),
        ],
        const SizedBox(height: 20),

        // Save button
        SizedBox(
          width: double.infinity, height: 46,
          child: ElevatedButton.icon(
            onPressed: _savingProfile ? null : _saveProfile,
            icon: _savingProfile
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.check_rounded, size: 17),
            label: Text(_savingProfile ? 'Saving…' : 'Save Changes',
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
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

  // ── Change password card ──────────────────────────────────────────────────────

  Widget _buildPasswordCard() => WebCard(
    padding: const EdgeInsets.all(22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _CardHeader(
          icon:     Icons.shield_outlined,
          title:    'Change Password',
          subtitle: 'Keep your account secure with a strong password',
          color:    Color(0xFF3B82F6),
        ),
        const SizedBox(height: 20),
        const Divider(color: kCardBorder),
        const SizedBox(height: 18),

        // Current password
        const _FieldLabel('Current Password'),
        const SizedBox(height: 7),
        _PwField(
          controller: _curPwCtrl,
          hint:    '••••••••',
          obscure: _obscureCur,
          onToggle: () => setState(() => _obscureCur = !_obscureCur),
        ),
        const SizedBox(height: 16),

        // New password + strength bar
        const _FieldLabel('New Password'),
        const SizedBox(height: 7),
        _PwField(
          controller: _newPwCtrl,
          hint:    'At least 6 characters',
          obscure: _obscureNew,
          onToggle: () => setState(() => _obscureNew = !_obscureNew),
        ),
        const SizedBox(height: 8),
        _PasswordStrengthBar(controller: _newPwCtrl),
        const SizedBox(height: 16),

        // Confirm password
        const _FieldLabel('Confirm New Password'),
        const SizedBox(height: 7),
        _PwField(
          controller:  _confPwCtrl,
          hint:        'Repeat new password',
          obscure:     _obscureConf,
          onToggle:    () => setState(() => _obscureConf = !_obscureConf),
          onSubmit:    _changePassword,
        ),

        if (_pwMsg != null) ...[
          const SizedBox(height: 14),
          _MsgBar(message: _pwMsg!, success: _pwSuccess),
        ],
        const SizedBox(height: 20),

        // Update button
        SizedBox(
          width: double.infinity, height: 46,
          child: ElevatedButton.icon(
            onPressed: _savingPw ? null : _changePassword,
            icon: _savingPw
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.lock_reset_rounded, size: 17),
            label: Text(_savingPw ? 'Updating…' : 'Update Password',
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w700,
              )),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1C1814),
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                const Color(0xFF1C1814).withValues(alpha: 0.55),
              disabledForegroundColor: Colors.white70,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const _SecurityNote(),
      ],
    ),
  );
}

// ── Info chip (banner) ────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  const _InfoChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
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
    ]),
  );
}

// ── Card section header ───────────────────────────────────────────────────────

class _CardHeader extends StatelessWidget {
  final IconData icon;
  final String   title;
  final String   subtitle;
  final Color    color;
  const _CardHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      width: 42, height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Icon(icon, color: color, size: 20),
    ),
    const SizedBox(width: 12),
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
            style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 15,
              fontWeight: FontWeight.w800, color: kText,
            )),
          const SizedBox(height: 1),
          Text(subtitle,
            style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 11, color: kSubText,
            )),
        ],
      ),
    ),
  ]);
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

// ── Password field ────────────────────────────────────────────────────────────

class _PwField extends StatelessWidget {
  final TextEditingController controller;
  final String       hint;
  final bool         obscure;
  final VoidCallback onToggle;
  final VoidCallback? onSubmit;
  const _PwField({
    required this.controller,
    required this.hint,
    required this.obscure,
    required this.onToggle,
    this.onSubmit,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller:   controller,
    obscureText:  obscure,
    onSubmitted:  onSubmit != null ? (_) => onSubmit!() : null,
    style: const TextStyle(
      fontFamily: 'Poppins', fontSize: 13.5, color: kText),
    decoration: webInputDeco(hint,
      icon: Icons.lock_outline_rounded).copyWith(
      suffixIcon: IconButton(
        icon: Icon(
          obscure
            ? Icons.visibility_outlined
            : Icons.visibility_off_outlined,
          size: 18, color: kMuted,
        ),
        onPressed: onToggle,
      ),
    ),
  );
}

// ── Password strength bar ─────────────────────────────────────────────────────

class _PasswordStrengthBar extends StatelessWidget {
  final TextEditingController controller;
  const _PasswordStrengthBar({required this.controller});

  static int _strength(String v) {
    if (v.isEmpty) return 0;
    if (v.length < 4) return 1;
    if (v.length < 6) return 2;
    if (v.length < 8) return 3;
    return 4;
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: controller,
    builder: (_, val, _) {
      final s = _strength(val.text);
      if (s == 0) return const SizedBox.shrink();

      const colors = [
        Colors.transparent,
        Color(0xFFEF4444), // weak
        Color(0xFFF59E0B), // fair
        Color(0xFF3B82F6), // good
        Color(0xFF10B981), // strong
      ];
      const labels = ['', 'Weak', 'Fair', 'Good', 'Strong'];
      final c = colors[s];

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(4, (i) => Expanded(
              child: Container(
                height: 3,
                margin: EdgeInsets.only(right: i < 3 ? 5 : 0),
                decoration: BoxDecoration(
                  color: i < s ? c : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            )),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(labels[s],
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 10.5,
                  fontWeight: FontWeight.w600, color: c,
                )),
            ],
          ),
        ],
      );
    },
  );
}

// ── Feedback message bar ──────────────────────────────────────────────────────

class _MsgBar extends StatelessWidget {
  final String message;
  final bool   success;
  const _MsgBar({required this.message, required this.success});

  @override
  Widget build(BuildContext context) {
    final color  = success ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final bg     = success ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2);
    final border = success ? const Color(0xFFA7F3D0) : const Color(0xFFFCA5A5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(children: [
        Icon(
          success
            ? Icons.check_circle_outline_rounded
            : Icons.error_outline_rounded,
          size: 15, color: color,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message,
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 12,
              color: color, height: 1.4,
            )),
        ),
      ]),
    );
  }
}

// ── Security note ─────────────────────────────────────────────────────────────

class _SecurityNote extends StatelessWidget {
  const _SecurityNote();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    decoration: BoxDecoration(
      color: const Color(0xFFF0F4FF),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFBFD0F5)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, size: 14, color: Color(0xFF3B82F6)),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Your password is encrypted and never stored in plain text. '
            'Use at least 8 characters with a mix of letters and numbers for best security.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              color: Color(0xFF1D4ED8),
              height: 1.5,
            )),
        ),
      ],
    ),
  );
}

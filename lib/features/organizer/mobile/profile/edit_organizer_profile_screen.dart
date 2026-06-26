import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:eventhub/core/services/supabase_service.dart';
import '../../../../core/app_colors.dart';

class EditOrganizerProfileScreen extends StatefulWidget {
  final String? fullName;
  final String? email;
  final String? username;
  final String? organization;

  const EditOrganizerProfileScreen({
    super.key,
    this.fullName,
    this.email,
    this.username,
    this.organization,
  });

  @override
  State<EditOrganizerProfileScreen> createState() =>
      _EditOrganizerProfileScreenState();
}

class _EditOrganizerProfileScreenState
    extends State<EditOrganizerProfileScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _orgCtrl;

  bool _saving     = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.fullName    ?? '');
    _orgCtrl  = TextEditingController(text: widget.organization ?? '');
    _nameCtrl.addListener(_onFieldChanged);
    _orgCtrl.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _orgCtrl.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    final changed = _nameCtrl.text != (widget.fullName    ?? '') ||
                    _orgCtrl.text  != (widget.organization ?? '');
    if (changed != _hasChanges) setState(() => _hasChanges = changed);
  }

  String _initials(String name) {
    final t = name.trim();
    if (t.isEmpty) return 'O';
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
        title: const Text(
          'Discard changes?',
          style: TextStyle(
            fontFamily: 'Poppins', fontWeight: FontWeight.w700,
            fontSize: 17, color: kText,
          ),
        ),
        content: const Text(
          'You have unsaved changes. Are you sure you want to leave?',
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 13,
            color: kSubText, height: 1.55,
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: OutlinedButton.styleFrom(
              foregroundColor: kGold,
              side: const BorderSide(color: kGold),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text(
              'Keep Editing',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade50,
              foregroundColor: Colors.red.shade700,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text(
              'Discard',
              style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 13),
            ),
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
      final user = SupabaseService.currentUser;
      if (user == null) throw Exception('Not authenticated');
      await SupabaseService.client
          .from('organizers')
          .update({
            'full_name':    _nameCtrl.text.trim(),
            'organization': _orgCtrl.text.trim(),
          })
          .eq('user_id', user.id);
      if (!mounted) return;
      _snack('Profile updated!', isError: false);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _snack('Update failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(
            isError ? Icons.error_rounded : Icons.check_circle_rounded,
            color: Colors.white, size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(msg, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
          ),
        ]),
        backgroundColor: isError ? Colors.red.shade600 : const Color(0xFF16A34A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasChanges && !_saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final ok  = await _confirmDiscard();
        if (ok && mounted) nav.pop();
      },
      child: Scaffold(
        backgroundColor: kBackgroundAlt,
        body: SingleChildScrollView(
          child: Column(children: [
            _buildHero(),
            _buildBody(),
          ]),
        ),
        bottomNavigationBar: _buildSaveBar(),
      ),
    );
  }

  // ── Hero ──────────────────────────────────────────────────────────────────

  Widget _buildHero() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1C1814), Color(0xFF2D2318), Color(0xFF3A2F1E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Decorative circles
          Positioned(top: -30, right: -20,
              child: _decCircle(160, Colors.white.withValues(alpha: 0.04))),
          Positioned(bottom: 10, left: -40,
              child: _decCircle(110, Colors.white.withValues(alpha: 0.03))),
          Positioned(top: 50, left: 60,
              child: _decCircle(60, kGold.withValues(alpha: 0.07))),

          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 68),
              child: Column(children: [
                // Back button + unsaved badge
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
                const Text(
                  'Edit Profile',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white, height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Update your organizer information',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 12, color: Colors.white60,
                  ),
                ),
              ]),
            ),
          ),

          // Avatar — overlaps the bottom of the hero
          Positioned(
            bottom: -48, left: 0, right: 0,
            child: Center(
              child: ListenableBuilder(
                listenable: _nameCtrl,
                builder: (_, child) => _avatarCircle(_initials(_nameCtrl.text)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarCircle(String initials) {
    return Container(
      width: 96, height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: kGoldGradient,
        border: Border.all(color: Colors.white, width: 3.5),
        boxShadow: [
          BoxShadow(
            color: kGold.withValues(alpha: 0.45),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            fontFamily: 'Poppins', fontSize: 34,
            fontWeight: FontWeight.w800, color: Colors.white,
          ),
        ),
      ),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────────

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 64, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Personal Info ────────────────────────────────────────────────
          _sectionLabel('Personal Info', Icons.person_rounded, kGold),
          const SizedBox(height: 10),
          _formCard(children: [
            _editField(
              ctrl:      _nameCtrl,
              label:     'Full Name',
              hint:      'e.g. Juan dela Cruz',
              icon:      Icons.badge_outlined,
              maxLength: 60,
              isFirst:   true,
              isLast:    true,
            ),
          ]),

          const SizedBox(height: 20),

          // ── Organization ─────────────────────────────────────────────────
          _sectionLabel('Organization', Icons.business_rounded, const Color(0xFF2563EB)),
          const SizedBox(height: 10),
          _formCard(children: [
            _editField(
              ctrl:      _orgCtrl,
              label:     'Organization Name',
              hint:      'e.g. J-Jireh Student Council',
              icon:      Icons.corporate_fare_rounded,
              maxLength: 80,
              isFirst:   true,
              isLast:    true,
            ),
          ]),

          const SizedBox(height: 20),

          // ── Locked Account Fields ────────────────────────────────────────
          _sectionLabel('Account', Icons.lock_rounded, kMuted),
          const SizedBox(height: 10),
          _formCard(children: [
            _lockedField(
              label:   'Email Address',
              value:   widget.email ?? '—',
              icon:    Icons.email_outlined,
              note:    'Contact support to update',
              isFirst: true,
              isLast:  true,
            ),
          ]),

          const SizedBox(height: 10),
          _infoNote(
            'Some fields are managed by your administrator and cannot be edited here.',
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Save bar ──────────────────────────────────────────────────────────────

  Widget _buildSaveBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.97, end: 1.0).animate(anim),
              child: child,
            ),
          ),
          child: _hasChanges
              ? _saveBtn(key: const ValueKey('save'))
              : _noChangeBtn(key: const ValueKey('noop')),
        ),
      ),
    );
  }

  Widget _saveBtn({Key? key}) {
    return DecoratedBox(
      key: key,
      decoration: BoxDecoration(
        gradient: kGoldGradient,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: kGold.withValues(alpha: 0.40),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.0),
                )
              : const Icon(Icons.check_rounded, size: 20),
          label: Text(
            _saving ? 'Saving…' : 'Save Changes',
            style: const TextStyle(
              fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor:  Colors.transparent,
            foregroundColor:  Colors.white,
            elevation:        0,
            shadowColor:      Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
    );
  }

  Widget _noChangeBtn({Key? key}) {
    return SizedBox(
      key: key,
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back_rounded, size: 18),
        label: const Text(
          'Go Back',
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: kSubText,
          side: BorderSide(color: Colors.grey.shade300),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  // ── Field widgets ─────────────────────────────────────────────────────────

  Widget _editField({
    required TextEditingController ctrl,
    required String label,
    required String hint,
    required IconData icon,
    int?     maxLength,
    String?  helperText,
    TextInputType keyboard = TextInputType.text,
    bool isFirst = false,
    bool isLast  = false,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(14, isFirst ? 14 : 6, 14, isLast ? 14 : 6),
      child: TextFormField(
        controller:   ctrl,
        keyboardType: keyboard,
        maxLength:    maxLength,
        style: const TextStyle(
          fontFamily: 'Poppins', fontSize: 14,
          color: kText, fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          labelText:   label,
          hintText:    hint,
          labelStyle:  const TextStyle(fontFamily: 'Poppins', fontSize: 13, color: kSubText),
          hintStyle:   TextStyle(fontFamily: 'Poppins', fontSize: 13, color: Colors.grey.shade400),
          helperText:  helperText,
          helperStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 10, color: kMuted),
          prefixIcon:  Icon(icon, color: kGold, size: 20),
          counterStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 10, color: kMuted),
          filled:       true,
          fillColor:    const Color(0xFFFFFBF0),
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
    required String label,
    required String value,
    required IconData icon,
    String? note,
    bool isFirst = false,
    bool isLast  = false,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(14, isFirst ? 14 : 6, 14, isLast ? 14 : 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 13, 12, 13),
        decoration: BoxDecoration(
          color:        Colors.grey.shade50,
          borderRadius: BorderRadius.circular(13),
          border:       Border.all(color: Colors.grey.shade200, width: 1.2),
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color:        Colors.grey.shade100,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: kMuted, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: kMuted)),
                const SizedBox(height: 3),
                Text(value, style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w500, color: kSubText)),
                if (note != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    note,
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 10,
                      color: Colors.grey.shade400, fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.lock_rounded, size: 15, color: Colors.grey.shade300),
        ]),
      ),
    );
  }

  // ── Layout helpers ─────────────────────────────────────────────────────────

  Widget _formCard({required List<Widget> children}) => Container(
    decoration: BoxDecoration(
      color:        Colors.white,
      borderRadius: BorderRadius.circular(18),
      border:       Border.all(color: Colors.grey.withValues(alpha: 0.10)),
      boxShadow: [
        BoxShadow(
          color:     Colors.black.withValues(alpha: 0.05),
          blurRadius: 12,
          offset:    const Offset(0, 4),
        ),
      ],
    ),
    child: Column(children: children),
  );

  Widget _sectionLabel(String title, IconData icon, Color color) {
    return Row(children: [
      Container(
        width: 26, height: 26,
        decoration: BoxDecoration(
          color:        color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Icon(icon, size: 13, color: color),
      ),
      const SizedBox(width: 8),
      Text(
        title.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Poppins', fontSize: 10,
          fontWeight: FontWeight.w700, letterSpacing: 1.0, color: color,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(child: Divider(height: 1, color: color.withValues(alpha: 0.15))),
    ]);
  }

  Widget _backBtn() {
    return GestureDetector(
      onTap: () async {
        final nav = Navigator.of(context);
        final ok  = await _confirmDiscard();
        if (ok && mounted) nav.pop();
      },
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color:  Colors.white.withValues(alpha: 0.12),
          shape:  BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: const Icon(
          Icons.arrow_back_ios_new_rounded, size: 16, color: Colors.white,
        ),
      ),
    );
  }

  Widget _unsavedBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color:        kGold.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(20),
      border:       Border.all(color: kGold.withValues(alpha: 0.4)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: const [
      Icon(Icons.edit_rounded, size: 10, color: kGold),
      SizedBox(width: 5),
      Text(
        'Unsaved changes',
        style: TextStyle(
          fontFamily: 'Poppins', fontSize: 10,
          fontWeight: FontWeight.w600, color: kGold,
        ),
      ),
    ]),
  );

  Widget _infoNote(String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(Icons.info_outline_rounded, size: 12, color: kMuted.withValues(alpha: 0.7)),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 10,
            color: kMuted.withValues(alpha: 0.8), height: 1.5,
          ),
        ),
      ),
    ],
  );

  Widget _decCircle(double size, Color color) => Container(
    width: size, height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

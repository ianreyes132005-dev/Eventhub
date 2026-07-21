import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/audit_service.dart';
import '../../core/services/rate_limit_service.dart';
import '../../shared/widgets/gradient_button.dart';
import '../../shared/widgets/app_alert.dart';
import '../organizer/mobile/dashboard/organizer_dashboard.dart';
import '../student/dashboard/student_dashboard.dart';
import '../../core/app_colors.dart';
import '../../core/theme_store.dart';

// ── Enums ──────────────────────────────────────────────────────────────────────
enum _LegalType  { terms, privacy }
enum _LoginMode  { student, organizer }

// ── Auth screen ────────────────────────────────────────────────────────────────
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _loginFormKey = GlobalKey<FormState>();
  bool       _loginLoading         = false;
  bool       _loginShowPassword    = false;
  bool       _rememberMe           = false;
  bool       _isLoadingCredentials = true;
  _LoginMode _mode                 = _LoginMode.student;

  // ── Rate limiting ──────────────────────────────────────────────────────────
  int       _failedAttempts = 0;
  DateTime? _lockedUntil;
  Timer?    _lockTimer;

  static const String _kAttemptKey = 'rl_login_attempts';
  static const String _kLockedKey  = 'rl_login_locked_until';

  bool get _isLocked =>
      _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);

  String get _lockMessage {
    if (!_isLocked) return '';
    final rem = _lockedUntil!.difference(DateTime.now());
    if (rem.inMinutes >= 1) {
      final m = rem.inMinutes;
      final s = (rem.inSeconds % 60).toString().padLeft(2, '0');
      return 'Try again in ${m}m ${s}s';
    }
    return 'Try again in ${rem.inSeconds}s';
  }

  static const _storage = FlutterSecureStorage();

  static const String _kLrnPrefix   = '12345626';
  static const String _kEmailDomain = '@gmail.com';

  late final TextEditingController _emailCtrl;
  late final TextEditingController _lrnCtrl;
  late final TextEditingController _passwordCtrl;
  late final TapGestureRecognizer  _termsTap;
  late final TapGestureRecognizer  _privacyTap;

  // ── Colors ────────────────────────────────────────────────────────────────────
  static const _kGoldLight = Color(0xFFFEF9E7);
  static const _kBlue      = Color(0xFF0EA5E9);   // sky-500 — student accent
  static const _kBlueLight = Color(0xFFE0F2FE);   // sky-100 — student bg tint

  @override
  void initState() {
    super.initState();
    _emailCtrl    = TextEditingController();
    _lrnCtrl      = TextEditingController();
    _passwordCtrl = TextEditingController();
    _termsTap     = TapGestureRecognizer()
      ..onTap = () => _showLegalSheet(_LegalType.terms);
    _privacyTap   = TapGestureRecognizer()
      ..onTap = () => _showLegalSheet(_LegalType.privacy);
    _loadSavedCredential();
    _loadRateLimitState();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _lrnCtrl.dispose();
    _passwordCtrl.dispose();
    _termsTap.dispose();
    _privacyTap.dispose();
    _lockTimer?.cancel();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  bool get _isOrganizer => _mode == _LoginMode.organizer;

  void _switchMode() {
    setState(() {
      _mode = _isOrganizer ? _LoginMode.student : _LoginMode.organizer;
      _emailCtrl.clear();
      _lrnCtrl.clear();
      _passwordCtrl.clear();
      _loginShowPassword = false;
      _loginFormKey.currentState?.reset();
    });
  }

  void _showLegalSheet(_LegalType type) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LegalSheet(type: type),
    );
  }

  // ── Credential persistence ─────────────────────────────────────────────────────

  Future<void> _loadSavedCredential() async {
    try {
      final remember = await _storage.read(key: 'remember_me') == 'true';
      if (!remember) return;

      final savedMode  = await _storage.read(key: 'saved_mode');
      final savedLrn   = await _storage.read(key: 'saved_lrn');
      final savedEmail = await _storage.read(key: 'saved_email');

      if (!mounted) return;
      setState(() {
        _rememberMe = true;
        if (savedMode == 'organizer') {
          _mode = _LoginMode.organizer;
          if (savedEmail != null) _emailCtrl.text = savedEmail;
        } else {
          _mode = _LoginMode.student;
          if (savedLrn != null) _lrnCtrl.text = savedLrn;
        }
      });
    } catch (e) {
      debugPrint('Error loading saved credential: $e');
    } finally {
      if (mounted) setState(() => _isLoadingCredentials = false);
    }
  }

  Future<void> _saveCredential() async {
    if (!_rememberMe) {
      await _clearSavedCredential();
      return;
    }
    try {
      await _storage.write(key: 'remember_me', value: 'true');
      await _storage.write(
          key: 'saved_mode', value: _isOrganizer ? 'organizer' : 'student');
      if (_isOrganizer) {
        await _storage.write(
            key: 'saved_email',
            value: _emailCtrl.text.trim().toLowerCase());
      } else {
        await _storage.write(
            key: 'saved_lrn',
            value: _lrnCtrl.text.trim());
      }
    } catch (e) {
      debugPrint('Error saving credential: $e');
    }
  }

  Future<void> _clearSavedCredential() async {
    try {
      await _storage.delete(key: 'remember_me');
      await _storage.delete(key: 'saved_mode');
      await _storage.delete(key: 'saved_lrn');
      await _storage.delete(key: 'saved_email');
    } catch (e) {
      debugPrint('Error clearing credential: $e');
    }
  }

  // ── Rate limit methods ─────────────────────────────────────────────────────

  Future<void> _loadRateLimitState() async {
    try {
      final prefs      = await SharedPreferences.getInstance();
      final attempts   = prefs.getInt(_kAttemptKey) ?? 0;
      final lockedMs   = prefs.getInt(_kLockedKey)  ?? 0;
      final locked     = lockedMs > 0
          ? DateTime.fromMillisecondsSinceEpoch(lockedMs)
          : null;
      if (!mounted) return;
      final stillLocked = locked != null && locked.isAfter(DateTime.now());
      setState(() {
        _failedAttempts = stillLocked ? attempts : 0;
        _lockedUntil    = stillLocked ? locked : null;
      });
      if (stillLocked) {
        _startLockTimer();
      } else if (attempts > 0) {
        prefs.setInt(_kAttemptKey, 0);
        prefs.remove(_kLockedKey);
      }
    } catch (_) {}
  }

  Future<void> _recordFailure() async {
    _failedAttempts++;
    final lockDur = _failedAttempts >= 5
        ? const Duration(seconds: 30)
        : Duration.zero;
    _lockedUntil = lockDur > Duration.zero
        ? DateTime.now().add(lockDur)
        : null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kAttemptKey, _failedAttempts);
      await prefs.setInt(_kLockedKey,  _lockedUntil?.millisecondsSinceEpoch ?? 0);
    } catch (_) {}
    if (_lockedUntil != null) _startLockTimer();
    if (mounted) setState(() {});
  }

  Future<void> _clearRateLimit() async {
    _failedAttempts = 0;
    _lockedUntil    = null;
    _lockTimer?.cancel();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kAttemptKey);
      await prefs.remove(_kLockedKey);
    } catch (_) {}
  }

  void _startLockTimer() {
    _lockTimer?.cancel();
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) { _lockTimer?.cancel(); return; }
      if (!_isLocked) {
        _lockTimer?.cancel();
        _failedAttempts = 0;
        SharedPreferences.getInstance().then((prefs) {
          prefs.setInt(_kAttemptKey, 0);
          prefs.remove(_kLockedKey);
        }).catchError((_) {});
      }
      setState(() {});
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Brief wait while secure storage is read on first launch
    if (_isLoadingCredentials) {
      return const Scaffold(
        backgroundColor: Color(0xFF1C1814),
        body: Center(
          child: CircularProgressIndicator(
            color: kGold,
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    return Scaffold(
      // Dark warm background — only visible in the hero area
      backgroundColor: const Color(0xFF1C1814),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Hero: brand identity on dark background ───────────────────────
          _buildHero(),

          // ── Form sheet: white panel slides up with rounded top corners ────
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
              ),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  28, 32, 28,
                  MediaQuery.of(context).padding.bottom + 28,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Greeting — restyled as the form-sheet heading
                    const Text(
                      'Welcome back',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A1A),
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 26),
                    _buildModeToggle(),
                    const SizedBox(height: 26),
                    Form(key: _loginFormKey, child: _buildLoginForm()),
                    const SizedBox(height: 28),
                    _buildFooterText(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Hero sits on the dark background and contains only brand identity
  Widget _buildHero() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
        child: _buildLogo(),
      ),
    );
  }

  // ── Logo ──────────────────────────────────────────────────────────────────────

  Widget _buildLogo() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Circular logo image with gold ring + glow
        Container(
          width: 60, height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: kGold.withValues(alpha: 0.55),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: kGold.withValues(alpha: 0.22),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: Image.asset(
              'assets/logo.jpg',
              width: 60, height: 60,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 60, height: 60,
                decoration: const BoxDecoration(
                  color: Color(0xFF2C2520),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.image_outlined,
                    color: Colors.white38, size: 26),
              ),
            ),
          ),
        ),
        const SizedBox(width: 18),
        // Brand name — gold + white on dark background
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text(
              'J-Jireh',
              style: TextStyle(
                fontFamily: 'Playball',
                fontSize: 30,
                color: kGold,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                height: 1.1,
              ),
            ),
            Text(
              'EventHub',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: Colors.white54,
                letterSpacing: 3.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Mode toggle ───────────────────────────────────────────────────────────────

  Widget _buildModeToggle() {
    final accent = _isOrganizer ? kGold : _kBlue;
    final bg     = _isOrganizer ? _kGoldLight : _kBlueLight;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accent.withValues(alpha: 0.45),
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: _switchMode,
          borderRadius: BorderRadius.circular(16),
          splashColor: accent.withValues(alpha: 0.08),
          highlightColor: accent.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                // Role icon
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    key: ValueKey(_isOrganizer),
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _isOrganizer
                          ? Icons.badge_rounded
                          : Icons.school_rounded,
                      size: 19,
                      color: accent,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Label
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.15),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: Column(
                      key: ValueKey(_isOrganizer),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isOrganizer ? 'Organizer Login' : 'Student Login',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isOrganizer
                              ? 'For event coordinators'
                              : 'For students & attendees',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: accent.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Switch button
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.swap_horiz_rounded,
                    size: 18,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Login form ────────────────────────────────────────────────────────────────

  Widget _buildLoginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Animates between student and organizer email fields
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.08),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
              child: child,
            ),
          ),
          child: _isOrganizer ? _buildEmailField() : _buildLrnField(),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: ValueKey('password-${_mode.name}'),
          controller: _passwordCtrl,
          obscureText: !_loginShowPassword,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _loginLoading ? null : _handleLogin(),
          decoration: _fieldDecoration(
            hint: 'Password',
            icon: Icons.lock_outline,
            suffix: IconButton(
              icon: Icon(
                _loginShowPassword ? Icons.visibility : Icons.visibility_off,
                color: Colors.grey[500],
                size: 21,
              ),
              onPressed: () =>
                  setState(() => _loginShowPassword = !_loginShowPassword),
            ),
          ),
          validator: (value) {
            final pass = value ?? '';
            if (pass.isEmpty) return 'Password is required';
            if (pass.length < 6) return 'Password must be at least 6 characters';
            return null;
          },
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Remember me checkbox
            GestureDetector(
              onTap: () => setState(() => _rememberMe = !_rememberMe),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 20, height: 20,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _rememberMe ? kGold : Colors.grey[300]!,
                        width: _rememberMe ? 2.0 : 1.2,
                      ),
                      color: _rememberMe ? kGold : Colors.transparent,
                    ),
                    child: _rememberMe
                        ? const Icon(Icons.check, size: 13, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Remember me',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // ── Warning banner (visible at ≥3 failures, while not locked) ────────
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, anim) => SizeTransition(
            sizeFactor: anim,
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: (_failedAttempts >= 3 && !_isLocked)
              ? Container(
                  key: const ValueKey('warn'),
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Color(0xFFD97706), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${5 - _failedAttempts} more failed attempt${5 - _failedAttempts == 1 ? '' : 's'} will trigger a 30-second lockout.',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF92400E),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('no-warn')),
        ),
        // ── Login button / lockout countdown ─────────────────────────────────
        _isLocked
            ? Container(
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.grey.shade400,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _lockMessage,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              )
            : GradientButton(
                _isOrganizer ? 'Log In as Organizer' : 'Log In as Student',
                isLoading: _loginLoading,
                onPressed: _loginLoading ? null : _handleLogin,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFC49230),
                    Color(0xFFD6A742),
                    Color(0xFFEAB866),
                  ],
                ),
                glowColor: const Color(0xFFD6A742),
              ),
      ],
    );
  }

  // Organizer: username-only field (app appends @gmail.com before sign-in)
  Widget _buildEmailField() {
    return TextFormField(
      key: const ValueKey('email-field'),
      controller: _emailCtrl,
      keyboardType: TextInputType.text,
      textCapitalization: TextCapitalization.none,
      textInputAction: TextInputAction.next,
      decoration: _fieldDecoration(
        hint: 'Username',
        icon: Icons.person_outline_rounded,
      ),
      validator: (value) {
        final username = value?.trim() ?? '';
        if (username.isEmpty) return 'Username is required';
        if (username.length < 3) return 'Username must be at least 3 characters';
        if (username.contains('@') || username.contains(' ')) {
          return 'Enter your username only, without @gmail.com';
        }
        return null;
      },
    );
  }

  Widget _buildLrnField() {
    return TextFormField(
      key: const ValueKey('lrn-field'),
      controller: _lrnCtrl,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: _fieldDecoration(
        hint: 'LRN (last 4 digits)',
        icon: Icons.school_rounded,
      ),
      validator: (value) {
        final lrn = value?.trim() ?? '';
        if (lrn.isEmpty) return 'LRN is required';
        if (lrn.length != 4) return 'Please enter the last 4 digits of your LRN';
        return null;
      },
    );
  }

  // ── Login handler ─────────────────────────────────────────────────────────────

  Future<void> _handleLogin() async {
    if (_isLocked) return;
    if (!_loginFormKey.currentState!.validate()) return;
    final email = _isOrganizer
        ? '${_emailCtrl.text.trim().toLowerCase()}@gmail.com'
        : '$_kLrnPrefix${_lrnCtrl.text.trim()}$_kEmailDomain';
    final pass  = _passwordCtrl.text;
    setState(() => _loginLoading = true);
    // Block setupAuthStateListener from racing us to the navigator.
    SupabaseService.handlingAppLogin = true;
    try {
      // S-01: server-side rate limit check — enforced across all devices/sessions.
      final rlStatus = await RateLimitService.check(email);
      if (!rlStatus.allowed) {
        if (mounted) setState(() => _lockedUntil = rlStatus.lockedUntil);
        if (rlStatus.lockedUntil != null) _startLockTimer();
        return;
      }

      final response = await Supabase.instance.client.auth
          .signInWithPassword(email: email, password: pass);
      final user = response.user;
      if (user == null) return;

      // ── Admin check — blocked on mobile ──────────────────────────────────
      final adminData = await SupabaseService.client
          .from('admins')
          .select('admin_id')
          .eq('user_id', user.id)
          .maybeSingle();

      if (adminData != null) {
        await Supabase.instance.client.auth.signOut();
        if (mounted) {
          setState(() => _loginLoading = false);
          AppAlert.warning(
            context,
            title: 'Web Portal Only',
            message: 'Admin accounts can only be accessed through the EventHub web portal. '
                'Please use a browser to log in.',
            buttonText: 'Got it',
          );
        }
        return;
      }

      final organizerData = await SupabaseService.client
          .from('organizers')
          .select('organizer_id, full_name')
          .eq('user_id', user.id)
          .maybeSingle();

      final isOrganizer = organizerData != null;

      // ── Role gate ───────────────────────────────────────────────────────────
      if (_mode == _LoginMode.student && isOrganizer) {
        // Organizer account tried in student portal â†’ sign out + warn
        await Supabase.instance.client.auth.signOut();
        if (mounted) {
          setState(() => _loginLoading = false);
          AppAlert.warning(
            context,
            title: 'Organizer Account Detected',
            message: 'This account is registered as an Organizer.\n'
                'Tap the toggle above to switch to Organizer Login.',
            buttonText: 'Got it',
            onDismiss: _switchMode,
          );
        }
        return;
      }

      if (_mode == _LoginMode.organizer && !isOrganizer) {
        // Student account tried in organizer portal â†’ sign out + warn
        await Supabase.instance.client.auth.signOut();
        if (mounted) {
          setState(() => _loginLoading = false);
          AppAlert.warning(
            context,
            title: 'Student Account Detected',
            message: 'No organizer account found for these credentials.\n'
                'Tap the toggle above to switch to Student Login.',
            buttonText: 'Got it',
            onDismiss: _switchMode,
          );
        }
        return;
      }

      // ── Persist credential if Remember Me is on ────────────────────────────
      await _clearRateLimit();
      unawaited(RateLimitService.clear(email));
      await _saveCredential();

      // ── Audit log ───────────────────────────────────────────────────────────
      if (isOrganizer) {
        AuditService.logLogin(
          userId: user.id, role: 'organizer',
          fullName:   organizerData!['full_name'] as String?,
          identifier: (organizerData['organizer_id'] as String? ?? '').toLowerCase(),
        );
      } else {
        AuditService.logLogin(
          userId: user.id, role: 'student',
          identifier: _lrnCtrl.text.trim(),
        );
      }

      // ── Load per-user theme before navigating ───────────────────────────────
      await ThemeStore.loadForUser(
          user.id, isOrganizer ? 'organizer' : 'student');

      // ── Route correctly ─────────────────────────────────────────────────────
      if (mounted) {
        Navigator.of(context).pushReplacement(
          _dashRoute(isOrganizer
              ? const OrganizerDashboardScreen()
              : const StudentDashboard()),
        );
      }
    } catch (e, stack) {
      debugPrint('Login failed: $e\n$stack');
      await _recordFailure();
      unawaited(RateLimitService.recordFailure(email));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Login failed: ${_extractSupabaseError(e)}',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
            ),
            backgroundColor: Colors.red[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          ),
        );
      }
    } finally {
      SupabaseService.handlingAppLogin = false;
      if (mounted) setState(() => _loginLoading = false);
    }
  }

  // ── Field decoration ──────────────────────────────────────────────────────────

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: Colors.grey[400],
        fontSize: 15,
        fontWeight: FontWeight.w400,
      ),
      prefixIcon: Icon(icon, color: Colors.grey[500], size: 22),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding:
          const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey[200]!, width: 1.2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey[200]!, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: kGold, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.red[300]!, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.red[400]!, width: 1.8),
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────────

  Widget _buildFooterText() {
    return Text.rich(
      TextSpan(
        style: const TextStyle(
            fontFamily: 'Poppins', fontSize: 12, height: 1.65),
        children: [
          TextSpan(
            text: 'By signing in, you agree to our ',
            style: TextStyle(
                color: Colors.grey[600], fontWeight: FontWeight.w400),
          ),
          TextSpan(
            text: 'Terms and Conditions',
            recognizer: _termsTap,
            style: const TextStyle(
              color: kGold,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
              decorationColor: kGold,
            ),
          ),
          TextSpan(
            text: ' and ',
            style: TextStyle(
                color: Colors.grey[600], fontWeight: FontWeight.w400),
          ),
          TextSpan(
            text: 'Privacy Policy',
            recognizer: _privacyTap,
            style: const TextStyle(
              color: kGold,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
              decorationColor: kGold,
            ),
          ),
          TextSpan(
            text: '.',
            style: TextStyle(
                color: Colors.grey[600], fontWeight: FontWeight.w400),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  String _extractSupabaseError(Object e) {
    if (e is AuthException) return e.message;
    if (e is PostgrestException) {
      if (e.message.isNotEmpty) return e.message;
      return e.details ?? e.hint ?? 'Supabase error';
    }
    final text = e.toString();
    return text.isEmpty ? 'Unknown error' : text;
  }

  Route<void> _dashRoute(Widget screen) => PageRouteBuilder<void>(
    transitionDuration:        const Duration(milliseconds: 500),
    reverseTransitionDuration: const Duration(milliseconds: 350),
    pageBuilder:        (ctx, a, b) => screen,
    transitionsBuilder: (ctx, anim, b, child) {
      final fade  = CurvedAnimation(parent: anim, curve: Curves.easeOut);
      final slide = Tween<Offset>(
        begin: const Offset(0, 0.022),
        end:   Offset.zero,
      ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
      return FadeTransition(
        opacity: fade,
        child: SlideTransition(position: slide, child: child),
      );
    },
  );
}

// ── Legal bottom sheet ─────────────────────────────────────────────────────────

class _LegalSheet extends StatelessWidget {
  const _LegalSheet({required this.type});

  final _LegalType type;

  bool get _isTerms => type == _LegalType.terms;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 20, 16),
              child: Row(
                children: [
                  Container(
                    width: 50, height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF9E7),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: kGold.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Icon(
                      _isTerms
                          ? Icons.gavel_rounded
                          : Icons.privacy_tip_outlined,
                      color: kGold,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isTerms ? 'Terms and Conditions' : 'Privacy Policy',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        Text(
                          'Last updated: June 2026',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Material(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () => Navigator.pop(ctx),
                      borderRadius: BorderRadius.circular(10),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.close_rounded,
                            size: 18, color: Colors.black54),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: Colors.grey.shade100, height: 1),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                children: _isTerms ? _termsContent() : _privacyContent(),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                24, 12, 24, MediaQuery.of(ctx).padding.bottom + 20,
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kGold,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'Got it',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _termsContent() => [
        _section(Icons.handshake_outlined, 'Acceptance of Terms',
            'By accessing or using the J-Jireh EventHub application, you agree to be bound by these Terms and Conditions. If you do not agree to these terms, please do not use the application.'),
        _section(Icons.school_outlined, 'Eligibility',
            'EventHub is intended exclusively for currently enrolled students and authorized school personnel of J-Jireh. Access is granted only through school-provisioned accounts.'),
        _section(Icons.manage_accounts_outlined, 'Account Responsibility',
            'Your account credentials are personal and confidential. You are responsible for all activity that occurs under your account. Do not share your login credentials with others. If you believe your account has been compromised, contact your school administrator immediately.'),
        _section(Icons.check_circle_outline_rounded, 'Permitted Use',
            'You may use EventHub solely for legitimate school event registration, attendance, and communication purposes — including browsing events, registering for activities, viewing QR tickets, and receiving school announcements.'),
        _section(Icons.block_outlined, 'Prohibited Conduct',
            '• Accessing accounts that do not belong to you\n'
                '• Using the app for commercial or non-school purposes\n'
                '• Sharing or tampering with event QR codes\n'
                '• Uploading inappropriate or misleading selfie photos\n'
                '• Circumventing the check-in verification system'),
        _section(Icons.camera_alt_outlined, 'Check-In Media',
            'Selfie photos submitted during check-in are used solely for identity verification. They are stored securely and accessible only to authorized event organizers within the school.'),
        _section(Icons.shield_outlined, 'Limitation of Liability',
            'EventHub is provided "as is" without warranties of any kind. The school shall not be liable for damages arising from your use of or inability to use the application.'),
        _section(Icons.edit_note_outlined, 'Amendments',
            'These Terms and Conditions may be updated from time to time. Continued use of the application after changes are posted constitutes acceptance of the revised terms.'),
        _section(Icons.mail_outline_rounded, 'Contact Us',
            'For questions about these Terms and Conditions, please contact your school administrator or the EventHub support team.',
            isLast: true),
      ];

  List<Widget> _privacyContent() => [
        _section(Icons.info_outline_rounded, 'Information We Collect',
            'We collect the following personal data to operate EventHub:\n\n'
                '• Identity: full name, email address\n'
                '• Student: Learner Reference Number (LRN), grade level\n'
                '• Events: registrations, attendance records, timestamps\n'
                '• Media: selfie photos submitted during event check-in\n'
                '• Usage: AI chat session activity logs'),
        _section(Icons.settings_suggest_outlined, 'How We Use Your Information',
            'Your information is used to:\n\n'
                '• Authenticate your identity and grant app access\n'
                '• Process event registrations and generate QR tickets\n'
                '• Facilitate the selfie check-in verification process\n'
                '• Deliver school announcements and event updates\n'
                '• Power personalized AI assistant responses\n'
                '• Generate attendance analytics for organizers'),
        _section(Icons.cloud_outlined, 'Data Storage & Security',
            'All data is stored on secure cloud infrastructure provided by Supabase. We implement industry-standard security measures including encrypted connections (TLS) and role-based access controls to protect your personal information.'),
        _section(Icons.face_outlined, 'Selfie and Photo Data',
            'Selfie photos captured during event check-in are stored in a private, access-controlled storage bucket. These images are:\n\n'
                '• Used exclusively for attendance verification\n'
                '• Visible only to authorized event organizers\n'
                '• Never shared with third parties\n'
                '• Retained only as long as operationally necessary'),
        _section(Icons.people_outline_rounded, 'Information Sharing',
            'We do not sell, trade, or transfer your personal information to third parties. Your data may be shared with school administrators and authorized organizers only as needed to operate school events.'),
        _section(Icons.access_time_outlined, 'Data Retention',
            'Personal data is retained for the duration of your enrollment and a reasonable period thereafter, as required by school policy. You may request deletion of your data by contacting your school administrator.'),
        _section(Icons.verified_user_outlined, 'Your Rights',
            'You have the right to:\n\n'
                '• Access the personal information we hold about you\n'
                '• Request correction of inaccurate data\n'
                '• Request deletion of your account and associated data\n'
                '• Withdraw consent for data processing where applicable\n\n'
                'Contact your school administrator to exercise these rights.'),
        _section(Icons.mail_outline_rounded, 'Contact Us',
            'For questions or concerns about this Privacy Policy, please contact your school administrator or reach out to the EventHub support team.',
            isLast: true),
      ];

  Widget _section(IconData icon, String title, String body,
      {bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 4 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF9E7),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 16, color: const Color(0xFFD6A742)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: Colors.grey.shade700,
              height: 1.75,
            ),
          ),
          if (!isLast) ...[
            const SizedBox(height: 16),
            Divider(color: Colors.grey.shade100, height: 1),
          ],
        ],
      ),
    );
  }
}

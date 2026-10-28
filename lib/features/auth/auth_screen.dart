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
import '../../core/services/notif_read_store.dart';
import '../../shared/widgets/gradient_button.dart';
import '../../shared/widgets/app_alert.dart';
import '../../shared/widgets/error_alert.dart';
import '../../shared/widgets/web/swal.dart';
import '../../core/friendly_error.dart';
import '../organizer/mobile/dashboard/organizer_dashboard.dart';
import '../student/dashboard/student_dashboard.dart';
import '../../core/app_colors.dart';
import '../../core/theme_store.dart';
import 'terms_content.dart';
import 'privacy_content.dart';
import '../../shared/utils/lrn_input_formatter.dart' show lrnDigits;

// ── Enums ──────────────────────────────────────────────────────────────────────
enum _LegalType { terms, privacy }

enum _LoginMode { student, organizer }

// ── Auth screen ────────────────────────────────────────────────────────────────
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _loginFormKey = GlobalKey<FormState>();
  bool _loginLoading = false;
  bool _loginShowPassword = false;
  bool _rememberMe = false;
  bool _isLoadingCredentials = true;
  _LoginMode _mode = _LoginMode.student;

  // ── Rate limiting ──────────────────────────────────────────────────────────
  final Map<_LoginMode, int> _failedAttemptsByMode = {};
  final Map<_LoginMode, DateTime?> _lockedUntilByMode = {};
  final Map<_LoginMode, Timer> _lockTimers = {};

  static const String _kLegacyAttemptKey = 'rl_login_attempts';
  static const String _kLegacyLockedKey = 'rl_login_locked_until';

  String _attemptKey(_LoginMode mode) => 'rl_login_attempts_${mode.name}';
  String _lockedKey(_LoginMode mode) => 'rl_login_locked_until_${mode.name}';

  int get _failedAttempts => _failedAttemptsByMode[_mode] ?? 0;

  DateTime? get _lockedUntil => _lockedUntilByMode[_mode];

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

  static const String _kEmailDomain = '@gmail.com';

  late final TextEditingController _emailCtrl;
  late final TextEditingController _lrnCtrl;
  late final TextEditingController _passwordCtrl;
  late final TapGestureRecognizer _termsTap;
  late final TapGestureRecognizer _privacyTap;

  // ── Colors ────────────────────────────────────────────────────────────────────
  static const _kGoldLight = Color(0xFFFEF9E7);
  static const _kBlue = Color(0xFF0EA5E9); // sky-500 — student accent
  static const _kBlueLight = Color(0xFFE0F2FE); // sky-100 — student bg tint

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController();
    _lrnCtrl = TextEditingController();
    _passwordCtrl = TextEditingController();
    _termsTap = TapGestureRecognizer()
      ..onTap = () => _showLegalSheet(_LegalType.terms);
    _privacyTap = TapGestureRecognizer()
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
    for (final timer in _lockTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  bool get _isOrganizer => _mode == _LoginMode.organizer;

  void _switchMode() {
    _loginFormKey.currentState?.reset();
    _emailCtrl.clear();
    _lrnCtrl.clear();
    _passwordCtrl.clear();

    setState(() {
      _mode = _isOrganizer ? _LoginMode.student : _LoginMode.organizer;
      _loginShowPassword = false;
    });
  }

  void _showLegalSheet(_LegalType type) =>
      showLegalSheet(context, terms: type == _LegalType.terms);

  // ── Credential persistence ─────────────────────────────────────────────────────

  Future<void> _loadSavedCredential() async {
    try {
      final remember = await _storage.read(key: 'remember_me') == 'true';
      if (!remember) return;

      final savedMode = await _storage.read(key: 'saved_mode');
      final savedLrn = await _storage.read(key: 'saved_lrn');
      final savedEmail = await _storage.read(key: 'saved_email');

      if (!mounted) return;
      setState(() {
        _rememberMe = true;
        if (savedMode == 'organizer') {
          _mode = _LoginMode.organizer;
          if (savedEmail != null) _emailCtrl.text = savedEmail;
        } else {
          _mode = _LoginMode.student;
          if (savedLrn != null) _lrnCtrl.text = _restoreSavedLrn(savedLrn);
        }
      });
    } catch (e) {
      debugPrint('Error loading saved credential: $e');
    } finally {
      if (mounted) setState(() => _isLoadingCredentials = false);
    }
  }

  // Remembered credentials from earlier app versions may contain either the
  // full LRN or only the suffix. The login field now uses the last four digits.
  String _restoreSavedLrn(String saved) {
    final d = lrnDigits(saved);
    return d.length > 4 ? d.substring(d.length - 4) : d;
  }

  Future<void> _saveCredential() async {
    if (!_rememberMe) {
      await _clearSavedCredential();
      return;
    }
    try {
      await _storage.write(key: 'remember_me', value: 'true');
      await _storage.write(
        key: 'saved_mode',
        value: _isOrganizer ? 'organizer' : 'student',
      );
      if (_isOrganizer) {
        await _storage.write(
          key: 'saved_email',
          value: _emailCtrl.text.trim().toLowerCase(),
        );
      } else {
        await _storage.write(
          key: 'saved_lrn',
          value: _restoreSavedLrn(_lrnCtrl.text),
        );
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
      final prefs = await SharedPreferences.getInstance();
      for (final mode in _LoginMode.values) {
        final attemptKey = _attemptKey(mode);
        final lockedKey = _lockedKey(mode);
        final isLegacyStudentKey = mode == _LoginMode.student;
        final attempts =
            prefs.getInt(attemptKey) ??
            (isLegacyStudentKey ? prefs.getInt(_kLegacyAttemptKey) : null) ??
            0;
        final lockedMs =
            prefs.getInt(lockedKey) ??
            (isLegacyStudentKey ? prefs.getInt(_kLegacyLockedKey) : null) ??
            0;
        final locked = lockedMs > 0
            ? DateTime.fromMillisecondsSinceEpoch(lockedMs)
            : null;
        final stillLocked = locked != null && locked.isAfter(DateTime.now());
        _failedAttemptsByMode[mode] = stillLocked ? attempts : 0;
        _lockedUntilByMode[mode] = stillLocked ? locked : null;
        if (stillLocked) {
          _startLockTimer(mode);
        } else {
          await prefs.remove(attemptKey);
          await prefs.remove(lockedKey);
        }
        if (isLegacyStudentKey) {
          await prefs.remove(_kLegacyAttemptKey);
          await prefs.remove(_kLegacyLockedKey);
        }
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _recordFailure(_LoginMode mode) async {
    final attempts = (_failedAttemptsByMode[mode] ?? 0) + 1;
    final lockDur = attempts >= 5 ? const Duration(seconds: 30) : Duration.zero;
    final lockedUntil = lockDur > Duration.zero
        ? DateTime.now().add(lockDur)
        : null;
    _failedAttemptsByMode[mode] = attempts;
    _lockedUntilByMode[mode] = lockedUntil;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_attemptKey(mode), attempts);
      await prefs.setInt(
        _lockedKey(mode),
        lockedUntil?.millisecondsSinceEpoch ?? 0,
      );
    } catch (_) {}
    if (lockedUntil != null) _startLockTimer(mode);
    if (mounted) setState(() {});
  }

  Future<void> _clearRateLimit(_LoginMode mode) async {
    _failedAttemptsByMode[mode] = 0;
    _lockedUntilByMode[mode] = null;
    _lockTimers.remove(mode)?.cancel();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_attemptKey(mode));
      await prefs.remove(_lockedKey(mode));
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _startLockTimer(_LoginMode mode) {
    _lockTimers.remove(mode)?.cancel();
    _lockTimers[mode] = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        _lockTimers.remove(mode);
        return;
      }
      final lockedUntil = _lockedUntilByMode[mode];
      if (lockedUntil == null || !DateTime.now().isBefore(lockedUntil)) {
        timer.cancel();
        _lockTimers.remove(mode);
        _failedAttemptsByMode[mode] = 0;
        _lockedUntilByMode[mode] = null;
        SharedPreferences.getInstance()
            .then((prefs) {
              prefs.remove(_attemptKey(mode));
              prefs.remove(_lockedKey(mode));
            })
            .catchError((_) {});
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
          child: CircularProgressIndicator(color: kGold, strokeWidth: 2.5),
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
                  28,
                  32,
                  28,
                  MediaQuery.of(context).padding.bottom + 28,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Greeting — restyled as the form-sheet heading
                    const Text(
                      'Welcome back!',
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
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: kGold.withValues(alpha: 0.55), width: 2),
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
              width: 60,
              height: 60,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  color: Color(0xFF2C2520),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.image_outlined,
                  color: Colors.white38,
                  size: 26,
                ),
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
    final bg = _isOrganizer ? _kGoldLight : _kBlueLight;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.5),
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
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _isOrganizer ? Icons.badge_rounded : Icons.school_rounded,
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
                  width: 34,
                  height: 34,
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
            if (pass.length < 6)
              return 'Password must be at least 6 characters';
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
                    width: 20,
                    height: 20,
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
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFD97706),
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${_isOrganizer ? 'Organizer' : 'Student'} login: '
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
        if (username.length < 3)
          return 'Username must be at least 3 characters';
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
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
      ],
      decoration: _fieldDecoration(
        hint: 'Last 4 digits of your LRN',
        icon: Icons.school_rounded,
      ),
      validator: (value) {
        final digits = lrnDigits(value ?? '');
        if (digits.isEmpty) return 'LRN is required';
        if (digits.length != 4) return 'Enter the last 4 digits of your LRN';
        return null;
      },
    );
  }

  // ── Login handler ─────────────────────────────────────────────────────────────

  Future<void> _handleLogin() async {
    if (_isLocked) return;
    if (!_loginFormKey.currentState!.validate()) return;
    final loginMode = _mode;
    final email = _isOrganizer
        ? '${_emailCtrl.text.trim().toLowerCase()}@gmail.com'
        : '$kSchoolLrnPrefix${lrnDigits(_lrnCtrl.text)}$_kEmailDomain';
    final pass = _passwordCtrl.text;
    setState(() => _loginLoading = true);
    // Block setupAuthStateListener from racing us to the navigator.
    SupabaseService.handlingAppLogin = true;
    try {
      // S-01: server-side rate limit check — enforced across all devices/sessions.
      final rlStatus = await RateLimitService.check(email);
      if (!rlStatus.allowed) {
        if (mounted) {
          setState(() {
            _lockedUntilByMode[loginMode] = rlStatus.lockedUntil;
          });
        }
        if (rlStatus.lockedUntil != null) _startLockTimer(loginMode);
        return;
      }

      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: pass,
      );
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
            message:
                'Admin accounts can only be accessed through the EventHub web portal. '
                'Please use a browser to log in.',
            buttonText: 'Got it',
          );
        }
        return;
      }

      final organizerData = await SupabaseService.client
          .from('organizers')
          .select('organizer_id, full_name, is_active')
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
            message:
                'This account is registered as an Organizer.\n'
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
            message:
                'No organizer account found for these credentials.\n'
                'Tap the toggle above to switch to Student Login.',
            buttonText: 'Got it',
            onDismiss: _switchMode,
          );
        }
        return;
      }

      // ── Account status gate ───────────────────────────────────────────────
      // Deactivated or deleted accounts must not reach the dashboard just
      // because Supabase Auth still accepts the password.
      if (isOrganizer) {
        if (organizerData!['is_active'] != true) {
          await Supabase.instance.client.auth.signOut();
          if (mounted) {
            setState(() => _loginLoading = false);
            AppAlert.warning(
              context,
              title: 'Account Deactivated',
              message:
                  'This organizer account has been deactivated. '
                  'Contact an administrator for assistance.',
              buttonText: 'Got it',
            );
          }
          return;
        }
      } else {
        final studentData = await SupabaseService.client
            .from('students')
            .select('is_active')
            .eq('user_id', user.id)
            .maybeSingle();
        if (studentData == null || studentData['is_active'] != true) {
          await Supabase.instance.client.auth.signOut();
          if (mounted) {
            setState(() => _loginLoading = false);
            AppAlert.warning(
              context,
              title: 'Account Deactivated',
              message:
                  'This student account has been deactivated. '
                  'Contact an administrator for assistance.',
              buttonText: 'Got it',
            );
          }
          return;
        }
      }

      // ── Persist credential if Remember Me is on ────────────────────────────
      await _clearRateLimit(loginMode);
      unawaited(RateLimitService.clear(email));
      await _saveCredential();

      // ── Audit log ───────────────────────────────────────────────────────────
      if (isOrganizer) {
        AuditService.logLogin(
          userId: user.id,
          role: 'organizer',
          fullName: organizerData!['full_name'] as String?,
          identifier: (organizerData['organizer_id'] as String? ?? '')
              .toLowerCase(),
        );
      } else {
        AuditService.logLogin(
          userId: user.id,
          role: 'student',
          identifier: '$kSchoolLrnPrefix${lrnDigits(_lrnCtrl.text)}',
        );
      }

      // ── Load per-user theme before navigating ───────────────────────────────
      await ThemeStore.loadForUser(
        user.id,
        isOrganizer ? 'organizer' : 'student',
      );
      if (!isOrganizer) await NotifReadStore.loadForUser(user.id);

      // ── Route correctly ─────────────────────────────────────────────────────
      if (mounted) {
        await Swal.fire(
          context,
          icon: SwalIcon.success,
          title: 'Welcome back!',
          text: isOrganizer
              ? 'You’re signed in to your organizer account.'
              : 'You’re signed in to your student account.',
          showConfirmButton: false,
          timer: const Duration(milliseconds: 1200),
          timerProgressBar: true,
          allowOutsideClick: false,
        );
      }
      if (mounted) {
        Navigator.of(context).pushReplacement(
          _dashRoute(
            isOrganizer
                ? const OrganizerDashboardScreen()
                : const StudentDashboard(),
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('Login failed: $e\n$stack');
      await _recordFailure(loginMode);
      unawaited(RateLimitService.recordFailure(email));
      if (mounted)
        showErrorAlert(context, _loginError(e), title: 'Login failed');
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
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
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
          fontFamily: 'Poppins',
          fontSize: 12,
          height: 1.65,
        ),
        children: [
          TextSpan(
            text: 'By signing in, you agree to our ',
            style: TextStyle(
              color: Colors.grey[600],
              fontWeight: FontWeight.w400,
            ),
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
              color: Colors.grey[600],
              fontWeight: FontWeight.w400,
            ),
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
              color: Colors.grey[600],
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  // A wrong LRN / username or password is the usual cause — say which one
  // this portal uses. Everything else is translated by friendlyError.
  Object _loginError(Object e) {
    if (e is AuthException &&
        e.message.toLowerCase().contains('invalid login credentials')) {
      return FriendlyException(
        _isOrganizer
            ? 'Incorrect username or password. Please try again.'
            : 'Incorrect LRN or password. Please try again.',
      );
    }
    return e;
  }

  Route<void> _dashRoute(Widget screen) => PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 500),
    reverseTransitionDuration: const Duration(milliseconds: 350),
    pageBuilder: (ctx, a, b) => screen,
    transitionsBuilder: (ctx, anim, b, child) {
      final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
      final slide = Tween<Offset>(
        begin: const Offset(0, 0.022),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
      return FadeTransition(
        opacity: fade,
        child: SlideTransition(position: slide, child: child),
      );
    },
  );
}

// ── Legal bottom sheet ─────────────────────────────────────────────────────────

/// The Terms and Conditions ([terms]) or the Privacy Policy, as on the sign-in
/// screen — the profiles' About EventHub opens it too.
Future<void> showLegalSheet(BuildContext context, {required bool terms}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _LegalSheet(type: terms ? _LegalType.terms : _LegalType.privacy),
    );

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
                width: 40,
                height: 4,
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
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF9E7),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: kGold.withValues(alpha: 0.25)),
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
                          'Last updated: $eventHubLegalUpdated',
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
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: Colors.black54,
                        ),
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
                24,
                12,
                24,
                MediaQuery.of(ctx).padding.bottom + 20,
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
                      borderRadius: BorderRadius.circular(16),
                    ),
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
    for (var i = 0; i < eventHubTerms.length; i++)
      _section(
        eventHubTerms[i].icon,
        eventHubTerms[i].title,
        eventHubTerms[i].body,
        isLast: i == eventHubTerms.length - 1,
      ),
  ];

  // The shared, accurate policy — privacy_content.dart (app and web).
  List<Widget> _privacyContent() => [
    for (var i = 0; i < eventHubPrivacy.length; i++)
      _section(
        eventHubPrivacy[i].icon,
        eventHubPrivacy[i].title,
        eventHubPrivacy[i].body,
        isLast: i == eventHubPrivacy.length - 1,
      ),
  ];

  Widget _section(
    IconData icon,
    String title,
    String body, {
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 4 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
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

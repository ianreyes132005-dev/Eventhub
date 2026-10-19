import 'dart:async';
import 'dart:math' show pi;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/audit_service.dart';
import '../../core/services/rate_limit_service.dart';
import '../../core/app_colors.dart';
import '../../core/friendly_error.dart';
import '../../core/theme_store.dart';
import '../../shared/widgets/app_alert.dart';
import '../organizer/web/web_shell.dart';
import '../admin/admin_web_dashboard.dart';
import 'terms_content.dart';

// ── Constants ──────────────────────────────────────────────────────────────────

const _kPanelDark = Color(0xFF1A1612);
const _kFormBg    = Color(0xFFF0F3F7);

// ── Shared field decoration ────────────────────────────────────────────────────

InputDecoration _webFieldDeco({
  required String hint,
  required IconData icon,
  Widget? suffix,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(
      fontFamily: 'Poppins',
      color: Color(0xFFB0B8C4),
      fontSize: 13.5,
      fontWeight: FontWeight.w400,
    ),
    prefixIcon: Icon(icon, color: const Color(0xFFB0B8C4), size: 19),
    suffixIcon: suffix,
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kGold, width: 1.8),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFFCA5A5), width: 1.2),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.8),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Entry widget
// ══════════════════════════════════════════════════════════════════════════════

class WebAuthScreen extends StatefulWidget {
  const WebAuthScreen({super.key});

  @override
  State<WebAuthScreen> createState() => _WebAuthScreenState();
}

class _WebAuthScreenState extends State<WebAuthScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double>   _fade;
  late final Animation<Offset>   _formSlide;
  late final Animation<Offset>   _panelSlide;

  final _formKey    = GlobalKey<FormState>();
  final _emailCtrl  = TextEditingController();
  final _pwCtrl     = TextEditingController();
  final _emailFocus = FocusNode();
  final _pwFocus    = FocusNode();

  bool    _obscure         = true;
  bool    _loading         = false;
  bool    _rememberMe      = false;
  bool    _checkingSession = true;
  String? _error;

  // ── Rate limiting ──────────────────────────────────────────────────────────
  int       _failedAttempts = 0;
  DateTime? _lockedUntil;
  Timer?    _lockTimer;

  static const String _kAttemptKey  = 'web_rl_login_attempts';
  static const String _kLockedKey   = 'web_rl_login_locked_until';
  static const String _kRememberKey = 'web_remember_me';
  static const String _kUsernameKey = 'web_saved_username';

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

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fade = CurvedAnimation(
        parent: _anim,
        curve: const Interval(0.15, 1.0, curve: Curves.easeOut));
    _formSlide = Tween<Offset>(
            begin: const Offset(0.04, 0), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _anim,
            curve: const Interval(0.0, 0.75, curve: Curves.easeOutCubic)));
    _panelSlide = Tween<Offset>(
            begin: const Offset(-0.04, 0), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _anim,
            curve: const Interval(0.0, 0.75, curve: Curves.easeOutCubic)));
    _loadRateLimitState();
    _loadSavedUsername();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkSession());
  }

  Future<void> _checkSession() async {
    final user = SupabaseService.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() => _checkingSession = false);
        _anim.forward();
      }
      return;
    }
    try {
      // Admin takes priority — check before organizer
      final adminRow = await SupabaseService.client
          .from('admins')
          .select('admin_id')
          .eq('user_id', user.id)
          .maybeSingle();
      if (!mounted) return;
      if (adminRow != null) {
        await ThemeStore.loadForUser(user.id, 'admin');
        if (!mounted) return;
        Navigator.of(context).pushReplacement(_adminRoute());
        return;
      }

      final row = await SupabaseService.client
          .from('organizers')
          .select('organizer_id')
          .eq('user_id', user.id)
          .maybeSingle();
      if (!mounted) return;
      if (row != null) {
        await ThemeStore.loadForUser(user.id, 'organizer');
        if (!mounted) return;
        Navigator.of(context).pushReplacement(_dashRoute());
      } else {
        setState(() => _checkingSession = false);
        _anim.forward();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _checkingSession = false);
        _anim.forward();
      }
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    _emailFocus.dispose();
    _pwFocus.dispose();
    _lockTimer?.cancel();
    super.dispose();
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

  // ── Remember Me ────────────────────────────────────────────────────────────

  Future<void> _loadSavedUsername() async {
    try {
      final prefs   = await SharedPreferences.getInstance();
      final remember = prefs.getBool(_kRememberKey) ?? false;
      if (!remember) return;
      final username = prefs.getString(_kUsernameKey);
      if (!mounted) return;
      setState(() {
        _rememberMe = true;
        if (username != null) _emailCtrl.text = username;
      });
    } catch (_) {}
  }

  Future<void> _saveUsername(String username) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setBool(_kRememberKey, true);
        await prefs.setString(_kUsernameKey, username);
      } else {
        await prefs.remove(_kRememberKey);
        await prefs.remove(_kUsernameKey);
      }
    } catch (_) {}
  }

  // Used by _checkSession (auto-login on reload) — no branded splash needed.
  Route<void> _dashRoute() => PageRouteBuilder<void>(
    transitionDuration:        const Duration(milliseconds: 500),
    reverseTransitionDuration: const Duration(milliseconds: 350),
    pageBuilder:        (ctx, a, b) => const OrganizerWebDashboard(),
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

  Route<void> _adminRoute() => PageRouteBuilder<void>(
    transitionDuration:        const Duration(milliseconds: 500),
    reverseTransitionDuration: const Duration(milliseconds: 350),
    pageBuilder:        (ctx, a, b) => const AdminWebDashboard(),
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

  // Used by explicit sign-in — plays branded splash before dashboard.
  Route<void> _transitionRoute() => PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (ctx, a, b) => const _TransitionScreen(),
    transitionsBuilder: (ctx, anim, b, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: child,
    ),
  );

  Future<void> _login() async {
    if (_isLocked) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final username = _emailCtrl.text.trim().toLowerCase();
    final email    = '$username@gmail.com';
    final pw       = _pwCtrl.text;

    setState(() {
      _loading = true;
      _error   = null;
    });
    SupabaseService.handlingAppLogin = true;

    try {
      // ── S-01: server-side rate limit check ────────────────────────────────
      // Enforced independently of client state — cannot be bypassed by clearing
      // app data or switching devices.
      final rlStatus = await RateLimitService.check(email);
      if (!rlStatus.allowed) {
        if (mounted) {
          setState(() {
            _lockedUntil = rlStatus.lockedUntil;
            _loading     = false;
          });
        }
        if (rlStatus.lockedUntil != null) _startLockTimer();
        return;
      }

      await SupabaseService.client.auth
          .signInWithPassword(email: email, password: pw);

      final user = SupabaseService.currentUser;
      if (user == null) throw Exception('Sign in failed');

      // Admin check — highest priority
      final adminRow = await SupabaseService.client
          .from('admins')
          .select('admin_id, full_name')
          .eq('user_id', user.id)
          .maybeSingle();

      if (adminRow != null) {
        AuditService.logLogin(
          userId: user.id, role: 'admin',
          fullName:   adminRow['full_name'] as String?,
          identifier: username,
        );
        await _clearRateLimit();
        unawaited(RateLimitService.clear(email));
        await _saveUsername(username);                    // BUG-01
        await ThemeStore.loadForUser(user.id, 'admin');
        if (mounted) Navigator.of(context).pushReplacement(_adminRoute());
        return;
      }

      final row = await SupabaseService.client
          .from('organizers')
          .select('organizer_id, full_name, is_active')
          .eq('user_id', user.id)
          .maybeSingle();

      if (row == null) {
        await SupabaseService.client.auth.signOut();
        if (mounted) {
          setState(() => _loading = false);
          AppAlert.warning(
            context,
            title: 'Wrong Portal',
            message: 'This portal is for organizers and admins only.\n'
                'Please use the EventHub mobile app to log in as a student.',
            buttonText: 'Got it',
            compact: true,
          );
        }
        return;
      }

      if (row['is_active'] != true) {
        await SupabaseService.client.auth.signOut();
        if (mounted) {
          setState(() => _loading = false);
          AppAlert.warning(
            context,
            title: 'Account Deactivated',
            message: 'This organizer account has been deactivated. '
                'Contact an administrator for assistance.',
            buttonText: 'Got it',
            compact: true,
          );
        }
        return;
      }

      AuditService.logLogin(
        userId: user.id, role: 'organizer',
        fullName:   row['full_name'] as String?,
        identifier: (row['organizer_id'] as String? ?? '').toLowerCase(),
      );
      await _clearRateLimit();
      unawaited(RateLimitService.clear(email));
      await _saveUsername(username);                      // BUG-01
      await ThemeStore.loadForUser(user.id, 'organizer');
      if (mounted) Navigator.of(context).pushReplacement(_transitionRoute());
    } on AuthException catch (e) {
      await _recordFailure();
      unawaited(RateLimitService.recordFailure(email));
      setState(() {
        _error = e.message.contains('Invalid')
            ? 'Incorrect username or password. Please try again.'
            : friendlyError(e);
        _loading = false;
      });
    } catch (_) {
      // BUG-02: auth may have succeeded before a role-lookup DB error.
      // If a session exists, sign it out so it doesn't dangle invisibly.
      if (SupabaseService.currentUser != null) {
        try { await SupabaseService.client.auth.signOut(); } catch (_) {}
      } else {
        // Auth itself failed — count it against the rate limit.
        await _recordFailure();
        unawaited(RateLimitService.recordFailure(email));
      }
      setState(() {
        _error = 'Something went wrong. Please check your connection and try again.';
        _loading = false;
      });
    } finally {
      SupabaseService.handlingAppLogin = false;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_checkingSession) {
      return const Scaffold(
        backgroundColor: _kPanelDark,
        body: Center(child: CircularProgressIndicator(color: kGold)),
      );
    }
    return Scaffold(
      backgroundColor: _kPanelDark,
      body: LayoutBuilder(builder: (_, constraints) {
        final wide = constraints.maxWidth >= 900;
        return wide ? _buildWide() : _buildNarrow();
      }),
    );
  }

  // ── Wide: dark left panel + grey right with floating white card ────────────

  Widget _buildWide() {
    return Row(
      children: [
        SlideTransition(
          position: _panelSlide,
          child: FadeTransition(
            opacity: _fade,
            child: const SizedBox(width: 460, child: _LeftPanel()),
          ),
        ),
        Expanded(
          child: SlideTransition(
            position: _formSlide,
            child: FadeTransition(
              opacity: _fade,
              child: Container(
                color: _kFormBg,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 48),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                              color: const Color(0xFFE8EBF0)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.07),
                              blurRadius: 40,
                              offset: const Offset(0, 8),
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 80,
                              offset: const Offset(0, 20),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(40),
                        child: _buildForm(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Narrow: dark hero top + white rounded card ────────────────────────────

  Widget _buildNarrow() {
    return FadeTransition(
      opacity: _fade,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 36),
              child: _buildNarrowHero(),
            ),
          ),
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
                child: _buildForm(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrowHero() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: kGold.withValues(alpha: 0.55), width: 2),
                boxShadow: [
                  BoxShadow(
                      color: kGold.withValues(alpha: 0.22),
                      blurRadius: 18,
                      spreadRadius: 2),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(27),
                child: Image.asset(
                  'assets/logo.jpg',
                  width: 54,
                  height: 54,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    decoration: const BoxDecoration(
                        color: Color(0xFF2C2520), shape: BoxShape.circle),
                    child: const Icon(Icons.image_outlined,
                        color: Colors.white38, size: 22),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'J-Jireh',
                  style: TextStyle(
                    fontFamily: 'Playball',
                    fontSize: 28,
                    color: kGold,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    height: 1.1,
                  ),
                ),
                Text(
                  'EVENTHUB',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 9,
                    color: Color(0xFF8C7B6A),
                    letterSpacing: 2.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'Your complete event\nmanagement platform.',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            height: 1.28,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Sign in as organizer to manage events and registrations.',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12.5,
            color: Colors.white.withValues(alpha: 0.55),
            height: 1.5,
          ),
        ),
      ],
    );
  }

  // ── Form ──────────────────────────────────────────────────────────────────

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Compact portal identity chip
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: kGold.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kGold.withValues(alpha: 0.28)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_rounded, size: 11, color: kGold),
                  SizedBox(width: 5),
                  Text(
                    'Organizer',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: kGold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Heading
          const Text(
            'Welcome Back!',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: kText,
              height: 1.1,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 30),

          // Username
          _FieldLabel('Username'),
          const SizedBox(height: 7),
          TextFormField(
            controller: _emailCtrl,
            focusNode: _emailFocus,
            keyboardType: TextInputType.text,
            textCapitalization: TextCapitalization.none,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _pwFocus.requestFocus(),
            style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 14, color: kText),
            decoration: _webFieldDeco(
                hint: 'Your username', icon: Icons.person_outline_rounded),
            validator: (v) {
              final s = v?.trim() ?? '';
              if (s.isEmpty) return 'Username is required';
              if (s.contains('@') || s.contains(' ')) {
                return 'Enter your username only, without @gmail.com';
              }
              return null;
            },
          ),
          const SizedBox(height: 18),

          const _FieldLabel('Password'),
          const SizedBox(height: 7),
          TextFormField(
            controller: _pwCtrl,
            focusNode: _pwFocus,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _login(),
            style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 14, color: kText),
            decoration: _webFieldDeco(
              hint: '••••••••',
              icon: Icons.lock_outline_rounded,
              suffix: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 19,
                  color: const Color(0xFFB0B8C4),
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Password is required';
              if (v.length < 6) return 'Password must be at least 6 characters';
              return null;
            },
          ),
          const SizedBox(height: 14),

          // Remember me
          GestureDetector(
            onTap: () => setState(() => _rememberMe = !_rememberMe),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 19,
                    height: 19,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: _rememberMe
                            ? kGold
                            : const Color(0xFFCBD5E1),
                        width: _rememberMe ? 2.0 : 1.2,
                      ),
                      color: _rememberMe ? kGold : Colors.transparent,
                    ),
                    child: _rememberMe
                        ? const Icon(Icons.check,
                            size: 12, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Remember me',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Error banner
          if (_error != null) ...[
            _ErrorBanner(message: _error!),
            const SizedBox(height: 16),
          ],

          // Warning banner (≥3 failures, while not locked)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, anim) => SizeTransition(
              sizeFactor: anim,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: (_failedAttempts >= 3 && !_isLocked)
                ? Container(
                    key: const ValueKey('web-warn'),
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFFF59E0B)
                              .withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(Icons.warning_amber_rounded,
                              size: 16, color: Color(0xFFD97706)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${5 - _failedAttempts} more failed attempt${5 - _failedAttempts == 1 ? '' : 's'} will trigger a 30-second lockout.',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              color: Color(0xFF92400E),
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('web-no-warn')),
          ),

          // Sign in button / lockout countdown
          _SignInButton(
            loading: _loading,
            locked: _isLocked,
            lockMessage: _lockMessage,
            onTap: (_loading || _isLocked) ? null : _login,
          ),

          const SizedBox(height: 24),

          // Students note — icon card
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F7FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBDD7FF)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.phone_android_rounded,
                      size: 15, color: Color(0xFF3B82F6)),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Are you a student?',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1D4ED8),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Use the EventHub mobile app to register and attend events.',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          color: Color(0xFF3B82F6),
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // Footer — Terms and Privacy are gold + underlined clickable links
          Text.rich(
            TextSpan(
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                color: kMuted,
                height: 1.5,
              ),
              children: [
                const TextSpan(text: 'By signing in, you agree to our '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => _WebLegalDialog.show(context, isTerms: true),
                      child: const Text(
                        'Terms and Conditions',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: kGold,
                          decoration: TextDecoration.underline,
                          decorationColor: kGold,
                        ),
                      ),
                    ),
                  ),
                ),
                const TextSpan(text: ' and '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => _WebLegalDialog.show(context, isTerms: false),
                      child: const Text(
                        'Privacy Policy',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: kGold,
                          decoration: TextDecoration.underline,
                          decorationColor: kGold,
                        ),
                      ),
                    ),
                  ),
                ),
                const TextSpan(text: '.'),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Â© ${DateTime.now().year} J-Jireh EventHub · All rights reserved',
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10.5,
              color: kMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Left branding panel
// ══════════════════════════════════════════════════════════════════════════════

class _LeftPanel extends StatelessWidget {
  const _LeftPanel();

  static const _features = [
    (Icons.event_rounded,      'Create and manage events effortlessly'),
    (Icons.how_to_reg_rounded, 'Track real-time student registrations'),
    (Icons.bar_chart_rounded,  'View analytics and attendance charts'),
    (Icons.campaign_rounded,   'Broadcast announcements to all students'),
  ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: _kPanelDark),
        const CustomPaint(painter: _BgPainter()),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0x33000000)],
              stops: [0.5, 1.0],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(36, 40, 36, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLogo(),
                const SizedBox(height: 44),
                _buildHeadline(),
                const SizedBox(height: 26),
                ..._features.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _buildFeatureRow(f.$1, f.$2),
                    )),
                const Spacer(),
                Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.08)),
                const SizedBox(height: 16),
                _buildTagline(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogo() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border:
                Border.all(color: kGold.withValues(alpha: 0.55), width: 2),
            boxShadow: [
              BoxShadow(
                  color: kGold.withValues(alpha: 0.25),
                  blurRadius: 18,
                  spreadRadius: 2),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Image.asset(
              'assets/logo.jpg',
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                decoration: const BoxDecoration(
                    color: Color(0xFF2C2520), shape: BoxShape.circle),
                child: const Icon(Icons.image_outlined,
                    color: Colors.white38, size: 24),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'J-Jireh',
              style: TextStyle(
                fontFamily: 'Playball',
                fontSize: 26,
                color: kGold,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
            Text(
              'EVENTHUB',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 9,
                color: Color(0xFF8C7B6A),
                letterSpacing: 2.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeadline() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: kGold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kGold.withValues(alpha: 0.25)),
          ),
          child: const Text(
            'Organizer Dashboard',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: kGold,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Your complete\nevent management\nplatform.',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 34,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            height: 1.22,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Streamline every step — from creation to check-in.',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.60),
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureRow(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  kGold.withValues(alpha: 0.22),
                  kGold.withValues(alpha: 0.09),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: kGold, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.78),
              ),
            ),
          ),
          Icon(Icons.check_rounded,
              color: kGold.withValues(alpha: 0.55), size: 14),
        ],
      ),
    );
  }

  Widget _buildTagline() {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            shape: BoxShape.circle,
          ),
          child:
              const Icon(Icons.format_quote_rounded, color: kGold, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Empowering J-Jireh organizers with\npowerful, real-time event tools.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11.5,
              fontStyle: FontStyle.italic,
              color: Colors.white.withValues(alpha: 0.40),
              height: 1.55,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Background geometric painter ──────────────────────────────────────────────

class _BgPainter extends CustomPainter {
  const _BgPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Subtle dot grid — base texture
    final gridDot = Paint()
      ..style = PaintingStyle.fill
      ..color = kGold.withValues(alpha: 0.030);
    for (var x = 0.0; x <= size.width + 30; x += 30) {
      for (var y = 0.0; y <= size.height + 30; y += 30) {
        canvas.drawCircle(Offset(x, y), 1.0, gridDot);
      }
    }

    final stroke = Paint()..style = PaintingStyle.stroke;

    stroke
      ..color = kGold.withValues(alpha: 0.08)
      ..strokeWidth = 1.0;
    canvas.drawCircle(Offset(size.width * 1.35, -size.height * 0.04),
        size.width * 0.95, stroke);

    stroke
      ..color = kGold.withValues(alpha: 0.07)
      ..strokeWidth = 0.8;
    canvas.drawCircle(Offset(size.width * 0.9, size.height * 0.52),
        size.width * 0.32, stroke);

    stroke
      ..color = kGold.withValues(alpha: 0.10)
      ..strokeWidth = 0.7;
    canvas.drawCircle(Offset(size.width * -0.08, size.height * 0.75),
        size.width * 0.38, stroke);

    final fill = Paint()..style = PaintingStyle.fill;

    fill.color = kGold.withValues(alpha: 0.04);
    canvas.drawCircle(Offset(size.width * 0.5, size.height * 1.05),
        size.width * 0.45, fill);

    fill.color = kGold.withValues(alpha: 0.03);
    canvas.drawCircle(Offset(size.width * -0.1, size.height * 0.12),
        size.width * 0.3, fill);

    final dot = Paint()..style = PaintingStyle.fill;

    dot.color = kGold.withValues(alpha: 0.25);
    canvas.drawCircle(
        Offset(size.width * 0.82, size.height * 0.30), 4.5, dot);
    canvas.drawCircle(
        Offset(size.width * 0.18, size.height * 0.58), 3.0, dot);

    dot.color = kGold.withValues(alpha: 0.16);
    canvas.drawCircle(
        Offset(size.width * 0.65, size.height * 0.85), 5.5, dot);
    canvas.drawCircle(
        Offset(size.width * 0.42, size.height * 0.14), 2.5, dot);
    canvas.drawCircle(
        Offset(size.width * 0.25, size.height * 0.90), 3.5, dot);
    canvas.drawCircle(
        Offset(size.width * 0.72, size.height * 0.08), 2.0, dot);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = kGold.withValues(alpha: 0.07);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(size.width * 0.78, size.height * 0.72),
        width: size.width * 0.35,
        height: size.width * 0.35,
      ),
      pi * 0.7,
      pi * 0.9,
      false,
      arc,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(size.width * 0.12, size.height * 0.28),
        width: size.width * 0.22,
        height: size.width * 0.22,
      ),
      pi * 1.2,
      pi * 0.8,
      false,
      arc..color = kGold.withValues(alpha: 0.06),
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

// ══════════════════════════════════════════════════════════════════════════════
// Reusable form widgets
// ══════════════════════════════════════════════════════════════════════════════

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: kText,
        ),
      );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFCA5A5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.error_outline_rounded,
                  size: 16, color: Color(0xFFEF4444)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: Color(0xFFB91C1C),
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      );
}

class _SignInButton extends StatefulWidget {
  final bool          loading;
  final bool          locked;
  final String        lockMessage;
  final VoidCallback? onTap;
  const _SignInButton({
    required this.loading,
    this.locked = false,
    this.lockMessage = '',
    this.onTap,
  });

  @override
  State<_SignInButton> createState() => _SignInButtonState();
}

class _SignInButtonState extends State<_SignInButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    if (widget.locked) {
      return Container(
        height: 52,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(14),
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
              widget.lockMessage,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 52,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _hovered && !widget.loading
                  ? [
                      const Color(0xFFB8892A),
                      const Color(0xFFCB9C3A),
                      const Color(0xFFDBAB50),
                    ]
                  : [
                      const Color(0xFFC49230),
                      kGold,
                      const Color(0xFFEAB866),
                    ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: kGold.withValues(alpha: _hovered ? 0.45 : 0.30),
                blurRadius: _hovered ? 20 : 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Center(
            child: widget.loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : const Text(
                    'Sign in',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Branded login â†’ dashboard transition screen
// ══════════════════════════════════════════════════════════════════════════════
//
// Timeline (2 000 ms controller):
//   0 %—30 %   Logo scales in with elasticOut bounce
//   0 %—18 %   Logo fades in
//   6 %—44 %   Inner ripple ring expands and fades
//  12 %—55 %   Outer ripple ring expands and fades
//  22 %—46 %   “J-Jireh” fades in
//  22 %—50 %   “J-Jireh” slides up from slight offset
//  34 %—54 %   “EVENTHUB” fades in
//  46 %—68 %   Gold divider line draws from centre outward
//  55 %—87 %   Gold progress bar fills left → right
//  70 %—88 %   “Preparing your dashboard…” fades in
//
// After the animation completes + 300 ms hold the dashboard fades in (650 ms).

class _TransitionScreen extends StatefulWidget {
  const _TransitionScreen();

  @override
  State<_TransitionScreen> createState() => _TransitionScreenState();
}

class _TransitionScreenState extends State<_TransitionScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // ── Logo ─────────────────────────────────────────────────────────────────
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;

  // ── Ripple rings ─────────────────────────────────────────────────────────
  late final Animation<double> _ring1Scale;
  late final Animation<double> _ring1Opacity;
  late final Animation<double> _ring2Scale;
  late final Animation<double> _ring2Opacity;

  // ── Text ─────────────────────────────────────────────────────────────────
  late final Animation<double> _titleOpacity;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _subtitleOpacity;

  // ── Decorative bar + progress ─────────────────────────────────────────────
  late final Animation<double> _lineWidth;
  late final Animation<double> _progress;

  // ── Final label ──────────────────────────────────────────────────────────
  late final Animation<double> _hintOpacity;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // Logo
    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.00, 0.30, curve: Curves.elasticOut),
      ),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.00, 0.18, curve: Curves.easeOut),
      ),
    );

    // Inner ring — fades in then out as it expands
    _ring1Scale = Tween<double>(begin: 1.0, end: 2.6).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.06, 0.44, curve: Curves.easeOut),
      ),
    );
    _ring1Opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.55), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.55, end: 0.0), weight: 80),
    ]).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.06, 0.44)),
    );

    // Outer ring — larger, slightly slower
    _ring2Scale = Tween<double>(begin: 1.0, end: 3.8).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.12, 0.55, curve: Curves.easeOut),
      ),
    );
    _ring2Opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.28), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.28, end: 0.0), weight: 80),
    ]).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.12, 0.55)),
    );

    // "J-Jireh"
    _titleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.22, 0.46, curve: Curves.easeOut),
      ),
    );
    _titleSlide = Tween<Offset>(
      begin: const Offset(0, 0.28),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.22, 0.50, curve: Curves.easeOutCubic),
      ),
    );

    // "EVENTHUB"
    _subtitleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.34, 0.54, curve: Curves.easeOut),
      ),
    );

    // Gold divider line
    _lineWidth = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.46, 0.68, curve: Curves.easeInOut),
      ),
    );

    // Progress bar
    _progress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.55, 0.87, curve: Curves.easeInOut),
      ),
    );

    // "Preparing your dashboard…"
    _hintOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.70, 0.88, curve: Curves.easeOut),
      ),
    );

    _ctrl.forward().then((_) async {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 650),
          pageBuilder: (_, _, _) => const OrganizerWebDashboard(),
          transitionsBuilder: (_, anim, _, child) => FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
            child: child,
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kPanelDark,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Same background painter as the login left panel — visual continuity
          const CustomPaint(painter: _BgPainter()),

          // Subtle radial gold glow emanating from centre
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 0.65,
                colors: [
                  kGold.withValues(alpha: 0.07),
                  Colors.transparent,
                ],
              ),
            ),
          ),

          // Bottom depth shadow
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0x55000000)],
                stops: [0.55, 1.0],
              ),
            ),
          ),

          // ── Centred content ──────────────────────────────────────────────
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Logo + ripple rings ─────────────────────────────────
                // SizedBox gives the Stack a finite size; rings overflow
                // via clipBehavior: Clip.none so they expand freely.
                SizedBox(
                  width: 300,
                  height: 300,
                  child: AnimatedBuilder(
                    animation: _ctrl,
                    builder: (_, _) => Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        // Outer ring
                        Transform.scale(
                          scale: _ring2Scale.value,
                          child: Opacity(
                            opacity: _ring2Opacity.value.clamp(0.0, 1.0),
                            child: Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: kGold.withValues(alpha: 0.50),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Inner ring
                        Transform.scale(
                          scale: _ring1Scale.value,
                          child: Opacity(
                            opacity: _ring1Opacity.value.clamp(0.0, 1.0),
                            child: Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: kGold.withValues(alpha: 0.70),
                                  width: 1.0,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Logo with glow
                        ScaleTransition(
                          scale: _logoScale,
                          child: FadeTransition(
                            opacity: _logoOpacity,
                            child: Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: kGold.withValues(alpha: 0.55),
                                  width: 2.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: kGold.withValues(alpha: 0.40),
                                    blurRadius: 44,
                                    spreadRadius: 6,
                                  ),
                                  BoxShadow(
                                    color: kGold.withValues(alpha: 0.14),
                                    blurRadius: 90,
                                    spreadRadius: 22,
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(48),
                                child: Image.asset(
                                  'assets/logo.jpg',
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(
                                    color: const Color(0xFF2C2520),
                                    child: const Icon(
                                      Icons.image_outlined,
                                      color: Colors.white38,
                                      size: 40,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Brand text ────────────────────────────────────────────
                const SizedBox(height: 2),

                SlideTransition(
                  position: _titleSlide,
                  child: FadeTransition(
                    opacity: _titleOpacity,
                    child: const Text(
                      'J-Jireh',
                      style: TextStyle(
                        fontFamily: 'Playball',
                        fontSize: 52,
                        color: kGold,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                FadeTransition(
                  opacity: _subtitleOpacity,
                  child: const Text(
                    'E V E N T H U B',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: Color(0xFF8C7B6A),
                      letterSpacing: 7.0,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                const SizedBox(height: 38),

                // ── Gold gradient divider — draws from centre outward ─────
                SizedBox(
                  width: 220,
                  child: AnimatedBuilder(
                    animation: _lineWidth,
                    builder: (_, _) => Align(
                      child: FractionallySizedBox(
                        widthFactor: _lineWidth.value.clamp(0.0, 1.0),
                        child: Container(
                          height: 1.5,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Color(0x00D6A742),
                                kGold,
                                Color(0x00D6A742),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 22),

                // ── Progress bar ─────────────────────────────────────────
                SizedBox(
                  width: 160,
                  child: AnimatedBuilder(
                    animation: _progress,
                    builder: (_, _) => ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        height: 2.5,
                        child: LinearProgressIndicator(
                          value: _progress.value,
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.06),
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(kGold),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                // ── Hint label ────────────────────────────────────────────
                FadeTransition(
                  opacity: _hintOpacity,
                  child: Text(
                    'Preparing your dashboard...',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.38),
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Legal dialog (Terms and Conditions / Privacy Policy)
// ══════════════════════════════════════════════════════════════════════════════

class _WebLegalDialog extends StatelessWidget {
  final bool isTerms;
  const _WebLegalDialog({required this.isTerms});

  static Future<void> show(BuildContext context, {required bool isTerms}) =>
      showDialog(
        context: context,
        builder: (_) => _WebLegalDialog(isTerms: isTerms),
      );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.of(context).size.height * 0.80,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(22, 18, 14, 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FC),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAB308).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isTerms ? Icons.gavel_rounded : Icons.privacy_tip_outlined,
                    color: const Color(0xFFEAB308), size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(isTerms ? 'Terms and Conditions' : 'Privacy Policy',
                      style: const TextStyle(
                        fontFamily: 'Poppins', fontSize: 15,
                        fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E))),
                    Text(isTerms ? 'J-Jireh EventHub' : 'How we handle your data',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
                        color: Colors.grey.shade500)),
                  ]),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: Colors.grey.shade400),
                  iconSize: 20,
                ),
              ]),
            ),
            // Scrollable content
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
                children: isTerms ? _termsContent() : _privacyContent(),
              ),
            ),
            // Close button
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEAB308),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: const Text('Close',
                    style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(IconData icon, String title, String body, {bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 15, color: const Color(0xFFEAB308)),
          const SizedBox(width: 8),
          Expanded(child: Text(title,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 13,
              fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E)))),
        ]),
        const SizedBox(height: 6),
        Text(body,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
            color: Colors.grey.shade700, height: 1.55)),
      ]),
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

  List<Widget> _privacyContent() => [
    _section(Icons.info_outline_rounded, 'Information We Collect',
        'We collect the following personal data to operate EventHub:\n\n'
        '• Identity: full name, email address\n'
        '• Academic: year level, LRN / student ID\n'
        '• Usage: event registrations, check-in selfies, timestamps'),
    _section(Icons.storage_outlined, 'How We Use Your Data',
        'Your data is used solely to:\n\n'
        '• Verify your identity for event check-in\n'
        '• Generate your QR code ticket\n'
        '• Track registration and attendance records\n'
        '• Send relevant event announcements'),
    _section(Icons.lock_outline_rounded, 'Data Security',
        'All data is stored securely on Supabase-hosted infrastructure. Selfie images are stored in a private bucket accessible only by authorized organizers. We do not sell or share your data with third parties.'),
    _section(Icons.av_timer_rounded, 'Data Retention',
        'Your data is retained for the duration of your enrollment. Upon request, the school administrator can arrange for deletion of your personal data.'),
    _section(Icons.verified_user_outlined, 'Your Rights',
        'You have the right to:\n\n'
        '• Access the personal data we hold about you\n'
        '• Request correction of inaccurate data\n'
        '• Withdraw consent for data processing where applicable\n\n'
        'Contact your school administrator to exercise these rights.'),
    _section(Icons.mail_outline_rounded, 'Contact Us',
        'For questions or concerns about this Privacy Policy, please contact your school administrator or reach out to the EventHub support team.',
        isLast: true),
  ];
}

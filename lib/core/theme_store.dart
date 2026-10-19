import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ThemeStore {
  static final notifier = ValueNotifier<ThemeMode>(ThemeMode.light);
  static String _userId = '';
  static String _role   = '';

  static String _key(String userId, String role) =>
      'theme_mode_${userId}_$role';

  // Called at startup — ensures a clean light default until sign-in loads prefs.
  static Future<void> init() async {
    notifier.value = ThemeMode.light;
  }

  // Called after every sign-in. Loads this specific user+role's saved preference.
  static Future<void> loadForUser(String userId, String role) async {
    _userId = userId;
    _role   = role;
    final String? stored;
    if (role == 'organizer') {
      final row = await Supabase.instance.client
          .from('organizers')
          .select('theme_mode')
          .eq('user_id', userId)
          .maybeSingle();
      if (row == null) {
        throw StateError('Could not load organizer theme preference.');
      }
      stored = row['theme_mode'] as String?;
    } else {
      final prefs = await SharedPreferences.getInstance();
      stored = prefs.getString(_key(userId, role));
    }
    notifier.value = stored == 'dark' ? ThemeMode.dark : ThemeMode.light;
  }

  // Explicitly set a mode (used by the theme picker) — idempotent.
  static Future<void> set(ThemeMode mode) async {
    if (notifier.value == mode) return;
    final previous = notifier.value;
    notifier.value = mode;
    if (_userId.isNotEmpty && _role == 'organizer') {
      try {
        await Supabase.instance.client.rpc(
          'set_organizer_theme_mode',
          params: {'p_theme_mode': mode == ThemeMode.dark ? 'dark' : 'light'},
        );
      } catch (_) {
        notifier.value = previous;
        rethrow;
      }
    } else if (_userId.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _key(_userId, _role), mode == ThemeMode.dark ? 'dark' : 'light');
    }
  }

  // Toggle saves under the currently signed-in user+role — no args needed.
  static Future<void> toggle() async {
    final next = notifier.value == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    await set(next);
  }

  static bool get isDark => notifier.value == ThemeMode.dark;
}

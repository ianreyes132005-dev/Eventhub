import 'package:shared_preferences/shared_preferences.dart';

/// Per-user organizer notification preferences.
///
/// Categories default to enabled — only disabled ones are persisted, so new
/// categories added later are on by default for existing users.
class OrgNotifPrefs {
  static const signups  = 'signups';
  static const live     = 'live';
  static const today    = 'today';
  static const tomorrow = 'tomorrow';

  static String _key(String userId) => 'org_notif_prefs_$userId';

  static Future<Set<String>> disabled(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return Set<String>.from(prefs.getStringList(_key(userId)) ?? const []);
  }

  static Future<void> setEnabled(
      String userId, String category, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    final off = Set<String>.from(prefs.getStringList(_key(userId)) ?? const []);
    if (enabled) {
      off.remove(category);
    } else {
      off.add(category);
    }
    await prefs.setStringList(_key(userId), off.toList());
  }
}

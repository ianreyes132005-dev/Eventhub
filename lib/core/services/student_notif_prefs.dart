import 'package:shared_preferences/shared_preferences.dart';

/// Per-user student notification preferences.
///
/// Categories default to enabled — only disabled ones are persisted.
/// Verification requests (selfie required / photo submitted) are intentionally
/// NOT a category: organizers depend on them for attendance, so they can
/// never be silenced.
class StudentNotifPrefs {
  static const announcements = 'announcements';
  static const checkins      = 'checkins';

  static String _key(String userId) => 'student_notif_prefs_$userId';

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

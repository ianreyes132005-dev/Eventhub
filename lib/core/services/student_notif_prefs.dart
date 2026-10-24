import 'package:shared_preferences/shared_preferences.dart';
import 'user_settings_cloud.dart';

/// Per-user student notification preferences — saved on the phone and in
/// the account's user_settings row, so they follow the student to any phone
/// (the saved row wins when there is one).
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
    final cloud = await UserSettingsCloud.fetch(userId);
    if (cloud != null) {
      await prefs.setStringList(_key(userId), cloud.disabledNotifications.toList());
      return cloud.disabledNotifications;
    }
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
    await UserSettingsCloud.save(userId, disabledNotifications: off);
  }
}

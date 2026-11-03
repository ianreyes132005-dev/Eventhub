import 'package:shared_preferences/shared_preferences.dart';
import 'user_settings_cloud.dart';

/// Per-user app language preference — saved on the phone and in the
/// account's user_settings row, so it follows the user to any phone.
///
/// Only English ships today — the stored code is honored across the app once
/// localized strings are added, so the selector persists the choice already.
class AppLangPrefs {
  static const english  = 'en';
  static const filipino = 'fil';

  static String _key(String userId) => 'app_lang_$userId';

  static Future<String> code(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final cloud = await UserSettingsCloud.fetch(userId);
    if (cloud != null) {
      final language = cloud.language == filipino ? english : cloud.language;
      await prefs.setString(_key(userId), language);
      return language;
    }
    final saved = prefs.getString(_key(userId)) ?? english;
    if (saved == filipino) {
      await prefs.setString(_key(userId), english);
      return english;
    }
    return saved;
  }

  static Future<void> setCode(String userId, String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(userId), code);
    await UserSettingsCloud.save(userId, language: code);
  }
}

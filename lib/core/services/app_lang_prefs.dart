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
      await prefs.setString(_key(userId), cloud.language);
      return cloud.language;
    }
    return prefs.getString(_key(userId)) ?? english;
  }

  static Future<void> setCode(String userId, String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(userId), code);
    await UserSettingsCloud.save(userId, language: code);
  }

  static String label(String code) =>
      code == filipino ? 'Filipino' : 'English';
}

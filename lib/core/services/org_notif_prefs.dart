import 'package:supabase_flutter/supabase_flutter.dart';

/// Account-backed organizer notification preferences.
/// Categories default to enabled, including for categories added later.
class OrgNotifPrefs {
  static const signups  = 'signups';
  static const live     = 'live';
  static const today    = 'today';
  static const tomorrow = 'tomorrow';

  static Future<Set<String>> disabled(String userId) async {
    final row = await Supabase.instance.client
        .from('organizers')
        .select('notification_preferences')
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) {
      throw StateError('Could not load organizer notification preferences.');
    }
    final preferences = row['notification_preferences'];
    if (preferences is! Map) return <String>{};
    return {
      for (final entry in preferences.entries)
        if (entry.value == false) entry.key.toString(),
    };
  }

  static Future<void> setEnabled(
      String userId, String category, bool enabled) async {
    await Supabase.instance.client.rpc(
      'set_organizer_notification_preference',
      params: {'p_category': category, 'p_enabled': enabled},
    );
  }
}

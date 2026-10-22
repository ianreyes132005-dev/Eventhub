import 'package:flutter/foundation.dart';

import 'supabase_service.dart';

/// The account's settings as saved in the database (table user_settings,
/// migration 202610210004), so they follow the user to any phone.
class CloudSettings {
  final Set<String> readIds;
  final Set<String> disabledNotifications;
  final String language;

  const CloudSettings({
    required this.readIds,
    required this.disabledNotifications,
    required this.language,
  });

  static Set<String> _set(Object? v) =>
      v is List ? v.map((e) => '$e').toSet() : <String>{};

  factory CloudSettings.fromRow(Map<String, dynamic> row) => CloudSettings(
        readIds: _set(row['read_notification_ids']),
        disabledNotifications: _set(row['disabled_notifications']),
        language: row['language'] as String? ?? 'en',
      );
}

/// Reads and writes the user's row in user_settings. The phone's own copy
/// (SharedPreferences) stays the fast, offline cache; this keeps it in step
/// across devices. Every call fails quietly — offline, or before the
/// migration is run, the app simply keeps using the phone's copy.
class UserSettingsCloud {
  UserSettingsCloud._();

  static final Map<String, CloudSettings?> _cache = {};

  /// The saved row, or null when there's none yet (or it can't be reached).
  /// Cached for the session; [refresh] fetches again (done at sign-in).
  static Future<CloudSettings?> fetch(String userId, {bool refresh = false}) async {
    if (!refresh && _cache.containsKey(userId)) return _cache[userId];
    try {
      final row = await SupabaseService.client
          .from('user_settings')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      final settings =
          row == null ? null : CloudSettings.fromRow(Map<String, dynamic>.from(row));
      _cache[userId] = settings;
      return settings;
    } catch (e) {
      debugPrint('user_settings fetch failed: $e');
      return _cache[userId];
    }
  }

  /// Saves the given fields (others are left as they are).
  static Future<void> save(
    String userId, {
    Iterable<String>? readIds,
    Iterable<String>? disabledNotifications,
    String? language,
  }) async {
    final row = <String, dynamic>{
      'user_id': userId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      if (readIds != null) 'read_notification_ids': readIds.toList(),
      if (disabledNotifications != null)
        'disabled_notifications': disabledNotifications.toList(),
      'language': ?language,
    };
    final old = _cache[userId];
    _cache[userId] = CloudSettings(
      readIds: readIds?.toSet() ?? old?.readIds ?? <String>{},
      disabledNotifications:
          disabledNotifications?.toSet() ?? old?.disabledNotifications ?? <String>{},
      language: language ?? old?.language ?? 'en',
    );
    try {
      await SupabaseService.client
          .from('user_settings')
          .upsert(row, onConflict: 'user_id');
    } catch (e) {
      debugPrint('user_settings save failed: $e');
    }
  }
}

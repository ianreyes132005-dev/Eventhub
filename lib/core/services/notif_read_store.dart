import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_colors.dart' show countsAsRegistered;
import 'user_settings_cloud.dart';

/// Notification id for "an event you registered for was cancelled" — shared
/// by the notifications screen and the dashboard bell badge so both agree.
String cancelledNotifId(String eventId) => 'evcancel_$eventId';

/// Notification id for "an event you registered for changed its date, time or
/// venue" (an approved change request stamps events.schedule_changed_at).
/// Returns null when [reg] shouldn't get one: no change, the event was
/// cancelled (that notice supersedes it), or the student registered after the
/// change and so already saw the new details. The timestamp is part of the id,
/// so a second change shows up as unread again.
String? updatedNotifIdFor(Map<String, dynamic> reg) {
  final ev      = reg['events'] as Map?;
  final eventId = reg['event_id'] as String?;
  final changed = DateTime.tryParse(ev?['schedule_changed_at'] as String? ?? '');
  if (ev == null || eventId == null || changed == null) return null;
  if ('${ev['event_status'] ?? ''}'.toLowerCase() == 'cancelled') return null;
  // A declined registration doesn't "still stand".
  if (!countsAsRegistered(reg)) return null;
  final registered = DateTime.tryParse(reg['registered_at'] as String? ?? '');
  if (registered != null && !registered.isBefore(changed)) return null;
  return 'evupdate_${eventId}_${changed.millisecondsSinceEpoch}';
}

/// Persists notification read-state across app restarts, scoped per student,
/// and across phones: the account's read marks are also saved in
/// user_settings (UserSettingsCloud) and merged in at sign-in.
/// Call [NotifReadStore.init()] once at app startup, then [loadForUser] after
/// every sign-in so read-state never bleeds between different students who
/// use the same device.
class NotifReadStore {
  static final _ids           = <String>{};
  static final unreadNotifier = ValueNotifier<int>(0);
  // Every current notification id (from [setAll]). The unread count is
  // always recounted from it, so marking items read can't make it drift.
  static List<String> _current = const [];
  static String _userId       = '';
  static const _maxStoredIds  = 300;

  static String _key(String userId) => 'notif_read_ids_$userId';

  // Called at startup — ensures a clean slate until sign-in loads this
  // specific student's own read history.
  static Future<void> init() async {
    _userId = '';
    _ids.clear();
    _current = const [];
    unreadNotifier.value = 0;
  }

  // Called after every sign-in. Loads this specific student's saved
  // read-state instead of whatever the previous student on this device left behind.
  static Future<void> loadForUser(String userId) async {
    _userId = userId;
    _ids.clear();
    final prefs  = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_key(userId)) ?? [];
    _ids.addAll(stored);
    _current = const [];
    unreadNotifier.value = 0;

    // Read on another phone counts as read here (and the other way round).
    final cloud = await UserSettingsCloud.fetch(userId, refresh: true);
    if (_userId != userId) return;   // signed out meanwhile
    final cloudIds = cloud?.readIds ?? const <String>{};
    final hadAll = _ids.containsAll(cloudIds);
    final cloudHadAll = cloudIds.containsAll(_ids);
    _ids.addAll(cloudIds);
    _recount();
    if (!hadAll) _persistLocal();
    if (!cloudHadAll) _persist();
  }

  static bool isRead(String id) => _ids.contains(id);

  static void mark(String id) {
    if (_ids.add(id)) _persist();
    _recount();
  }

  static void markAll(Iterable<String> ids) {
    _ids.addAll(ids);
    _recount();
    _persist();
  }

  /// The full current notification list (see StudentNotifications).
  static void setAll(Iterable<String> allIds) {
    _current = allIds.toList();
    _recount();
  }

  static void _recount() {
    unreadNotifier.value = _current.where((id) => !_ids.contains(id)).length;
  }

  static List<String> _trimmed() {
    final list = _ids.toList();
    return list.length > _maxStoredIds
        ? list.sublist(list.length - _maxStoredIds)
        : list;
  }

  static Future<void> _persistLocal() async {
    if (_userId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key(_userId), _trimmed());
  }

  /// On this phone and in the account's user_settings row.
  static Future<void> _persist() async {
    if (_userId.isEmpty) return;
    final userId = _userId;
    final ids = _trimmed();
    await _persistLocal();
    await UserSettingsCloud.save(userId, readIds: ids);
  }
}

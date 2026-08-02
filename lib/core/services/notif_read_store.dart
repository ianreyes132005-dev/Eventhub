import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists notification read-state across app restarts, scoped per student.
/// Call [NotifReadStore.init()] once at app startup, then [loadForUser] after
/// every sign-in so read-state never bleeds between different students who
/// use the same device.
class NotifReadStore {
  static final _ids           = <String>{};
  static final unreadNotifier = ValueNotifier<int>(0);
  static String _userId       = '';
  static const _maxStoredIds  = 300;

  static String _key(String userId) => 'notif_read_ids_$userId';

  // Called at startup — ensures a clean slate until sign-in loads this
  // specific student's own read history.
  static Future<void> init() async {
    _userId = '';
    _ids.clear();
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
    unreadNotifier.value = 0;
  }

  static bool isRead(String id) => _ids.contains(id);

  static void mark(String id) {
    _ids.add(id);
    _recalc(null);
    _persist();
  }

  static void markAll(Iterable<String> ids) {
    _ids.addAll(ids);
    _recalc(null);
    _persist();
  }

  static void setAll(Iterable<String> allIds) {
    final list = allIds.toList();
    unreadNotifier.value = list.where((id) => !_ids.contains(id)).length;
  }

  static void _recalc(Iterable<String>? allIds) {
    if (allIds != null) {
      unreadNotifier.value = allIds.where((id) => !_ids.contains(id)).length;
    } else if (unreadNotifier.value > 0) {
      unreadNotifier.value--;
    } else {
      unreadNotifier.value = 0;
    }
  }

  static Future<void> _persist() async {
    if (_userId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = _ids.toList();
    final trimmed = list.length > _maxStoredIds
        ? list.sublist(list.length - _maxStoredIds)
        : list;
    await prefs.setStringList(_key(_userId), trimmed);
  }
}

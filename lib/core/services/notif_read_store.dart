import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists notification read-state across app restarts.
/// Call [NotifReadStore.init()] once at app startup before using any other method.
class NotifReadStore {
  static final _ids           = <String>{};
  static final unreadNotifier = ValueNotifier<int>(0);
  static const _prefKey       = 'notif_read_ids';
  static const _maxStoredIds  = 300;

  static Future<void> init() async {
    final prefs  = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_prefKey) ?? [];
    _ids.addAll(stored);
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
    final prefs = await SharedPreferences.getInstance();
    final list = _ids.toList();
    final trimmed = list.length > _maxStoredIds
        ? list.sublist(list.length - _maxStoredIds)
        : list;
    await prefs.setStringList(_prefKey, trimmed);
  }
}

/// The row a realtime postgres change is about: its new values, or — for a
/// delete — the old ones (usually just the primary key). Null when the
/// payload carries neither.
Map<String, dynamic>? realtimeRow(Object? payload) {
  if (payload is! Map) return null;
  for (final key in const ['new', 'old']) {
    final row = payload[key];
    if (row is Map && row.isNotEmpty) return Map<String, dynamic>.from(row);
  }
  return null;
}

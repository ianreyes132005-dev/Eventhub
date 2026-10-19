import '../../../../core/app_colors.dart';

// What the organizer Home shows, worked out from the loaded rows — kept apart
// from the screen so the rules can be tested.

/// The countdown banner's event: the earliest approved event that's on now
/// or still ahead, by date and start time. Pending, rejected, expired,
/// cancelled and archived events never qualify.
Map<String, dynamic>? nextApprovedEvent(
  List<Map<String, dynamic>> events, {
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  Map<String, dynamic>? next;
  DateTime? nextStart;
  for (final e in events) {
    if (!eventIsApproved(e) || eventIsCancelled(e) || eventIsArchived(e)) continue;
    final w = eventWindow(e);
    if (w == null || !at.isBefore(w.end)) continue; // already over
    if (nextStart == null || w.start.isBefore(nextStart)) {
      next = e;
      nextStart = w.start;
    }
  }
  return next;
}

/// Events whose attendance is final: approved, not cancelled, had
/// registrations, and check-in has closed — oldest first.
/// [registrations] maps event_id → number of registrations.
List<Map<String, dynamic>> attendanceEvents(
  List<Map<String, dynamic>> events,
  Map<String, int> registrations, {
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final done = events.where((e) {
    if (!eventIsApproved(e) || eventIsCancelled(e)) return false;
    if ((registrations[e['event_id']] ?? 0) == 0) return false;
    final closes = checkInClosesAt(e);
    return closes != null && !at.isBefore(closes);
  }).toList()
    ..sort((a, b) => eventWindow(a)!.start.compareTo(eventWindow(b)!.start));
  return done;
}

/// Sign-ups per day for the last 7 days (index 6 = today) and the 7 days
/// before them (index i = the same weekday one week earlier).
({List<int> last7, List<int> prev7}) signupsByDay(
  Iterable<Map<String, dynamic>> registrations, {
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  // Calendar days (UTC dates avoid daylight-saving gaps in the arithmetic).
  final today = DateTime.utc(at.year, at.month, at.day);
  final last7 = List<int>.filled(7, 0);
  final prev7 = List<int>.filled(7, 0);
  for (final r in registrations) {
    final t = DateTime.tryParse(r['registered_at'] as String? ?? '')?.toLocal();
    if (t == null) continue;
    final daysAgo = today.difference(DateTime.utc(t.year, t.month, t.day)).inDays;
    if (daysAgo >= 0 && daysAgo < 7) {
      last7[6 - daysAgo]++;
    } else if (daysAgo >= 7 && daysAgo < 14) {
      prev7[13 - daysAgo]++;
    }
  }
  return (last7: last7, prev7: prev7);
}

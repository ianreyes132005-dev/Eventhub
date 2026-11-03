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
    if (!eventIsApproved(e) || eventIsCancelled(e) || eventIsArchived(e))
      continue;
    final w = eventWindow(e);
    if (w == null || !at.isBefore(w.end)) continue; // already over
    if (nextStart == null || w.start.isBefore(nextStart)) {
      next = e;
      nextStart = w.start;
    }
  }
  return next;
}

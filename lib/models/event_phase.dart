/// [checkInOpen]: the event has ended but the student's ticket can still be
/// checked in (kScanClosesAfter / kCheckInClosesAfter in app_colors.dart).
enum EventPhase { upcoming, ongoing, checkInOpen, completed, cancelled }

/// Derives the event phase from start and optional end times.
EventPhase resolveEventPhase(DateTime start, DateTime? end) {
  final now = DateTime.now();
  if (now.isBefore(start)) return EventPhase.upcoming;
  if (end != null && now.isAfter(end)) return EventPhase.completed;
  return EventPhase.ongoing;
}

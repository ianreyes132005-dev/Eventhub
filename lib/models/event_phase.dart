enum EventPhase { upcoming, ongoing, completed, cancelled }

/// Derives the event phase from start and optional end times.
EventPhase resolveEventPhase(DateTime start, DateTime? end) {
  final now = DateTime.now();
  if (now.isBefore(start)) return EventPhase.upcoming;
  if (end != null && now.isAfter(end)) return EventPhase.completed;
  return EventPhase.ongoing;
}

EventPhase eventPhaseFromStatus(String status) {
  return switch (status) {
    'ongoing' => EventPhase.ongoing,
    'ended' => EventPhase.completed,
    'cancelled' => EventPhase.cancelled,
    _ => EventPhase.upcoming,
  };
}

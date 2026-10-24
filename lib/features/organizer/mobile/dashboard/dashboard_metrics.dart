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

/// Registrations by weekday for the current Monday–Sunday week.
/// The returned list uses Monday at index 0 and Sunday at index 6.
List<int> weeklyRegistrationsByDay(
  Iterable<Map<String, dynamic>> registrations, {
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final monday = DateTime(
    at.year,
    at.month,
    at.day,
  ).subtract(Duration(days: at.weekday - DateTime.monday));
  final nextMonday = monday.add(const Duration(days: 7));
  final counts = List<int>.filled(DateTime.daysPerWeek, 0);
  for (final registration in registrations) {
    final registeredAt = DateTime.tryParse(
      registration['registered_at'] as String? ?? '',
    )?.toLocal();
    if (registeredAt == null) continue;
    final date = DateTime(
      registeredAt.year,
      registeredAt.month,
      registeredAt.day,
    );
    if (date.isBefore(monday) || !date.isBefore(nextMonday)) continue;
    counts[date.weekday - DateTime.monday]++;
  }
  return counts;
}

/// The five most recent past events used by the organizer attendance card.
/// Upcoming and ongoing events are excluded using the shared clock rules.
List<Map<String, dynamic>> recentPastEventsForAttendance(
  Iterable<Map<String, dynamic>> events, {
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final today = DateTime(at.year, at.month, at.day);
  final pastEvents =
      events.where((event) {
        final status = eventStatusValue(event, now: at);
        if (status == 'upcoming' || status == 'ongoing') return false;
        final eventDate = DateTime.tryParse(
          event['event_date'] as String? ?? '',
        );
        return eventDate != null &&
            !DateTime(
              eventDate.year,
              eventDate.month,
              eventDate.day,
            ).isAfter(today);
      }).toList()..sort((a, b) {
        final dateA =
            DateTime.tryParse(a['event_date'] as String? ?? '') ?? DateTime(0);
        final dateB =
            DateTime.tryParse(b['event_date'] as String? ?? '') ?? DateTime(0);
        return dateA.compareTo(dateB);
      });

  return pastEvents.length > 5
      ? pastEvents.sublist(pastEvents.length - 5)
      : pastEvents;
}

/// Builds per-event attendance rows for the events selected by
/// [recentPastEventsForAttendance], matching the organizer web dashboard.
List<Map<String, dynamic>> eventAttendanceBreakdown(
  Iterable<Map<String, dynamic>> events,
  Iterable<Map<String, dynamic>> registrations,
) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final regs = registrations.toList();
  return events.map((event) {
    final eventId = event['event_id'] as String;
    // Declined registrations don't count as registered.
    final eventRegs = regs.where(
      (reg) => reg['event_id'] == eventId && countsAsRegistered(reg),
    );
    final total = eventRegs.length;
    final checkedIn = eventRegs
        .where((reg) => reg['status'] == 'checked_in')
        .length;
    final date = DateTime.tryParse(event['event_date'] as String? ?? '');
    final label = date == null ? '—' : '${months[date.month - 1]} ${date.day}';
    return <String, dynamic>{
      'event_id': eventId,
      'title': event['title'] as String? ?? '—',
      'label': label,
      'checkedIn': checkedIn,
      'total': total,
    };
  }).toList();
}

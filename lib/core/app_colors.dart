import 'package:flutter/material.dart';

// ── App-wide palette ────────────────────────────────────────────────────────
// All screens import this file instead of redeclaring constants.
//
// Two background variants exist by design:
//   kBackground    — warm cream used by dashboards and list screens
//   kBackgroundAlt — slightly cooler tone used by profile and form screens

const Color kBackground    = Color(0xFFFBF6EA);
const Color kBackgroundAlt = Color(0xFFF7F4EE);
const Color kGold          = Color(0xFFD6A742);
const Color kGoldLight     = Color(0x22D6A742);
const Color kText          = Color(0xFF111827);
const Color kSubText       = Color(0xFF4B5563);
const Color kMuted         = Color(0xFF6B7280);
const Color kCard          = Colors.white;

// Web card border — used by shared web widgets (WebCard, WebBtn, etc.)
const Color kCardBorder    = Color(0xFFE8EBF0);

const LinearGradient kGoldGradient = LinearGradient(
  colors: [Color(0xFFC49230), Color(0xFFD6A742), Color(0xFFEAB866)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

// ── Shared theme tokens ──────────────────────────────────────────────────────
// Usage: `final t = AppTk(Theme.of(context).brightness == Brightness.dark);`

class AppTk {
  final bool dark;
  const AppTk(this.dark);

  Color get bg       => dark ? const Color(0xFF18140F) : kBackground;
  Color get card     => dark ? const Color(0xFF231E17) : Colors.white;
  Color get border   => dark ? const Color(0xFF352D20) : const Color(0xFFF0E8D8);
  Color get text     => dark ? const Color(0xFFF2EAD8) : kText;
  Color get sub      => dark ? const Color(0xFFB8A880) : kSubText;
  Color get muted    => dark ? const Color(0xFFB8A880) : kMuted;
  Color get divider  => dark ? const Color(0xFF2C2518) : const Color(0xFFF0EBE0);
  Color get shadow   => dark
      ? Colors.black.withValues(alpha: 0.40)
      : Colors.black.withValues(alpha: 0.055);
  Color get inputBg  => dark ? const Color(0xFF1E1912) : Colors.white;
  Color get navBg    => const Color(0xFF1C1814);
  Color get shimmer1 => dark ? const Color(0xFF2A2318) : const Color(0xFFF5EFE3);
  Color get shimmer2 => dark ? const Color(0xFF332B1E) : const Color(0xFFEDE6D6);
}

// ── Shared event status helpers ──────────────────────────────────────────────
// One set of event-timing rules for every screen (organizer, student, admin).
// The SAME rules are enforced server-side by
// supabase/migrations/202610180005_event_timing_rules.sql — keep them in step.
//
// The lifecycle is decided by the clock. The only stored decision that
// overrides it is a cancellation (event_status = 'cancelled'). Any other
// stored value ('upcoming', legacy 'ongoing'/'completed'/…) is ignored.

/// Check-in (QR scan → selfie → check in) is open from this long before the
/// event starts…
const Duration kCheckInOpensBefore = Duration(hours: 1);
/// …until this long after it ends.
const Duration kCheckInClosesAfter = Duration(hours: 2);

/// Local start/end of an event, or null when it has no valid date.
/// Missing times default to 8:00 AM (start) and 11:59:59 PM (end).
({DateTime start, DateTime end})? eventWindow(Map<String, dynamic> event) {
  final eventDate = DateTime.tryParse(event['event_date'] as String? ?? '');
  if (eventDate == null) return null;
  final endDateRaw = event['end_date'] as String?;
  final endDate = (endDateRaw == null || endDateRaw.isEmpty)
      ? eventDate
      : DateTime.tryParse(endDateRaw) ?? eventDate;
  final st = _eventTime(event['start_time'] as String?, 8, 0);
  final et = _eventTime(event['end_time'] as String?, 23, 59, 59);
  try {
    return (
      start: DateTime(eventDate.year, eventDate.month, eventDate.day, st.$1, st.$2),
      end: DateTime(endDate.year, endDate.month, endDate.day, et.$1, et.$2, et.$3),
    );
  } on RangeError {
    return null;
  }
}

bool eventIsCancelled(Map<String, dynamic> event) =>
    (event['event_status'] as String? ?? '').toLowerCase() == 'cancelled';

/// 'upcoming' | 'ongoing' | 'ended' | 'cancelled' — from the clock.
String eventStatusValue(Map<String, dynamic> event, {DateTime? now}) {
  if (eventIsCancelled(event)) return 'cancelled';
  final w = eventWindow(event);
  if (w == null) return 'upcoming';
  final at = now ?? DateTime.now();
  if (at.isBefore(w.start)) return 'upcoming';
  if (!at.isBefore(w.end)) return 'ended';
  return 'ongoing';
}

/// Count approved, non-archived events that are upcoming or ongoing by clock.
int activeApprovedEventCount(
  Iterable<Map<String, dynamic>> events, {
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  return events.where((event) {
    if (!eventIsApproved(event) || eventIsArchived(event)) return false;
    final status = eventStatusValue(event, now: at);
    return status == 'upcoming' || status == 'ongoing';
  }).length;
}

/// Total approved events, excluding archived records.
int totalApprovedEventCount(Iterable<Map<String, dynamic>> events) =>
    events.where((event) => eventIsApproved(event) && !eventIsArchived(event)).length;

/// Why students can (or can't) register right now.
enum RegistrationState { open, cancelled, ended, started, deadlinePassed, notApproved }

/// Registration closes at the deadline when one is set; otherwise when the
/// event starts. (Walk-in registration was removed — `allow_walk_in` is a
/// legacy column that's always false and ignored here and server-side.)
///
/// Never closes for capacity: an event's capacity is the number of active
/// students (StudentCountService) and each student registers once, so a
/// student who hasn't registered always has a spot. `max_participants` is a
/// legacy column, ignored here and server-side.
RegistrationState registrationState(Map<String, dynamic> event, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final approval = event['approval_status'] as String?;
  if (approval != null && approval != 'approved') return RegistrationState.notApproved;
  if (eventIsCancelled(event)) return RegistrationState.cancelled;

  final w = eventWindow(event);
  if (w != null && !at.isBefore(w.end)) return RegistrationState.ended;

  final deadline = DateTime.tryParse(event['registration_deadline'] as String? ?? '');
  if (deadline != null) {
    if (at.isAfter(deadline.toLocal())) return RegistrationState.deadlinePassed;
  } else if (w != null && !at.isBefore(w.start)) {
    return RegistrationState.started;
  }
  return RegistrationState.open;
}

/// Share of the capacity (all active students) that has registered, 0–1.
/// 0 while the student count isn't known.
double capacityFill(int registered, int? capacity) =>
    capacity == null || capacity <= 0 ? 0 : (registered / capacity).clamp(0.0, 1.0);

/// Short student-facing reason, or null when registration is open.
String? registrationClosedReason(RegistrationState s) => switch (s) {
  RegistrationState.open           => null,
  RegistrationState.cancelled      => 'This event was cancelled',
  RegistrationState.ended          => 'This event has ended',
  RegistrationState.started        => 'Registration closed — the event has started',
  RegistrationState.deadlinePassed => 'Registration closed — the deadline has passed',
  RegistrationState.notApproved    => 'This event isn’t open for registration',
};

/// Why a QR scan / check-in step isn't allowed right now, or null when it is.
String? checkInBlockedReason(Map<String, dynamic> event, {DateTime? now}) {
  if (eventIsCancelled(event)) return 'This event was cancelled — check-in is closed.';
  final w = eventWindow(event);
  if (w == null) return null;
  final at = now ?? DateTime.now();
  final opens  = w.start.subtract(kCheckInOpensBefore);
  final closes = w.end.add(kCheckInClosesAfter);
  if (at.isBefore(opens)) {
    return 'Check-in opens 1 hour before the event starts '
        '(${_fmtWhen(opens)}).';
  }
  if (at.isAfter(closes)) {
    return 'Check-in closed 2 hours after the event ended '
        '(${_fmtWhen(closes)}).';
  }
  return null;
}

/// A pending event whose start time passed without an admin decision.
/// It can no longer be approved — the organizer must reschedule & resubmit.
bool approvalExpired(Map<String, dynamic> event, {DateTime? now}) {
  if ((event['approval_status'] as String?) != 'pending') return false;
  final w = eventWindow(event);
  return w != null && !(now ?? DateTime.now()).isBefore(w.start);
}

String _fmtWhen(DateTime d) {
  const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  final h  = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ap = d.hour < 12 ? 'AM' : 'PM';
  return '${mo[d.month - 1]} ${d.day}, $h:${d.minute.toString().padLeft(2, '0')} $ap';
}

(int, int, int) _eventTime(
  String? value,
  int fallbackHour,
  int fallbackMinute, [
  int fallbackSecond = 0,
]) {
  if (value == null || value.isEmpty) {
    return (fallbackHour, fallbackMinute, fallbackSecond);
  }
  final parts = value.split(':');
  final hour = int.tryParse(parts[0]);
  final minute = parts.length > 1 ? int.tryParse(parts[1]) : null;
  final second = parts.length > 2
      ? int.tryParse(parts[2].split('.').first)
      : 0;
  if (hour == null ||
      minute == null ||
      second == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59 ||
      second < 0 ||
      second > 59) {
    return (fallbackHour, fallbackMinute, fallbackSecond);
  }
  return (hour, minute, second);
}

String eventStatusLabel(Map<String, dynamic> event) {
  return switch (eventStatusValue(event)) {
    'ongoing' => 'Ongoing',
    'ended' => 'Ended',
    'cancelled' => 'Cancelled',
    _ => 'Upcoming',
  };
}

/// Check-in stays open [kCheckInClosesAfter] past an event's end. For an
/// ended event still inside that window, when check-in closes; else null.
DateTime? checkInOpenUntil(Map<String, dynamic> event, {DateTime? now}) {
  if (eventIsCancelled(event)) return null;
  final w = eventWindow(event);
  if (w == null) return null;
  final at = now ?? DateTime.now();
  final closes = w.end.add(kCheckInClosesAfter);
  return !at.isBefore(w.end) && at.isBefore(closes) ? closes : null;
}

/// Organizer-facing status: "Ended · Check-in open until 5:00 PM" while late
/// check-ins are still possible, otherwise the plain [eventStatusLabel].
String organizerEventStatusLabel(Map<String, dynamic> event) {
  final closes = checkInOpenUntil(event);
  if (closes == null) return eventStatusLabel(event);
  final now = DateTime.now();
  final sameDay = closes.year == now.year && closes.month == now.month && closes.day == now.day;
  final h = closes.hour % 12 == 0 ? 12 : closes.hour % 12;
  final time = '$h:${closes.minute.toString().padLeft(2, '0')} ${closes.hour < 12 ? 'AM' : 'PM'}';
  return 'Ended · Check-in open until ${sameDay ? time : _fmtWhen(closes)}';
}

/// Archived by the admin (supabase/migrations/202610180010_event_archives.sql):
/// hidden from everyday lists, records frozen.
bool eventIsArchived(Map<String, dynamic> event) => event['archived_at'] != null;

/// Can the admin archive it? Cancelled events, or ended events whose check-in
/// has closed — the same rule the database enforces.
bool eventArchivable(Map<String, dynamic> event, {DateTime? now}) {
  if (eventIsArchived(event)) return false;
  if (eventIsCancelled(event)) return true;
  final w = eventWindow(event);
  return w != null && (now ?? DateTime.now()).isAfter(w.end.add(kCheckInClosesAfter));
}

// ── Organizer event actions ──────────────────────────────────────────────────
// What the organizer may do with one of their events — the same rules as the
// web Events table. The database enforces cancel / restore too
// (202610180006_event_cancellation.sql).

bool _eventHasEnded(Map<String, dynamic> event, DateTime at) {
  final w = eventWindow(event);
  return w != null && !at.isBefore(w.end);
}

/// Edit: upcoming or cancelled events — not ongoing, ended or archived.
bool organizerCanEditEvent(Map<String, dynamic> event) {
  if (eventIsArchived(event)) return false;
  final status = eventStatusValue(event);
  return status != 'ongoing' && status != 'ended';
}

/// Cancel: any approved event that hasn't ended, ongoing included.
bool organizerCanCancelEvent(Map<String, dynamic> event, {DateTime? now}) =>
    !eventIsArchived(event) &&
    (event['approval_status'] as String? ?? 'approved') == 'approved' &&
    !eventIsCancelled(event) &&
    !_eventHasEnded(event, now ?? DateTime.now());

/// Restore: a cancelled event that hasn't ended.
bool organizerCanRestoreEvent(Map<String, dynamic> event, {DateTime? now}) =>
    !eventIsArchived(event) &&
    eventIsCancelled(event) &&
    !_eventHasEnded(event, now ?? DateTime.now());

/// Badge color for that "check-in still open" state — amber: time-limited,
/// still actionable. Dark enough for white text (5:1).
const Color kCheckInOpenColor = Color(0xFFB45309);

Color eventStatusColor(String label) {
  switch (label) {
    case 'Ongoing':   return const Color(0xFF10B981);
    case 'Ended':     return const Color(0xFF6B7280);
    case 'Cancelled': return const Color(0xFFEF4444);
    default:          return const Color(0xFF3B82F6);
  }
}

// ── Event approval status helpers ────────────────────────────────────────────
// Orthogonal to eventStatusLabel/Color above — approval_status (pending /
// approved / rejected) tracks admin moderation, event_status tracks the
// event's own lifecycle. Shared by organizer mobile, organizer web, and
// admin web so the three platforms agree on wording/color.

String approvalStatusLabel(String? s) => switch (s) {
  'pending'  => 'Pending Review',
  'approved' => 'Approved',
  'rejected' => 'Rejected',
  _          => 'Approved', // pre-migration rows / unset — grandfathered live
};

Color approvalStatusColor(String? s) => switch (s) {
  'pending'  => const Color(0xFFF59E0B),
  'approved' => const Color(0xFF10B981),
  'rejected' => const Color(0xFFEF4444),
  _          => const Color(0xFF10B981),
};

/// Event-aware approval label: a pending event whose start time already
/// passed shows "Expired" (it can no longer be approved — see approvalExpired).
String approvalLabelFor(Map<String, dynamic> event) => approvalExpired(event)
    ? 'Expired'
    : approvalStatusLabel(event['approval_status'] as String?);

Color approvalColorFor(Map<String, dynamic> event) => approvalExpired(event)
    ? const Color(0xFF6B7280)
    : approvalStatusColor(event['approval_status'] as String?);

/// The one status an organizer sees for an event in a list — the web Events
/// table's pill and the app's event-card chip use the same words and colours.
/// Most important first: Archived → Rejected → Expired → Pending review →
/// Cancelled → Check-in open → Ongoing / Ended / Upcoming. An event that
/// isn't approved never shows a schedule state.
({String label, Color color}) organizerEventStatus(Map<String, dynamic> event) {
  final approval = (event['approval_status'] as String? ?? 'approved').toLowerCase();
  if (eventIsArchived(event)) return (label: 'Archived', color: const Color(0xFF6366F1));
  if (approval == 'rejected') return (label: 'Rejected', color: const Color(0xFFEF4444));
  if (approvalExpired(event)) return (label: 'Expired', color: const Color(0xFF6B7280));
  if (approval == 'pending') return (label: 'Pending review', color: const Color(0xFFF59E0B));
  if (eventIsCancelled(event)) return (label: 'Cancelled', color: const Color(0xFFEF4444));
  if (checkInOpenUntil(event) != null) {
    return (label: 'Check-in open', color: kCheckInOpenColor);
  }
  final label = eventStatusLabel(event); // Ongoing / Ended / Upcoming
  return (label: label, color: eventStatusColor(label));
}

/// Approved by the admin (no value = a legacy event, which is live).
bool eventIsApproved(Map<String, dynamic> event) =>
    (event['approval_status'] as String? ?? 'approved').toLowerCase() == 'approved';

/// When check-in closes: [kCheckInClosesAfter] after the event ends.
DateTime? checkInClosesAt(Map<String, dynamic> event) =>
    eventWindow(event)?.end.add(kCheckInClosesAfter);

// ── Student registrations (Home) ─────────────────────────────────────────────
// [reg] is a registrations row with its event under 'events'.

Map<String, dynamic>? _regEvent(Map<String, dynamic> reg) {
  final ev = reg['events'];
  return ev is Map ? Map<String, dynamic>.from(ev) : null;
}

/// Still on the student's schedule — the Home "Upcoming" number and the
/// "My upcoming events" list both use this: the event isn't cancelled, the
/// registration wasn't declined, and check-in hasn't closed yet.
bool registrationIsUpcoming(Map<String, dynamic> reg, {DateTime? now}) {
  final event = _regEvent(reg);
  if (event == null || eventIsCancelled(event)) return false;
  if ((reg['status'] as String?) == 'rejected') return false;
  final closes = checkInClosesAt(event);
  return closes != null && (now ?? DateTime.now()).isBefore(closes);
}

/// Over, for the attendance rate: the event wasn't cancelled and its
/// check-in has closed, so attended-or-not is final.
bool registrationIsFinished(Map<String, dynamic> reg, {DateTime? now}) {
  final event = _regEvent(reg);
  if (event == null || eventIsCancelled(event)) return false;
  final closes = checkInClosesAt(event);
  return closes != null && !(now ?? DateTime.now()).isBefore(closes);
}

// ── LRN display formatter ────────────────────────────────────────────────────
// Formats a raw 12-digit LRN (e.g. "123456261234") → "123456 - 26 - 1234".
// Returns the input unchanged if it is not exactly 12 digits.
String formatLrn(String lrn) {
  final d = lrn.replaceAll(RegExp(r'\D'), '');
  if (d.length != 12) return lrn;
  return '${d.substring(0, 6)} - ${d.substring(6, 8)} - ${d.substring(8)}';
}

/// The school's LRN prefix: school ID 123456 + enrollment year 26. The admin's
/// Add Student fills it in so only the last 4 digits are typed (a
/// "Different LRN prefix?" link allows the full 12 for other prefixes).
const String kSchoolLrnPrefix = '12345626';

// Legacy: before 2026-10-18 students logged in with only the last 4 LRN
// digits and the app rebuilt the rest from this fixed prefix. Login now
// takes the full 12-digit LRN (schools and enrollment years differ between
// students). Kept only so a "Remember me" value saved in the old 4-digit
// format can be expanded back into the full LRN on the login screen.
const String kLegacyLrnPrefix = kSchoolLrnPrefix;

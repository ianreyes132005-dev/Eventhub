import 'package:flutter/material.dart';

// ── App-wide palette ────────────────────────────────────────────────────────
// All screens import this file instead of redeclaring constants.

const Color kBackground    = Color(0xFFFBF6EA);
const Color kGold          = Color(0xFFD6A742);
const Color kGoldLight     = Color(0x22D6A742);
const Color kText          = Color(0xFF111827);
const Color kSubText       = Color(0xFF4B5563);
const Color kMuted         = Color(0xFF6B7280);

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

/// Total approved events, archived ones included: archiving hides an event
/// from everyday lists, it doesn't take it out of the organizer's history.
int totalApprovedEventCount(Iterable<Map<String, dynamic>> events) =>
    events.where(eventIsApproved).length;

/// Approved, non-archived events that are upcoming or on now by the clock,
/// soonest first (the admin dashboard's "Upcoming / Ongoing"). The stored
/// event_status only records a cancellation, so it can't be used for this.
List<Map<String, dynamic>> upcomingApprovedEvents(
  Iterable<Map<String, dynamic>> events, {
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final list = [
    for (final e in events)
      if (eventIsApproved(e) &&
          !eventIsArchived(e) &&
          const {'upcoming', 'ongoing'}.contains(eventStatusValue(e, now: at)))
        e,
  ];
  DateTime startOf(Map<String, dynamic> e) => eventWindow(e)?.start ?? DateTime(9999);
  list.sort((a, b) => startOf(a).compareTo(startOf(b)));
  return list;
}

/// Why students can (or can't) register right now.
enum RegistrationState { open, cancelled, ended, started, deadlinePassed, notApproved }

/// Registration stays open this long after the event starts (never past its
/// end). The database enforces the same: enforce_registration_insert_rules,
/// migration 202610210003.
const Duration kRegistrationClosesAfterStart = Duration(hours: 2);

/// When registration closes: the deadline when one is set; otherwise
/// [kRegistrationClosesAfterStart] after the start, or the end if that's
/// sooner. Null when the event has no valid date.
DateTime? registrationClosesAt(Map<String, dynamic> event) {
  final deadline = DateTime.tryParse(event['registration_deadline'] as String? ?? '');
  if (deadline != null) return deadline.toLocal();
  final w = eventWindow(event);
  if (w == null) return null;
  final close = w.start.add(kRegistrationClosesAfterStart);
  return close.isAfter(w.end) ? w.end : close;
}

/// Registration closes at the deadline when one is set; otherwise 2 hours
/// after the event starts (see [registrationClosesAt]). (Walk-in
/// registration was removed — `allow_walk_in` is a legacy column that's
/// always false and ignored here and server-side.)
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

  final hasDeadline = DateTime.tryParse(event['registration_deadline'] as String? ?? '') != null;
  final closes = registrationClosesAt(event);
  if (closes != null && !at.isBefore(closes)) {
    return hasDeadline ? RegistrationState.deadlinePassed : RegistrationState.started;
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
  RegistrationState.started        => 'Registration closed — it closes 2 hours after the event starts',
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

/// When check-in opens ([kCheckInOpensBefore] before the start) while that's
/// still ahead; null once it's open, after it closed, or for a cancelled event.
/// The organizer's scanner counts down to it.
DateTime? checkInOpensAt(Map<String, dynamic> event, {DateTime? now}) {
  if (eventIsCancelled(event)) return null;
  final w = eventWindow(event);
  if (w == null) return null;
  final opens = w.start.subtract(kCheckInOpensBefore);
  return (now ?? DateTime.now()).isBefore(opens) ? opens : null;
}

/// Check-in is open right now: not archived or cancelled, and inside the
/// window. Only then can a submitted selfie still be approved — the organizer
/// web's Registrations badge counts those.
bool checkInIsOpen(Map<String, dynamic> event, {DateTime? now}) =>
    !eventIsArchived(event) && checkInBlockedReason(event, now: now) == null;

/// Why an event nobody reviewed before it started was rejected. The database
/// saves the same text (reject_unreviewed_events, migration 202610210001) —
/// keep the two the same.
const String kNotReviewedInTimeReason =
    'Not reviewed by the admin before the event started.';

/// A pending event whose start time passed without an admin decision. It
/// can't be approved any more (trg_block_late_approval), so it counts as
/// rejected: the database rejects it automatically, and the app shows it as
/// rejected straight away.
bool pendingPastStart(Map<String, dynamic> event, {DateTime? now}) {
  if ((event['approval_status'] as String?) != 'pending') return false;
  final w = eventWindow(event);
  return w != null && !(now ?? DateTime.now()).isBefore(w.start);
}

/// The admin's decision as it stands: 'pending', 'approved' or 'rejected'.
/// No value is a legacy event, which is live (approved); a pending event that
/// reached its start counts as rejected ([pendingPastStart]).
String approvalStatusOf(Map<String, dynamic> event, {DateTime? now}) {
  if (pendingPastStart(event, now: now)) return 'rejected';
  return (event['approval_status'] as String? ?? 'approved').toLowerCase();
}

/// Why the event was rejected: the admin's reason, or
/// [kNotReviewedInTimeReason] for one nobody reviewed before it started.
String? rejectionReasonOf(Map<String, dynamic> event, {DateTime? now}) {
  final saved = (event['rejection_reason'] as String?)?.trim();
  if (saved != null && saved.isNotEmpty) return saved;
  return pendingPastStart(event, now: now) ? kNotReviewedInTimeReason : null;
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

/// The "Archived" colour (indigo) on organizer and admin screens.
const Color kArchivedColor = Color(0xFF6366F1);

/// Over for good: cancelled, or check-in has closed ([kCheckInClosesAfter]
/// after the end).
bool eventFinished(Map<String, dynamic> event, {DateTime? now}) {
  if (eventIsCancelled(event)) return true;
  final w = eventWindow(event);
  return w != null && (now ?? DateTime.now()).isAfter(w.end.add(kCheckInClosesAfter));
}

/// Where a finished event sits in the admin Archives tab.
///   archived  in the archives (records frozen, photos removed)
///   ready     an approved event with registrations: its attendance is a
///             record worth keeping, so it can be archived
///   empty     never approved, or nobody registered: nothing to keep, so it
///             is deleted instead of archived
enum ArchiveGroup { archived, ready, empty }

/// [registrations] counts every registration row, declined ones included
/// (they're part of the record). Null while the event isn't finished.
ArchiveGroup? archiveGroupOf(
  Map<String, dynamic> event, {
  required int registrations,
  DateTime? now,
}) {
  if (eventIsArchived(event)) return ArchiveGroup.archived;
  if (!eventFinished(event, now: now)) return null;
  return eventIsApproved(event) && registrations > 0
      ? ArchiveGroup.ready
      : ArchiveGroup.empty;
}

/// Can the admin archive it? An approved event with registrations that's
/// cancelled or whose check-in has closed — the same rule the database
/// enforces (event_archive_rules, migration 202610230003).
bool eventArchivable(
  Map<String, dynamic> event, {
  required int registrations,
  DateTime? now,
}) =>
    archiveGroupOf(event, registrations: registrations, now: now) == ArchiveGroup.ready;

// ── School years ─────────────────────────────────────────────────────────────
// The admin Archives group events by school year, not calendar year.

/// The month a school year starts (June: SY 2025–2026 runs June 2025 to May
/// 2026). Change it here if the school's calendar differs.
const int kSchoolYearStartMonth = DateTime.june;

/// The year a school year starts in, for a date in it.
int schoolYearOf(DateTime date) =>
    date.month >= kSchoolYearStartMonth ? date.year : date.year - 1;

/// The school year an event belongs to (by its start date), or null.
int? eventSchoolYear(Map<String, dynamic> event) {
  final d = DateTime.tryParse(event['event_date'] as String? ?? '');
  return d == null ? null : schoolYearOf(d);
}

/// "SY 2025–2026".
String schoolYearLabel(int startYear) => 'SY $startYear–${startYear + 1}';

// ── Organizer event actions ──────────────────────────────────────────────────
// What the organizer may do with one of their events — the same rules as the
// web Events table. The database enforces cancel / restore too
// (202610180006_event_cancellation.sql).

bool _eventHasEnded(Map<String, dynamic> event, DateTime at) {
  final w = eventWindow(event);
  return w != null && !at.isBefore(w.end);
}

/// Edit: upcoming or cancelled events — not ongoing, ended or archived. A
/// rejected event can always be edited, so it can be given a new date and
/// resubmitted even after its old start has passed (unreviewed events are
/// rejected right at their start).
bool organizerCanEditEvent(Map<String, dynamic> event) {
  if (eventIsArchived(event)) return false;
  if (approvalStatusOf(event) == 'rejected') return true;
  final status = eventStatusValue(event);
  return status != 'ongoing' && status != 'ended';
}

/// Delete: an event that never went live (pending or rejected) at any time;
/// an approved one only until it ends — after that it's part of the
/// attendance record. Never an archived one. Events with registrations are
/// refused separately, by the delete flow and the database
/// (block_event_delete_with_registrations).
bool organizerCanDeleteEvent(Map<String, dynamic> event, {DateTime? now}) {
  if (eventIsArchived(event)) return false;
  if (approvalStatusOf(event, now: now) != 'approved') return true;
  return eventStatusValue(event, now: now) != 'ended';
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

/// Event-aware approval label: a pending event that reached its start
/// without a decision shows as Rejected ([pendingPastStart]).
String approvalLabelFor(Map<String, dynamic> event) =>
    approvalStatusLabel(approvalStatusOf(event));

Color approvalColorFor(Map<String, dynamic> event) =>
    approvalStatusColor(approvalStatusOf(event));

/// The one status an organizer sees for an event in a list — the web Events
/// table's pill and the app's event-card chip use the same words and colours.
/// Most important first: Archived → Rejected → Pending review → Cancelled →
/// Check-in open → Ongoing / Ended / Upcoming. An event that isn't approved
/// never shows a schedule state; one nobody reviewed before it started is
/// Rejected ([approvalStatusOf]).
({String label, Color color}) organizerEventStatus(Map<String, dynamic> event) {
  final approval = approvalStatusOf(event);
  if (eventIsArchived(event)) return (label: 'Archived', color: kArchivedColor);
  if (approval == 'rejected') return (label: 'Rejected', color: const Color(0xFFEF4444));
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

/// Counts toward an event's "registered" number and attendance rate: every
/// registration except a declined one (status 'rejected'). The database
/// keeps events.current_participants the same way
/// (trg_maintain_participant_count, migration 202610230001).
bool countsAsRegistered(Map<String, dynamic> reg) =>
    (reg['status'] as String?) != 'rejected';

/// Organizers can delete a registration unless the student has checked in:
/// that's the attendance record. The database enforces the same
/// (organizer_delete_own_event_registrations, migration 202610230001).
bool registrationDeletable(Map<String, dynamic> reg) =>
    (reg['status'] as String?) != 'checked_in';

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

/// The school's LRN prefix: school ID 123456 + enrollment year 26. Student
/// sign-in takes the last 4 digits and adds this, and the admin's Add
/// Student fills it in the same way (a "Different LRN prefix?" link allows
/// the full 12 for other prefixes).
const String kSchoolLrnPrefix = '12345626';

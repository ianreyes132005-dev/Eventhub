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
const Color kMuted         = Color(0xFF9CA3AF);
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
  Color get muted    => dark ? const Color(0xFF7A6E55) : kMuted;
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
// Shared event lifecycle resolution for mobile and web status displays.

String eventStatusValue(Map<String, dynamic> event) {
  final stored = (event['event_status'] as String? ?? '').toLowerCase();
  if (stored == 'active') return 'ongoing';
  if (stored == 'cancelled') return 'cancelled';
  if (stored == 'completed' || stored == 'past' || stored == 'ended') {
    return 'ended';
  }

  final dateStr = event['event_date'] as String?;
  if (dateStr == null) return stored == 'ongoing' ? 'ongoing' : 'upcoming';

  try {
    final eventDate = DateTime.tryParse(dateStr);
    if (eventDate == null) {
      return stored == 'ongoing' ? 'ongoing' : 'upcoming';
    }
    final startDate = DateTime(eventDate.year, eventDate.month, eventDate.day);
    final endDateRaw = event['end_date'] as String?;
    final parsedEndDate = endDateRaw == null || endDateRaw.isEmpty
        ? eventDate
        : DateTime.tryParse(endDateRaw) ?? eventDate;
    final endDate = DateTime(
      parsedEndDate.year,
      parsedEndDate.month,
      parsedEndDate.day,
    );
    final startTime = _eventTime(event['start_time'] as String?, 8, 0);
    final endTime = _eventTime(event['end_time'] as String?, 23, 59, 59);
    final start = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
      startTime.$1,
      startTime.$2,
    );
    final end = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
      endTime.$1,
      endTime.$2,
      endTime.$3,
    );
    final now = DateTime.now();

    if (now.isBefore(start)) return 'upcoming';
    if (!now.isBefore(end)) return 'ended';
    return 'ongoing';
  } on RangeError {
    return stored == 'ongoing' ? 'ongoing' : 'upcoming';
  }
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

// ── LRN display formatter ────────────────────────────────────────────────────
// Formats a raw 12-digit LRN (e.g. "123456261234") → "123456 - 26 - 1234".
// Returns the input unchanged if it is not exactly 12 digits.
String formatLrn(String lrn) {
  final d = lrn.replaceAll(RegExp(r'\D'), '');
  if (d.length != 12) return lrn;
  return '${d.substring(0, 6)} - ${d.substring(6, 8)} - ${d.substring(8)}';
}

// The 8-digit school-code + enrollment-year prefix every student LRN must
// share. The student login screen only asks for the last 4 digits and
// rebuilds the rest from this constant, so any account created with a
// different prefix could never actually be logged into. Kept as the single
// shared source of truth between the login screen and admin account
// creation — if this ever needs to change (e.g. a new enrollment year),
// change it here only.
// NOTE: the `create-student` edge function (supabase/functions/create-student)
// enforces this same value server-side and must be kept in sync by hand,
// since edge functions run in a separate Deno runtime and can't import this file.
const String kRequiredLrnPrefix = '12345626';

import 'package:flutter/material.dart';

// ── Registration status (used in registrations lists / badges) ────────────────

String webStatusLabel(String? s) => switch (s) {
  'pending'         => 'Pending',
  'qr_scanned'      => 'QR Scanned',
  'photo_required'  => 'Awaiting Selfie',
  'photo_submitted' => 'Photo Submitted',
  'checked_in'      => 'Checked In',
  'rejected'        => 'Rejected',
  _                 => s ?? '—',
};

Color webStatusColor(String? s) => switch (s) {
  'pending'         => const Color(0xFF6B7280),
  'qr_scanned'      => const Color(0xFF3B82F6),
  'photo_required'  => const Color(0xFFF59E0B),
  'photo_submitted' => const Color(0xFF8B5CF6),
  'checked_in'      => const Color(0xFF10B981),
  'rejected'        => const Color(0xFFEF4444),
  _                 => const Color(0xFF9CA3AF),
};

// ── Event status (used in event lists) ───────────────────────────────────────

String webEventStatusLabel(String? s) => switch (s) {
  'upcoming'  => 'Upcoming',
  'ongoing'   => 'Ongoing',
  'completed' => 'Completed',
  'cancelled' => 'Cancelled',
  _           => s ?? '—',
};

Color webEventStatusColor(String? s) => switch (s) {
  'upcoming'  => const Color(0xFF3B82F6),
  'ongoing'   => const Color(0xFF10B981),
  'completed' => const Color(0xFF6B7280),
  'cancelled' => const Color(0xFFEF4444),
  _           => const Color(0xFF9CA3AF),
};

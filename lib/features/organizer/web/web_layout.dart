import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';

// ── Layout metrics ────────────────────────────────────────────────────────────
const kWebSideW  = 260.0;
const kWebSideWc = 76.0;
const kWebTopH   = 64.0;
const kWebPad    = 24.0;

// ── Sidebar palette ───────────────────────────────────────────────────────────
const kSideTop    = Color(0xFFF7F3E3);
const kSideMid    = Color(0xFFF3ECD8);
const kSideBot    = Color(0xFFEFE4CD);
const kSideBorder = Color(0xFFD4C9AD);

const kNavText = Color(0xFF3A3324);
const kNavIcon = Color(0xFF6B5E47);

const kSideGrad = LinearGradient(
  colors: [kSideTop, kSideMid, kSideBot],
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
);

// ── Content palette ───────────────────────────────────────────────────────────
const kWebBg      = Color(0xFFF0F3F7);
const kWebLightGold = Color(0xFFD4AA60);

// ── Navigation enum ───────────────────────────────────────────────────────────
enum OrganizerPage { dashboard, events, registrations, announcements, settings }

// ── Shared web-dashboard dark/light tokens ─────────────────────────────────────
// Used by BOTH the organizer and admin web dashboards, so the two render an
// identical dark theme — a cool graphite "SaaS dashboard" look (in the spirit
// of Linear/GitHub/Vercel), deliberately different from the warm espresso/gold
// AppTk dark mode used by the organizer/student MOBILE apps.
//
// Usage: `final t = WebTk(Theme.of(context).brightness == Brightness.dark);`
class WebTk {
  final bool dark;
  const WebTk(this.dark);

  Color get bg       => dark ? const Color(0xFF0B0D12) : kWebBg;
  Color get card     => dark ? const Color(0xFF12151B) : Colors.white;
  Color get border   => dark ? const Color(0xFF232833) : kCardBorder;
  Color get text     => dark ? const Color(0xFFE7EAEE) : kText;
  Color get sub      => dark ? const Color(0xFF9AA3B2) : kSubText;
  Color get muted    => dark ? const Color(0xFF666E7D) : kMuted;
  Color get divider  => dark ? const Color(0xFF1B1F27) : kCardBorder;
  Color get shadow   => dark
      ? Colors.black.withValues(alpha: 0.55)
      : Colors.black.withValues(alpha: 0.055);
  Color get inputBg  => dark ? const Color(0xFF0E1116) : Colors.white;
}

// ── Web input decoration helper ───────────────────────────────────────────────
// `dark` defaults to false. Both organizer and admin dashboards pass
// `dark: t.dark` explicitly when their own WebTk instance is dark.
InputDecoration webInputDeco(String hint, {IconData? icon, int? maxLines, bool dark = false}) =>
  InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
        color: dark ? const Color(0xFF666E7D) : kMuted),
    prefixIcon: icon != null
        ? Icon(icon, size: 18, color: dark ? const Color(0xFF666E7D) : kMuted)
        : null,
    alignLabelWithHint: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: dark ? const Color(0xFF232833) : kCardBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: dark ? const Color(0xFF232833) : kCardBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: kGold, width: 1.5),
    ),
    filled: true,
    fillColor: dark ? const Color(0xFF0E1116) : const Color(0xFFF8F9FC),
  );

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

// ── Web input decoration helper ───────────────────────────────────────────────
InputDecoration webInputDeco(String hint, {IconData? icon, int? maxLines}) =>
  InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: kMuted),
    prefixIcon: icon != null ? Icon(icon, size: 18, color: kMuted) : null,
    alignLabelWithHint: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: kCardBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: kCardBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: kGold, width: 1.5),
    ),
    filled: true,
    fillColor: const Color(0xFFF8F9FC),
  );

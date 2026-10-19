// ─────────────────────────────────────────────────────────────────────────────
// Shared pieces used by more than one admin tab page.
// Split out of admin_web_dashboard.dart so each tab's own file doesn't need
// to duplicate them. Everything here is public (no leading underscore)
// specifically so the per-tab files and the shell can all import it.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/friendly_error.dart';
import '../../core/services/supabase_service.dart';
import '../organizer/web/web_shared.dart';

// ─── Palette ──────────────────────────────────────────────────────────────────
const kAdminAccent = Color(0xFFEA580C); // orange

/// Confirm button for admin SweetAlert2 popups — kAdminAccent darkened so
/// white text passes WCAG AA (5.2:1).
const kAdminSwalConfirm = Color(0xFFC2410C);

/// A failed admin action as a SweetAlert2 error popup, in plain words
/// (database / network wording is translated by friendlyError).
Future<void> adminErrorAlert(
  BuildContext context,
  Object? error, {
  required String title,
  String fallback = FriendlyErrors.generic,
  SwalIcon icon = SwalIcon.error,
}) =>
    showErrorAlert(context, error,
        title: title, fallback: fallback, icon: icon,
        confirmButtonColor: kAdminSwalConfirm);

// ─── Navigation ───────────────────────────────────────────────────────────────
enum AdminPage { overview, students, organizers, events, registrations, announcements, archives, logs }

// ─── Dashboard-style KPI card ─────────────────────────────────────────────────
class AdminKpiCard extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String label, value, subtitle;
  final Color subtitleColor;
  final VoidCallback? onTap;

  const AdminKpiCard({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.subtitleColor,
    this.onTap,
  });

  @override
  State<AdminKpiCard> createState() => _AdminKpiCardState();
}

class _AdminKpiCardState extends State<AdminKpiCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hovered ? 1.016 : 1.0,
          duration: const Duration(milliseconds: 140),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: t.shadow,
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: t.card,
                  border: Border.all(color: t.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 3, color: widget.color),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 15, 18, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  widget.label,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 11.5,
                                    color: t.muted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: widget.color.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  widget.icon,
                                  color: widget.color,
                                  size: 18,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.value,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: t.text,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Divider(height: 1, color: t.border),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: widget.subtitleColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  widget.subtitle,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: widget.subtitleColor,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Stat card (full-width Expanded KPI tile) ──────────────────────────────────
// Shared by Students, Organizers, Events, Registrations and Announcements header rows.
class AdminStatCard extends StatelessWidget {
  final String   label, value;
  final Color    color;
  final IconData icon;
  const AdminStatCard({
    super.key,
    required this.label, required this.value,
    required this.color, required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: t.shadow,
              blurRadius: 8, offset: const Offset(0, 1))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: t.card,
              border: Border.all(color: t.border),
            ),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(width: 3, color: color),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                  child: Row(children: [
                    Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(icon, size: 17, color: color),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(value,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 20,
                              fontWeight: FontWeight.w800, color: t.text, height: 1.0)),
                        const SizedBox(height: 2),
                        Text(label,
                          style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
                              color: t.sub)),
                      ],
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Sortable table column header button ───────────────────────────────────────
// Shared by Students, Organizers, Events and Registrations table headers.
class AdminSortColBtn extends StatefulWidget {
  final String   label, field;
  final bool     active, asc;
  final void Function(String) onSort;
  const AdminSortColBtn({
    super.key,
    required this.label, required this.field,
    required this.active, required this.asc, required this.onSort});
  @override State<AdminSortColBtn> createState() => _AdminSortColBtnState();
}
class _AdminSortColBtnState extends State<AdminSortColBtn> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: () => widget.onSort(widget.field),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.label,
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 10.5,
              fontWeight: FontWeight.w700, letterSpacing: 0.8,
              color: widget.active ? kAdminAccent : _h ? t.text : t.sub,
            )),
          const SizedBox(width: 3),
          Icon(
            widget.active
                ? (widget.asc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded)
                : Icons.unfold_more_rounded,
            size: 11,
            color: widget.active ? kAdminAccent : _h ? t.sub : t.border,
          ),
        ]),
      ),
    );
  }
}

// ─── Shared time formatter (Events + Registrations) ────────────────────────────
String adminFmtIsoTime(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  try {
    final dt     = DateTime.parse(iso).toLocal();
    final h      = dt.hour;
    final m      = dt.minute;
    final period = h >= 12 ? 'PM' : 'AM';
    final h12    = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${m.toString().padLeft(2, '0')} $period';
  } catch (_) { return ''; }
}

// ─── Load-error state (Students, Organizers, Events, Registrations, Logs) ───
// Shows the ACTUAL error (message) when the caller has one — a network
// blip, a schema mismatch (e.g. a column a pending migration hasn't added
// yet), or a real RLS denial all look different and all need a different
// fix, so mislabeling every failure as "Permission Required" was actively
// misleading. Falls back to a generic hint only when a caller has no
// message to give (some pass '').
class AdminErrorState extends StatelessWidget {
  final String message; final VoidCallback onRetry;
  const AdminErrorState({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    final text = message.trim().isNotEmpty
        ? message.trim()
        : 'Check your internet connection and try again. If this keeps '
            'happening, contact the system administrator.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 68, height: 68,
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2), shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFFCA5A5), width: 1.5),
            ),
            child: const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 30),
          ),
          const SizedBox(height: 16),
          Text("Couldn't Load This Tab",
            style: TextStyle(fontFamily: 'Poppins', fontSize: 15,
                fontWeight: FontWeight.w700, color: t.text)),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            // Callers pass friendlyError(e) — never the raw database error.
            child: Text(text,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                  color: t.sub, height: 1.6),
              textAlign: TextAlign.center),
          ),
          const SizedBox(height: 20),
          WebBtn(label: 'Retry', icon: Icons.refresh_rounded, onTap: onRetry),
        ]),
      ),
    );
  }
}

// ─── Password strength bar ────────────────────────────────────────────────────
class AdminPasswordStrengthBar extends StatelessWidget {
  final String password;
  const AdminPasswordStrengthBar({super.key, required this.password});

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    if (password.isEmpty) return const SizedBox(height: 4);
    int score = 0;
    if (password.length >= 6)  score++;
    if (password.length >= 10) score++;
    if (RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[0-9]').hasMatch(password)) score++;

    const red   = Color(0xFFEF4444);
    const amber = Color(0xFFF59E0B);
    const green = Color(0xFF10B981);
    final color = score <= 1 ? red : score == 2 ? amber : green;
    final label = score == 0 ? 'Too short' : score == 1 ? 'Weak' : score == 2 ? 'Fair' : 'Strong';

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        for (int i = 0; i < 3; i++) ...[
          Expanded(child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            height: 3,
            decoration: BoxDecoration(
              color: i < score ? color : t.border,
              borderRadius: BorderRadius.circular(2),
            ),
          )),
          if (i < 2) const SizedBox(width: 4),
        ],
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 10,
            fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

// ─── Small icon action button (row-hover edit/toggle/delete actions) ───────────
// Shared by Students, Organizers, Events and Registrations row actions.
class AdminActBtn extends StatefulWidget {
  final IconData icon; final Color color; final String tip; final VoidCallback onTap;
  const AdminActBtn({super.key, required this.icon, required this.color, required this.tip, required this.onTap});
  @override State<AdminActBtn> createState() => _AdminActBtnState();
}
class _AdminActBtnState extends State<AdminActBtn> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _h = true),
        onExit:  (_) => setState(() => _h = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: _h ? 0.12 : 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.color.withValues(alpha: _h ? 0.28 : 0.14)),
            ),
            child: Icon(widget.icon, size: 16,
                color: widget.color.withValues(alpha: _h ? 1 : 0.88)),
          ),
        ),
      ),
    );
  }
}

// ─── Dialog header row (icon + title + close button) ───────────────────────────
class AdminDialogHeader extends StatelessWidget {
  final IconData icon; final Color iconColor; final String title;
  final String? subtitle;
  final bool    closeEnabled;
  const AdminDialogHeader({super.key, required this.icon, required this.iconColor,
      required this.title, this.subtitle, this.closeEnabled = true});

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return Row(children: [
      Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 19, color: iconColor),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
            style: TextStyle(fontFamily: 'Poppins', fontSize: 16,
                fontWeight: FontWeight.w800, color: t.text)),
          if (subtitle != null) ...[
            const SizedBox(height: 1),
            Text(subtitle!,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.sub)),
          ],
        ],
      )),
      Builder(builder: (ctx) => GestureDetector(
        onTap: closeEnabled ? () => Navigator.of(ctx).pop() : null,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: Colors.transparent, borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.close_rounded, size: 18, color: t.muted),
          ),
        ),
      )),
    ]);
  }
}

// ─── Shared dialog chrome (header + form body + buttons) ───────────────────────
// Used by both the Students and Organizers "Add/Edit" dialogs.
Widget adminDialogShell({
  required IconData  icon,
  required Color     iconColor,
  required String    title,
  required Widget    body,
  required String    confirmLabel,
  required Color     confirmColor,
  required VoidCallback? onConfirm,
  bool loading = false,
  String? subtitle,
}) {
  return Builder(builder: (context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 40, offset: const Offset(0, 14)),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.max, children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border))),
          child: AdminDialogHeader(icon: icon, iconColor: iconColor, title: title,
              subtitle: subtitle, closeEnabled: !loading),
        ),
        // Body (scrollable so tall content never overflows)
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: body,
          ),
        ),
        // Buttons
        Divider(height: 1, color: t.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: Row(children: [
            Expanded(
              child: Builder(builder: (ctx) => OutlinedButton(
                onPressed: loading ? null : () => Navigator.of(ctx).pop(),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: t.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: Text('Cancel',
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: t.sub)),
              )),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: loading ? null : onConfirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: confirmColor, foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: loading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(confirmLabel,
                      style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ]),
    );
  });
}

// ─── Form building blocks (Add/Edit Student & Organizer dialogs) ──────────────
// Labels above fields, errors inline under the field that caused them,
// server errors as a banner at the top of the dialog body.

const kAdminErrorRed = Color(0xFFEF4444);

Widget adminFormSection(String text, WebTk t) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: Text(text,
    style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5,
        fontWeight: FontWeight.w700, letterSpacing: 0.9, color: t.muted)),
);

Widget adminFormLabel(String text, WebTk t, {double bottom = 6, String? hint}) => Padding(
  padding: EdgeInsets.only(bottom: bottom),
  child: Text.rich(TextSpan(children: [
    TextSpan(text: text,
      style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
          fontWeight: FontWeight.w600, color: t.text)),
    if (hint != null)
      TextSpan(text: '  $hint',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
            fontWeight: FontWeight.w400, color: t.muted)),
  ])),
);

TextStyle adminInputStyle(WebTk t) =>
    TextStyle(fontFamily: 'Poppins', fontSize: 13, color: t.text);

InputDecoration adminFormDeco(String hint, WebTk t, {String? error}) =>
    webInputDeco(hint, dark: t.dark).copyWith(
      errorText: error,
      errorStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: kAdminErrorRed),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: kAdminErrorRed.withValues(alpha: 0.6)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kAdminErrorRed, width: 1.5),
      ),
      helperStyle: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted),
    );

// A fixed, non-typed prefix shown inside a field ("123456 - 26 -", "Org").
Widget adminFieldPrefix(String text, WebTk t) => Padding(
  padding: const EdgeInsets.only(left: 14, right: 6),
  child: Text(text,
    style: adminInputStyle(t).copyWith(color: t.muted,
        fontFeatures: const [FontFeature.tabularFigures()])),
);

Widget adminFormInlineError(String text, {double indent = 0}) => Padding(
  padding: EdgeInsets.only(top: 6, left: indent),
  child: Text(text,
    style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: kAdminErrorRed)),
);

class AdminFormErrorBanner extends StatelessWidget {
  final String text;
  const AdminFormErrorBanner(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: kAdminErrorRed.withValues(alpha: t.dark ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kAdminErrorRed.withValues(alpha: 0.30)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.error_outline_rounded, size: 16, color: kAdminErrorRed),
        const SizedBox(width: 8),
        Expanded(child: Text(text,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 12, height: 1.45,
              color: t.dark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C)))),
      ]),
    );
  }
}

// Locked value (e.g. LRN / Organizer ID in edit mode).
class AdminReadOnlyField extends StatelessWidget {
  final String value, lockMessage;
  const AdminReadOnlyField({super.key, required this.value, required this.lockMessage});

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: t.dark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.border),
      ),
      child: Row(children: [
        Expanded(child: Text(value, style: adminInputStyle(t).copyWith(color: t.sub))),
        Tooltip(
          message: lockMessage,
          child: Icon(Icons.lock_outline_rounded, size: 15, color: t.muted),
        ),
      ]),
    );
  }
}

// Trims and collapses spaces. Typed-all-lowercase / ALL-CAPS input is
// title-cased; mixed case ("dela Cruz", "McArthur") is kept as typed.
String adminCleanName(String raw) {
  final s = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (s != s.toLowerCase() && s != s.toUpperCase()) return s;
  return s.split(' ').map((w) => w.isEmpty
      ? w
      : w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
}

// 10 chars, always with an uppercase letter and a digit (rates "Strong");
// look-alike characters (0/O, 1/l/I) left out so it can be read aloud.
String adminGeneratePassword() {
  const upper  = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const lower  = 'abcdefghjkmnpqrstuvwxyz';
  const digits = '23456789';
  const all    = upper + lower + digits;
  final r = Random.secure();
  return ([
    upper[r.nextInt(upper.length)],
    digits[r.nextInt(digits.length)],
    for (var i = 0; i < 8; i++) all[r.nextInt(all.length)],
  ]..shuffle(r)).join();
}

// "Initial password" block: label + Generate, visible field with show/hide,
// strength bar, and a hand-over hint. State lives in the owning dialog.
// Also used for "New password" when an admin resets a password ([label] /
// [note] override the add-account wording).
class AdminInitialPasswordField extends StatelessWidget {
  final TextEditingController controller;
  final bool    hidden, enabled;
  final String? error;
  final String  recipient;          // "student" | "organizer"
  final Color   accent;
  final String  label;
  final String? note;               // hand-over hint; defaults to the add wording
  final bool    autofocus;
  final VoidCallback onToggleHidden, onGenerate, onSubmitted;
  final ValueChanged<String> onChanged;

  const AdminInitialPasswordField({
    super.key,
    required this.controller, required this.hidden, required this.enabled,
    required this.error, required this.recipient, required this.accent,
    required this.onToggleHidden, required this.onGenerate,
    required this.onSubmitted, required this.onChanged,
    this.label = 'Initial password', this.note, this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: adminFormLabel(label, t, bottom: 0)),
        TextButton.icon(
          onPressed: enabled ? onGenerate : null,
          icon: const Icon(Icons.auto_awesome_rounded, size: 14),
          label: const Text('Generate',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600)),
          style: TextButton.styleFrom(
            foregroundColor: accent,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 30),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ]),
      const SizedBox(height: 6),
      TextField(
        controller: controller,
        enabled: enabled,
        autofocus: autofocus,
        obscureText: hidden,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => onSubmitted(),
        onChanged: onChanged,
        style: adminInputStyle(t),
        decoration: adminFormDeco('At least 6 characters', t, error: error).copyWith(
          suffixIcon: IconButton(
            tooltip: hidden ? 'Show password' : 'Hide password',
            icon: Icon(hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                size: 18, color: t.muted),
            onPressed: onToggleHidden,
          ),
        ),
      ),
      AdminPasswordStrengthBar(password: controller.text),
      const SizedBox(height: 8),
      Text(note ?? 'Share this password with the $recipient — they can’t reset it themselves.',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted, height: 1.4)),
    ]);
  }
}

// ─── Reset password (Edit Student / Edit Organizer) ───────────────────────────
// Sets a new password through the admin-only `reset-password` Edge Function
// (changing another user's password needs the service-role key, which never
// ships in the app). [role] is 'student' (id = LRN) or 'organizer'
// (id = organizer_id). Returns null on success, else a message to show.
Future<String?> adminResetPassword({
  required String role,
  required String id,
  required String password,
}) async {
  try {
    final res = await SupabaseService.client.functions.invoke(
      'reset-password',
      body: {'role': role, 'id': id, 'password': password},
    );
    if (res.status == 200) return null;
    final body = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : null;
    final message = body?['message'] as String?;
    // Supabase answers 404 "Requested function was not found" when the
    // Edge Function was never deployed.
    if (res.status == 404 && (message == null || message.contains('function'))) {
      return 'The password reset service isn’t set up yet. '
          'Please contact the system administrator.';
    }
    return friendlyError(message,
        fallback: 'Couldn’t reset the password. Please try again.');
  } catch (e) {
    debugPrint('reset-password failed: $e');
    return friendlyError(e,
        fallback: 'Couldn’t reach the password reset service. Please try again.');
  }
}

// Collapsed state of the dialog's LOGIN section: the password itself is never
// shown, just a way to set a new one. Tapping Reset swaps this for an
// AdminInitialPasswordField labelled "New password".
class AdminResetPasswordPrompt extends StatelessWidget {
  final String recipient;           // "student" | "organizer"
  final Color  accent;
  final bool   enabled;
  final VoidCallback onReset;

  const AdminResetPasswordPrompt({
    super.key,
    required this.recipient, required this.accent,
    required this.enabled, required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: t.inputBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.border),
      ),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.lock_outline_rounded, size: 16, color: accent),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Password', style: TextStyle(fontFamily: 'Poppins',
                fontSize: 12.5, fontWeight: FontWeight.w600, color: t.text)),
            const SizedBox(height: 1),
            Text('Forgot it? Set a new one for the $recipient.',
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted)),
          ],
        )),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: enabled ? onReset : null,
          icon: const Icon(Icons.lock_reset_rounded, size: 15),
          label: const Text('Reset password',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
            foregroundColor: accent,
            side: BorderSide(color: accent.withValues(alpha: 0.45)),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 32),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ]),
    );
  }
}

// Shown instead of the reset prompt when the account has no login yet
// (user_id is null) — there is no password to reset.
class AdminNoLoginNote extends StatelessWidget {
  final String recipient;
  const AdminNoLoginNote({super.key, required this.recipient});

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.info_outline_rounded, size: 14, color: t.muted),
      const SizedBox(width: 6),
      Expanded(child: Text(
        'This $recipient has no login account yet, so there’s no password to reset.',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.muted, height: 1.4))),
    ]);
  }
}

// ─── Table pagination footer (Students / Organizers) ──────────────────────────
//   Showing 11–20 of 47 students            ‹ Previous  1 [2] 3 4 5  Next ›
// Page numbers collapse to 1 … 4 [5] 6 … 12 when there are many. Buttons are
// Material + InkWell so they get keyboard focus, Enter/Space and semantics.
const kAdminPageSize = 10;

class AdminPaginationBar extends StatelessWidget {
  final int    page;          // 0-based, already clamped by the caller
  final int    total;         // rows after filtering
  final int?   unfiltered;    // all rows, shown as "filtered from N" when set
  final String noun;          // "students", "organizers"
  final String? note;         // extra context, e.g. a load cap
  final int    pageSize;
  final ValueChanged<int> onPage;

  const AdminPaginationBar({
    super.key,
    required this.page, required this.total, required this.noun,
    required this.onPage, this.unfiltered, this.note,
    this.pageSize = kAdminPageSize,
  });

  int get pageCount => total == 0 ? 1 : (total + pageSize - 1) ~/ pageSize;

  // 1-based page numbers to show; null = ellipsis.
  List<int?> _pageItems() {
    final n = pageCount, cur = page + 1;
    if (n <= 7) return [for (var i = 1; i <= n; i++) i];
    final items = <int?>[1];
    final lo = (cur - 1).clamp(2, n - 1), hi = (cur + 1).clamp(2, n - 1);
    if (lo > 2) items.add(null);
    for (var i = lo; i <= hi; i++) { items.add(i); }
    if (hi < n - 1) items.add(null);
    items.add(n);
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final t     = WebTk(Theme.of(context).brightness == Brightness.dark);
    final first = total == 0 ? 0 : page * pageSize + 1;
    final last  = (page * pageSize + pageSize).clamp(0, total);
    final range = total <= pageSize ? '$total' : '$first–$last of $total';
    final from  = (unfiltered != null && unfiltered != total
        ? ' · filtered from $unfiltered' : '') + (note != null ? ' · $note' : '');

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: t.border))),
      child: Row(children: [
        Expanded(child: Text(
          total <= pageSize ? '$range $noun$from' : 'Showing $range $noun$from',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: t.muted))),
        if (pageCount > 1) ...[
          _PagerBtn(
            label: 'Previous', icon: Icons.chevron_left_rounded, leading: true,
            onTap: page > 0 ? () => onPage(page - 1) : null),
          const SizedBox(width: 4),
          for (final p in _pageItems())
            p == null
                ? SizedBox(width: 24, child: Center(child: Text('…',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.muted))))
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _PagerBtn(
                      label: '$p', selected: p == page + 1,
                      onTap: p == page + 1 ? null : () => onPage(p - 1)),
                  ),
          const SizedBox(width: 4),
          _PagerBtn(
            label: 'Next', icon: Icons.chevron_right_rounded,
            onTap: page < pageCount - 1 ? () => onPage(page + 1) : null),
        ],
      ]),
    );
  }
}

class _PagerBtn extends StatelessWidget {
  final String    label;
  final IconData? icon;
  final bool      leading, selected;
  final VoidCallback? onTap;
  const _PagerBtn({
    required this.label, this.icon, this.onTap,
    this.leading = false, this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final t       = WebTk(Theme.of(context).brightness == Brightness.dark);
    final enabled = onTap != null;
    final color   = selected ? kAdminAccent : enabled ? t.sub : t.muted.withValues(alpha: 0.5);
    final text = Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w600, color: color));
    return Semantics(
      button: true, selected: selected, enabled: enabled || selected,
      label: icon == null ? 'Page $label' : '$label page',
      excludeSemantics: true,
      child: Material(
        color: selected ? kAdminAccent.withValues(alpha: 0.10) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: selected ? kAdminAccent.withValues(alpha: 0.35) : Colors.transparent),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          hoverColor: kAdminAccent.withValues(alpha: 0.06),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: icon == null ? 6 : 8),
              child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                if (icon != null && leading) ...[Icon(icon, size: 16, color: color), const SizedBox(width: 2)],
                text,
                if (icon != null && !leading) ...[const SizedBox(width: 2), Icon(icon, size: 16, color: color)],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Filter menu trigger pill ─────────────────────────────────────────────────
//   [ ◉ Grade · All grades ▾ ]      active: [ ◉ Grade · Grade 8 ✕ ]
// Same padding, radius, border and palette as WebFilterChip so it sits flush
// with the status chips. Pair with a MenuAnchor (see adminFilterMenuStyle).
// Used by the Students (Grade) and Events (Organizer) filters.
class AdminFilterTrigger extends StatefulWidget {
  final IconData icon;
  final String   label;       // "Grade", "Organizer"
  final String   value;       // "All grades", "Maria Santos"
  final bool     active;      // a non-default value is selected
  final bool     open;        // the menu is open
  final double   maxValueWidth;
  final VoidCallback onTap, onClear;

  const AdminFilterTrigger({
    super.key,
    required this.icon, required this.label, required this.value,
    required this.active, required this.open,
    required this.onTap, required this.onClear,
    this.maxValueWidth = 180,
  });

  @override
  State<AdminFilterTrigger> createState() => _AdminFilterTriggerState();
}

class _AdminFilterTriggerState extends State<AdminFilterTrigger> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    const c = kAdminAccent;
    final active = widget.active;
    final lit    = _hovered || widget.open;
    final bg = active
        ? c.withValues(alpha: 0.08)
        : t.dark
            ? (lit ? const Color(0xFF1B2029) : const Color(0xFF171B22))
            : (lit ? const Color(0xFFEEF2F7) : const Color(0xFFF8F9FC));
    final border = active
        ? c.withValues(alpha: 0.35)
        : t.dark
            ? (lit ? const Color(0xFF2A3040) : const Color(0xFF232833))
            : (lit ? const Color(0xFFD1D5DB) : kCardBorder);

    return Semantics(
      button: true,
      label: '${widget.label} filter: ${widget.value}',
      child: Material(
        color: bg,
        shape: StadiumBorder(side: BorderSide(color: border, width: active ? 1.5 : 1.0)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onHover: (h) => setState(() => _hovered = h),
          hoverColor: Colors.transparent,
          splashColor: c.withValues(alpha: 0.06),
          child: Padding(
            padding: EdgeInsets.fromLTRB(10, 7, active ? 6 : 10, 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: c.withValues(alpha: active ? 0.18 : 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, size: 12, color: active ? c : t.muted),
              ),
              const SizedBox(width: 7),
              Text(widget.label,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                    fontWeight: FontWeight.w500, color: t.muted)),
              Text('  ·  ',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: t.muted)),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: widget.maxValueWidth),
                child: Text(widget.value,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                      color: active ? c : t.text)),
              ),
              const SizedBox(width: 6),
              if (active)
                // One-click clear without opening the menu.
                Tooltip(
                  message: 'Clear ${widget.label.toLowerCase()} filter',
                  child: InkWell(
                    onTap: widget.onClear,
                    customBorder: const CircleBorder(),
                    child: const Padding(
                      padding: EdgeInsets.all(3),
                      child: Icon(Icons.close_rounded, size: 14, color: c),
                    ),
                  ),
                )
              else
                AnimatedRotation(
                  turns: widget.open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: t.muted),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

// Card-surface dropdown panel shared by the admin filter menus.
MenuStyle adminFilterMenuStyle(WebTk t, {required double width, double maxHeight = 560}) =>
    MenuStyle(
      backgroundColor: WidgetStatePropertyAll(t.card),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(10),
      shadowColor: WidgetStatePropertyAll(
          Colors.black.withValues(alpha: t.dark ? 0.55 : 0.16)),
      padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
      minimumSize: WidgetStatePropertyAll(Size(width, 0)),
      maximumSize: WidgetStatePropertyAll(Size(width, maxHeight)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: t.border),
      )),
    );

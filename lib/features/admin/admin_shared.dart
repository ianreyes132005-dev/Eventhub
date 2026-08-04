// ─────────────────────────────────────────────────────────────────────────────
// Shared pieces used by more than one admin tab page.
// Split out of admin_web_dashboard.dart so each tab's own file doesn't need
// to duplicate them. Everything here is public (no leading underscore)
// specifically so the per-tab files and the shell can all import it.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../organizer/web/web_shared.dart';

// ─── Palette ──────────────────────────────────────────────────────────────────
const kAdminAccent = Color(0xFFEA580C); // orange

// ─── Navigation ───────────────────────────────────────────────────────────────
enum AdminPage { overview, students, organizers, events, registrations, announcements, logs }

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
    final hasDetail = message.trim().isNotEmpty;
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
            child: SelectableText(
              hasDetail
                  ? message
                  : 'Run the admin RLS policies SQL in Supabase to grant\nthe admin account read access to this table.',
              style: TextStyle(fontFamily: hasDetail ? 'monospace' : 'Poppins',
                  fontSize: hasDetail ? 11.5 : 12,
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

// ─── Credential preview chip (live login-ID display in add dialogs) ──────────
class AdminCredentialPreview extends StatelessWidget {
  final String username;
  final bool   isReady;
  const AdminCredentialPreview({super.key, required this.username, required this.isReady});

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: isReady
            ? (t.dark
                ? const Color(0xFF10B981).withValues(alpha: 0.12)
                : const Color(0xFFF0FDF4))
            : t.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isReady
              ? const Color(0xFF10B981).withValues(alpha: 0.35)
              : t.border,
        ),
      ),
      child: Row(children: [
        Icon(Icons.login_rounded, size: 13,
            color: isReady ? const Color(0xFF10B981) : t.muted),
        const SizedBox(width: 8),
        Text('Login ID ',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: t.sub)),
        Text(username,
          style: TextStyle(
            fontFamily: 'Poppins', fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: isReady ? const Color(0xFF10B981) : t.muted,
          )),
      ]),
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

// ─── Info note box used inside dialogs ─────────────────────────────────────────
class AdminInfoNote extends StatelessWidget {
  final String text;
  const AdminInfoNote(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.inputBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF0EA5E9).withValues(alpha: 0.25)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline_rounded, size: 15, color: Color(0xFF0EA5E9)),
        const SizedBox(width: 8),
        Expanded(child: Text(text,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 11,
              color: t.dark ? const Color(0xFF7DD3FC) : const Color(0xFF0369A1),
              height: 1.5))),
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
    final t = WebTk(Theme.of(context).brightness == Brightness.dark);
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
              color: _h ? widget.color.withValues(alpha: 0.10) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _h ? widget.color.withValues(alpha: 0.25) : Colors.transparent),
            ),
            child: Icon(widget.icon, size: 16,
                color: _h ? widget.color : t.muted.withValues(alpha: 0.70)),
          ),
        ),
      ),
    );
  }
}

// ─── Dialog header row (icon + title + close button) ───────────────────────────
class AdminDialogHeader extends StatelessWidget {
  final IconData icon; final Color iconColor; final String title;
  const AdminDialogHeader({super.key, required this.icon, required this.iconColor, required this.title});

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
      Expanded(child: Text(title,
        style: TextStyle(fontFamily: 'Poppins', fontSize: 16,
            fontWeight: FontWeight.w800, color: t.text))),
      Builder(builder: (ctx) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
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
          child: AdminDialogHeader(icon: icon, iconColor: iconColor, title: title),
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

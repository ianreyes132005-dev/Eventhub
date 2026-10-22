import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';

// The shared look of the organizer app's list tabs (Events, Registrations):
// the header, search field, pinned filter chips, buttons and the empty /
// error message. Purely visual — each tab keeps its own data, filters and
// actions and hands them in, so the two tabs always look like one app.

/// Text and icons on a gold fill. White on kGold is only 2.2:1; this ink
/// reads 7.8:1.
const Color kOnGold = Color(0xFF211A0D);

/// Gold for small text and icons: kGold on dark surfaces, a deeper gold on
/// light ones (kGold on white is only 2.1:1).
Color goldText(AppTk t) => t.dark ? kGold : const Color(0xFF8A6516);

/// The filter bar's height — a 48 px tap row with 4 px above and below.
const double kOrgFilterBarHeight = 56;

ButtonStyle _primaryStyle() => FilledButton.styleFrom(
      backgroundColor: kGold,
      foregroundColor: kOnGold,
      minimumSize: const Size(0, 46),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(
          fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700),
    );

ButtonStyle _secondaryStyle(AppTk t) => OutlinedButton.styleFrom(
      foregroundColor: t.text,
      minimumSize: const Size(0, 46),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      side: BorderSide(color: orgOutlineColor(t), width: 1.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(
          fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700),
    );

/// The border of [OrgSecondaryButton] and other outlined controls.
Color orgOutlineColor(AppTk t) =>
    t.dark ? const Color(0xFF4A3F2C) : const Color(0xFFE2D8C3);

/// The tab's main call to action, in gold.
class OrgPrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  const OrgPrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        onPressed: onPressed,
        style: _primaryStyle(),
        icon: Icon(icon, size: 18),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
}

/// A quieter, outlined action next to [OrgPrimaryButton].
class OrgSecondaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final AppTk t;
  const OrgSecondaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.t,
  });

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onPressed,
        style: _secondaryStyle(t),
        icon: Icon(icon, size: 18, color: t.sub),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
}

// ── Header ──────────────────────────────────────────────────────────────────

/// A tab's title with the gold accent bar, and an optional action on the right.
class OrgTabHeader extends StatelessWidget {
  final String title;
  final Widget? action;
  final AppTk t;
  const OrgTabHeader({
    super.key,
    required this.title,
    required this.t,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Row(
        children: [
          // Gold accent bar — the same header on every organizer tab.
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFC49230), kGold, Color(0xFFEAB866)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: t.text,
                height: 1.15,
              ),
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 12),
            action!,
          ],
        ],
      ),
    );
  }
}

// ── Search ──────────────────────────────────────────────────────────────────

class OrgSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final AppTk t;
  const OrgSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onClear,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: w),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: t.text),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              fontFamily: 'Poppins', fontSize: 13.5, color: t.muted),
          prefixIcon: Icon(Icons.search_rounded, color: t.muted, size: 22),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  tooltip: 'Clear search',
                  icon: Icon(Icons.cancel_rounded, color: t.muted, size: 20),
                  onPressed: onClear,
                )
              : null,
          filled: true,
          fillColor: t.card,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: border(t.border, 1.2),
          enabledBorder: border(t.border, 1.2),
          focusedBorder: border(kGold, 1.6),
        ),
      ),
    );
  }
}

// ── Filter bar ──────────────────────────────────────────────────────────────

/// Pins an [OrgFilterBar] under the search field while the list scrolls.
class OrgFilterBarDelegate extends SliverPersistentHeaderDelegate {
  /// Builds the bar; `scrolled` is true once cards pass underneath it.
  final Widget Function(bool scrolled) builder;
  const OrgFilterBarDelegate(this.builder);

  @override
  double get minExtent => kOrgFilterBarHeight;
  @override
  double get maxExtent => kOrgFilterBarHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      builder(shrinkOffset > 0 || overlapsContent);

  @override
  bool shouldRebuild(covariant OrgFilterBarDelegate oldDelegate) => true;
}

/// A row of filter chips with counts — the same colours as the web filters:
/// the selected one tinted with [accent] (gold for status).
class OrgFilterBar extends StatelessWidget {
  final List<String> options;
  final String selected;
  final int Function(String option) countFor;
  final ValueChanged<String> onSelect;
  final bool scrolled;

  /// The selected chip's colour.
  final Color accent;

  /// On every chip in place of the selected dot, e.g. an event icon.
  final IconData? icon;

  /// What a chip says for an option (defaults to the option itself).
  final String Function(String option)? labelFor;

  /// Long labels (event titles) end with "…" past this width.
  final double? maxLabelWidth;

  final AppTk t;
  const OrgFilterBar({
    super.key,
    required this.options,
    required this.selected,
    required this.countFor,
    required this.onSelect,
    required this.t,
    this.scrolled = false,
    this.accent = kGold,
    this.icon,
    this.labelFor,
    this.maxLabelWidth,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: kOrgFilterBarHeight,
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(
          bottom: BorderSide(
            color: scrolled ? t.border : t.border.withValues(alpha: 0),
          ),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final f = options[i];
          return _FilterChip(
            label: labelFor?.call(f) ?? f,
            count: countFor(f),
            selected: f == selected,
            onTap: () => onSelect(f),
            accent: accent,
            icon: icon,
            maxLabelWidth: maxLabelWidth,
            t: t,
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;
  final IconData? icon;
  final double? maxLabelWidth;
  final AppTk t;
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    required this.accent,
    required this.icon,
    required this.maxLabelWidth,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    // The same colors as the web filters: the selected one in the accent.
    Widget text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: 'Poppins',
        fontSize: 13,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? accent : t.sub,
        letterSpacing: selected ? 0.1 : 0,
      ),
    );
    if (maxLabelWidth != null) {
      text = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxLabelWidth!),
        child: text,
      );
    }
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $count',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque, // the whole 48 px row is tappable
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            height: 36,
            padding: EdgeInsets.only(left: selected || icon != null ? 12 : 14, right: 8),
            decoration: BoxDecoration(
              color: selected ? accent.withValues(alpha: 0.08) : t.inputBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? accent.withValues(alpha: 0.35) : t.border,
                width: selected ? 1.5 : 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: selected ? accent : t.muted),
                  const SizedBox(width: 6),
                ] else if (selected) ...[
                  // Status dot — only on the selected filter.
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                text,
                const SizedBox(width: 6),
                Container(
                  constraints: const BoxConstraints(minWidth: 22),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected ? accent.withValues(alpha: 0.15) : t.divider,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected ? accent : t.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Empty / error message ───────────────────────────────────────────────────

class OrgMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  /// Red tint for errors; gold otherwise.
  final bool isError;
  final AppTk t;
  const OrgMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.t,
    this.action,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    final tint = isError
        ? (t.dark ? const Color(0xFFF87171) : const Color(0xFFDC2626))
        : goldText(t);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 34, color: tint),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 16.5,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: t.muted,
              height: 1.55,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 22),
            action!,
          ],
        ],
      ),
    );
  }
}

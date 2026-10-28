import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'web_nav_badge.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The web portals' sidebar (organizer and admin): links in titled groups,
// always open beside the page, and a drawer on narrow windows.
//
//   (logo) J-Jireh            ← "Organizer portal" / "Admin console"
//   ▣ Dashboard
//   MANAGE                    ← group title
//   ▣ Events
//   ▣ Registrations   3       ← WebNavBadge
//   …
//
// Every link is keyboard-reachable (Tab, Enter or Space) with a focus ring,
// and tells screen readers which page is open.
// ─────────────────────────────────────────────────────────────────────────────

/// Narrower than this, the sidebar is a drawer behind a menu button; wider,
/// it's always open beside the page.
const kWebNavDrawerMax = 1024.0;

bool webNavUsesDrawer(double width) => width < kWebNavDrawerMax;

/// The sidebar's colours — each portal makes its own (organizer gold, admin
/// orange; light or dark).
class WebNavPalette {
  final Gradient background;
  final Color border;
  /// Link text on hover, and the wordmark.
  final Color text;
  /// The open page's label.
  final Color activeText;
  /// Links at rest (icon and label).
  final Color icon;
  /// Group titles and the portal name.
  final Color label;
  final Color hover;
  /// The open page's tint and outline.
  final Color accent;
  /// The open page's icon — dark enough to read on its tint.
  final Color accentStrong;
  /// The keyboard focus ring.
  final Color focus;

  const WebNavPalette({
    required this.background,
    required this.border,
    required this.text,
    required this.activeText,
    required this.icon,
    required this.label,
    required this.hover,
    required this.accent,
    required this.accentStrong,
    required this.focus,
  });
}

/// One sidebar link to a page. [badge] > 0 shows a [WebNavBadge];
/// [badgeTip] says what it counts.
class WebNavEntry<T> {
  final T page;
  final IconData icon;
  final String label;
  final int badge;
  final String? badgeTip;

  const WebNavEntry({
    required this.page,
    required this.icon,
    required this.label,
    this.badge = 0,
    this.badgeTip,
  });
}

/// Links under one title, e.g. MANAGE. No [title]: links without a heading
/// (Dashboard, at the top).
class WebNavGroup<T> {
  final String? title;
  final List<WebNavEntry<T>> entries;

  const WebNavGroup({this.title, required this.entries});
}

class WebSideNav<T> extends StatelessWidget {
  /// Under the wordmark: "Organizer portal" or "Admin console".
  final String portalLabel;
  final WebNavPalette palette;
  final List<WebNavGroup<T>> groups;
  final T current;
  final ValueChanged<T> onSelect;

  /// Shown in the drawer: a close button, and Esc closes too.
  final VoidCallback? onClose;

  /// Shown when the school logo can't load.
  final IconData logoFallbackIcon;

  /// The header's height — the same as the portal's top bar.
  final double headerHeight;

  const WebSideNav({
    super.key,
    required this.portalLabel,
    required this.palette,
    required this.groups,
    required this.current,
    required this.onSelect,
    this.onClose,
    this.logoFallbackIcon = Icons.celebration_rounded,
    this.headerHeight = 64,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    Widget nav = Container(
      decoration: BoxDecoration(
        gradient: p.background,
        border: Border(right: BorderSide(color: p.border)),
      ),
      child: Column(
        children: [
          _header(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              children: [
                for (var i = 0; i < groups.length; i++) ..._group(groups[i], first: i == 0),
              ],
            ),
          ),
        ],
      ),
    );
    final close = onClose;
    if (close != null) {
      nav = CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
        child: FocusScope(autofocus: true, child: nav),
      );
    }
    return Semantics(container: true, label: 'Main navigation', child: nav);
  }

  Widget _header() {
    final p = palette;
    return Container(
      height: headerHeight,
      padding: const EdgeInsets.only(left: 18, right: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.border.withValues(alpha: 0.6))),
      ),
      child: Row(
        children: [
          _logo(38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'J-Jireh',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Playball',
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    color: p.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  portalLabel.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.9,
                    color: p.label,
                  ),
                ),
              ],
            ),
          ),
          if (onClose != null)
            IconButton(
              onPressed: onClose,
              tooltip: 'Close menu',
              icon: Icon(Icons.close_rounded, size: 20, color: p.icon),
            ),
        ],
      ),
    );
  }

  Widget _logo(double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: palette.accent.withValues(alpha: 0.45), width: 2),
    ),
    child: ClipOval(
      child: Image.asset(
        'assets/logo.jpg',
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => ColoredBox(
          color: palette.accent,
          child: Icon(logoFallbackIcon, color: Colors.white, size: size * 0.44),
        ),
      ),
    ),
  );

  List<Widget> _group(WebNavGroup<T> group, {required bool first}) {
    final p = palette;
    final title = group.title;
    return [
      if (!first) const SizedBox(height: 14),
      if (title != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Semantics(
            header: true,
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.9,
                color: p.label,
              ),
            ),
          ),
        ),
      for (final e in group.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: _NavTile(
            icon: e.icon,
            label: e.label,
            badge: e.badge,
            badgeTip: e.badgeTip,
            active: e.page == current,
            palette: p,
            onTap: () => onSelect(e.page),
          ),
        ),
    ];
  }
}

// A sidebar link: focusable, Enter or Space opens it, with a ring for
// keyboard focus.
class _NavTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final int badge;
  final String? badgeTip;
  final bool active;
  final WebNavPalette palette;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.label,
    required this.palette,
    required this.onTap,
    this.badge = 0,
    this.badgeTip,
    this.active = false,
  });

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hover = false;
  bool _focus = false;

  String get _badgeText =>
      widget.badge > 0 && widget.badgeTip != null ? widget.badgeTip! : '';

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final active = widget.active;
    final fg = active ? p.activeText : (_hover ? p.text : p.icon);
    final radius = BorderRadius.circular(10);
    final showBadge = widget.badge > 0;

    final icon = Icon(widget.icon, size: 19, color: active ? p.accentStrong : fg);
    Widget tile = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: active
            ? p.accent.withValues(alpha: 0.14)
            : _hover
                ? p.hover
                : Colors.transparent,
        borderRadius: radius,
        border: Border.all(
          color: active ? p.accent.withValues(alpha: 0.34) : Colors.transparent,
        ),
      ),
      foregroundDecoration: _focus
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: p.focus, width: 2),
            )
          : null,
      child: Row(
        children: [
          icon,
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: fg,
              ),
            ),
          ),
          if (showBadge) WebNavBadge(count: widget.badge),
        ],
      ),
    );

    if (_badgeText.isNotEmpty) {
      tile = Tooltip(
        message: _badgeText,
        waitDuration: const Duration(milliseconds: 300),
        child: tile,
      );
    }

    // One node for screen readers: the label (with what the badge counts),
    // selected on the open page, and the tap and focus actions from the
    // detectors below — the tile's own text is left out so it isn't read
    // twice.
    return Semantics(
      container: true,
      button: true,
      selected: active,
      label: _badgeText.isEmpty ? widget.label : '${widget.label}, $_badgeText',
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            widget.onTap();
            return null;
          }),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: ExcludeSemantics(child: tile),
        ),
      ),
    );
  }
}

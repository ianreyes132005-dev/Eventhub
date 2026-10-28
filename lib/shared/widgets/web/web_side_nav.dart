import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'web_nav_badge.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The web portals' sidebar (organizer and admin): links in titled groups,
// an icon rail when collapsed, and a drawer on narrow windows.
//
//   (logo) J-Jireh            ← "Organizer portal" / "Admin console"
//   ▣ Dashboard
//   MANAGE                    ← group title
//   ▣ Events
//   ▣ Registrations   3       ← WebNavBadge
//   …
//   « Collapse                ← remembered per browser (WebNavPrefs)
//
// Every link is keyboard-reachable (Tab, Enter or Space) with a focus ring,
// and tells screen readers which page is open.
// ─────────────────────────────────────────────────────────────────────────────

/// Narrower than this, the sidebar is a drawer behind a menu button…
const kWebNavDrawerMax = 1024.0;

/// …from there to this width it starts as an icon rail; wider, it starts
/// open. Either way the « button switches it, and the choice is remembered.
const kWebNavWideMin = 1280.0;

/// How the sidebar shows at the window's width.
enum WebNavLayout { drawer, medium, wide }

WebNavLayout webNavLayoutFor(double width) => width < kWebNavDrawerMax
    ? WebNavLayout.drawer
    : width < kWebNavWideMin
        ? WebNavLayout.medium
        : WebNavLayout.wide;

/// Remembers, per browser and portal, whether the sidebar was left
/// collapsed — separately on wide and medium windows, since medium starts
/// collapsed.
class WebNavPrefs {
  WebNavPrefs._();

  static String _key(String portal, WebNavLayout layout) =>
      'web_nav_collapsed_${portal}_${layout.name}';

  static Future<({bool wide, bool medium})> load(String portal) async {
    final prefs = await SharedPreferences.getInstance();
    return (
      wide: prefs.getBool(_key(portal, WebNavLayout.wide)) ?? false,
      medium: prefs.getBool(_key(portal, WebNavLayout.medium)) ?? true,
    );
  }

  static Future<void> save(String portal, WebNavLayout layout, bool collapsed) async {
    if (layout == WebNavLayout.drawer) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(portal, layout), collapsed);
  }
}

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

  /// An icon rail: labels move into tooltips.
  final bool collapsed;

  /// The « Collapse / » Expand button; none in the drawer.
  final VoidCallback? onToggleCollapse;

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
    this.collapsed = false,
    this.onToggleCollapse,
    this.onClose,
    this.logoFallbackIcon = Icons.celebration_rounded,
    this.headerHeight = 64,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final pad = collapsed ? 10.0 : 12.0;
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
              padding: EdgeInsets.fromLTRB(pad, 10, pad, 10),
              children: [
                for (var i = 0; i < groups.length; i++) ..._group(groups[i], first: i == 0),
              ],
            ),
          ),
          if (onToggleCollapse != null)
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 4, pad, 12),
              child: _NavTile(
                icon: collapsed
                    ? Icons.keyboard_double_arrow_right_rounded
                    : Icons.keyboard_double_arrow_left_rounded,
                label: 'Collapse',
                tooltip: 'Expand sidebar',
                semanticLabel: collapsed ? 'Expand sidebar' : 'Collapse sidebar',
                collapsed: collapsed,
                outlined: true,
                palette: p,
                onTap: onToggleCollapse!,
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
      padding: collapsed ? EdgeInsets.zero : const EdgeInsets.only(left: 18, right: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.border.withValues(alpha: 0.6))),
      ),
      alignment: collapsed ? Alignment.center : Alignment.centerLeft,
      child: collapsed
          ? _logo(36)
          : Row(
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
      if (!first)
        collapsed
            // The rail has no room for titles: a line between groups.
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1, color: p.border.withValues(alpha: 0.7)),
              )
            : const SizedBox(height: 14),
      if (title != null && !collapsed)
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
            collapsed: collapsed,
            palette: p,
            onTap: () => onSelect(e.page),
          ),
        ),
    ];
  }
}

// A sidebar link (or the « Collapse button): focusable, Enter or Space
// opens it, with a ring for keyboard focus. Collapsed, the label is a
// tooltip, which also shows on keyboard focus.
class _NavTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final int badge;
  final String? badgeTip;
  final bool active;
  final bool collapsed;
  final bool outlined;
  /// The collapsed tooltip, when it isn't the label.
  final String? tooltip;
  final String? semanticLabel;
  final WebNavPalette palette;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.label,
    required this.collapsed,
    required this.palette,
    required this.onTap,
    this.badge = 0,
    this.badgeTip,
    this.active = false,
    this.outlined = false,
    this.tooltip,
    this.semanticLabel,
  });

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hover = false;
  bool _focus = false;
  final _tip = GlobalKey<TooltipState>();

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
      padding: widget.collapsed ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: active
            ? p.accent.withValues(alpha: 0.14)
            : _hover
                ? p.hover
                : Colors.transparent,
        borderRadius: radius,
        border: Border.all(
          color: active
              ? p.accent.withValues(alpha: 0.34)
              : widget.outlined
                  ? p.border
                  : Colors.transparent,
        ),
      ),
      foregroundDecoration: _focus
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: p.focus, width: 2),
            )
          : null,
      child: widget.collapsed
          ? Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  icon,
                  if (showBadge)
                    Positioned(top: -8, right: -12, child: WebNavBadge(count: widget.badge)),
                ],
              ),
            )
          : Row(
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

    if (widget.collapsed) {
      final tip = widget.tooltip ??
          (_badgeText.isEmpty ? widget.label : '${widget.label} · $_badgeText');
      tile = Tooltip(
        key: _tip,
        message: tip,
        positionDelegate: _besideTile,
        waitDuration: const Duration(milliseconds: 300),
        child: tile,
      );
    } else if (_badgeText.isNotEmpty) {
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
      label: widget.semanticLabel ??
          (_badgeText.isEmpty ? widget.label : '${widget.label}, $_badgeText'),
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) {
          setState(() => _focus = v);
          if (v && widget.collapsed) _tip.currentState?.ensureTooltipVisible();
        },
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

// Rail tooltips sit beside the icon, centred on it, rather than above or
// below it where they would cover the next icon.
Offset _besideTile(TooltipPositionContext c) {
  final maxY = c.overlaySize.height - c.tooltipSize.height;
  return Offset(
    c.target.dx + c.targetSize.width / 2 + 12,
    (c.target.dy - c.tooltipSize.height / 2).clamp(0.0, maxY > 0 ? maxY : 0.0),
  );
}

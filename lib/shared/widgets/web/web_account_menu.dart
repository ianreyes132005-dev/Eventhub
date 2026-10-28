import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The web portals' account menu, top right: the signed-in person's photo
// and name open
//
//   (photo) Name / Organizer
//   ──────────────
//   Dark mode          [◐]   ← a switch; the menu stays open
//   ──────────────
//   Sign out                 ← red, asks first
//
// Both portals show just these two; Profile has its own sidebar link.
//
// Built on MenuAnchor, so the arrow keys move through it and Esc closes it.
// ─────────────────────────────────────────────────────────────────────────────

// The open menu's width. Fixed so the menu can line up with the button's
// right edge; MenuAnchor would otherwise push it against the window's edge.
const _kMenuWidth = 260.0;
const _kMenuPad = 6.0;

/// One account menu row. [toggled] non-null shows a switch on the right
/// (Dark mode) and keeps the menu open when chosen; [danger] is the red
/// Sign out, set apart by a line.
class WebAccountAction {
  final IconData icon;
  final String label;
  final VoidCallback onSelected;
  final bool? toggled;
  final bool danger;

  const WebAccountAction({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.toggled,
    this.danger = false,
  });
}

class WebAccountMenu extends StatelessWidget {
  final String name;

  /// Under the name in the menu: "Organizer" / "Administrator".
  final String role;
  final Widget avatar;
  final List<WebAccountAction> actions;

  /// The portal's accent, for the switch.
  final Color accent;

  /// Narrow windows: the photo only.
  final bool compact;

  const WebAccountMenu({
    super.key,
    required this.name,
    required this.role,
    required this.avatar,
    required this.actions,
    required this.accent,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final card = dark ? const Color(0xFF12151B) : Colors.white;
    final border = dark ? const Color(0xFF232833) : kCardBorder;
    final text = dark ? const Color(0xFFE7EAEE) : kText;
    final muted = dark ? const Color(0xFF9AA3B2) : kMuted;
    final danger = dark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
    final hover = dark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF1F5F9);

    MenuItemButton item(WebAccountAction a) {
      final color = a.danger ? danger : text;
      return MenuItemButton(
        closeOnActivate: a.toggled == null,
        onPressed: a.onSelected,
        leadingIcon: Icon(a.icon, size: 18, color: a.danger ? danger : muted),
        trailingIcon: a.toggled == null
            ? null
            : ExcludeFocus(
                child: IgnorePointer(
                  child: Transform.scale(
                    scale: 0.8,
                    child: Switch(
                      value: a.toggled!,
                      onChanged: (_) {},
                      activeThumbColor: Colors.white,
                      activeTrackColor: accent,
                    ),
                  ),
                ),
              ),
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
          foregroundColor: WidgetStatePropertyAll(color),
          overlayColor: WidgetStatePropertyAll(hover),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
        child: Text(a.label),
      );
    }

    return MenuAnchor(
      // Under the button, right edges lined up.
      alignmentOffset: const Offset(-_kMenuWidth, 8),
      style: MenuStyle(
        alignment: AlignmentDirectional.bottomEnd,
        backgroundColor: WidgetStatePropertyAll(card),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(10),
        shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.30)),
        side: WidgetStatePropertyAll(BorderSide(color: border)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(_kMenuPad)),
      ),
      menuChildren: [
        SizedBox(
          width: _kMenuWidth - 2 * _kMenuPad,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Row(
                  children: [
                    avatar,
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: text,
                            ),
                          ),
                          Text(
                            role,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 11.5, color: muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: border),
              const SizedBox(height: 4),
              for (final a in actions) ...[
                if (a.danger) Divider(height: 9, color: border),
                item(a),
              ],
            ],
          ),
        ),
      ],
      builder: (context, controller, _) => _AccountButton(
        name: name,
        avatar: avatar,
        compact: compact,
        open: controller.isOpen,
        textColor: text,
        mutedColor: muted,
        borderColor: border,
        hoverColor: hover,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

class _AccountButton extends StatelessWidget {
  final String name;
  final Widget avatar;
  final bool compact;
  final bool open;
  final Color textColor;
  final Color mutedColor;
  final Color borderColor;
  final Color hoverColor;
  final VoidCallback onTap;

  const _AccountButton({
    required this.name,
    required this.avatar,
    required this.compact,
    required this.open,
    required this.textColor,
    required this.mutedColor,
    required this.borderColor,
    required this.hoverColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // One node for screen readers: "Account menu, <name>", a button that says
    // whether the menu is open; the photo and name inside aren't read again.
    return Semantics(
      container: true,
      button: true,
      expanded: open,
      label: 'Account menu, $name',
      child: Tooltip(
        message: 'Account',
        excludeFromSemantics: true,
        waitDuration: const Duration(milliseconds: 600),
        child: Material(
          color: open ? hoverColor : Colors.transparent,
          shape: StadiumBorder(side: BorderSide(color: borderColor)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            hoverColor: hoverColor,
            child: ExcludeSemantics(
              child: Padding(
                padding: EdgeInsets.fromLTRB(4, 4, compact ? 4 : 10, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    avatar,
                    if (!compact) ...[
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: mutedColor),
                    ],
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

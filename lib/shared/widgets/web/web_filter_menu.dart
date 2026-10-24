import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Compact filter for the web portal:
//
//   Trigger:  [ ◉ Status · All  2 ▾ ]       active: [ ◉ Status · Rejected  1 ✕ ]
//   Menu:     ✓ All                      2
//             ● Upcoming                 1
//             ● Ongoing                  0   ← dimmed: none right now
//             …
//
// One button instead of a row of chips that runs off narrow screens (or a
// laptop at 125% zoom). Every option and its count is one click away, the
// current choice is always visible on the button, and ✕ clears it. Built on
// MenuAnchor / MenuItemButton, so arrow keys, Enter and Esc work. Modelled on
// the admin portal's organizer filter (admin_web_events.dart).
// ─────────────────────────────────────────────────────────────────────────────

/// One choice in a [WebFilterMenu].
class WebFilterOption<T> {
  final T      value;
  final String label;
  final int    count;
  /// The dot in front of the label (a status colour); the accent if null.
  final Color? color;
  const WebFilterOption({
    required this.value,
    required this.label,
    required this.count,
    this.color,
  });
}

class WebFilterMenu<T> extends StatefulWidget {
  final IconData icon;
  /// What is being filtered: "Status", "Event".
  final String label;
  /// Every choice; the first one is "show everything" (what ✕ goes back to).
  final List<WebFilterOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelect;
  final Color accent;
  final double menuWidth;
  /// A search box above the list — for long lists, like one per event.
  final bool searchable;
  final String searchHint;
  final double maxValueWidth;

  const WebFilterMenu({
    super.key,
    required this.icon,
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelect,
    this.accent = kGold,
    this.menuWidth = 260,
    this.searchable = false,
    this.searchHint = 'Search…',
    this.maxValueWidth = 170,
  });

  @override
  State<WebFilterMenu<T>> createState() => _WebFilterMenuState<T>();
}

class _WebFilterMenuState<T> extends State<WebFilterMenu<T>> {
  final _menu   = MenuController();
  final _search = TextEditingController();
  String _query = '';
  bool   _hovered = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _pick(T value) {
    _menu.close();
    widget.onSelect(value);
  }

  @override
  Widget build(BuildContext context) {
    final dark   = Theme.of(context).brightness == Brightness.dark;
    final card   = dark ? const Color(0xFF12151B) : Colors.white;
    final border = dark ? const Color(0xFF232833) : kCardBorder;
    final text   = dark ? const Color(0xFFE7EAEE) : kText;
    final muted  = dark ? const Color(0xFF9AA3B2) : kMuted;

    final all = widget.options.first;
    final selected = widget.options.firstWhere(
        (o) => o.value == widget.selected, orElse: () => all);
    final active = selected.value != all.value;

    final q = _query.trim().toLowerCase();
    final rest = widget.options.skip(1).where(
        (o) => q.isEmpty || o.label.toLowerCase().contains(q)).toList();

    return MenuAnchor(
      controller: _menu,
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(card),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(10),
        shadowColor: WidgetStatePropertyAll(
            Colors.black.withValues(alpha: dark ? 0.55 : 0.16)),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
        minimumSize: WidgetStatePropertyAll(Size(widget.menuWidth, 0)),
        maximumSize: WidgetStatePropertyAll(Size(widget.menuWidth, 460)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: border),
        )),
      ),
      onClose: () {
        if (_query.isNotEmpty) setState(() { _query = ''; _search.clear(); });
      },
      menuChildren: [
        if (widget.searchable)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
            child: SizedBox(
              width: widget.menuWidth - 16,
              height: 38,
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5, color: text),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: widget.searchHint,
                  hintStyle: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: muted),
                  prefixIcon: Icon(Icons.search_rounded, size: 16, color: muted),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  filled: true,
                  fillColor: dark ? const Color(0xFF0E1116) : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: widget.accent, width: 1.5),
                  ),
                ),
              ),
            ),
          ),
        _MenuRow(
          option: all, accent: widget.accent, width: widget.menuWidth - 8,
          selected: !active, dark: dark, onPressed: () => _pick(all.value),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
          child: Divider(height: 1, thickness: 1, color: border),
        ),
        if (rest.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Text('Nothing matches “${_query.trim()}”.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: muted)),
          )
        else
          for (final o in rest)
            _MenuRow(
              option: o, accent: widget.accent, width: widget.menuWidth - 8,
              selected: active && o.value == selected.value, dark: dark,
              onPressed: () => _pick(o.value),
            ),
      ],
      builder: (context, controller, _) {
        final c   = widget.accent;
        final lit = _hovered || controller.isOpen;
        final bg = active
            ? c.withValues(alpha: 0.08)
            : dark
                ? (lit ? const Color(0xFF1B2029) : const Color(0xFF171B22))
                : (lit ? const Color(0xFFEEF2F7) : const Color(0xFFF8F9FC));
        final edge = active
            ? c.withValues(alpha: 0.35)
            : dark
                ? (lit ? const Color(0xFF2A3040) : const Color(0xFF232833))
                : (lit ? const Color(0xFFD1D5DB) : kCardBorder);
        final valueColor = active ? (dark ? c : _darker(c)) : text;

        return Semantics(
          button: true,
          label: '${widget.label} filter: ${selected.label}, ${selected.count}',
          child: Material(
            color: bg,
            shape: StadiumBorder(side: BorderSide(color: edge, width: active ? 1.5 : 1.0)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => controller.isOpen ? controller.close() : controller.open(),
              onHover: (h) => setState(() => _hovered = h),
              hoverColor: Colors.transparent,
              splashColor: c.withValues(alpha: 0.06),
              child: SizedBox(
                height: 40,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(10, 0, active ? 6 : 10, 0),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 22, height: 22,
                      decoration: BoxDecoration(
                        color: c.withValues(alpha: active ? 0.18 : 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(widget.icon, size: 12, color: active ? valueColor : muted),
                    ),
                    const SizedBox(width: 7),
                    Text(widget.label,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                          fontWeight: FontWeight.w500, color: muted)),
                    Text('  ·  ',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: muted)),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: widget.maxValueWidth),
                      child: Text(selected.label,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                            fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                            color: valueColor)),
                    ),
                    const SizedBox(width: 7),
                    _CountBadge(count: selected.count, color: active ? c : null, dark: dark),
                    const SizedBox(width: 6),
                    if (active)
                      // One click back to everything, without opening the menu.
                      Tooltip(
                        message: 'Clear ${widget.label.toLowerCase()} filter',
                        child: InkWell(
                          onTap: () { controller.close(); widget.onSelect(all.value); },
                          customBorder: const CircleBorder(),
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: Icon(Icons.close_rounded, size: 14, color: valueColor),
                          ),
                        ),
                      )
                    else
                      AnimatedRotation(
                        turns: controller.isOpen ? 0.5 : 0,
                        duration: const Duration(milliseconds: 160),
                        child: Icon(Icons.expand_more_rounded, size: 18, color: muted),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// Text in the accent colour on light backgrounds needs a darker shade for
// contrast (gold #D6A742 is ~2:1 on white).
Color _darker(Color c) => Color.lerp(c, Colors.black, 0.38)!;

class _CountBadge extends StatelessWidget {
  final int    count;
  final Color? color;   // null = neutral
  final bool   dark;
  const _CountBadge({required this.count, required this.color, required this.dark});

  @override
  Widget build(BuildContext context) {
    final c = color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: c != null
            ? c.withValues(alpha: 0.15)
            : (dark ? const Color(0xFF20252E) : const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('$count',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700,
            color: c != null
                ? (dark ? c : _darker(c))
                : (dark ? const Color(0xFF9AA3B2) : kMuted))),
    );
  }
}

// One option: dot · label · count · check.
class _MenuRow<T> extends StatelessWidget {
  final WebFilterOption<T> option;
  final Color accent;
  final double width;
  final bool selected;
  final bool dark;
  final VoidCallback onPressed;
  const _MenuRow({
    required this.option, required this.accent, required this.width,
    required this.selected, required this.dark, required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final text  = dark ? const Color(0xFFE7EAEE) : kText;
    final sub   = dark ? const Color(0xFF9AA3B2) : kSubText;
    final empty = option.count == 0;
    final dot   = option.color ?? accent;
    final selColor = dark ? accent : _darker(accent);

    return Semantics(
      selected: selected,
      label: '${option.label}, ${option.count}',
      child: MenuItemButton(
        onPressed: onPressed,
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
          minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (selected) return accent.withValues(alpha: 0.10);
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return dark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9);
            }
            return Colors.transparent;
          }),
        ),
        child: SizedBox(
          width: width - 16,
          child: Row(children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: empty ? dot.withValues(alpha: 0.35) : dot,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(option.label,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? selColor : (empty ? sub : text))),
            ),
            const SizedBox(width: 8),
            _CountBadge(count: option.count, color: selected ? accent : null, dark: dark),
            SizedBox(
              width: 22,
              child: selected
                  ? Icon(Icons.check_rounded, size: 15, color: selColor)
                  : null,
            ),
          ]),
        ),
      ),
    );
  }
}

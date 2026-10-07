import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';

class WebCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  const WebCard({super.key, required this.child, this.padding, this.radius = 16});

  @override
  Widget build(BuildContext context) {
    // Web-only dark check — organizer web never enables dark mode, so this
    // branch only ever fires for the admin dashboard, using the same cool
    // graphite palette as its AdminTk tokens (kept literal here since this
    // is a shared widget with no access to a feature-local token class).
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF12151B) : Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: dark ? const Color(0xFF232833) : kCardBorder),
        boxShadow: [
          BoxShadow(
            color: dark
                ? Colors.black.withValues(alpha: 0.55)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class WebSectionHeader extends StatelessWidget {
  final String  title;
  final String? subtitle;
  final Widget? action;
  const WebSectionHeader({super.key, required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w800, color: kText)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: kSubText)),
            ],
          ],
        ),
      ),
      ?action,
    ],
  );
}

class WebColHeader extends StatelessWidget {
  final String text;
  const WebColHeader(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Text(text,
      style: TextStyle(
        fontFamily: 'Poppins', fontSize: 10.5, fontWeight: FontWeight.w700,
        color: dark ? const Color(0xFFE7EAEE) : kText,
        letterSpacing: 0.8,
      ));
  }
}

class WebHoverTile extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final Color? hoverColor;
  const WebHoverTile({super.key, required this.child, required this.onTap, this.hoverColor});

  @override
  State<WebHoverTile> createState() => _WebHoverTileState();
}

class _WebHoverTileState extends State<WebHoverTile> {
  bool _h = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _h = true),
    onExit:  (_) => setState(() => _h = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        color: _h ? (widget.hoverColor ?? Colors.black.withValues(alpha: 0.04)) : Colors.transparent,
        child: widget.child,
      ),
    ),
  );
}

class WebDividerLabel extends StatelessWidget {
  final String label;
  const WebDividerLabel(this.label, {super.key});

  @override
  Widget build(BuildContext context) => Row(children: [
    const Expanded(child: Divider(color: kCardBorder)),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(label,
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: kMuted, fontWeight: FontWeight.w600)),
    ),
    const Expanded(child: Divider(color: kCardBorder)),
  ]);
}

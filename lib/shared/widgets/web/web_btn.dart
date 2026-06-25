import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';

class WebBtn extends StatefulWidget {
  final String       label;
  final IconData?    icon;
  final VoidCallback onTap;
  final bool         small;
  final bool         outlined;
  final Color?       color;
  const WebBtn({
    super.key,
    required this.label,
    this.icon,
    required this.onTap,
    this.small    = false,
    this.outlined = false,
    this.color,
  });

  @override
  State<WebBtn> createState() => _WebBtnState();
}

class _WebBtnState extends State<WebBtn> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color ?? kGold;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit:  (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
            horizontal: widget.small ? 14 : 18,
            vertical:   widget.small ? 8  : 11,
          ),
          decoration: widget.outlined
            ? BoxDecoration(
                color: _h ? c.withValues(alpha: 0.06) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c, width: 1.5),
              )
            : BoxDecoration(
                gradient: LinearGradient(
                  colors: _h
                    ? [const Color(0xFFB8892A), c]
                    : [const Color(0xFFC49230), c],
                  begin: Alignment.topLeft,
                  end:   Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: c.withValues(alpha: _h ? 0.38 : 0.22),
                    blurRadius: _h ? 10 : 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon!, size: widget.small ? 14 : 15, color: widget.outlined ? c : Colors.white),
                const SizedBox(width: 7),
              ],
              Text(widget.label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: widget.small ? 12 : 13,
                  fontWeight: FontWeight.w700,
                  color: widget.outlined ? c : Colors.white,
                )),
            ],
          ),
        ),
      ),
    );
  }
}

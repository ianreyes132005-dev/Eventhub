import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';

class WebStatCard extends StatefulWidget {
  final String   label;
  final String   value;
  final IconData icon;
  final Color    color;
  final String?  badge;
  const WebStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.badge,
  });

  @override
  State<WebStatCard> createState() => _WebStatCardState();
}

class _WebStatCardState extends State<WebStatCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c    = widget.color;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return MouseRegion(
      cursor:  SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve:    Curves.easeOut,
        transform:          Matrix4.translationValues(0, _hovered ? -4 : 0, 0),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: _hovered
                  ? c.withValues(alpha: 0.14)
                  : Colors.black.withValues(alpha: dark ? 0.45 : 0.04),
              blurRadius: _hovered ? 24 : 10,
              offset:     Offset(0, _hovered ? 10 : 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: c),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    decoration: BoxDecoration(
                      color: dark ? const Color(0xFF12151B) : Colors.white,
                      border: Border(
                        top:    BorderSide(color: _hovered ? c.withValues(alpha: 0.30) : (dark ? const Color(0xFF232833) : kCardBorder)),
                        right:  BorderSide(color: _hovered ? c.withValues(alpha: 0.30) : (dark ? const Color(0xFF232833) : kCardBorder)),
                        bottom: BorderSide(color: _hovered ? c.withValues(alpha: 0.30) : (dark ? const Color(0xFF232833) : kCardBorder)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(widget.value,
                                style: TextStyle(
                                  fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w800,
                                  color: _hovered ? c : (dark ? const Color(0xFFE7EAEE) : kText), height: 1.0,
                                )),
                              const SizedBox(height: 3),
                              Text(widget.label,
                                style: TextStyle(
                                  fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w500,
                                  color: dark ? const Color(0xFF9AA3B2) : kSubText,
                                )),
                            ],
                          ),
                        ),
                        if (widget.badge != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(widget.badge!,
                              style: const TextStyle(
                                fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF10B981),
                              )),
                          ),
                        ],
                        const SizedBox(width: 12),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve:    Curves.easeOut,
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                c.withValues(alpha: _hovered ? 0.22 : 0.10),
                                c.withValues(alpha: _hovered ? 0.10 : 0.04),
                              ],
                              begin: Alignment.topLeft,
                              end:   Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: c.withValues(alpha: _hovered ? 0.25 : 0.0)),
                          ),
                          child: Icon(widget.icon, color: c, size: 20),
                        ),
                      ],
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

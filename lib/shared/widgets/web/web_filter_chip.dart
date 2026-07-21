import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';

class WebFilterChip extends StatefulWidget {
  final String       label;
  final bool         selected;
  final VoidCallback onTap;
  final Color?       selectedColor;
  final int?         count;
  const WebFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.selectedColor,
    this.count,
  });

  @override
  State<WebFilterChip> createState() => _WebFilterChipState();
}

class _WebFilterChipState extends State<WebFilterChip> {
  bool _hovered = false;

  static const _palette = [
    Color(0xFF3B82F6), Color(0xFF8B5CF6), Color(0xFF10B981),
    Color(0xFFF59E0B), Color(0xFF0D9488), Color(0xFFEA580C), Color(0xFF6366F1),
  ];

  Color _chipColor(String label) {
    if (label == 'All') return kGold;
    return _palette[label.hashCode.abs() % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final c        = widget.selectedColor ?? kGold;
    final isAll    = widget.label == 'All';
    final dotColor = _chipColor(widget.label);
    final initial  = (!isAll && widget.label.trim().isNotEmpty)
        ? widget.label.trim()[0].toUpperCase()
        : null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final unselectedBg = dark
        ? (_hovered ? const Color(0xFF1B2029) : const Color(0xFF171B22))
        : (_hovered ? const Color(0xFFEEF2F7) : const Color(0xFFF8F9FC));
    final unselectedBorder = dark
        ? (_hovered ? const Color(0xFF2A3040) : const Color(0xFF232833))
        : (_hovered ? const Color(0xFFD1D5DB) : kCardBorder);
    final unselectedText  = dark ? const Color(0xFF9AA3B2) : kSubText;
    final unselectedMuted = dark ? const Color(0xFF666E7D) : kMuted;
    final unselectedCountBg = dark ? const Color(0xFF20252E) : const Color(0xFFE5E7EB);

    return MouseRegion(
      cursor:  SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve:    Curves.easeOut,
          padding:  const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: widget.selected
                ? c.withValues(alpha: 0.08)
                : unselectedBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.selected
                  ? c.withValues(alpha: 0.35)
                  : unselectedBorder,
              width: widget.selected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: widget.selected
                      ? c.withValues(alpha: 0.18)
                      : dotColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: isAll
                      ? Icon(Icons.layers_rounded, size: 11, color: widget.selected ? c : unselectedMuted)
                      : Text(initial ?? '?',
                          style: TextStyle(
                            fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w800,
                            color: widget.selected ? c : dotColor,
                          )),
                ),
              ),
              const SizedBox(width: 7),
              Text(widget.label,
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 12,
                  fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
                  color: widget.selected ? c : unselectedText,
                  letterSpacing: widget.selected ? 0.1 : 0,
                )),
              if (widget.count != null) ...[
                const SizedBox(width: 7),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: widget.selected ? c.withValues(alpha: 0.15) : unselectedCountBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${widget.count}',
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700,
                      color: widget.selected ? c : unselectedMuted,
                    )),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

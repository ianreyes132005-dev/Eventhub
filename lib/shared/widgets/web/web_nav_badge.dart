import 'package:flutter/material.dart';

/// "Needs your review" count on a web sidebar item — the admin's Events
/// (events and change requests to review) and the organizer's Registrations
/// (selfies to review). Amber, the "needs attention" colour used for Pending
/// Review, rather than the accent that marks the page you're on. 9+ above nine.
class WebNavBadge extends StatelessWidget {
  final int count;

  /// What the number counts, e.g. "3 selfies waiting for your review" —
  /// shown on hover and read by screen readers. None: just the number.
  final String? tooltip;

  const WebNavBadge({super.key, required this.count, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 4, offset: const Offset(0, 1)),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        count > 9 ? '9+' : '$count',
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 10,
            fontWeight: FontWeight.w800, color: Colors.white, height: 1.0),
      ),
    );
    final tip = tooltip;
    if (tip == null) return badge;
    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 300),
      child: Semantics(label: tip, excludeSemantics: true, child: badge),
    );
  }
}

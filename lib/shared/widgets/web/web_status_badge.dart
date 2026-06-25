import 'package:flutter/material.dart';

class WebStatusBadge extends StatelessWidget {
  final String label;
  final Color  color;
  const WebStatusBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Text(label,
      style: TextStyle(
        fontFamily: 'Poppins',
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        color: color,
      )),
  );
}

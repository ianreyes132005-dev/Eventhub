import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';

class WebEmptyState extends StatelessWidget {
  final IconData icon;
  final String   title;
  final String   subtitle;
  final Widget?  action;
  const WebEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: kGold.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: kGold.withValues(alpha: 0.60)),
            ),
            const SizedBox(height: 18),
            Text(title,
              style: TextStyle(
                fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700,
                color: dark ? const Color(0xFFE7EAEE) : kText,
              ),
              textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(subtitle,
              style: TextStyle(
                fontFamily: 'Poppins', fontSize: 12.5, height: 1.5,
                color: dark ? const Color(0xFF9AA3B2) : kSubText,
              ),
              textAlign: TextAlign.center),
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

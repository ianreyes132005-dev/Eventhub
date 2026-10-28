import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import 'web/swal.dart' show kSwalGold;

/// The notification header's "Mark all as read". Once nothing is left
/// unread (right after it's tapped, or when every item was read one by one)
/// it turns into a green "All read". Shared by the student Notifications
/// screen and the organizer app's notification sheet.
class MarkAllReadButton extends StatelessWidget {
  const MarkAllReadButton({super.key, required this.unread, required this.onTap});

  /// How many notifications are still unread.
  final int unread;
  final VoidCallback onTap;

  static const _green = Color(0xFF16A34A);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: unread > 0
          ? Semantics(
              key: const ValueKey('mark-all-read'),
              button: true,
              child: GestureDetector(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: kGold.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kGold.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    'Mark all as read',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      // Darker gold on light cards for contrast, like the web bell.
                      color: dark ? kGold : kSwalGold,
                    ),
                  ),
                ),
              ),
            )
          : Semantics(
              key: const ValueKey('all-read'),
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(10),
                  // Same size as the button, so the header doesn't jump.
                  border: Border.all(color: _green.withValues(alpha: 0.25)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, size: 13, color: _green),
                    SizedBox(width: 5),
                    Text(
                      'All read',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: _green),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

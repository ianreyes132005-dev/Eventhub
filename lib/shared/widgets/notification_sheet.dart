import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/services/organizer_notices.dart' show noticeTimeAgo;
import 'mark_all_read_button.dart';

/// One row under the bell.
class NotificationItem {
  final String id;
  final String title;
  final String message;
  final IconData icon;
  final Color color;

  /// When it happened. Rows without one (the organizer's reminders) show a
  /// one-line message; rows with one show it in full (a reason, a new date).
  final DateTime? at;

  const NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
    this.at,
  });
}

/// The bell's bottom sheet in the organizer and student apps: one list of
/// messages, newest first — no tabs, no separate page.
///
/// Opening it doesn't read anything (same as the web bell): an unread row
/// stays gold until it's tapped or "Mark all as read" is used.
class NotificationSheet extends StatefulWidget {
  final List<NotificationItem> items;

  /// Not read yet (highlighted). Asks the screen that owns the bell, so the
  /// sheet and the bell's number always agree.
  final bool Function(String id) isUnread;

  /// Marks rows read on the screen that owns the bell.
  final void Function(Iterable<String> ids) onRead;

  /// Under "You're all caught up!" when there's nothing to show.
  final String emptyHint;

  const NotificationSheet({
    super.key,
    required this.items,
    required this.isUnread,
    required this.onRead,
    required this.emptyHint,
  });

  @override
  State<NotificationSheet> createState() => _NotificationSheetState();
}

class _NotificationSheetState extends State<NotificationSheet> {
  void _read(Iterable<String> ids) {
    widget.onRead(ids);
    if (mounted) setState(() {}); // the gold fades
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTk(Theme.of(context).brightness == Brightness.dark);
    final items = widget.items;
    final unread = [
      for (final n in items)
        if (widget.isUnread(n.id)) n.id,
    ];

    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: t.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.notifications_rounded, size: 18, color: t.text),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Notifications',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                  ),
                  if (unread.isNotEmpty) ...[
                    Text(
                      '${unread.length} new',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: t.sub,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  // Mark all as read → All read
                  MarkAllReadButton(
                    unread: unread.length,
                    onTap: () => _read(unread),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: t.divider),
            // Content
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 36,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle_outline_rounded,
                        size: 26,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      "You're all caught up!",
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: t.text,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.emptyHint,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: t.sub,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.65,
                ),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: t.divider),
                  itemBuilder: (_, i) => _buildItem(items[i], t),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(NotificationItem n, AppTk t) {
    final isNew = widget.isUnread(n.id);
    final gold = kGold.withValues(alpha: t.dark ? 0.10 : 0.07);
    // Tapping an unread row reads it (the web reads on hover or click).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _read([n.id]),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        color: isNew ? gold : gold.withValues(alpha: 0),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: n.color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(n.icon, size: 19, color: n.color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          n.title,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: t.text,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (n.at != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          noticeTimeAgo(n.at!),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10.5,
                            color: t.sub,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  // Messages with a time carry a reason or a new date — show
                  // them in full.
                  Text(
                    n.message,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11.5,
                      height: 1.45,
                      color: t.sub,
                    ),
                    maxLines: n.at != null ? 6 : 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Kept in place once read (just faded) so the text doesn't shift.
            Padding(
              padding: const EdgeInsets.only(left: 10, top: 6),
              child: ExcludeSemantics(
                excluding: !isNew,
                child: Semantics(
                  label: 'New',
                  child: AnimatedOpacity(
                    opacity: isNew ? 1 : 0,
                    duration: const Duration(milliseconds: 350),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: kGold,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

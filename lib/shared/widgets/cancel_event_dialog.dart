import 'package:flutter/material.dart';
import '../../core/app_colors.dart';

/// "Cancel event?" — asks for the reason registered students will see.
/// Shared by organizer web and mobile. Resolves to the reason, or null when
/// the organizer keeps the event.
Future<String?> showCancelEventDialog(
  BuildContext context, {
  required String eventTitle,
  required int registrationCount,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _CancelEventDialog(
      eventTitle: eventTitle,
      registrationCount: registrationCount,
    ),
  );
}

const _kRed = Color(0xFFDC2626);

// Common reasons, one tap to fill — still editable.
const _kQuickReasons = [
  'Bad weather',
  'Venue not available',
  'Schedule conflict',
  'Too few registrations',
  'Rescheduled — new date to follow',
];

class _CancelEventDialog extends StatefulWidget {
  final String eventTitle;
  final int registrationCount;
  const _CancelEventDialog({
    required this.eventTitle,
    required this.registrationCount,
  });

  @override
  State<_CancelEventDialog> createState() => _CancelEventDialogState();
}

class _CancelEventDialogState extends State<_CancelEventDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final card = dark ? const Color(0xFF1E1B18) : Colors.white;
    final text = dark ? const Color(0xFFF2EAD8) : kText;
    final sub = dark ? const Color(0xFFB8A880) : kSubText;
    final border = dark ? const Color(0xFF3A3328) : const Color(0xFFE5E7EB);
    final field = dark ? const Color(0xFF16130F) : const Color(0xFFF9FAFB);
    final n = widget.registrationCount;
    final ok = _ctrl.text.trim().isNotEmpty;

    return Dialog(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        // Content scrolls; the buttons stay pinned so they're always visible,
        // even on a small phone with the keyboard open.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _kRed.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.event_busy_rounded,
                            color: _kRed,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Cancel event?',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: text,
                                ),
                              ),
                              Text(
                                widget.eventTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12.5,
                                  color: sub,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // What happens
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: field,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _bullet(
                            Icons.notifications_active_outlined,
                            n == 0
                                ? 'No students are registered yet.'
                                : '$n registered student${n == 1 ? '' : 's'} will be notified with your reason.',
                            sub,
                          ),
                          _bullet(
                            Icons.block_rounded,
                            'Registration and check-in stop immediately.',
                            sub,
                          ),
                          _bullet(
                            Icons.inventory_2_outlined,
                            'Registrations and attendance records are kept. '
                            'You can restore the event before it ends.',
                            sub,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    Text(
                      'Reason',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: text,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final r in _kQuickReasons)
                          ActionChip(
                            label: Text(
                              r,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11.5,
                                color: _ctrl.text == r ? _kRed : sub,
                              ),
                            ),
                            backgroundColor: _ctrl.text == r
                                ? _kRed.withValues(alpha: 0.08)
                                : field,
                            side: BorderSide(
                              color: _ctrl.text == r
                                  ? _kRed.withValues(alpha: 0.5)
                                  : border,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() {
                              _ctrl.text = r;
                              _ctrl.selection = TextSelection.collapsed(
                                offset: r.length,
                              );
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _ctrl,
                      maxLines: 3,
                      maxLength: 200,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: text,
                      ),
                      decoration: InputDecoration(
                        hintText:
                            'e.g. The gym is being repaired — we’ll announce a new date soon.',
                        hintStyle: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12.5,
                          color: sub.withValues(alpha: 0.7),
                        ),
                        filled: true,
                        fillColor: field,
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: _kRed,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 18),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: border),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Keep event',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          color: sub,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: ok
                          ? () => Navigator.pop(context, _ctrl.text.trim())
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kRed,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _kRed.withValues(alpha: 0.35),
                        disabledForegroundColor: Colors.white70,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Cancel event',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bullet(IconData icon, String text, Color c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: c),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: c,
              height: 1.45,
            ),
          ),
        ),
      ],
    ),
  );
}

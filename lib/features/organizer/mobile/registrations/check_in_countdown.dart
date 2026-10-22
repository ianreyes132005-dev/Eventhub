import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/app_colors.dart';
import '../../../../shared/widgets/event_phase_pill.dart' show countdownLabel;

/// What a scan result says once its countdown reaches zero.
const kCheckInJustOpened = 'Check-in just opened — continue to check this ticket in.';

/// "Check-in opens in 00:42:15" — on a scan result when a valid ticket is
/// scanned before check-in opens, so the organizer knows how long to wait.
///
/// Ticks on the second (rounded up, so it never sits on 00:00 while still
/// closed) and calls [onOpened] once when check-in opens.
class CheckInCountdown extends StatefulWidget {
  const CheckInCountdown({
    super.key,
    required this.opensAt,
    required this.onOpened,
    required this.textColor,
    required this.accentColor,
    this.now = DateTime.now,
  });

  final DateTime opensAt;
  final VoidCallback onOpened;

  /// The ticking time.
  final Color textColor;

  /// The "Check-in opens in" label and clock icon.
  final Color accentColor;

  /// The clock — tests pass a fake one.
  final DateTime Function() now;

  @override
  State<CheckInCountdown> createState() => _CheckInCountdownState();
}

class _CheckInCountdownState extends State<CheckInCountdown> {
  Timer? _timer;
  Duration _left = Duration.zero;
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    _update();
  }

  @override
  void didUpdateWidget(CheckInCountdown old) {
    super.didUpdateWidget(old);
    if (old.opensAt != widget.opensAt) {
      _timer?.cancel();
      _opened = false;
      _update();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _update() {
    _left = widget.opensAt.difference(widget.now());
    if (_left > Duration.zero) {
      // Wake up exactly when the shown second changes.
      final ms = _left.inMilliseconds % 1000;
      _timer = Timer(Duration(milliseconds: ms == 0 ? 1000 : ms), () {
        if (mounted) setState(_update);
      });
    } else if (!_opened) {
      _opened = true;
      // After this frame, so the screen can rebuild into its "open" state.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onOpened();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final seconds = (_left.inMilliseconds / 1000).ceil();
    final time = countdownLabel(Duration(seconds: seconds < 0 ? 0 : seconds));
    return Semantics(
      label: 'Check-in opens in $time',
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: kGold.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kGold.withValues(alpha: 0.30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule_rounded, size: 14, color: widget.accentColor),
                const SizedBox(width: 6),
                Text(
                  'CHECK-IN OPENS IN',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.9,
                    color: widget.accentColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              time,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 30,
                fontWeight: FontWeight.w800,
                height: 1.2,
                color: widget.textColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

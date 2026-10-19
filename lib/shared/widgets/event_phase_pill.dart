import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../models/event_phase.dart';

export '../../models/event_phase.dart'; // re-export so callers only need this file

/// Where [event] is right now, for a student holding a ticket: upcoming →
/// ongoing → check-in open (ended, late check-in still allowed) → completed.
EventPhase eventPhaseOf(Map<String, dynamic> event, {DateTime? now}) {
  if (eventIsCancelled(event)) return EventPhase.cancelled;
  final w = eventWindow(event);
  if (w == null) return EventPhase.upcoming;
  final at = now ?? DateTime.now();
  if (at.isBefore(w.start)) return EventPhase.upcoming;
  if (at.isBefore(w.end)) return EventPhase.ongoing;
  if (at.isBefore(w.end.add(kCheckInClosesAfter))) return EventPhase.checkInOpen;
  return EventPhase.completed;
}

/// "20d 4h" when it's a day or more away, otherwise a ticking "04:12:33"
/// (or "12:33" under an hour).
String countdownLabel(Duration left) {
  if (left.isNegative) return '00:00';
  if (left.inDays >= 1) {
    final h = left.inHours.remainder(24);
    return h > 0 ? '${left.inDays}d ${h}h' : '${left.inDays}d';
  }
  final h = left.inHours;
  final m = left.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = left.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s';
}

/// "3h 20m left"-style remaining time.
String _timeLeft(Duration d) {
  if (d.isNegative) return 'Ended';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h > 0) return m > 0 ? '${h}h ${m}m' : '${h}h';
  if (m > 0) return '${m}m';
  return 'Less than a minute';
}

// ── Mobile banner pill ────────────────────────────────────────────────────────

/// [EventPhasePill] that keeps itself current as the event starts and ends.
class LiveEventPhasePill extends StatefulWidget {
  final Map<String, dynamic> event;
  const LiveEventPhasePill({super.key, required this.event});

  @override
  State<LiveEventPhasePill> createState() => _LiveEventPhasePillState();
}

class _LiveEventPhasePillState extends State<LiveEventPhasePill> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      EventPhasePill(phase: eventPhaseOf(widget.event));
}

class EventPhasePill extends StatelessWidget {
  final EventPhase phase;
  final String? upcomingLabel;
  const EventPhasePill({super.key, required this.phase, this.upcomingLabel});

  @override
  Widget build(BuildContext context) {
    switch (phase) {
      case EventPhase.upcoming:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: kGold,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: kGold.withValues(alpha: 0.45), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bolt_rounded, size: 11, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                upcomingLabel ?? 'NEXT UP',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: Colors.white),
              ),
            ],
          ),
        );

      case EventPhase.ongoing:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: const Color(0xFF10B981).withValues(alpha: 0.45), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 7, color: Colors.white),
              SizedBox(width: 5),
              Text('Ongoing', style: TextStyle(fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.2, color: Colors.white)),
            ],
          ),
        );

      case EventPhase.checkInOpen:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: kCheckInOpenColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: kCheckInOpenColor.withValues(alpha: 0.45), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.qr_code_scanner_rounded, size: 11, color: Colors.white),
              SizedBox(width: 4),
              Text('CHECK-IN OPEN', style: TextStyle(fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: Colors.white)),
            ],
          ),
        );

      case EventPhase.completed:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, size: 11, color: Colors.white),
              SizedBox(width: 4),
              Text('COMPLETED', style: TextStyle(fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: Colors.white)),
            ],
          ),
        );

    case EventPhase.cancelled:
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          'CANCELLED',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: Colors.white,
          ),
        ),
      );
    }
  }
}

// ── Mobile live status timer ──────────────────────────────────────────────────

class EventStatusTimer extends StatefulWidget {
  final DateTime  start;
  final DateTime? end;
  final Map<String, dynamic>? statusEvent;
  const EventStatusTimer({
    super.key,
    required this.start,
    this.end,
    this.statusEvent,
  });

  @override
  State<EventStatusTimer> createState() => _EventStatusTimerState();
}

class _EventStatusTimerState extends State<EventStatusTimer> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  EventPhase get _phase => widget.statusEvent == null
      ? resolveEventPhase(widget.start, widget.end)
      : eventPhaseOf(widget.statusEvent!);

  String _countdown() => countdownLabel(widget.start.difference(DateTime.now()));

  String _remaining() {
    if (widget.end == null) return 'Ongoing';
    final diff = widget.end!.difference(DateTime.now());
    if (diff.isNegative) return 'Ended';
    final h = diff.inHours;
    final m = diff.inMinutes.remainder(60);
    if (h > 0) return m > 0 ? '${h}h ${m}m left' : '${h}h left';
    if (m > 0) return '${m}m left';
    return 'Ending soon';
  }

  @override
  Widget build(BuildContext context) {
    final phase = _phase;

    if (phase == EventPhase.completed || phase == EventPhase.cancelled) {
      _timer?.cancel();
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              phase == EventPhase.cancelled
                  ? Icons.cancel_rounded
                  : Icons.check_circle_rounded,
              size: 13,
              color: Colors.white70,
            ),
            const SizedBox(width: 5),
            Text(
              phase == EventPhase.cancelled ? 'Cancelled' : 'Completed',
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      );
    }

    // Ended, but late check-in is still open — say for how long.
    if (phase == EventPhase.checkInOpen && widget.end != null) {
      final closes = widget.end!.add(kCheckInClosesAfter);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('CHECK-IN CLOSES IN', style: TextStyle(fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: Colors.white60)),
          const SizedBox(height: 4),
          Text(_timeLeft(closes.difference(DateTime.now())), style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
        ],
      );
    }

    if (phase == EventPhase.ongoing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('ENDS IN', style: TextStyle(fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: Colors.white60)),
          const SizedBox(height: 4),
          Text(_remaining(), style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('STARTS IN', style: TextStyle(fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: Colors.white60)),
        const SizedBox(height: 4),
        Text(
          _countdown(),
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ── Web pulsing live dot ──────────────────────────────────────────────────────

class WebLiveDot extends StatefulWidget {
  final double size;
  const WebLiveDot({super.key, this.size = 8});

  @override
  State<WebLiveDot> createState() => _WebLiveDotState();
}

class _WebLiveDotState extends State<WebLiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _fade = Tween<double>(begin: 0.25, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Container(
        width: widget.size, height: widget.size,
        decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
      ),
    );
  }
}

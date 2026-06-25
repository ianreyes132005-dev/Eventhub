import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../models/event_phase.dart';

export '../../models/event_phase.dart'; // re-export so callers only need this file

// ── Mobile banner pill ────────────────────────────────────────────────────────

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
              Text('LIVE NOW', style: TextStyle(fontFamily: 'Poppins', fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: Colors.white)),
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
    }
  }
}

// ── Mobile live status timer ──────────────────────────────────────────────────

class EventStatusTimer extends StatefulWidget {
  final DateTime  start;
  final DateTime? end;
  const EventStatusTimer({super.key, required this.start, this.end});

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

  EventPhase get _phase => resolveEventPhase(widget.start, widget.end);

  String _countdown() {
    final diff = widget.start.difference(DateTime.now());
    if (diff.isNegative) return '00:00';
    final h = diff.inHours;
    final m = diff.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = diff.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s';
  }

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

    if (phase == EventPhase.completed) {
      _timer?.cancel();
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 13, color: Colors.white70),
            SizedBox(width: 5),
            Text('Completed', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white70)),
          ],
        ),
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

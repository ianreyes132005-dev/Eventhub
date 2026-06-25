import 'dart:async';
import 'package:flutter/material.dart';

class LiveCountdown extends StatefulWidget {
  final DateTime target;
  final Color    textColor;
  const LiveCountdown({required this.target, required this.textColor, super.key});

  @override
  State<LiveCountdown> createState() => _LiveCountdownState();
}

class _LiveCountdownState extends State<LiveCountdown> {
  Timer?    _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  void _update() {
    final diff = widget.target.difference(DateTime.now());
    if (!mounted) return;
    if (diff.isNegative) {
      setState(() => _remaining = Duration.zero);
      _timer?.cancel();
    } else {
      setState(() => _remaining = diff);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_remaining == Duration.zero) {
      return Text(
        'Live now',
        style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700, color: widget.textColor),
      );
    }
    final d = _remaining.inDays;
    final h = _remaining.inHours.remainder(24).toString().padLeft(2, '0');
    final m = _remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _remaining.inSeconds.remainder(60).toString().padLeft(2, '0');

    return d > 0
        ? RichText(
            text: TextSpan(
              style: TextStyle(fontFamily: 'Poppins', color: widget.textColor),
              children: [
                TextSpan(text: '$d', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const TextSpan(text: 'd  ', style: TextStyle(fontSize: 11)),
                TextSpan(text: '$h:$m:$s', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ),
          )
        : Text(
            '$h:$m:$s',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w800, color: widget.textColor),
          );
  }
}

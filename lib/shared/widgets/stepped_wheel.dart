import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A scroll drum (ListWheelScrollView) that moves one item per step — used
/// by the event forms' time pickers (organizer app and web).
///
/// A plain ListWheelScrollView jumps a mouse-wheel notch's full distance
/// (≈100 px, about two items) and lets a short swipe coast past the next
/// item, so 10 became 12. Here:
///   • one mouse-wheel notch = one item;
///   • a short swipe or flick = one item; dragging follows the finger and
///     stops on the item it's released on; only a long, fast spin coasts on;
///   • trackpad scrolling follows the fingers and settles on the nearest item;
///   • tapping a visible item selects it.
class SteppedWheel extends StatefulWidget {
  const SteppedWheel({
    super.key,
    required this.controller,
    required this.itemExtent,
    required this.childCount,
    required this.itemBuilder,
    this.onSelectedItemChanged,
    this.diameterRatio = 1.8,
    this.perspective = 0.003,
  });

  final FixedExtentScrollController controller;
  final double itemExtent;
  final int childCount;
  final IndexedWidgetBuilder itemBuilder;
  final ValueChanged<int>? onSelectedItemChanged;
  final double diameterRatio;
  final double perspective;

  @override
  State<SteppedWheel> createState() => _SteppedWheelState();
}

class _SteppedWheelState extends State<SteppedWheel> {
  static const _settle = Duration(milliseconds: 180);
  // Mouse-wheel events closer together than this belong to one notch
  // (high-resolution wheels send a burst of small events per notch).
  static const _notchGap = Duration(milliseconds: 35);
  // Swipes slower than this (px/s) just settle where they were released.
  static const _flickSpeed = 150.0;
  // A spin longer than 1.5 items and faster than this keeps going.
  static const _spinSpeed = 1400.0;

  FixedExtentScrollController get _c => widget.controller;
  double get _ext => widget.itemExtent;

  int? _target;           // the item a running animation is heading to
  double _dragStart = 0;  // offset when the current drag began
  Duration? _lastNotch;   // time of the last mouse-wheel step
  Timer? _trackpadSettle; // settles once trackpad scrolling stops

  @override
  void dispose() {
    _trackpadSettle?.cancel();
    super.dispose();
  }

  void _goTo(int item) {
    if (!_c.hasClients) return;
    final to = item.clamp(0, widget.childCount - 1);
    _target = to;
    _c.animateToItem(to, duration: _settle, curve: Curves.easeOutCubic).whenComplete(() {
      if (_target == to) _target = null;
    });
  }

  // ── Mouse wheel / trackpad ─────────────────────────────────────────────────

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    // Claim it, so the dialog or page behind the drum doesn't scroll too.
    GestureBinding.instance.pointerSignalResolver
        .register(event, (e) => _onScroll(e as PointerScrollEvent));
  }

  void _onScroll(PointerScrollEvent e) {
    if (!_c.hasClients) return;
    final dy = e.scrollDelta.dy;
    if (e.kind == PointerDeviceKind.trackpad) {
      _target = null;
      _c.jumpTo(_c.offset + dy);
      _trackpadSettle?.cancel();
      _trackpadSettle = Timer(const Duration(milliseconds: 140),
          () => _goTo((_c.offset / _ext).round()));
      return;
    }
    final last = _lastNotch;
    if (last != null && (e.timeStamp - last).abs() < _notchGap) return;
    _lastNotch = e.timeStamp;
    _goTo((_target ?? _c.selectedItem) + (dy > 0 ? 1 : -1));
  }

  // ── Touch / mouse drag ─────────────────────────────────────────────────────

  void _onDragStart(DragStartDetails d) {
    _trackpadSettle?.cancel();
    _target = null;
    _c.jumpTo(_c.offset); // stops a running animation
    _dragStart = _c.offset;
  }

  void _onDragUpdate(DragUpdateDetails d) => _c.jumpTo(_c.offset - d.delta.dy);

  void _onDragEnd(DragEndDetails d) {
    final v = -(d.primaryVelocity ?? 0); // + = toward later items
    final pos = _c.offset / _ext;
    if (v.abs() < _flickSpeed) {
      _goTo(pos.round());
      return;
    }
    // A flick finishes the item it was heading to, and always moves at
    // least one — a short swipe is exactly one step.
    final start = (_dragStart / _ext).round();
    var item = v > 0
        ? math.max((pos - 0.15).ceil(), start + 1)
        : math.min((pos + 0.15).floor(), start - 1);
    final travelled = (_c.offset - _dragStart).abs() / _ext;
    if (travelled >= 1.5 && v.abs() > _spinSpeed) {
      item += v.sign.toInt() * ((v.abs() - _spinSpeed) / 700).floor().clamp(0, 6);
    }
    _goTo(item);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onVerticalDragStart: _onDragStart,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        onVerticalDragCancel: () {
          if (_c.hasClients) _goTo((_c.offset / _ext).round());
        },
        child: ListWheelScrollView.useDelegate(
          controller: _c,
          itemExtent: _ext,
          diameterRatio: widget.diameterRatio,
          perspective: widget.perspective,
          // Input is handled above; the wheel itself never scrolls on its own.
          physics: const NeverScrollableScrollPhysics(),
          onSelectedItemChanged: widget.onSelectedItemChanged,
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: widget.childCount,
            builder: (context, i) => MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _goTo(i),
                child: widget.itemBuilder(context, i),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/friendly_error.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SweetAlert2 for Flutter.
//
// The look and behaviour of SweetAlert2 (sweetalert2.github.io): an outlined
// animated icon, a large centred title and text, centred buttons with a focus
// ring, a loader while the confirmed action runs (preConfirm), an inline
// validation message, an optional text input and footer, and an auto-close
// timer with a progress bar. Built in Flutter rather than loading the JS
// library, so it uses the app font, follows dark mode and works offline.
//
//   final r = await Swal.fire(context,
//       icon: SwalIcon.warning,
//       title: 'Are you sure?',
//       text: 'You won’t be able to revert this!',
//       showCancelButton: true,
//       confirmButtonText: 'Yes, delete it!',
//       // Runs with a loader; return an error message to keep the popup open.
//       preConfirm: (_) async { await deleteIt(); return null; });
//   if (r.isConfirmed) Swal.fire(context, icon: SwalIcon.success, title: 'Deleted!');
// ─────────────────────────────────────────────────────────────────────────────

enum SwalIcon { success, error, warning, info, question }

/// SweetAlert2's default button colours (white text passes WCAG AA on each).
const kSwalConfirmColor = Color(0xFF7066E0);
const kSwalDenyColor    = Color(0xFFDC3741);
const kSwalCancelColor  = Color(0xFF6E7881);

/// EventHub's gold, darkened so white button text passes AA (4.9:1) — for
/// the organizer screens, where the brand colour is gold.
const kSwalGold = Color(0xFFA16207);

class SwalResult {
  final bool    isConfirmed;
  /// The input's text when the popup had an input.
  final String? value;
  const SwalResult._(this.isConfirmed, [this.value]);
  bool get isDismissed => !isConfirmed;
}

class Swal {
  Swal._();

  static Future<SwalResult> fire(
    BuildContext context, {
    SwalIcon? icon,
    required String title,
    String? text,
    Widget? footer,
    bool    showConfirmButton  = true,
    String  confirmButtonText  = 'OK',
    Color   confirmButtonColor = kSwalConfirmColor,
    bool    showCancelButton   = false,
    String  cancelButtonText   = 'Cancel',
    Color   cancelButtonColor  = kSwalCancelColor,
    bool    reverseButtons     = false,
    TextStyle? buttonTextStyle,
    bool    input = false,
    String? inputLabel,
    String? inputPlaceholder,
    /// Runs on Confirm before [preConfirm]; return a message to show it.
    String? Function(String value)? inputValidator,
    /// Runs on Confirm with a loader in place of the button. Return null when
    /// done (the popup closes, confirmed) or an error message to show inline.
    Future<String?> Function(String? value)? preConfirm,
    Duration? timer,
    bool timerProgressBar  = false,
    bool allowOutsideClick = true,
  }) async {
    final result = await Navigator.of(context, rootNavigator: true).push<SwalResult>(
      _SwalRoute(
        dismissible: allowOutsideClick,
        builder: (_) => _SwalPopup(
          icon: icon, title: title, text: text, footer: footer,
          showConfirmButton: showConfirmButton,
          confirmButtonText: confirmButtonText, confirmButtonColor: confirmButtonColor,
          showCancelButton: showCancelButton,
          cancelButtonText: cancelButtonText, cancelButtonColor: cancelButtonColor,
          reverseButtons: reverseButtons, buttonTextStyle: buttonTextStyle,
          input: input, inputLabel: inputLabel, inputPlaceholder: inputPlaceholder,
          inputValidator: inputValidator, preConfirm: preConfirm,
          timer: timer, timerProgressBar: timerProgressBar,
        ),
      ),
    );
    return result ?? const SwalResult._(false);
  }
}

// ── Route: backdrop + swal2-show / swal2-hide animations ──────────────────────

class _SwalRoute extends PopupRoute<SwalResult> {
  _SwalRoute({required this.builder, required this.dismissible});
  final WidgetBuilder builder;
  final bool dismissible;

  @override Color  get barrierColor => const Color(0x66000000);   // rgba(0,0,0,.4)
  @override bool   get barrierDismissible => dismissible;
  @override String get barrierLabel => 'Close';
  @override Duration get transitionDuration => const Duration(milliseconds: 300);
  @override Duration get reverseTransitionDuration => const Duration(milliseconds: 150);

  // swal2-show: scale .7 → 1.05 → .95 → 1
  static final _show = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.7, end: 1.05), weight: 45),
    TweenSequenceItem(tween: Tween(begin: 1.05, end: 0.95), weight: 35),
    TweenSequenceItem(tween: Tween(begin: 0.95, end: 1.0), weight: 20),
  ]);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) => builder(context);

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (_, child) {
        final v = animation.value;
        // swal2-hide: shrink to .5 and fade out.
        final hiding = animation.status == AnimationStatus.reverse;
        return Opacity(
          opacity: hiding ? v : (v * 4).clamp(0.0, 1.0),
          child: Transform.scale(scale: hiding ? 0.5 + 0.5 * v : _show.transform(v), child: child),
        );
      },
    );
  }
}

// ── Popup ─────────────────────────────────────────────────────────────────────

class _SwalPopup extends StatefulWidget {
  final SwalIcon? icon;
  final String  title;
  final String? text;
  final Widget? footer;
  final bool    showConfirmButton, showCancelButton, input, timerProgressBar;
  final String  confirmButtonText, cancelButtonText;
  final Color   confirmButtonColor, cancelButtonColor;
  final bool    reverseButtons;
  final TextStyle? buttonTextStyle;
  final String? inputLabel, inputPlaceholder;
  final String? Function(String value)? inputValidator;
  final Future<String?> Function(String? value)? preConfirm;
  final Duration? timer;

  const _SwalPopup({
    required this.icon, required this.title, required this.text, required this.footer,
    required this.showConfirmButton, required this.confirmButtonText,
    required this.confirmButtonColor, required this.showCancelButton,
    required this.cancelButtonText, required this.cancelButtonColor,
    required this.reverseButtons, required this.buttonTextStyle,
    required this.input, required this.inputLabel, required this.inputPlaceholder,
    required this.inputValidator, required this.preConfirm,
    required this.timer, required this.timerProgressBar,
  });

  @override
  State<_SwalPopup> createState() => _SwalPopupState();
}

class _SwalPopupState extends State<_SwalPopup> with SingleTickerProviderStateMixin {
  final _inputCtrl  = TextEditingController();
  final _inputFocus = FocusNode();
  bool    _loading = false;
  String? _validation;
  AnimationController? _timer;

  @override
  void initState() {
    super.initState();
    _inputFocus.addListener(() => setState(() {}));
    if (widget.timer != null) {
      _timer = AnimationController(vsync: this, duration: widget.timer)
        ..addStatusListener((s) {
          // Only close ourselves — never a route opened on top of us.
          if (s == AnimationStatus.completed && mounted &&
              (ModalRoute.of(context)?.isCurrent ?? false)) {
            Navigator.of(context).pop(const SwalResult._(false));
          }
        })
        ..forward();
    }
  }

  @override
  void dispose() {
    _timer?.dispose();
    _inputCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_loading) return;
    final value = widget.input ? _inputCtrl.text : null;
    final invalid = widget.inputValidator?.call(value ?? '');
    if (invalid != null) {
      setState(() => _validation = invalid);
      return;
    }
    if (widget.preConfirm != null) {
      _timer?.stop();
      setState(() { _loading = true; _validation = null; });
      String? error;
      try {
        error = await widget.preConfirm!(value);
      } catch (e) {
        error = friendlyError(e);
      }
      if (!mounted) return;
      if (error != null) {
        setState(() { _loading = false; _validation = error; });
        return;
      }
    }
    if (mounted) Navigator.of(context).pop(SwalResult._(true, value));
  }

  @override
  Widget build(BuildContext context) {
    final dark   = Theme.of(context).brightness == Brightness.dark;
    final bg     = dark ? const Color(0xFF1B1E24) : Colors.white;
    final fg     = dark ? const Color(0xFFE4E7EB) : const Color(0xFF545454);
    final line   = dark ? const Color(0xFF2E333C) : const Color(0xFFEEEEEE);
    final w      = widget;

    final popup = Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(height: 34),
      if (w.icon != null) ...[_SwalIconView(w.icon!), const SizedBox(height: 18)],
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26),
        child: Text(w.title, textAlign: TextAlign.center, style: TextStyle(
            fontFamily: 'Poppins', fontSize: 25, fontWeight: FontWeight.w600,
            color: fg, height: 1.25)),
      ),
      if (w.text != null && w.text!.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
          child: Text(w.text!, textAlign: TextAlign.center, style: TextStyle(
              fontFamily: 'Poppins', fontSize: 15, color: fg, height: 1.55)),
        ),
      if (w.input) _buildInput(dark, fg),
      AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: _validation == null ? const SizedBox(width: double.infinity)
            : _ValidationMessage(_validation!, dark: dark),
      ),
      const SizedBox(height: 22),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 10, runSpacing: 10,
        children: [
          if (w.reverseButtons) ...[
            if (w.showCancelButton)
              _SwalButton(label: w.cancelButtonText, color: w.cancelButtonColor,
                  textStyle: w.buttonTextStyle,
                  onPressed: _loading ? null
                      : () => Navigator.of(context).pop(const SwalResult._(false))),
            if (w.showConfirmButton)
              _loading
                  ? _SwalLoader(color: w.confirmButtonColor)
                  : _SwalButton(label: w.confirmButtonText, color: w.confirmButtonColor,
                      textStyle: w.buttonTextStyle,
                      autofocus: !w.input, onPressed: _confirm),
          ] else ...[
            if (w.showConfirmButton)
              _loading
                  ? _SwalLoader(color: w.confirmButtonColor)
                  : _SwalButton(label: w.confirmButtonText, color: w.confirmButtonColor,
                      textStyle: w.buttonTextStyle,
                      autofocus: !w.input, onPressed: _confirm),
            if (w.showCancelButton)
              _SwalButton(label: w.cancelButtonText, color: w.cancelButtonColor,
                  textStyle: w.buttonTextStyle,
                  onPressed: _loading ? null
                      : () => Navigator.of(context).pop(const SwalResult._(false))),
          ],
        ],
      ),
      if (w.footer != null) ...[
        const SizedBox(height: 18),
        Divider(height: 1, thickness: 1, color: line),
        Padding(padding: const EdgeInsets.only(top: 14), child: w.footer),
      ],
      const SizedBox(height: 22),
      if (_timer != null && w.timerProgressBar)
        AnimatedBuilder(
          animation: _timer!,
          builder: (_, _) => Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 1 - _timer!.value,
              child: Container(height: 4,
                  color: dark ? Colors.white.withValues(alpha: 0.22)
                              : Colors.black.withValues(alpha: 0.2)),
            ),
          ),
        ),
    ]);

    Widget card = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: SizedBox(
        width: double.infinity,
        child: DecoratedBox(
          // No drop shadow — like SweetAlert2, the dimmed backdrop does the work.
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: dark ? Border.all(color: line) : null,
          ),
          child: ClipRRect(borderRadius: BorderRadius.circular(12), child: popup),
        ),
      ),
    );
    // Hovering pauses the auto-close timer (as most SweetAlert2 setups do).
    if (_timer != null) {
      card = MouseRegion(
        onEnter: (_) => _timer!.stop(),
        onExit: (_) { if (!_loading) _timer!.forward(); },
        child: card,
      );
    }

    return PopScope(
      canPop: !_loading,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Material(
              type: MaterialType.transparency,
              child: Semantics(
                namesRoute: true, scopesRoute: true, explicitChildNodes: true,
                label: w.title,
                child: card,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // swal2-input: centred label, field with a soft focus ring.
  Widget _buildInput(bool dark, Color fg) {
    final focused = _inputFocus.hasFocus;
    final border  = dark ? const Color(0xFF3A3F48) : const Color(0xFFD9D9D9);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 18, 32, 0),
      child: Column(children: [
        if (widget.inputLabel != null) ...[
          Text(widget.inputLabel!, textAlign: TextAlign.center, style: TextStyle(
              fontFamily: 'Poppins', fontSize: 13.5, fontWeight: FontWeight.w600, color: fg)),
          const SizedBox(height: 8),
        ],
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            boxShadow: focused
                ? [const BoxShadow(color: Color(0x806496C8), spreadRadius: 3)]
                : const [],
          ),
          child: TextField(
            controller: _inputCtrl,
            focusNode: _inputFocus,
            autofocus: true,
            enabled: !_loading,
            onSubmitted: (_) => _confirm(),
            onChanged: (_) { if (_validation != null) setState(() => _validation = null); },
            style: TextStyle(fontFamily: 'Poppins', fontSize: 15, color: fg),
            decoration: InputDecoration(
              hintText: widget.inputPlaceholder,
              hintStyle: TextStyle(fontFamily: 'Poppins', fontSize: 15,
                  color: fg.withValues(alpha: 0.45)),
              isDense: true,
              filled: true,
              fillColor: dark ? const Color(0xFF15181D) : Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: border)),
              disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFFB4DBED))),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Pieces ────────────────────────────────────────────────────────────────────

/// swal2-validation-message: full-width grey strip with a red "!" badge.
class _ValidationMessage extends StatelessWidget {
  final String message;
  final bool dark;
  const _ValidationMessage(this.message, {required this.dark});

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      color: dark ? const Color(0xFF272B32) : const Color(0xFFF0F0F0),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 22, height: 22,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: Color(0xFFF27474), shape: BoxShape.circle),
          child: const Text('!', style: TextStyle(fontFamily: 'Poppins', fontSize: 13,
              fontWeight: FontWeight.w700, color: Colors.white, height: 1.1)),
        ),
        const SizedBox(width: 10),
        Flexible(child: Text(message, style: TextStyle(fontFamily: 'Poppins', fontSize: 13.5,
            color: dark ? const Color(0xFFC9CED6) : const Color(0xFF666666), height: 1.4))),
      ]),
    ),
  );
}

/// swal2-styled button: solid colour, darker on hover, focus ring.
class _SwalButton extends StatefulWidget {
  final String label;
  final Color  color;
  final TextStyle? textStyle;
  final VoidCallback? onPressed;
  final bool autofocus;
  const _SwalButton({required this.label, required this.color,
      required this.onPressed, this.textStyle, this.autofocus = false});
  @override
  State<_SwalButton> createState() => _SwalButtonState();
}

class _SwalButtonState extends State<_SwalButton> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 120),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      boxShadow: _focused && widget.onPressed != null
          ? [BoxShadow(color: widget.color.withValues(alpha: 0.5), spreadRadius: 3)]
          : const [],
    ),
    // Only watches the button's focus — not a tab stop of its own.
    child: Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) => setState(() => _focused = f),
      child: ElevatedButton(
        autofocus: widget.autofocus,
        onPressed: widget.onPressed,
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.disabled) ? widget.color.withValues(alpha: 0.45)
              : s.contains(WidgetState.hovered) || s.contains(WidgetState.pressed)
                  ? Color.alphaBlend(Colors.black.withValues(alpha: 0.12), widget.color)
                  : widget.color),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 24, vertical: 15)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
          textStyle: WidgetStatePropertyAll(widget.textStyle ??
              const TextStyle(fontFamily: 'Poppins',
                  fontSize: 14.5, fontWeight: FontWeight.w600)),
        ),
        child: Text(widget.label),
      ),
    ),
  );
}

/// swal2-loader: two opposite arcs spinning.
class _SwalLoader extends StatefulWidget {
  final Color color;
  const _SwalLoader({required this.color});
  @override
  State<_SwalLoader> createState() => _SwalLoaderState();
}

class _SwalLoaderState extends State<_SwalLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Working…',
    child: SizedBox(
      width: 50, height: 50,
      child: RotationTransition(turns: _c,
          child: CustomPaint(painter: _LoaderPainter(widget.color))),
    ),
  );
}

class _LoaderPainter extends CustomPainter {
  final Color color;
  _LoaderPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: 15);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -math.pi * 0.75, math.pi * 0.5, false, p);
    canvas.drawArc(rect, math.pi * 0.25, math.pi * 0.5, false, p);
  }
  @override
  bool shouldRepaint(_LoaderPainter old) => old.color != color;
}

// ── Icons ─────────────────────────────────────────────────────────────────────

class _SwalIconView extends StatefulWidget {
  final SwalIcon icon;
  const _SwalIconView(this.icon);
  @override
  State<_SwalIconView> createState() => _SwalIconViewState();
}

class _SwalIconViewState extends State<_SwalIconView> with SingleTickerProviderStateMixin {
  // SweetAlert2's icon colours: ring, mark.
  static const _colors = {
    SwalIcon.success:  (ring: Color(0x4DA5DC86), mark: Color(0xFFA5DC86)),
    SwalIcon.error:    (ring: Color(0xFFF27474), mark: Color(0xFFF27474)),
    SwalIcon.warning:  (ring: Color(0xFFFACEA8), mark: Color(0xFFF8BB86)),
    SwalIcon.info:     (ring: Color(0xFF9DE0F6), mark: Color(0xFF3FC3EE)),
    SwalIcon.question: (ring: Color(0xFFC9DAE1), mark: Color(0xFF87ADBD)),
  };

  late final int _ms = switch (widget.icon) {
    SwalIcon.success  => 850,
    SwalIcon.question => 800,
    _                 => 500,
  };
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Duration(milliseconds: _ms))..forward();

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  // Piecewise-linear keyframes: [(at, value), …] with at in 0..1.
  static double _keys(double t, List<(double, double)> k) {
    if (t <= k.first.$1) return k.first.$2;
    for (var i = 1; i < k.length; i++) {
      if (t <= k[i].$1) {
        final (a, va) = k[i - 1];
        final (b, vb) = k[i];
        return va + (vb - va) * ((t - a) / (b - a));
      }
    }
    return k.last.$2;
  }

  @override
  Widget build(BuildContext context) {
    final c = _colors[widget.icon]!;
    return ExcludeSemantics(
      child: SizedBox(
        width: 80, height: 80,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) {
            final t = _c.value;
            if (widget.icon == SwalIcon.success) {
              // swal2-animate-success-line-tip / -long: the check is drawn.
              return CustomPaint(painter: _IconPainter(SwalIcon.success, c.ring, c.mark,
                  draw: Curves.easeOut.transform(t)));
            }
            // swal2-animate-error-icon: the whole icon flips in (rotateX 100° → 0).
            final f = (t * _ms / 500).clamp(0.0, 1.0);
            final flip = (1 - Curves.easeOut.transform(f)) * 100 * math.pi / 180;
            Widget mark = CustomPaint(size: const Size(80, 80),
                painter: _IconPainter(widget.icon, Colors.transparent, c.mark));
            switch (widget.icon) {
              case SwalIcon.error:
                // swal2-animate-error-x-mark: hidden, then pops in (.4 → 1.15 → 1).
                final s = _keys(t, const [(0, .4), (.5, .4), (.8, 1.15), (1, 1)]);
                final dy = _keys(t, const [(0, 26), (.5, 26), (.8, -6), (1, 0)]);
                mark = Opacity(opacity: _keys(t, const [(0, 0), (.5, 0), (1, 1)]),
                    child: Transform.translate(offset: Offset(0, dy),
                        child: Transform.scale(scale: s, child: mark)));
              case SwalIcon.warning || SwalIcon.info:
                // swal2-animate-i-mark: a little wiggle into place.
                final deg = _keys(t, const [(0, 45), (.25, -25), (.5, 15), (.75, -5), (1, 0)]);
                mark = Opacity(opacity: _keys(t, const [(0, 0), (.25, .4), (.5, .8), (.75, 1)]),
                    child: Transform.rotate(angle: deg * math.pi / 180, child: mark));
              case SwalIcon.question:
                // swal2-animate-question-mark: one turn around the Y axis.
                mark = Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.002)
                      ..rotateY(-2 * math.pi * (1 - Curves.easeOut.transform(t))),
                    child: mark);
              case SwalIcon.success:
                break;
            }
            return Opacity(
              opacity: f,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()..setEntry(3, 2, 0.002)..rotateX(flip),
                child: Stack(children: [
                  CustomPaint(size: const Size(80, 80),
                      painter: _IconPainter(null, c.ring, Colors.transparent)),
                  mark,
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Draws the 80×80 icon: the ring (when [ring] isn't transparent) and the
/// mark for [icon] (when set). [draw] is the success check's progress.
class _IconPainter extends CustomPainter {
  final SwalIcon? icon;
  final Color ring, mark;
  final double draw;
  _IconPainter(this.icon, this.ring, this.mark, {this.draw = 1});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 80, size.height / 80);
    if (ring.a > 0) {
      canvas.drawCircle(const Offset(40, 40), 38, Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4);
    }
    if (icon == null || mark.a == 0) return;
    final p = Paint()
      ..color = mark
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 5.5;
    final dot = Paint()..color = mark;
    switch (icon!) {
      case SwalIcon.success:
        const a = Offset(21, 42), b = Offset(34, 55), c = Offset(60, 29);
        final t1 = (draw / 0.35).clamp(0.0, 1.0), t2 = ((draw - 0.35) / 0.65).clamp(0.0, 1.0);
        if (t1 > 0) canvas.drawLine(a, Offset.lerp(a, b, t1)!, p);
        if (t2 > 0) canvas.drawLine(b, Offset.lerp(b, c, t2)!, p);
      case SwalIcon.error:
        canvas.drawLine(const Offset(24, 24), const Offset(56, 56), p);
        canvas.drawLine(const Offset(56, 24), const Offset(24, 56), p);
      case SwalIcon.warning:
        p.strokeWidth = 6.5;
        canvas.drawLine(const Offset(40, 19), const Offset(40, 47), p);
        canvas.drawCircle(const Offset(40, 60), 4.2, dot);
      case SwalIcon.info:
        p.strokeWidth = 6.5;
        canvas.drawCircle(const Offset(40, 21), 4.2, dot);
        canvas.drawLine(const Offset(40, 34), const Offset(40, 61), p);
      case SwalIcon.question:
        p.strokeWidth = 6.5;
        final q = Path()
          ..moveTo(29.5, 30)
          ..arcToPoint(const Offset(50.5, 30), radius: const Radius.circular(10.5))
          ..cubicTo(50.5, 36, 46.5, 38.5, 43.5, 40.5)
          ..cubicTo(41, 42.2, 40, 44, 40, 47.5);
        canvas.drawPath(q, p);
        canvas.drawCircle(const Offset(40, 60), 4.2, dot);
    }
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.draw != draw || old.icon != icon || old.ring != ring || old.mark != mark;
}

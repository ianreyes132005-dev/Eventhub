import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../models/event_registration.dart';
import '../../core/app_colors.dart';


// ══════════════════════════════════════════════════════════════════════════════
// Registration success popup — auto-dismisses after 3 s then opens QR sheet
// ══════════════════════════════════════════════════════════════════════════════

class RegistrationSuccessPopup {
  RegistrationSuccessPopup._();

  static Future<void> show(
    BuildContext context, {
    required String       eventTitle,
    required VoidCallback onComplete,
  }) =>
      showGeneralDialog<void>(
        context:          context,
        barrierDismissible: false,
        barrierLabel:     '',
        barrierColor:     Colors.black.withValues(alpha: 0.58),
        transitionDuration: const Duration(milliseconds: 380),
        transitionBuilder: (_, anim, _, child) => ScaleTransition(
          scale: Tween<double>(begin: 0.72, end: 1.0).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
          ),
          child: FadeTransition(opacity: anim, child: child),
        ),
        pageBuilder: (ctx, _, _) => _SuccessPopupWidget(
          eventTitle: eventTitle,
          onComplete: onComplete,
        ),
      );
}

class _SuccessPopupWidget extends StatefulWidget {
  final String       eventTitle;
  final VoidCallback onComplete;
  const _SuccessPopupWidget({required this.eventTitle, required this.onComplete});

  @override
  State<_SuccessPopupWidget> createState() => _SuccessPopupWidgetState();
}

class _SuccessPopupWidgetState extends State<_SuccessPopupWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..forward();
    _timer = Timer(const Duration(seconds: 3), _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _progress.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88, height: 88,
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.25),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                size: 48,
                color: Color(0xFF22C55E),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Registration Successful!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily:  'Poppins',
                fontSize:    18,
                fontWeight:  FontWeight.w800,
                color:       Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.eventTitle,
              textAlign:     TextAlign.center,
              maxLines:      2,
              overflow:      TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily:  'Poppins',
                fontSize:    13,
                fontWeight:  FontWeight.w500,
                color:       Color(0xFF64748B),
                height:      1.5,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Your QR ticket is ready.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize:   12,
                color:      Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 26),
            AnimatedBuilder(
              animation: _progress,
              builder: (_, __) => ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value:      _progress.value,
                  backgroundColor: const Color(0xFFE2E8F0),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF22C55E)),
                  minHeight:  5,
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Opening your QR ticket…',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize:   11,
                color:      Color(0xFFB0B8C4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// QR ticket sheet
// ══════════════════════════════════════════════════════════════════════════════

class QRCodeDialog extends StatelessWidget {
  final EventRegistration registration;
  const QRCodeDialog({required this.registration, super.key});

  // Tickets scanned at the door while the app is open — fed by the student
  // dashboard's live registration updates; an open ticket shows "scanned".
  static final ValueNotifier<Set<String>> _scanned = ValueNotifier<Set<String>>(const {});

  static void markScanned(String registrationId) {
    if (_scanned.value.contains(registrationId)) return;
    _scanned.value = {..._scanned.value, registrationId};
  }

  static void show(BuildContext context, EventRegistration registration) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QRCodeDialog(registration: registration),
    );
  }

  String _fmtDate(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final t         = AppTk(Theme.of(context).brightness == Brightness.dark);
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: t.inputBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: t.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 4, 20, bottomPad + 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildHeader(t),
                  ValueListenableBuilder<Set<String>>(
                    valueListenable: _scanned,
                    builder: (_, scanned, _) => AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      child: scanned.contains(registration.registrationId)
                          ? Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: _ScannedBanner(t: t),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildQRSection(t),
                  const SizedBox(height: 14),
                  _buildInfoGrid(t),
                  const SizedBox(height: 12),
                  _buildNote(t),
                  const SizedBox(height: 20),
                  _buildDoneButton(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(AppTk t) {
    return Column(
      children: [
        // "EVENT TICKET" gold badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            gradient: kGoldGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: kGold.withValues(alpha: 0.30),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.confirmation_num_rounded, size: 11, color: Colors.white),
              SizedBox(width: 6),
              Text(
                'EVENT TICKET',
                style: TextStyle(
                  fontFamily:    'Poppins',
                  fontSize:      10,
                  fontWeight:    FontWeight.w800,
                  color:         Colors.white,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          registration.eventTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize:   20,
            fontWeight: FontWeight.w800,
            color:      t.text,
            height:     1.25,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 10),
        // Student name + school ID
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 26, height: 26,
              decoration: const BoxDecoration(
                gradient: kGoldGradient,
                shape:    BoxShape.circle,
              ),
              child: const Icon(Icons.person_rounded, size: 13, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                registration.studentName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize:   13,
                  fontWeight: FontWeight.w600,
                  color:      t.text,
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 3, height: 3,
              decoration: BoxDecoration(color: t.muted, shape: BoxShape.circle),
            ),
            Text(
              registration.studentId,
              style: TextStyle(
                fontFamily: 'Courier',
                fontSize:   12,
                fontWeight: FontWeight.w700,
                color:      t.sub,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── QR section ──────────────────────────────────────────────────────────────

  Widget _buildQRSection(AppTk t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      decoration: BoxDecoration(
        color:        t.bg,
        borderRadius: BorderRadius.circular(24),
        border:       Border.all(color: t.border),
        boxShadow: [
          BoxShadow(color: t.shadow, blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color:        Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color:        kGold.withValues(alpha: 0.14),
                      blurRadius:   32,
                      spreadRadius: 2,
                      offset:       const Offset(0, 6),
                    ),
                    BoxShadow(
                      color:      t.shadow,
                      blurRadius: 20,
                      offset:     const Offset(0, 6),
                    ),
                  ],
                ),
                child: QrImageView(
                  data:            registration.qrCodeData,
                  version:         QrVersions.auto,
                  size:            200,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color:    Color(0xFF1A1209),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color:           Color(0xFF1A1209),
                  ),
                ),
              ),
              Positioned(top: 0,    left: 0,  child: _CornerBracket(top: true,  left: true)),
              Positioned(top: 0,    right: 0, child: _CornerBracket(top: true,  left: false)),
              Positioned(bottom: 0, left: 0,  child: _CornerBracket(top: false, left: true)),
              Positioned(bottom: 0, right: 0, child: _CornerBracket(top: false, left: false)),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color:        kGold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border:       Border.all(color: kGold.withValues(alpha: 0.20)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.qr_code_scanner_rounded, size: 12,
                    color: kGold.withValues(alpha: 0.80)),
                const SizedBox(width: 6),
                Text(
                  'Present this code at the event entrance',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize:   11,
                    fontWeight: FontWeight.w600,
                    color:      kGold.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _Perforation(color: t.border),
          const SizedBox(height: 14),
          _buildTicketStub(t),
        ],
      ),
    );
  }

  // ── Ticket stub — the Ticket ID, big enough to read off the screen ─────────

  Widget _buildTicketStub(AppTk t) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TICKET ID',
                style: TextStyle(
                  fontFamily:    'Poppins',
                  fontSize:      10,
                  fontWeight:    FontWeight.w800,
                  color:         t.muted,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'QR won’t scan? The organizer can type this instead.',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize:   11,
                  color:      t.sub,
                  height:     1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Text(
          registration.ticketCode,
          style: TextStyle(
            fontFamily:    'Poppins',
            fontSize:      30,
            fontWeight:    FontWeight.w800,
            color:         t.text,
            letterSpacing: 3,
            height:        1.1,
          ),
        ),
      ],
    );
  }

  // ── Info grid ───────────────────────────────────────────────────────────────

  Widget _buildInfoGrid(AppTk t) {
    return Container(
      decoration: BoxDecoration(
        color:        t.card,
        borderRadius: BorderRadius.circular(18),
        border:       Border.all(color: t.border),
        boxShadow: [
          BoxShadow(color: t.shadow, blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _InfoCell(icon: Icons.person_rounded, label: 'Student Name',
                    value: registration.studentName, t: t)),
                VerticalDivider(width: 1, thickness: 1, color: t.divider),
                Expanded(child: _InfoCell(icon: Icons.badge_rounded, label: 'School ID',
                    value: registration.studentId, t: t, mono: true)),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: t.divider),
          // The Ticket ID already sits big under the QR, so it isn't repeated.
          SizedBox(
            width: double.infinity,
            child: _InfoCell(icon: Icons.calendar_today_rounded, label: 'Registered On',
                value: _fmtDate(registration.registrationDate), t: t),
          ),
        ],
      ),
    );
  }

  // ── Note ────────────────────────────────────────────────────────────────────

  Widget _buildNote(AppTk t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color:        kGold.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: kGold.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: kGold.withValues(alpha: 0.75), size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Show this QR code at the event entrance. '
              'Don’t share it or your Ticket ID — both are tied to your registration.',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize:   11.5,
                color:      t.sub,
                height:     1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Done button ─────────────────────────────────────────────────────────────

  Widget _buildDoneButton(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color:      kGold.withValues(alpha: 0.34),
            blurRadius: 14,
            offset:     const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: Ink(
            height: 54,
            decoration: const BoxDecoration(gradient: kGoldGradient),
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              child: const Center(
                child: Text(
                  'Close Ticket',
                  style: TextStyle(
                    fontFamily:    'Poppins',
                    fontSize:      15,
                    fontWeight:    FontWeight.w700,
                    color:         Colors.white,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Sub-widgets
// ══════════════════════════════════════════════════════════════════════════════

/// "Ticket scanned" — shown on the open ticket the moment the organizer scans
/// it (with a chime + vibration from ScanFeedback.ticketScanned).
class _ScannedBanner extends StatelessWidget {
  final AppTk t;
  const _ScannedBanner({required this.t});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF16A34A);
    final text = t.dark ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: green.withValues(alpha: t.dark ? 0.16 : 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: green.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: text, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ticket scanned',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 14,
                        fontWeight: FontWeight.w700, color: text)),
                  const SizedBox(height: 1),
                  Text('Stay here — you’ll be asked for a check-in photo next.',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12,
                        color: t.sub, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// The dashed "tear here" line above the ticket stub.
class _Perforation extends StatelessWidget {
  final Color color;
  const _Perforation({required this.color});

  @override
  Widget build(BuildContext context) => SizedBox(
        width:  double.infinity,
        height: 1.5,
        child:  CustomPaint(painter: _DashPainter(color)),
      );
}

class _DashPainter extends CustomPainter {
  final Color color;
  const _DashPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color       = color
      ..strokeWidth = size.height
      ..strokeCap   = StrokeCap.round;
    const dash = 6.0, gap = 5.0;
    final y = size.height / 2;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      canvas.drawLine(Offset(x, y), Offset((x + dash).clamp(0.0, size.width), y), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

class _InfoCell extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  final AppTk    t;
  final bool     mono;

  const _InfoCell({
    required this.icon,
    required this.label,
    required this.value,
    required this.t,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  gradient:     kGoldGradient,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 13, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize:   9.5,
                    fontWeight: FontWeight.w600,
                    color:      t.muted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            value,
            style: TextStyle(
              fontFamily: mono ? 'Courier' : 'Poppins',
              fontSize:   mono ? 12 : 13,
              fontWeight: FontWeight.w700,
              color:      t.text,
              height:     1.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _CornerBracket extends StatelessWidget {
  final bool top;
  final bool left;
  const _CornerBracket({required this.top, required this.left});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24, height: 24,
      child: CustomPaint(
        painter: _CornerPainter(color: kGold, thickness: 3.5, top: top, left: left),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color  color;
  final double thickness;
  final bool   top;
  final bool   left;

  const _CornerPainter({
    required this.color,
    required this.thickness,
    required this.top,
    required this.left,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color       = color
      ..strokeWidth = thickness
      ..style       = PaintingStyle.stroke
      ..strokeCap   = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    canvas.drawLine(
      left ? Offset(0, top ? 0 : h) : Offset(w, top ? 0 : h),
      left ? Offset(w, top ? 0 : h) : Offset(0, top ? 0 : h),
      paint,
    );
    canvas.drawLine(
      left ? Offset(0, top ? 0 : h) : Offset(w, top ? 0 : h),
      left ? Offset(0, top ? h : 0) : Offset(w, top ? h : 0),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CornerPainter old) =>
      old.color != color || old.thickness != thickness;
}

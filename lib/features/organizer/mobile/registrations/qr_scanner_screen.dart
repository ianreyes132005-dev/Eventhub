import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'auto_check_in.dart';
import 'scan_confirm_screen.dart';
import 'ticket_entry_dialog.dart';
import 'package:eventhub/core/services/scan_feedback.dart';
import '../../../../core/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  // ── Camera ──────────────────────────────────────────────────────────────────
  final MobileScannerController _camera = MobileScannerController();
  bool _scanning = true; // false while the Type Ticket ID screens are open
  bool _frontCam = false;

  // ── Scans, one after another (auto_check_in.dart) ───────────────────────────
  final ScanGate _gate = ScanGate();
  bool _checking = false;
  ScanResult? _result; // the last scan's, while it's shown
  bool _showResult = false;
  Color? _frameFlash; // the frame turns green or red for a moment
  Timer? _hideTimer;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _flashTimer?.cancel();
    _camera.dispose();
    super.dispose();
  }

  // ── QR detection ────────────────────────────────────────────────────────────

  // Every new ticket is confirmed on its own — no sheet, no Confirm tap — so
  // the camera stays open for the next student. A ticket still in view is
  // read many times a second; it counts once (ScanGate).
  Future<void> _onDetect(BarcodeCapture capture) async {
    if (!_scanning) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || !_gate.admit(raw, DateTime.now(), busy: _checking)) {
      return;
    }

    _hideTimer?.cancel();
    setState(() {
      _checking = true;
      _result = null; // "Checking ticket…"
      _showResult = true;
    });

    final result = await autoCheckIn(raw);
    // Vibrate once EventHub has checked the ticket: one tap when it went
    // ahead, two when it didn't (ScanFeedback).
    result.ok ? ScanFeedback.accepted() : ScanFeedback.blocked();
    if (!mounted) return;

    _flashTimer?.cancel();
    setState(() {
      _checking = false;
      _result = result;
      _frameFlash = result.ok
          ? const Color(0xFF22C55E)
          : const Color(0xFFEF4444);
    });
    _flashTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _frameFlash = null);
    });
    // Problems stay up a little longer, so they're read.
    _hideTimer = Timer(Duration(seconds: result.ok ? 4 : 6), () {
      if (mounted && !_checking) setState(() => _showResult = false);
    });
  }

  void _flipCamera() {
    _camera.switchCamera();
    setState(() => _frontCam = !_frontCam);
    HapticFeedback.lightImpact();
  }

  // "Type Ticket ID": the 4-digit code under the student's QR, for a ticket
  // the camera can't read. Scanning pauses while the box and the confirm
  // screen are open, so a stray scan can't check someone in behind them.
  Future<void> _showManualEntry() async {
    HapticFeedback.lightImpact();
    setState(() => _scanning = false);
    final qrValue = await showTicketEntryDialog(context);
    if (mounted && qrValue != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ScanConfirmScreen(qrCode: qrValue)),
      );
    }
    if (mounted) setState(() => _scanning = true);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final frameSize = (constraints.maxWidth - 56)
                .clamp(0.0, 320.0)
                .clamp(0.0, constraints.maxHeight * 0.42);
            final frameLeft = (constraints.maxWidth - frameSize) / 2;
            final frameTop = (constraints.maxHeight - frameSize) / 2 - 18;

            return Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(controller: _camera, onDetect: _onDetect),
                CustomPaint(
                  painter: _ScrimPainter(
                    left: frameLeft,
                    top: frameTop,
                    size: frameSize,
                    radius: 20,
                  ),
                  child: const SizedBox.expand(),
                ),
                Positioned(
                  left: frameLeft,
                  top: frameTop,
                  width: frameSize,
                  height: frameSize,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color:
                            _frameFlash ?? Colors.white.withValues(alpha: 0.9),
                        width: _frameFlash == null ? 1.5 : 3,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                Positioned(
                  top: frameTop - 58,
                  left: 24,
                  right: 24,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Scan QR Code',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Student check-in · confirms automatically',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: frameTop + frameSize + 20,
                  left: 24,
                  right: 24,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _showResult
                        ? ScanResultCard(
                            key: ValueKey(_result),
                            result: _result,
                          )
                        : const Column(
                            key: ValueKey('hint'),
                            children: [
                              Text(
                                'Align the QR code within the frame',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Each scan confirms on its own — no tapping',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 0,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _flipCamera,
                              icon: const Icon(
                                Icons.flip_camera_android_rounded,
                              ),
                              label: Text(
                                _frontCam ? 'Front camera' : 'Rear camera',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.55),
                                ),
                                backgroundColor: Colors.black.withValues(
                                  alpha: 0.38,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                textStyle: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _showManualEntry,
                              icon: const Icon(Icons.keyboard_rounded),
                              label: const Text('Type Ticket ID'),
                              style: FilledButton.styleFrom(
                                backgroundColor: kGold,
                                foregroundColor: const Color(0xFF211A0D),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                textStyle: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom painters
// ─────────────────────────────────────────────────────────────────────────────

/// Draws a subtle dark scrim around the camera's scan area.
class _ScrimPainter extends CustomPainter {
  final double left;
  final double top;
  final double size;
  final double radius;

  const _ScrimPainter({
    required this.left,
    required this.top,
    required this.size,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final scrimPaint = Paint()..color = Colors.black.withValues(alpha: 0.73);

    final rrect = RRect.fromLTRBR(
      left,
      top,
      left + size,
      top + size,
      Radius.circular(radius),
    );

    canvas.drawPath(
      Path()
        ..addRect(Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height))
        ..addRRect(rrect)
        ..fillType = PathFillType.evenOdd,
      scrimPaint,
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter o) =>
      o.left != left || o.top != top || o.size != size || o.radius != radius;
}

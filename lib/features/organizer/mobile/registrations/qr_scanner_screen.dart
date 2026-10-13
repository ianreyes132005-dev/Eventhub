import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'scan_confirm_screen.dart';
import 'package:eventhub/core/services/registration_service.dart';
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
  bool _scanning = true;
  bool _frontCam = false;
  bool _showingSheet = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  }

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  // ── QR detection ────────────────────────────────────────────────────────────

  void _onDetect(BarcodeCapture capture) {
    if (!_scanning || _showingSheet) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    setState(() {
      _scanning = false;
      _showingSheet = true;
    });
    HapticFeedback.mediumImpact();

    // Show the result sheet over the live camera — no route push needed
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      enableDrag: false,
      builder: (_) => _ScanResultSheet(qrCode: raw),
    ).then((_) {
      if (!mounted) return;
      // Scanner resets automatically when the sheet closes for any reason
      setState(() {
        _scanning = true;
        _showingSheet = false;
      });
    });
  }

  void _flipCamera() {
    _camera.switchCamera();
    setState(() => _frontCam = !_frontCam);
    HapticFeedback.lightImpact();
  }

  void _showManualEntry() {
    HapticFeedback.lightImpact();
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1C1814),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: kGold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.keyboard_rounded,
                      color: kGold,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Enter Code Manually',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Paste or type the registration ID',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: ctrl,
                autofocus: true,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  hintText: 'e.g. a1b2c3d4-…',
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.07),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: kGold, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          color: Colors.white60,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () {
                        final code = ctrl.text.trim();
                        if (code.isEmpty) return;
                        Navigator.pop(ctx);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ScanConfirmScreen(qrCode: code),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kGold,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Look Up',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.9),
                        width: 1.5,
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
                        'Student check-in',
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
                  child: const Column(
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
                        'Keep the ticket steady until it scans',
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
                              label: const Text('Enter code'),
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
// _ScanResultSheet — shown over the live camera after every successful scan
// ─────────────────────────────────────────────────────────────────────────────

class _ScanResultSheet extends StatefulWidget {
  final String qrCode;
  const _ScanResultSheet({required this.qrCode});

  @override
  State<_ScanResultSheet> createState() => _ScanResultSheetState();
}

class _ScanResultSheetState extends State<_ScanResultSheet> {
  Map<String, dynamic>? _reg;
  bool _loading = true;
  bool _confirming = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final reg = await RegistrationService.getByQRCode(widget.qrCode);
      if (reg == null) {
        if (mounted)
          setState(() {
            _error = 'No registration found for this QR code.';
            _loading = false;
          });
        return;
      }
      if (reg['status'] == 'pending') {
        await RegistrationService.updateStatus(
          reg['id'] as String,
          'qr_scanned',
        );
        reg['status'] = 'qr_scanned';
      }
      if (mounted)
        setState(() {
          _reg = reg;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  Future<void> _confirm() async {
    if (_reg == null) return;
    setState(() => _confirming = true);
    try {
      await RegistrationService.updateStatus(
        _reg!['id'] as String,
        'photo_required',
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _confirming = false);
        _snack('Error: $e', Colors.red);
      }
    }
  }

  Future<void> _retrigger() async {
    if (_reg == null) return;
    setState(() => _confirming = true);
    try {
      await RegistrationService.updateStatus(
        _reg!['id'] as String,
        'photo_required',
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _confirming = false);
        _snack('Error: $e', Colors.red);
      }
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottomPad + 12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1C1814),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: _loading
            ? _buildLoading()
            : _error != null
            ? _buildError()
            : _buildContent(),
      ),
    );
  }

  Widget _buildLoading() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 52),
    child: Center(
      child: CircularProgressIndicator(color: kGold, strokeWidth: 2.5),
    ),
  );

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          _DragHandle(),
          const SizedBox(height: 20),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.qr_code_2, color: Colors.red, size: 28),
          ),
          const SizedBox(height: 14),
          const Text(
            'Invalid QR Code',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.45),
              height: 1.55,
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Dismiss — Scan Next',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  color: Colors.white60,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final reg = _reg!;
    final status = reg['status'] as String? ?? '';
    final name = reg['student_name'] as String? ?? '—';
    final sid = reg['student_school_id'] as String? ?? '—';
    final title = reg['event_title'] as String? ?? '—';

    final canRetrigger = status == 'photo_required';
    final isFinal =
        status == 'photo_submitted' ||
        status == 'checked_in' ||
        status == 'rejected';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          _DragHandle(),
          const SizedBox(height: 18),

          // Student row
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: kGold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    _initials(name),
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: kGold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sid,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _SheetStatusChip(status: status),
            ],
          ),

          const SizedBox(height: 14),

          // Event row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.event_rounded,
                  color: Colors.white.withValues(alpha: 0.35),
                  size: 14,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Primary action
          if (isFinal)
            _buildFinalBanner(status)
          else if (canRetrigger)
            _buildRetriggerBtn()
          else
            _buildConfirmBtn(),

          const SizedBox(height: 10),

          // Dismiss link
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withValues(alpha: 0.35),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            child: const Text(
              'Dismiss — Scan Next Student',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Action builders ───────────────────────────────────────────────────────

  Widget _buildConfirmBtn() => ElevatedButton.icon(
    onPressed: _confirming ? null : _confirm,
    icon: _confirming
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2,
            ),
          )
        : const Icon(Icons.camera_alt_rounded, size: 18),
    label: Text(
      _confirming ? 'Opening camera…' : 'Confirm — Open Student Camera',
      style: const TextStyle(
        fontFamily: 'Poppins',
        fontWeight: FontWeight.w700,
        fontSize: 14,
      ),
    ),
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF16A34A),
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
    ),
  );

  Widget _buildRetriggerBtn() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.30)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.amber.shade600,
              size: 17,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Student dismissed the camera. Tap below to re-open it.',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11.5,
                  color: Colors.amber.shade300,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
      ElevatedButton.icon(
        onPressed: _confirming ? null : _retrigger,
        icon: _confirming
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.refresh_rounded, size: 18),
        label: Text(
          _confirming ? 'Re-opening camera…' : 'Re-open Student Camera',
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF9333EA),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
      ),
    ],
  );

  Widget _buildFinalBanner(String status) {
    final (Color color, IconData icon, String text) = switch (status) {
      'checked_in' => (
        const Color(0xFF16A34A),
        Icons.check_circle_rounded,
        'Already checked in',
      ),
      'photo_submitted' => (
        const Color(0xFF0891B2),
        Icons.photo_camera_rounded,
        'Selfie already submitted',
      ),
      _ => (
        const Color(0xFFDC2626),
        Icons.cancel_rounded,
        'Registration rejected',
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts.isNotEmpty && parts[0].isNotEmpty
        ? parts[0][0].toUpperCase()
        : '?';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

/// Status chip rendered inside the dark sheet — uses its own color mapping.
class _SheetStatusChip extends StatelessWidget {
  final String status;
  const _SheetStatusChip({required this.status});

  static const _labels = {
    'pending': 'Pending',
    'qr_scanned': 'QR Scanned',
    'photo_required': 'Awaiting Selfie',
    'photo_submitted': 'Photo Submitted',
    'checked_in': 'Checked In',
    'rejected': 'Rejected',
  };

  static Color _color(String s) {
    switch (s) {
      case 'pending':
        return const Color(0xFFE87A00);
      case 'qr_scanned':
        return const Color(0xFF2979C8);
      case 'photo_required':
        return const Color(0xFF9333EA);
      case 'photo_submitted':
        return const Color(0xFF0891B2);
      case 'checked_in':
        return const Color(0xFF16A34A);
      case 'rejected':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFF9CA3AF);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        _labels[status] ?? status,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.2,
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

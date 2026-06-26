import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'scan_confirm_screen.dart';
import 'package:eventhub/core/services/registration_service.dart';
import '../../../../core/app_colors.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const Color kGoldDk   = Color(0xFFC49230);
const Color kGoldLt   = Color(0xFFEAB866);
const Color _kSuccess = Color(0xFF22C55E);

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen>
    with TickerProviderStateMixin {
  // ── Camera ──────────────────────────────────────────────────────────────────
  final MobileScannerController _camera = MobileScannerController();
  bool _scanning     = true;
  bool _torchOn      = false;
  bool _frontCam     = false;
  bool _detected     = false;
  bool _showingSheet = false;

  // ── Animation controllers ───────────────────────────────────────────────────
  late final AnimationController _lineCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _successCtrl;
  late final AnimationController _bannerCtrl;

  // 0 â†’ 1, drives scan-line from top to bottom of frame
  late final Animation<double> _lineFrac;
  // 1.00 â†’ 1.04, subtle corner-bracket breathe
  late final Animation<double> _cornerScale;
  // 0 â†’ 1 on detect, fades success overlay
  late final Animation<double> _successFrac;
  // Slides the top success banner in/out
  late final Animation<Offset> _bannerSlide;
  late final Animation<double> _bannerFade;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    _lineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _lineFrac = CurvedAnimation(parent: _lineCtrl, curve: Curves.easeInOut);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _cornerScale = Tween<double>(begin: 1.00, end: 1.035).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _successCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    );
    _successFrac = CurvedAnimation(parent: _successCtrl, curve: Curves.easeOut);

    _bannerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _bannerSlide = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: _bannerCtrl, curve: Curves.easeOut));
    _bannerFade = CurvedAnimation(parent: _bannerCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _camera.dispose();
    _lineCtrl.dispose();
    _pulseCtrl.dispose();
    _successCtrl.dispose();
    _bannerCtrl.dispose();
    super.dispose();
  }

  // ── QR detection ────────────────────────────────────────────────────────────

  void _onDetect(BarcodeCapture capture) {
    if (!_scanning || _showingSheet) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    setState(() {
      _scanning     = false;
      _detected     = true;
      _showingSheet = true;
    });
    HapticFeedback.mediumImpact();
    _successCtrl.forward();

    // Slide in the green top banner, auto-hide after 2.8 s
    _bannerCtrl.forward();
    Future.delayed(const Duration(milliseconds: 2800), () {
      if (mounted) _bannerCtrl.reverse();
    });

    // Show the result sheet over the live camera — no route push needed
    showModalBottomSheet<void>(
      context:            context,
      isScrollControlled: true,
      backgroundColor:    Colors.transparent,
      barrierColor:       Colors.black.withValues(alpha: 0.45),
      enableDrag:         false,
      builder: (_) => _ScanResultSheet(qrCode: raw),
    ).then((_) {
      if (!mounted) return;
      // Scanner resets automatically when the sheet closes for any reason
      setState(() {
        _scanning     = true;
        _detected     = false;
        _showingSheet = false;
      });
      _successCtrl.reset();
    });
  }

  void _toggleTorch() {
    _camera.toggleTorch();
    setState(() => _torchOn = !_torchOn);
    HapticFeedback.lightImpact();
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
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: kGold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.keyboard_rounded, color: kGold, size: 20),
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
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
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
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ScanConfirmScreen(qrCode: code),
                        ));
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
    final scr       = MediaQuery.of(context).size;
    final topPad    = MediaQuery.of(context).padding.top;
    final frameSize = scr.width * 0.72;
    final frameLeft = (scr.width  - frameSize) / 2;
    final frameTop  = (scr.height - frameSize) / 2 - 28.0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // ── 1 · Camera preview ──────────────────────────────────────────
            MobileScanner(controller: _camera, onDetect: _onDetect),

            // ── 2 · Dark scrim with rounded-rect cutout ──────────────────────
            CustomPaint(
              painter: _ScrimPainter(
                left: frameLeft, top: frameTop,
                size: frameSize, radius: 22,
              ),
              child: const SizedBox.expand(),
            ),

            // ── 3 · Corner brackets (animated scale + colour morph) ───────────
            AnimatedBuilder(
              animation: Listenable.merge([_cornerScale, _successFrac]),
              builder: (_, __) {
                final bracketColor =
                    Color.lerp(kGold, _kSuccess, _successFrac.value)!;
                return Positioned(
                  left: frameLeft, top: frameTop,
                  width: frameSize, height: frameSize,
                  child: Transform.scale(
                    scale: _cornerScale.value,
                    child: CustomPaint(
                      painter: _CornerBracketPainter(
                        color:     bracketColor,
                        arm:       46,
                        thickness: 4,
                        radius:    22,
                      ),
                    ),
                  ),
                );
              },
            ),

            // ── 4 · Scan beam (hidden once QR detected) ──────────────────────
            if (_scanning)
              AnimatedBuilder(
                animation: Listenable.merge([_lineFrac, _successFrac]),
                builder: (_, __) {
                  final beamColor =
                      Color.lerp(kGold, _kSuccess, _successFrac.value * 0.5)!;
                  return Positioned(
                    left: frameLeft + 18,
                    top:  frameTop + (_lineFrac.value * (frameSize - 3)),
                    child: Container(
                      width:  frameSize - 36,
                      height: 2.5,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            beamColor.withValues(alpha: 0.25),
                            beamColor.withValues(alpha: 0.85),
                            beamColor,
                            beamColor.withValues(alpha: 0.85),
                            beamColor.withValues(alpha: 0.25),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.1, 0.3, 0.5, 0.7, 0.9, 1.0],
                        ),
                      ),
                    ),
                  );
                },
              ),

            // ── 5 · Green success flash inside the frame ─────────────────────
            AnimatedBuilder(
              animation: _successFrac,
              builder: (_, __) {
                if (_successFrac.value == 0) return const SizedBox.shrink();
                return Positioned(
                  left:   frameLeft + 4,
                  top:    frameTop  + 4,
                  width:  frameSize - 8,
                  height: frameSize - 8,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _kSuccess.withValues(
                        alpha: (1.0 - _successFrac.value) * 0.28,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                );
              },
            ),

            // ── 6 · Top navigation bar ────────────────────────────────────────
            SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    _NavButton(
                      icon:  Icons.arrow_back_ios_new_rounded,
                      onTap: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Text(
                          'Scan QR Code',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize:   17,
                            fontWeight: FontWeight.w700,
                            color:      Colors.white,
                            letterSpacing: 0.2,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Student check-in',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize:   11,
                            fontWeight: FontWeight.w400,
                            color:      Colors.white38,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    _NavButton(
                      icon:   _torchOn
                          ? Icons.flash_on_rounded
                          : Icons.flash_off_rounded,
                      onTap:  _toggleTorch,
                      active: _torchOn,
                    ),
                  ],
                ),
              ),
            ),

            // ── 7 · Instruction text above frame ─────────────────────────────
            Positioned(
              top:   frameTop - 52,
              left:  0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.qr_code_2_rounded,
                        color: Colors.white.withValues(alpha: 0.55),
                        size: 14,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'Point at the student\'s QR ticket',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize:   12,
                          fontWeight: FontWeight.w500,
                          color:      Colors.white.withValues(alpha: 0.70),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── 8 · Status pill below frame ───────────────────────────────────
            Positioned(
              top:   frameTop + frameSize + 22,
              left:  0,
              right: 0,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(scale: anim, child: child),
                  ),
                  child: _detected
                      ? _StatusPill.success(key: const ValueKey('ok'))
                      : _StatusPill.scanning(key: const ValueKey('scan')),
                ),
              ),
            ),

            // ── 9 · Bottom glass panel ────────────────────────────────────────
            Positioned(
              bottom: 0,
              left:   0,
              right:  0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10),
                            width: 1,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 20, horizontal: 12,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _PanelButton(
                              icon:   _torchOn
                                  ? Icons.flash_on_rounded
                                  : Icons.flash_off_rounded,
                              label:  _torchOn ? 'Flash On' : 'Flash Off',
                              active: _torchOn,
                              onTap:  _toggleTorch,
                            ),
                            _PanelDivider(),
                            _PanelButton(
                              icon:  Icons.flip_camera_ios_rounded,
                              label: _frontCam ? 'Front Cam' : 'Rear Cam',
                              onTap: _flipCamera,
                            ),
                            _PanelDivider(),
                            _PanelButton(
                              icon:  Icons.keyboard_alt_outlined,
                              label: 'Manual',
                              onTap: _showManualEntry,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── 10 · Top success banner (slides in from above nav bar) ─────────
            AnimatedBuilder(
              animation: _bannerCtrl,
              builder: (_, __) {
                if (_bannerCtrl.value == 0) return const SizedBox.shrink();
                return Positioned(
                  top:   topPad + 68,
                  left:  20,
                  right: 20,
                  child: SlideTransition(
                    position: _bannerSlide,
                    child: FadeTransition(
                      opacity: _bannerFade,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        decoration: BoxDecoration(
                          color: _kSuccess,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color:      _kSuccess.withValues(alpha: 0.38),
                              blurRadius: 20,
                              offset:     const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_rounded,
                                color: Colors.white, size: 17),
                            SizedBox(width: 10),
                            Text(
                              'QR Code Scanned Successfully',
                              style: TextStyle(
                                fontFamily:  'Poppins',
                                fontSize:    13,
                                fontWeight:  FontWeight.w700,
                                color:       Colors.white,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
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
  bool    _loading    = true;
  bool    _confirming = false;
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
        if (mounted) setState(() { _error = 'No registration found for this QR code.'; _loading = false; });
        return;
      }
      if (reg['status'] == 'pending') {
        await RegistrationService.updateStatus(reg['id'] as String, 'qr_scanned');
        reg['status'] = 'qr_scanned';
      }
      if (mounted) setState(() { _reg = reg; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _confirm() async {
    if (_reg == null) return;
    setState(() => _confirming = true);
    try {
      await RegistrationService.updateStatus(_reg!['id'] as String, 'photo_required');
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
      await RegistrationService.updateStatus(_reg!['id'] as String, 'photo_required');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _confirming = false);
        _snack('Error: $e', Colors.red);
      }
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottomPad + 12),
      child: Container(
        decoration: BoxDecoration(
          color:        const Color(0xFF1C1814),
          borderRadius: BorderRadius.circular(28),
          border:       Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
    child: Center(child: CircularProgressIndicator(color: kGold, strokeWidth: 2.5)),
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
            width: 56, height: 56,
            decoration: BoxDecoration(
              color:        Colors.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.qr_code_2, color: Colors.red, size: 28),
          ),
          const SizedBox(height: 14),
          const Text(
            'Invalid QR Code',
            style: TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w700,
              fontSize: 16, color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins', fontSize: 12,
              color: Colors.white.withValues(alpha: 0.45), height: 1.55,
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text(
                'Dismiss — Scan Next',
                style: TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w600,
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
    final reg    = _reg!;
    final status = reg['status']           as String? ?? '';
    final name   = reg['student_name']     as String? ?? '—';
    final sid    = reg['student_school_id'] as String? ?? '—';
    final title  = reg['event_title']      as String? ?? '—';

    final canRetrigger = status == 'photo_required';
    final isFinal      = status == 'photo_submitted' ||
                         status == 'checked_in'      ||
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
                width: 50, height: 50,
                decoration: BoxDecoration(
                  color:        kGold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    _initials(name),
                    style: const TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w800,
                      fontSize: 17, color: kGold,
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
                        fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                        fontSize: 16, color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sid,
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 12,
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
              color:        Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border:       Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: Row(
              children: [
                Icon(Icons.event_rounded,
                    color: Colors.white.withValues(alpha: 0.35), size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Poppins', fontSize: 12,
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
                fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w500,
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
            width: 18, height: 18,
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
          )
        : const Icon(Icons.camera_alt_rounded, size: 18),
    label: Text(
      _confirming ? 'Opening camera…' : 'Confirm — Open Student Camera',
      style: const TextStyle(
        fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14,
      ),
    ),
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF16A34A),
      foregroundColor: Colors.white,
      padding:  const EdgeInsets.symmetric(vertical: 15),
      shape:    RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
    ),
  );

  Widget _buildRetriggerBtn() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        margin:  const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color:  Colors.amber.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.30)),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: Colors.amber.shade600, size: 17),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Student dismissed the camera. Tap below to re-open it.',
                style: TextStyle(
                  fontFamily: 'Poppins', fontSize: 11.5,
                  color: Colors.amber.shade300, height: 1.45,
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
                width: 18, height: 18,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : const Icon(Icons.refresh_rounded, size: 18),
        label: Text(
          _confirming ? 'Re-opening camera…' : 'Re-open Student Camera',
          style: const TextStyle(
            fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF9333EA),
          foregroundColor: Colors.white,
          padding:  const EdgeInsets.symmetric(vertical: 15),
          shape:    RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
      ),
    ],
  );

  Widget _buildFinalBanner(String status) {
    final (Color color, IconData icon, String text) = switch (status) {
      'checked_in'      => (const Color(0xFF16A34A), Icons.check_circle_rounded,  'Already checked in'),
      'photo_submitted' => (const Color(0xFF0891B2), Icons.photo_camera_rounded,   'Selfie already submitted'),
      _                 => (const Color(0xFFDC2626), Icons.cancel_rounded,          'Registration rejected'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w700,
              fontSize: 13, color: color,
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
      width: 36, height: 4,
      decoration: BoxDecoration(
        color:        Colors.white.withValues(alpha: 0.15),
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
    'pending':         'Pending',
    'qr_scanned':      'QR Scanned',
    'photo_required':  'Awaiting Selfie',
    'photo_submitted': 'Photo Submitted',
    'checked_in':      'Checked In',
    'rejected':        'Rejected',
  };

  static Color _color(String s) {
    switch (s) {
      case 'pending':         return const Color(0xFFE87A00);
      case 'qr_scanned':     return const Color(0xFF2979C8);
      case 'photo_required': return const Color(0xFF9333EA);
      case 'photo_submitted':return const Color(0xFF0891B2);
      case 'checked_in':     return const Color(0xFF16A34A);
      case 'rejected':       return const Color(0xFFDC2626);
      default:               return const Color(0xFF9CA3AF);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border:       Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        _labels[status] ?? status,
        style: TextStyle(
          fontFamily:  'Poppins',
          fontSize:    9.5,
          fontWeight:  FontWeight.w700,
          color:       color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Circular button used in the top navigation bar.
class _NavButton extends StatelessWidget {
  final IconData     icon;
  final VoidCallback onTap;
  final bool         active;

  const _NavButton({
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width:  44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? kGold.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.12),
          border: Border.all(
            color: active
                ? kGold.withValues(alpha: 0.65)
                : Colors.white.withValues(alpha: 0.22),
            width: 1.2,
          ),
        ),
        child: Icon(icon, size: 19, color: active ? kGold : Colors.white),
      ),
    );
  }
}

/// Control button inside the bottom glass panel.
class _PanelButton extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final VoidCallback onTap;
  final bool         active;

  const _PanelButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = active ? kGold : Colors.white;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 76,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width:  52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? kGold.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.07),
                border: Border.all(
                  color: active
                      ? kGold.withValues(alpha: 0.55)
                      : Colors.white.withValues(alpha: 0.18),
                  width: 1.5,
                ),
              ),
              child: Icon(icon, color: fg, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize:   11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                color:      active
                    ? kGold
                    : Colors.white.withValues(alpha: 0.60),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thin vertical divider between panel buttons.
class _PanelDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width:  1,
    height: 36,
    color:  Colors.white.withValues(alpha: 0.10),
  );
}

/// Status pill shown below the scan frame.
class _StatusPill extends StatelessWidget {
  final Color    color;
  final IconData icon;
  final String   label;
  final bool     pulse;

  const _StatusPill({
    super.key,
    required this.color,
    required this.icon,
    required this.label,
    this.pulse = false,
  });

  factory _StatusPill.scanning({Key? key}) => _StatusPill(
    key:   key,
    color: kGold,
    icon:  Icons.qr_code_scanner_rounded,
    label: 'Ready to scan',
    pulse: true,
  );

  factory _StatusPill.success({Key? key}) => _StatusPill(
    key:   key,
    color: _kSuccess,
    icon:  Icons.check_circle_rounded,
    label: 'QR Code Detected!',
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
        border:       Border.all(color: color.withValues(alpha: 0.50), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          pulse
              ? _PulseDot(color: color)
              : Icon(icon, color: color, size: 15),
          const SizedBox(width: 9),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize:   13,
              fontWeight: FontWeight.w600,
              color:      color,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated pulsing circle for the "Ready" status.
class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width:  8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: _anim.value),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom painters
// ─────────────────────────────────────────────────────────────────────────────

/// Draws a 73%-opaque scrim over the full canvas with a rounded-rect hole.
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
    final scrimPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.73);

    final rrect = RRect.fromLTRBR(
      left, top, left + size, top + size, Radius.circular(radius),
    );

    canvas.drawPath(
      Path()
        ..addRect(Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height))
        ..addRRect(rrect)
        ..fillType = PathFillType.evenOdd,
      scrimPaint,
    );

    canvas.drawRRect(
      rrect,
      Paint()
        ..color       = kGold.withValues(alpha: 0.10)
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter o) =>
      o.left != left || o.top != top || o.size != size || o.radius != radius;
}

/// Draws four L-shaped corner brackets.
class _CornerBracketPainter extends CustomPainter {
  final Color  color;
  final double arm;
  final double thickness;
  final double radius;

  const _CornerBracketPainter({
    required this.color,
    required this.arm,
    required this.thickness,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color       = color
      ..style       = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap   = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    final r = radius;

    void line(Offset a, Offset b) => canvas.drawLine(a, b, p);

    // Top-left
    line(Offset(r,     0),      Offset(r + arm,      0));
    line(Offset(0,     r),      Offset(0,             r + arm));
    // Top-right
    line(Offset(w - r, 0),      Offset(w - r - arm,  0));
    line(Offset(w,     r),      Offset(w,             r + arm));
    // Bottom-left
    line(Offset(r,     h),      Offset(r + arm,      h));
    line(Offset(0,     h - r),  Offset(0,             h - r - arm));
    // Bottom-right
    line(Offset(w - r, h),      Offset(w - r - arm,  h));
    line(Offset(w,     h - r),  Offset(w,             h - r - arm));
  }

  @override
  bool shouldRepaint(_CornerBracketPainter o) =>
      o.color != color || o.arm != arm ||
      o.thickness != thickness || o.radius != radius;
}

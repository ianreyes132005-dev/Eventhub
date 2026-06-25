import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../models/event_registration.dart';
import '../../core/app_colors.dart';


// ══════════════════════════════════════════════════════════════════════════════
// Dialog
// ══════════════════════════════════════════════════════════════════════════════

class QRCodeDialog extends StatelessWidget {
  final EventRegistration registration;
  const QRCodeDialog({required this.registration, super.key});

  static void show(BuildContext context, EventRegistration registration) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QRCodeDialog(registration: registration),
    );
  }

  String get _shortId {
    final id = registration.registrationId;
    return id.length > 10 ? '#…${id.substring(id.length - 8)}' : '#$id';
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
            padding: const EdgeInsets.only(top: 12, bottom: 4),
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
              padding: EdgeInsets.fromLTRB(20, 8, 20, bottomPad + 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildHeader(t),
                  const SizedBox(height: 22),
                  _buildQRSection(t),
                  const SizedBox(height: 14),
                  _buildInfoGrid(t),
                  const SizedBox(height: 12),
                  _buildNote(t),
                  const SizedBox(height: 20),
                  _buildDoneButton(context, t),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(AppTk t) {
    return Column(
      children: [
        Container(
          width: 44, height: 3,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFC49230), kGold, Color(0xFFEAB866)],
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF16A34A).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF16A34A).withValues(alpha: 0.28),
              width: 1.2,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 14),
              SizedBox(width: 6),
              Text(
                'Successfully Registered',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF16A34A),
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
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: t.text,
            height: 1.25,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 5),
        Text(
          registration.studentName,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: t.sub,
          ),
        ),
      ],
    );
  }

  Widget _buildQRSection(AppTk t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: t.shadow,
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: QrImageView(
                  data: registration.qrCodeData,
                  version: QrVersions.auto,
                  size: 196,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF1A1209),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF1A1209),
                  ),
                ),
              ),
              Positioned(top: 0,    left: 0,  child: _CornerBracket(top: true,  left: true)),
              Positioned(top: 0,    right: 0, child: _CornerBracket(top: true,  left: false)),
              Positioned(bottom: 0, left: 0,  child: _CornerBracket(top: false, left: true)),
              Positioned(bottom: 0, right: 0, child: _CornerBracket(top: false, left: false)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.qr_code_scanner_rounded, size: 13, color: t.muted),
              const SizedBox(width: 6),
              Text(
                'Present this code at check-in',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: t.muted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoGrid(AppTk t) {
    return Container(
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.border),
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
                Expanded(child: _InfoCell(icon: Icons.person_rounded,   label: 'Student Name', value: registration.studentName, t: t)),
                VerticalDivider(width: 1, thickness: 1, color: t.divider),
                Expanded(child: _InfoCell(icon: Icons.badge_rounded,    label: 'School ID',    value: registration.studentId,   t: t, mono: true)),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: t.divider),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _InfoCell(icon: Icons.calendar_today_rounded,   label: 'Registered On', value: _fmtDate(registration.registrationDate), t: t)),
                VerticalDivider(width: 1, thickness: 1, color: t.divider),
                Expanded(child: _InfoCell(icon: Icons.confirmation_num_rounded, label: 'Ticket ID',     value: _shortId, t: t, mono: true)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNote(AppTk t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: kGold.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kGold.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: kGold.withValues(alpha: 0.75), size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Show this QR code at the event entrance. '
              'Do not share it — this ticket is uniquely tied to your registration.',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11.5,
                color: t.sub,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoneButton(BuildContext context, AppTk t) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: () => Navigator.of(context).pop(),
        style: ElevatedButton.styleFrom(
          backgroundColor: kGold,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: const Text(
          'Done',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Sub-widgets
// ══════════════════════════════════════════════════════════════════════════════

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
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: kGold.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, size: 12, color: kGold),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Poppins', fontSize: 9.5,
                    fontWeight: FontWeight.w600, color: t.muted,
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
              fontSize: mono ? 12 : 13,
              fontWeight: FontWeight.w700,
              color: t.text,
              height: 1.2,
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

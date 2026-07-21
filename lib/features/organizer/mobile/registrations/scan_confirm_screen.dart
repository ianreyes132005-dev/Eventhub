import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/services/registration_service.dart';
import '../../../../core/app_colors.dart';

/// Shown after the organizer scans a student's QR code.
/// Handles all status transitions including re-triggering the selfie camera
/// when the student accidentally dismissed it.
class ScanConfirmScreen extends StatefulWidget {
  final String qrCode;
  const ScanConfirmScreen({required this.qrCode, super.key});

  @override
  State<ScanConfirmScreen> createState() => _ScanConfirmScreenState();
}

class _ScanConfirmScreenState extends State<ScanConfirmScreen> {
  Map<String, dynamic>? _reg;
  bool _loading    = true;
  bool _confirming = false;
  String? _error;

  AppTk get _t => AppTk(Theme.of(context).brightness == Brightness.dark);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final reg = await RegistrationService.getByQRCode(widget.qrCode);
      if (reg == null) {
        setState(() { _error = 'No registration found for this QR code.'; _loading = false; });
        return;
      }
      // Auto-advance pending â†’ qr_scanned on first scan
      if (reg['status'] == 'pending') {
        await RegistrationService.updateStatus(reg['id'] as String, 'qr_scanned');
        reg['status'] = 'qr_scanned';
      }
      setState(() { _reg = reg; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  /// First-time confirm: sets status â†’ photo_required, opening student camera.
  Future<void> _confirm() async {
    if (_reg == null) return;
    HapticFeedback.mediumImpact();
    setState(() => _confirming = true);
    try {
      await RegistrationService.updateStatus(_reg!['id'] as String, 'photo_required');
      if (mounted) {
        _showSnack("Student's camera has been opened — waiting for selfie.", Colors.green);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  /// Re-trigger: student dismissed the camera. Writing photo_required again
  /// fires a Supabase realtime UPDATE on the student's device and re-opens
  /// their front camera immediately.
  Future<void> _retriggerCamera() async {
    if (_reg == null) return;
    HapticFeedback.lightImpact();
    setState(() => _confirming = true);
    try {
      await RegistrationService.updateStatus(_reg!['id'] as String, 'photo_required');
      if (mounted) {
        _showSnack("Camera re-opened on student's device.", Colors.green);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = AppTk(Theme.of(context).brightness == Brightness.dark);
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.card,
        foregroundColor: t.text,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Confirm Check-In',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 17),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kGold))
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  // ── Error state ───────────────────────────────────────────────────────────

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(24)),
              child: Icon(Icons.qr_code_2, size: 40, color: Colors.red.shade400),
            ),
            const SizedBox(height: 20),
            Text('Invalid QR Code',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 18, color: _t.text)),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: _t.sub, height: 1.5)),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: kGold, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              ),
              child: const Text('Scan Again',
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Main content ──────────────────────────────────────────────────────────

  Widget _buildContent() {
    final reg    = _reg!;
    final status = reg['status'] as String? ?? '';

    // photo_required  â†’ student dismissed camera, can re-trigger
    // photo_submitted â†’ selfie received, awaiting organizer approval
    // checked_in      â†’ fully done
    final canRetrigger = status == 'photo_required';
    final isFinal      = status == 'photo_submitted' || status == 'checked_in' || status == 'rejected';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Student card ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _t.card,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(color: _t.shadow, blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: kGold.withValues(alpha: 0.15),
                      child: Text(
                        _initials(reg['student_name'] as String? ?? ''),
                        style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 18, color: kGold),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            reg['student_name'] as String? ?? '—',
                            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 17, color: _t.text),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            reg['student_school_id'] as String? ?? '—',
                            style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: _t.sub),
                          ),
                        ],
                      ),
                    ),
                    // Live status chip
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _statusColor(status).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _statusLabel(status),
                        style: TextStyle(
                          fontFamily: 'Poppins', fontSize: 10,
                          fontWeight: FontWeight.w700, color: _statusColor(status),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Divider(height: 1, color: _t.divider),
                const SizedBox(height: 14),
                _row(Icons.event_rounded,     'Event',    reg['event_title'] as String? ?? '—'),
                const SizedBox(height: 10),
                _row(Icons.badge_rounded,     'Reg ID',   _short(reg['id'] as String? ?? '—')),
                const SizedBox(height: 10),
                _row(Icons.circle_outlined,   'Status',   _statusLabel(status)),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Action area — depends on current status ─────────────────────
          if (isFinal)
            _buildFinalBanner(status)

          else if (canRetrigger)
            _buildRetriggerSection()

          else ...[
            // Normal first-time confirm (status = qr_scanned)
            _buildInfoBanner(
              icon: Icons.camera_alt_outlined,
              color: Colors.green,
              message: "Tap Confirm to open the student's front camera for a selfie verification.",
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _confirming ? null : _confirm,
              icon: _confirming
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.camera_alt_rounded, size: 20),
              label: Text(
                _confirming ? 'Opening camera…' : 'Confirm — Open Student Camera',
                style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ],

          const Spacer(),

          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kGold),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text(
              'Scan Another Student',
              style: TextStyle(fontFamily: 'Poppins', color: kGold, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ── Re-trigger section (photo_required — student dismissed camera) ────────

  Widget _buildRetriggerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Explanation banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.shade300),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.amber.shade700, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Student dismissed the camera',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 13,
                        fontWeight: FontWeight.w700, color: Colors.amber.shade800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'The selfie request was sent but the student closed the camera before taking a photo. Tap the button below to re-open it on their device.',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontSize: 12,
                        color: Colors.amber.shade700, height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Re-trigger button
        ElevatedButton.icon(
          onPressed: _confirming ? null : _retriggerCamera,
          icon: _confirming
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.refresh_rounded, size: 20),
          label: Text(
            _confirming ? 'Re-opening camera…' : 'Re-open Student Camera',
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF9333EA),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
        ),

        const SizedBox(height: 10),
        Text(
          'This instantly re-opens the front camera on the student\'s device.',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: _t.sub),
        ),
      ],
    );
  }

  // ── Final state banner (photo_submitted / checked_in / rejected) ──────────

  Widget _buildFinalBanner(String status) {
    final Color color;
    final IconData icon;
    final String title;
    final String subtitle;

    if (status == 'checked_in') {
      color    = const Color(0xFF16A34A);
      icon     = Icons.check_circle_rounded;
      title    = 'Already checked in';
      subtitle = 'This student has been fully verified and checked in.';
    } else if (status == 'photo_submitted') {
      color    = const Color(0xFF0891B2);
      icon     = Icons.photo_camera_rounded;
      title    = 'Selfie already submitted';
      subtitle = 'The student has submitted their selfie. Go to the Registrations tab to review and approve it.';
    } else {
      color    = const Color(0xFFDC2626);
      icon     = Icons.cancel_rounded;
      title    = 'Registration rejected';
      subtitle = 'This registration has been marked as rejected.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700, color: color)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: _t.sub, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Info banner ───────────────────────────────────────────────────────────

  Widget _buildInfoBanner({
    required IconData icon,
    required Color color,
    required String message,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: color, height: 1.5)),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _row(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: kGold),
        const SizedBox(width: 8),
        Text('$label: ', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: _t.sub)),
        Expanded(
          child: Text(value,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: _t.text),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts.isNotEmpty && parts[0].isNotEmpty ? parts[0][0].toUpperCase() : '?';
  }

  String _short(String id) => id.length > 12 ? '…${id.substring(id.length - 8)}' : id;

  String _statusLabel(String s) {
    const labels = {
      'pending':         'Pending',
      'qr_scanned':      'QR Scanned',
      'photo_required':  'Awaiting Selfie',
      'photo_submitted': 'Photo Submitted',
      'checked_in':      'Checked In',
      'rejected':        'Rejected',
    };
    return labels[s] ?? s;
  }

  Color _statusColor(String s) {
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
}

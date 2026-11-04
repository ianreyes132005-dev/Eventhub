import 'package:flutter/material.dart';
import 'package:eventhub/core/services/registration_service.dart';
import '../../../../core/friendly_error.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Scan QR, one student after another: each scanned ticket is confirmed on
// its own — marked scanned and the student's phone asked for the check-in
// photo — so the organizer never taps Confirm and the camera stays open. The
// result shows under the frame (ScanResultCard) instead of a sheet.
//
// The rules are the old result sheet's: only the organizer's own tickets
// (RLS), only inside the check-in window, and a finished registration
// (selfie sent, checked in, declined) is only reported, never changed.
// ─────────────────────────────────────────────────────────────────────────────

/// What one scan did.
enum ScanOutcome {
  /// Scanned and the check-in photo requested.
  requested,

  /// Scanned before and still no photo: asked again.
  requestedAgain,

  /// The student already sent the selfie; it waits for the organizer.
  awaitingReview,
  alreadyCheckedIn,
  declined,

  /// Check-in isn't open (yet, any more, or the event was cancelled).
  notOpen,

  /// Not a ticket for any of this organizer's events.
  notYours,

  /// It couldn't be checked (no connection, an error).
  failed,
}

class ScanResult {
  final ScanOutcome outcome;

  /// The student's name, or what went wrong.
  final String title;
  final String message;

  const ScanResult(this.outcome, this.title, this.message);

  /// The check-in went ahead (or is already waiting for the organizer).
  bool get ok =>
      outcome == ScanOutcome.requested ||
      outcome == ScanOutcome.requestedAgain ||
      outcome == ScanOutcome.awaitingReview;
}

/// The database calls a scan makes — replaced in tests.
class ScanServices {
  final Future<Map<String, dynamic>?> Function(String qrCode) findTicket;
  final Future<({String? problem, DateTime? opensAt})> Function(
    String? eventId, {
    bool scanning,
  }) checkInWindow;
  final Future<void> Function(String id, String status) setStatus;

  const ScanServices({
    this.findTicket = RegistrationService.getByQRCode,
    this.checkInWindow = RegistrationService.checkInWindow,
    this.setStatus = RegistrationService.updateStatus,
  });
}

/// Checks [qrCode] and, when the check-in can go ahead, confirms it at once:
/// a new ticket is marked scanned, and the student's phone is asked for the
/// check-in photo (asked again when it was asked before and no photo came).
Future<ScanResult> autoCheckIn(
  String qrCode, {
  ScanServices services = const ScanServices(),
}) async {
  try {
    final reg = await services.findTicket(qrCode);
    if (reg == null) {
      return const ScanResult(ScanOutcome.notYours, 'Not your ticket',
          'This QR code isn’t a ticket for any of your events.');
    }
    final id = reg['id'] as String;
    final name = (reg['student_name'] as String?)?.trim().isNotEmpty == true
        ? (reg['student_name'] as String).trim()
        : 'This student';
    final event = (reg['event_title'] as String?)?.trim().isNotEmpty == true
        ? (reg['event_title'] as String).trim()
        : 'this event';
    final status = reg['status'] as String? ?? 'pending';

    switch (status) {
      case 'photo_submitted':
        return ScanResult(ScanOutcome.awaitingReview, name,
            'Selfie sent — waiting for your review · $event');
      case 'checked_in':
        return ScanResult(ScanOutcome.alreadyCheckedIn, name,
            'Already checked in · $event');
      case 'rejected':
        return ScanResult(ScanOutcome.declined, name,
            'Registration declined · $event');
    }

    // A new ticket can be scanned from 1 h before the start until 30 min
    // after the end; a check-in already started can be finished until 2 h
    // after the end; never for a cancelled event.
    final window = await services.checkInWindow(
      reg['event_id'] as String?,
      scanning: status == 'pending',
    );
    if (window.problem != null) {
      return ScanResult(ScanOutcome.notOpen, name, window.problem!);
    }

    final again = status == 'photo_required';
    if (status == 'pending') await services.setStatus(id, 'qr_scanned');
    await services.setStatus(id, 'photo_required');
    return again
        ? ScanResult(ScanOutcome.requestedAgain, name,
            'Photo requested again · $event')
        : ScanResult(ScanOutcome.requested, name,
            'Scanned — photo requested · $event');
  } catch (e) {
    debugPrint('QR check failed: $e');
    return ScanResult(ScanOutcome.failed, 'Couldn’t check this ticket',
        friendlyError(e, fallback: 'Please scan it again.'));
  }
}

/// Decides which camera reads are new scans. The camera reads a ticket
/// several times a second while it's in view, so a ticket counts once while
/// it stays there, and again only after it has been out of view for [gap]
/// (shown again on purpose). While the last scan is still being checked
/// nothing is taken, but a ticket already waiting in view goes through as
/// soon as that's done.
class ScanGate {
  ScanGate({this.gap = const Duration(seconds: 3)});

  final Duration gap;
  final _seen = <String, DateTime>{}; // last time each ticket was in view
  final _handled = <String>{}; // counted since it came into view

  /// Records that [code] is in view at [now]; true when it's a new scan.
  bool admit(String code, DateTime now, {bool busy = false}) {
    final last = _seen[code];
    _seen[code] = now;
    if (last == null || now.difference(last) > gap) _handled.remove(code);
    if (_seen.length > 300) {
      _seen.removeWhere((_, t) => now.difference(t) > const Duration(minutes: 2));
      _handled.retainWhere(_seen.containsKey);
    }
    if (busy || _handled.contains(code)) return false;
    _handled.add(code);
    return true;
  }
}

/// The last scan's result, under the camera frame. [result] null = checking.
class ScanResultCard extends StatelessWidget {
  final ScanResult? result;
  const ScanResultCard({super.key, required this.result});

  static const _green = Color(0xFF22C55E);
  static const _red = Color(0xFFEF4444);
  static const _blue = Color(0xFF38BDF8);

  @override
  Widget build(BuildContext context) {
    final r = result;
    final (Color color, IconData icon) = r == null
        ? (Colors.white, Icons.qr_code_scanner_rounded)
        : switch (r.outcome) {
            ScanOutcome.requested ||
            ScanOutcome.requestedAgain =>
              (_green, Icons.check_circle_rounded),
            ScanOutcome.awaitingReview => (_blue, Icons.photo_camera_rounded),
            ScanOutcome.alreadyCheckedIn => (_red, Icons.how_to_reg_rounded),
            ScanOutcome.notOpen => (_red, Icons.lock_clock_rounded),
            _ => (_red, Icons.error_rounded),
          };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1814).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.55), width: 1.4),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: r == null
                  ? const Padding(
                      padding: EdgeInsets.all(3),
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                    )
                  : Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    r?.title ?? 'Checking ticket…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Poppins', fontSize: 14,
                        fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  if (r != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      r.message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 12, height: 1.4,
                          color: Colors.white.withValues(alpha: 0.75)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

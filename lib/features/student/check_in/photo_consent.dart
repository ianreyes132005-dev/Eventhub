import 'package:flutter/material.dart';
import '../../../shared/widgets/web/swal.dart';

/// Asks the student before the camera opens for a check-in photo — the
/// organizer has just requested one after scanning their ticket (status
/// photo_required). SweetAlert2: "Allow & Take Photo" (true) or "Not now"
/// (false). Declining keeps the request open: the student can take it later
/// from My Registrations, and the organizer can ask again.
Future<bool> askCheckInPhotoConsent(BuildContext context, {String? eventTitle}) async {
  final title = eventTitle?.trim() ?? '';
  final event = title.isEmpty ? 'this event' : '“$title”';
  final result = await Swal.fire(
    context,
    icon: SwalIcon.question,
    title: 'Take a check-in photo?',
    text: 'Your organizer at $event is asking for a selfie as proof that '
        'you’re at the venue. Only organizers and the school admin can see it.',
    showCancelButton: true,
    confirmButtonText: 'Allow & Take Photo',
    confirmButtonColor: kSwalGold,
    cancelButtonText: 'Not now',
    allowOutsideClick: false,
  );
  return result.isConfirmed;
}

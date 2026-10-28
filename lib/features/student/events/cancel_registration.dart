import 'package:flutter/material.dart';
import '../../../core/app_colors.dart';
import '../../../core/friendly_error.dart';
import '../../../core/services/registration_service.dart';
import '../../../shared/widgets/web/swal.dart';

/// Asks before cancelling the student's registration [registrationId] and
/// cancels it (SweetAlert2, with a loader while it runs; a refusal shows
/// in the popup). True when it was cancelled. Allowed while the ticket is
/// still Registered and check-in hasn't opened ([registrationCancellable]).
Future<bool> confirmCancelRegistration(
  BuildContext context, {
  required String registrationId,
  String? eventTitle,
}) async {
  final title = eventTitle?.trim() ?? '';
  final event = title.isEmpty ? 'this event' : '“$title”';
  final r = await Swal.fire(
    context,
    icon: SwalIcon.warning,
    title: 'Cancel your registration?',
    text: 'Your ticket for $event will be removed. You can register again '
        'while registration is still open.',
    showCancelButton: true,
    confirmButtonText: 'Yes, cancel it',
    confirmButtonColor: kSwalDenyColor,
    cancelButtonText: 'Keep it',
    preConfirm: (_) async {
      try {
        await RegistrationService.cancelMyRegistration(registrationId);
        return null;
      } catch (e) {
        return friendlyError(
          e,
          fallback: 'Your registration couldn’t be cancelled. Please try again.',
        );
      }
    },
  );
  return r.isConfirmed;
}

/// "Can't make it? Cancel registration", under a ticket's main button while
/// [registrationCancellable].
class CancelRegistrationLink extends StatelessWidget {
  final VoidCallback onTap;
  const CancelRegistrationLink({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AppTk(Theme.of(context).brightness == Brightness.dark);
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(Icons.event_busy_rounded, size: 16, color: t.sub),
      label: Text(
        'Can’t make it? Cancel registration',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: t.sub,
        ),
      ),
      style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
    );
  }
}

import 'package:flutter/material.dart';
import '../../../../core/app_colors.dart';
import '../../../../core/friendly_error.dart';
import '../../../../core/services/event_cancellation_service.dart';
import '../../../../shared/widgets/app_alert.dart';
import '../../../../shared/widgets/cancel_event_dialog.dart';
import '../../../../shared/widgets/error_alert.dart';

// Cancel / restore from the organizer app — the same dialogs, rules and
// service as the web Events table. Each returns true when the event changed,
// and tells the organizer how it went: a snackbar on success, a SweetAlert2
// popup in plain words on failure.

const _kGreen = Color(0xFF16A34A);

/// Asks for the reason registered students will see, then cancels.
/// [registrationCount] skips the lookup when the caller already has it.
Future<bool> cancelEventFlow(
  BuildContext context,
  Map<String, dynamic> event, {
  int? registrationCount,
}) async {
  final id = event['event_id'] as String?;
  if (id == null || !organizerCanCancelEvent(event)) return false;
  final title     = event['title'] as String? ?? 'this event';
  final messenger = ScaffoldMessenger.of(context);
  try {
    final count = registrationCount ?? await EventCancellationService.registrationCount(id);
    if (!context.mounted) return false;
    final reason = await showCancelEventDialog(context,
        eventTitle: title, registrationCount: count);
    if (reason == null) return false;
    await EventCancellationService.cancel(
      eventId: id,
      eventTitle: title,
      reason: reason,
      organizerId: event['organizer_id'] as String?,
    );
    _toast(messenger, count == 0
        ? 'Event cancelled.'
        : 'Event cancelled · $count student${count == 1 ? '' : 's'} notified.');
    return true;
  } catch (e) {
    _fail(context, messenger, e, 'Couldn’t cancel the event');
    return false;
  }
}

/// Confirms, then puts a cancelled event back on.
Future<bool> restoreEventFlow(BuildContext context, Map<String, dynamic> event) async {
  final id = event['event_id'] as String?;
  if (id == null || !organizerCanRestoreEvent(event)) return false;
  final title     = event['title'] as String? ?? 'this event';
  final messenger = ScaffoldMessenger.of(context);

  var confirmed = false;
  await AppAlert.confirm(
    context,
    title: 'Restore This Event?',
    message: '"$title" will be back on. Students can register and check in '
        'again, following the normal schedule rules.',
    confirmText: 'Restore',
    cancelText: 'Keep Cancelled',
    confirmColor: _kGreen,
    icon: Icons.restore_rounded,
    iconColor: _kGreen,
    onConfirm: () => confirmed = true,
  );
  if (!confirmed) return false;

  try {
    await EventCancellationService.restore(
      eventId: id,
      eventTitle: title,
      organizerId: event['organizer_id'] as String?,
    );
    _toast(messenger, 'Event restored.');
    return true;
  } catch (e) {
    _fail(context, messenger, e, 'Couldn’t restore the event');
    return false;
  }
}

// If the screen closed while the request ran, fall back to a snackbar on
// the screen underneath.
void _fail(BuildContext context, ScaffoldMessengerState messenger, Object e, String title) {
  if (context.mounted) {
    showErrorAlert(context, e, title: title);
  } else {
    _toast(messenger, friendlyError(e), error: true);
  }
}

void _toast(ScaffoldMessengerState messenger, String msg, {bool error = false}) {
  messenger.showSnackBar(SnackBar(
    content: Text(msg, style: const TextStyle(fontFamily: 'Poppins', fontSize: 13)),
    backgroundColor: error ? const Color(0xFFEF4444) : _kGreen,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  ));
}

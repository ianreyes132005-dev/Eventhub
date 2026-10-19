import 'package:flutter/material.dart';

import '../../core/friendly_error.dart';
import 'web/swal.dart';

/// Shows a failed action as a SweetAlert2 error popup, in plain words.
///
///   } catch (e) {
///     if (mounted) showErrorAlert(context, e, title: 'Couldn’t save the event');
///   }
///
/// [error] may be an exception or a message (e.g. an Edge Function's
/// `message`); database and network wording is translated by
/// [friendlyError]. The technical detail still goes to the debug log.
Future<void> showErrorAlert(
  BuildContext context,
  Object? error, {
  String title = 'Something went wrong',
  String fallback = FriendlyErrors.generic,
  Color confirmButtonColor = kSwalGold,
  /// [SwalIcon.warning] when the action partly succeeded.
  SwalIcon icon = SwalIcon.error,
}) async {
  if (error != null && error is! String && error is! FriendlyException) {
    debugPrint('[$title] $error');
  }
  if (!context.mounted) return;
  await Swal.fire(
    context,
    icon: icon,
    title: title,
    text: friendlyError(error, fallback: fallback),
    confirmButtonText: 'OK',
    confirmButtonColor: confirmButtonColor,
  );
}

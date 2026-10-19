import 'package:flutter/material.dart';

import '../../shared/widgets/web/swal.dart';
import 'supabase_service.dart';

class OrganizerSessionGuard {
  OrganizerSessionGuard._();

  static bool _handlingDeactivation = false;

  static Future<bool> ensureActive(
    BuildContext context, {
    required bool isActive,
  }) async {
    if (isActive) return true;
    if (_handlingDeactivation) return false;

    _handlingDeactivation = true;
    try {
      await Swal.fire(
        context,
        icon: SwalIcon.warning,
        title: 'Account deactivated',
        text: 'Your account has been deactivated. Contact the administrator.',
        allowOutsideClick: false,
      );
      await SupabaseService.signOut();
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true)
            .pushNamedAndRemoveUntil('/', (_) => false);
      }
    } finally {
      _handlingDeactivation = false;
    }
    return false;
  }
}

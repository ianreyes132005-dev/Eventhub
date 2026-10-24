import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/widgets/web/swal.dart';
import 'supabase_service.dart';

class AccountSessionGuard {
  AccountSessionGuard._();

  static bool _handlingDeactivation = false;

  /// Signs the user out the moment their account is deactivated. Any other
  /// change to their row (an admin editing the name, organization or photo)
  /// goes to [onUpdate], so headers can follow it.
  static RealtimeChannel? watch(
    BuildContext context, {
    required String table,
    required String userId,
    void Function(Map<String, dynamic> row)? onUpdate,
  }) {
    final client = Supabase.instance.client;
    return client.channel('account-status-$table-$userId').on(
      RealtimeListenTypes.postgresChanges,
      ChannelFilter(
        event: 'UPDATE',
        schema: 'public',
        table: table,
        filter: 'user_id=eq.$userId',
      ),
      (payload, [_]) {
        final newRecord = Map<String, dynamic>.from(
          (payload['new'] as Map?) ?? {},
        );
        if (newRecord['is_active'] == false) {
          ensureActive(context, isActive: false);
        } else if (newRecord.isNotEmpty) {
          onUpdate?.call(newRecord);
        }
      },
    )..subscribe();
  }

  static Future<bool> ensureActive(
    BuildContext context, {
    required bool isActive,
  }) async {
    if (isActive) return true;
    if (_handlingDeactivation || !context.mounted) return false;

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
        Navigator.of(
          context,
          rootNavigator: true,
        ).pushNamedAndRemoveUntil('/', (_) => false);
      }
    } finally {
      _handlingDeactivation = false;
    }
    return false;
  }
}

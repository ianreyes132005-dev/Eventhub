import 'package:flutter/foundation.dart';
import 'supabase_service.dart';

class RateLimitStatus {
  final bool      allowed;
  final DateTime? lockedUntil;
  final int       attemptsRemaining;

  const RateLimitStatus({
    required this.allowed,
    this.lockedUntil,
    this.attemptsRemaining = 0,
  });
}

/// Server-side rate limiting via the `login-rate-limit` Edge Function.
///
/// All methods swallow exceptions internally — a service outage must never
/// block a legitimate login attempt. On error, [check] returns [allowed: true]
/// so the client-side gate remains the last line of defence.
class RateLimitService {
  RateLimitService._();

  static const _fn = 'login-rate-limit';

  /// Returns whether [identifier] (the full login email) is permitted to attempt
  /// login right now. Also returns the server-enforced [lockedUntil] timestamp
  /// so callers can sync their local countdown UI.
  static Future<RateLimitStatus> check(String identifier) async {
    try {
      final res = await SupabaseService.client.functions.invoke(
        _fn,
        body: {'identifier': identifier, 'action': 'check'},
      );
      if (res.status == 200 && res.data is Map) {
        final data = res.data as Map<String, dynamic>;
        final lockedStr = data['lockedUntil'] as String?;
        return RateLimitStatus(
          allowed:           data['allowed'] as bool? ?? true,
          lockedUntil:       lockedStr != null
              ? DateTime.parse(lockedStr).toLocal()
              : null,
          attemptsRemaining: data['attemptsRemaining'] as int? ?? 0,
        );
      }
    } catch (e) {
      debugPrint('[RateLimit] check error: $e');
    }
    return const RateLimitStatus(allowed: true);
  }

  /// Records a failed login attempt for [identifier] on the server.
  /// Fire-and-forget — callers should use [unawaited] where appropriate.
  static Future<void> recordFailure(String identifier) async {
    try {
      await SupabaseService.client.functions.invoke(
        _fn,
        body: {'identifier': identifier, 'action': 'record'},
      );
    } catch (e) {
      debugPrint('[RateLimit] recordFailure error: $e');
    }
  }

  /// Clears all failed attempts for [identifier] after a successful login.
  /// Fire-and-forget — callers should use [unawaited] where appropriate.
  static Future<void> clear(String identifier) async {
    try {
      await SupabaseService.client.functions.invoke(
        _fn,
        body: {'identifier': identifier, 'action': 'clear'},
      );
    } catch (e) {
      debugPrint('[RateLimit] clear error: $e');
    }
  }
}

import 'package:flutter/foundation.dart' show kIsWeb;
import 'supabase_service.dart';

class AuditService {
  AuditService._();

  static Future<void> logLogin({
    required String userId,
    required String role,   // 'student' | 'organizer' | 'admin'
    String? fullName,
    String? identifier,     // lrn, organizer_id in lowercase, or admin username
  }) async {
    try {
      await SupabaseService.client.from('login_logs').insert({
        'user_id':    userId,
        'user_role':  role,
        'full_name':  fullName,
        'identifier': identifier,
        'platform':   kIsWeb ? 'web' : 'mobile',
      });
    } catch (_) {
      // Audit failures must never interrupt the main flow
    }
  }

  static Future<void> logEvent({
    required String action,       // 'created' | 'updated' | 'deleted'
    required String eventTitle,
    String? eventId,
    String? organizerId,
    String? organizerName,
    String? details,
  }) async {
    try {
      final user = SupabaseService.currentUser;
      if (user == null) return;
      await SupabaseService.client.from('event_logs').insert({
        'event_id':       eventId,
        'event_title':    eventTitle,
        'organizer_id':   organizerId,
        'organizer_name': organizerName,
        'action':         action,
        'details':        details,
        'performed_by':   user.id,
      });
    } catch (_) {
      // Audit failures must never interrupt the main flow
    }
  }
}

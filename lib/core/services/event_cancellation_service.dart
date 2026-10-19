import 'package:supabase_flutter/supabase_flutter.dart';
import '../friendly_error.dart';
import 'audit_service.dart';
import 'supabase_service.dart';

/// Cancel / restore an event — shared by organizer web and mobile.
///
/// The rules live in the database (202610180006_event_cancellation.sql):
/// a reason is required, cancelled_at is stamped, nothing is possible once
/// the event has ended, and registrations are always kept. Registered
/// students see the cancellation (with the reason) in their notifications.
class EventCancellationService {
  EventCancellationService._();

  static SupabaseClient get _db => SupabaseService.client;

  /// Number of registrations for [eventId] — shown in the cancel dialog and
  /// used to decide whether an event may be deleted.
  static Future<int> registrationCount(String eventId) async {
    final rows = await _db.from('registrations').select('id').eq('event_id', eventId);
    return (rows as List).length;
  }

  static Future<void> cancel({
    required String eventId,
    required String eventTitle,
    required String reason,
    String? organizerId,
  }) async {
    await _update(eventId, {
      'event_status':  'cancelled',
      'cancel_reason': reason.trim(),
    });
    AuditService.logEvent(
      action: 'cancelled',
      eventTitle: eventTitle,
      eventId: eventId,
      organizerId: organizerId,
      details: 'Event cancelled — ${reason.trim()}',
    );
  }

  static Future<void> restore({
    required String eventId,
    required String eventTitle,
    String? organizerId,
  }) async {
    await _update(eventId, {'event_status': 'upcoming'});
    AuditService.logEvent(
      action: 'updated',
      eventTitle: eventTitle,
      eventId: eventId,
      organizerId: organizerId,
      details: 'Event restored after being cancelled',
    );
  }

  static Future<void> _update(String eventId, Map<String, dynamic> data) async {
    try {
      final rows = await _db.from('events').update(data)
          .eq('event_id', eventId).select('event_id');
      if ((rows as List).isEmpty) {
        throw Exception('The event wasn’t updated — it may have been removed, '
            'or you don’t have permission to change it.');
      }
    } on PostgrestException catch (e) {
      // Rule messages pass through as-is; database wording is translated.
      throw FriendlyException(friendlyError(e));
    }
  }
}

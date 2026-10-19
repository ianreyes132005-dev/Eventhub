import 'package:supabase_flutter/supabase_flutter.dart';
import '../friendly_error.dart';
import 'audit_service.dart';
import 'supabase_service.dart';

/// Edits to a LIVE (approved) event go through admin review as a change
/// request — see supabase/migrations/202610180007_event_change_requests.sql.
///
/// The live event keeps its current details until an admin approves; then
/// the changes are applied and, if date/time/venue changed, registered
/// students get an "Event updated" notification. Events that aren't live
/// yet (pending / rejected) are still edited directly.
class EventChangeRequestService {
  EventChangeRequestService._();

  static SupabaseClient get _db => SupabaseService.client;

  /// Columns a change request may change. (Not capacity — that's the number
  /// of active students, see StudentCountService.)
  static const editableFields = [
    'title', 'description', 'event_type', 'location', 'event_date', 'end_date',
    'start_time', 'end_time', 'event_image_url',
  ];

  /// Fields that make registered students get an "Event updated" notice.
  static const scheduleFields = ['event_date', 'end_date', 'start_time', 'end_time', 'location'];

  /// True when [event] is live, so edits need admin approval.
  static bool needsApproval(Map<String, dynamic> event) =>
      (event['approval_status'] as String? ?? 'approved') == 'approved';

  /// Only the fields in [proposed] whose value differs from [current].
  static Map<String, dynamic> diff(
      Map<String, dynamic> current, Map<String, dynamic> proposed) {
    String norm(Object? v) {
      final s = (v ?? '').toString().trim();
      // "09:00:00" vs "09:00" — compare times by hh:mm.
      final t = RegExp(r'^(\d{2}:\d{2})(:\d{2})?$').firstMatch(s);
      return t != null ? t.group(1)! : s;
    }
    return {
      for (final k in editableFields)
        if (proposed.containsKey(k) && norm(proposed[k]) != norm(current[k])) k: proposed[k],
    };
  }

  static bool touchesSchedule(Map<String, dynamic> changes) =>
      changes.keys.any(scheduleFields.contains);

  /// Pending / latest change requests for the given events, keyed by event_id.
  /// Returns {} if the change-request table isn't installed yet.
  static Future<Map<String, Map<String, dynamic>>> latestFor(Iterable<String> eventIds) async {
    final ids = eventIds.toSet().toList();
    if (ids.isEmpty) return {};
    try {
      final rows = await _db.from('event_revisions').select()
          .in_('event_id', ids).order('created_at', ascending: false);
      final out = <String, Map<String, dynamic>>{};
      for (final r in rows as List) {
        final m = Map<String, dynamic>.from(r as Map);
        if (m['status'] == 'withdrawn') continue;
        out.putIfAbsent(m['event_id'] as String, () => m);   // newest first
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  /// Submits (or updates the open) change request for [eventId].
  static Future<void> submit({
    required String eventId,
    required String organizerId,
    required String eventTitle,
    required Map<String, dynamic> changes,
  }) async {
    try {
      final open = await _db.from('event_revisions').select('id')
          .eq('event_id', eventId).eq('status', 'pending').maybeSingle();
      if (open != null) {
        await _db.from('event_revisions')
            .update({'changes': changes}).eq('id', open['id'] as String);
      } else {
        await _db.from('event_revisions').insert({
          'event_id':     eventId,
          'organizer_id': organizerId,
          'changes':      changes,
        });
      }
    } on PostgrestException catch (e) {
      throw FriendlyException(friendlyError(e));
    }
    AuditService.logEvent(
      action: 'updated',
      eventTitle: eventTitle,
      eventId: eventId,
      organizerId: organizerId,
      details: 'Changes submitted for admin review: ${changes.keys.join(', ')}',
    );
  }

  /// Organizer takes back their open request.
  static Future<void> withdraw(String revisionId) async {
    try {
      await _db.from('event_revisions')
          .update({'status': 'withdrawn'}).eq('id', revisionId);
    } on PostgrestException catch (e) {
      throw FriendlyException(friendlyError(e));
    }
  }

  // ── Admin ──────────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> pendingForAdmin() async {
    try {
      final rows = await _db.from('event_revisions')
          .select('*, events(*, organizers(full_name, organization))')
          .eq('status', 'pending')
          .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (_) {
      return [];
    }
  }

  static Future<void> approve(String revisionId) async {
    try {
      await _db.rpc('approve_event_revision', params: {'p_revision_id': revisionId});
    } on PostgrestException catch (e) {
      throw FriendlyException(friendlyError(e));
    }
  }

  static Future<void> reject(String revisionId, String reason) async {
    try {
      await _db.rpc('reject_event_revision',
          params: {'p_revision_id': revisionId, 'p_reason': reason});
    } on PostgrestException catch (e) {
      throw FriendlyException(friendlyError(e));
    }
  }
}

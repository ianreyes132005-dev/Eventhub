import 'package:flutter/foundation.dart' show debugPrint;
import '../friendly_error.dart';
import 'supabase_service.dart';

/// Admin archive actions — rules live in
/// supabase/migrations/202610180010_event_archives.sql (admin-only, cancelled
/// or check-in-closed events only, archived records frozen, audit-logged).
class EventArchiveService {
  EventArchiveService._();

  /// Archives [eventIds]. Throws a readable message when nothing changed.
  static Future<void> archive(List<String> eventIds) =>
      _setArchived(eventIds, archived: true);

  /// Restores [eventIds] to the everyday lists.
  static Future<void> restore(List<String> eventIds) =>
      _setArchived(eventIds, archived: false);

  static Future<void> _setArchived(List<String> ids, {required bool archived}) async {
    if (ids.isEmpty) return;
    try {
      final rows = await SupabaseService.client
          .from('events')
          // The database stamps the real time and the admin's id.
          .update({'archived_at': archived ? DateTime.now().toUtc().toIso8601String() : null})
          .in_('event_id', ids)
          .select('event_id');
      if ((rows as List).length != ids.length) {
        throw Exception(rows.isEmpty
            ? 'Nothing was changed — you may not have permission.'
            : 'Only ${rows.length} of ${ids.length} events were updated.');
      }
    } catch (e) {
      throw FriendlyException(friendlyError(e));
    }
  }

  /// Permanently deletes an archived event with its registrations and
  /// attendance, then removes its check-in selfies and banner from Storage.
  /// [typedTitle] must match the event title (checked again server-side).
  /// Returns how many registrations were deleted.
  static Future<int> deletePermanently(Map<String, dynamic> event, String typedTitle) async {
    final id = event['event_id'] as String;

    // Collect file paths first — the rows are gone after the delete.
    final regs = await SupabaseService.client
        .from('registrations')
        .select('selfie_url')
        .eq('event_id', id);
    final selfies = [
      for (final r in regs as List)
        if ((r['selfie_url'] as String? ?? '').isNotEmpty) r['selfie_url'] as String,
    ];

    final int deleted;
    try {
      final res = await SupabaseService.client.rpc('admin_delete_archived_event',
          params: {'p_event_id': id, 'p_confirm_title': typedTitle});
      deleted = (res as num?)?.toInt() ?? 0;
    } catch (e) {
      throw FriendlyException(friendlyError(e));
    }

    // Records are already gone; file clean-up is best effort.
    try {
      for (var i = 0; i < selfies.length; i += 100) {
        await SupabaseService.client.storage
            .from('selfies')
            .remove(selfies.sublist(i, (i + 100).clamp(0, selfies.length)));
      }
    } catch (e) {
      debugPrint('Archive delete: selfie clean-up failed: $e');
    }
    final banner = event['event_image_url'] as String?;
    const marker = '/event-banners/';
    if (banner != null && banner.contains(marker)) {
      try {
        final path = Uri.decodeComponent(banner.substring(banner.indexOf(marker) + marker.length)
            .split('?').first);
        await SupabaseService.client.storage.from('event-banners').remove([path]);
      } catch (e) {
        debugPrint('Archive delete: banner clean-up failed: $e');
      }
    }
    return deleted;
  }

  /// Registered / present / rejected counts per event_id.
  static Future<Map<String, ({int registered, int present, int rejected})>>
      attendanceSummary() async {
    final rows = await SupabaseService.client
        .from('event_attendance_summary')
        .select('event_id, registered, present, rejected');
    return {
      for (final r in rows as List)
        r['event_id'] as String: (
          registered: (r['registered'] as num?)?.toInt() ?? 0,
          present:    (r['present']    as num?)?.toInt() ?? 0,
          rejected:   (r['rejected']   as num?)?.toInt() ?? 0,
        ),
    };
  }

  /// Student profiles for the admin (reads the students table directly — the
  /// organizer view only covers the calling organizer's events).
  static Future<Map<String, Map<String, dynamic>>> adminProfiles(
      Iterable<String?> userIds) async {
    final ids = userIds.whereType<String>().toSet().toList();
    if (ids.isEmpty) return {};
    final out = <String, Map<String, dynamic>>{};
    // Chunked so a big event doesn't build an over-long URL.
    for (var i = 0; i < ids.length; i += 150) {
      final rows = await SupabaseService.client
          .from('students')
          .select('user_id, lrn, full_name, first_name, last_name, year_level, '
              'strand, section, profile_image_url')
          .in_('user_id', ids.sublist(i, (i + 150).clamp(0, ids.length)));
      for (final r in rows as List) {
        out[r['user_id'] as String] = Map<String, dynamic>.from(r as Map);
      }
    }
    return out;
  }
}

import 'dart:math' show min;

import 'package:flutter/foundation.dart' show debugPrint;
import '../app_colors.dart';
import '../friendly_error.dart';
import 'supabase_service.dart';

/// Admin archive actions — rules live in
/// supabase/migrations/202610180010_event_archives.sql and
/// 202610230003_archive_records.sql (admin-only; only approved events with
/// registrations that are cancelled or check-in-closed; archived records
/// frozen and kept when accounts are deleted; photos removed on archive;
/// audit-logged; organizers get a bell notice).
class EventArchiveService {
  EventArchiveService._();

  // Event ids per request — a long `in` filter would make an over-long URL.
  static const _chunk = 50;

  static List<List<T>> _chunks<T>(List<T> items, int size) => [
        for (var i = 0; i < items.length; i += size)
          items.sublist(i, min(i + size, items.length)),
      ];

  /// Archives [eventIds], then deletes their check-in photos (the attendance
  /// is kept). Throws a readable message when the events weren't archived.
  /// Returns how many photos couldn't be deleted; the Archives tab offers to
  /// retry those ([purgeSelfies]).
  static Future<int> archive(List<String> eventIds) async {
    await _setArchived(eventIds, archived: true);
    return (await purgeSelfies(eventIds: eventIds)).failed;
  }

  /// Restores [eventIds] to the everyday lists. Their photos don't come back.
  static Future<void> restore(List<String> eventIds) =>
      _setArchived(eventIds, archived: false);

  static Future<void> _setArchived(List<String> ids, {required bool archived}) async {
    if (ids.isEmpty) return;
    var changed = 0;
    try {
      for (final part in _chunks(ids, _chunk)) {
        final rows = await SupabaseService.client
            .from('events')
            // The database stamps the real time and the admin's id.
            .update({'archived_at': archived ? DateTime.now().toUtc().toIso8601String() : null})
            .in_('event_id', part)
            .select('event_id');
        changed += (rows as List).length;
      }
    } catch (e) {
      if (changed == 0) throw FriendlyException(friendlyError(e));
      throw FriendlyException('Only $changed of ${ids.length} events were updated. '
          '${friendlyError(e)}');
    }
    if (changed != ids.length) {
      throw FriendlyException(changed == 0
          ? 'Nothing was changed — you may not have permission.'
          : 'Only $changed of ${ids.length} events were updated.');
    }
  }

  /// Registrations of archived events whose check-in photo is still stored
  /// (only [eventIds] when given).
  static Future<List<({String id, String path})>> _archivedSelfies(
      {List<String>? eventIds}) async {
    Future<List<dynamic>> fetch(List<String>? ids) async {
      var q = SupabaseService.client
          .from('registrations')
          .select('id, selfie_url, events!inner(archived_at)')
          .not('selfie_url', 'is', null)
          .not('events.archived_at', 'is', null);
      if (ids != null) q = q.in_('event_id', ids);
      return await q as List;
    }

    final rows = eventIds == null
        ? await fetch(null)
        : [for (final part in _chunks(eventIds, _chunk)) ...await fetch(part)];
    return [
      for (final r in rows)
        if ((r['selfie_url'] as String? ?? '').isNotEmpty)
          (id: r['id'] as String, path: r['selfie_url'] as String),
    ];
  }

  /// How many check-in photos archived events still have (archived before
  /// photos were removed on archive, or a removal that didn't finish).
  static Future<int> archivedSelfieCount() async =>
      (await _archivedSelfies()).length;

  /// Deletes the check-in photos of archived events ([eventIds], or all) and
  /// clears their links; status, check-in time and reviewer stay. A link is
  /// only cleared once its file is gone, so a failure can simply be retried.
  static Future<({int removed, int failed})> purgeSelfies({List<String>? eventIds}) async {
    final List<({String id, String path})> photos;
    try {
      photos = await _archivedSelfies(eventIds: eventIds);
    } catch (e) {
      // Unknown how many: report one so the caller says it didn't finish.
      debugPrint('Archive: listing photos failed: $e');
      return (removed: 0, failed: 1);
    }
    var removed = 0, failed = 0;
    for (final part in _chunks(photos, 100)) {
      try {
        await SupabaseService.client.storage
            .from('selfies')
            .remove([for (final p in part) p.path]);
        final cleared = await SupabaseService.client
            .from('registrations')
            .update({'selfie_url': null})
            .in_('id', [for (final p in part) p.id])
            .select('id');
        removed += (cleared as List).length;
        failed += part.length - cleared.length;
      } catch (e) {
        debugPrint('Archive: photo removal failed: $e');
        failed += part.length;
      }
    }
    return (removed: removed, failed: failed);
  }

  /// Permanently deletes an archived event with its registrations and
  /// attendance, then removes any check-in selfies left and its banner from
  /// Storage. [typedTitle] must match the event title (checked again
  /// server-side). Returns how many registrations were deleted.
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
      for (final part in _chunks(selfies, 100)) {
        await SupabaseService.client.storage.from('selfies').remove(part);
      }
    } catch (e) {
      debugPrint('Archive delete: selfie clean-up failed: $e');
    }
    await _removeBanner(event);
    return deleted;
  }

  /// Deletes a finished event that has nothing to keep — never approved, or
  /// nobody registered — and its banner. The organizer gets a bell notice.
  static Future<void> deleteUnused(Map<String, dynamic> event) async {
    try {
      await SupabaseService.client.rpc('admin_delete_unused_event',
          params: {'p_event_id': event['event_id'] as String});
    } catch (e) {
      throw FriendlyException(friendlyError(e));
    }
    await _removeBanner(event);
  }

  static Future<void> _removeBanner(Map<String, dynamic> event) async {
    final banner = event['event_image_url'] as String?;
    const marker = '/event-banners/';
    if (banner == null || !banner.contains(marker)) return;
    try {
      final path = Uri.decodeComponent(banner.substring(banner.indexOf(marker) + marker.length)
          .split('?').first);
      await SupabaseService.client.storage.from('event-banners').remove([path]);
    } catch (e) {
      debugPrint('Archive delete: banner clean-up failed: $e');
    }
  }

  /// Registered / present / rejected counts per event_id. `registered` is
  /// every registration row, declined ones included.
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

  /// The events that could be archived and their registration counts, for the
  /// admin sidebar's "ready to archive" number. Kept by the caller so the
  /// count can follow the clock between loads ([ArchiveReadiness.readyCount]).
  static Future<ArchiveReadiness> loadReadiness() async {
    final rows = await SupabaseService.client
        .from('events')
        .select('event_id, event_date, end_date, start_time, end_time, '
            'event_status, approval_status, archived_at')
        .eq('approval_status', 'approved')
        .is_('archived_at', null);
    final summary = await attendanceSummary();
    return ArchiveReadiness(
      List<Map<String, dynamic>>.from(rows as List),
      {for (final e in summary.entries) e.key: e.value.registered},
    );
  }

  /// Registrations in archived events per student user_id. Those accounts
  /// can only be deactivated: deleting them would change archived records.
  static Future<Map<String, int>> archivedAttendanceByStudent(
      Iterable<String?> userIds) async {
    final ids = userIds.whereType<String>().toSet().toList();
    final out = <String, int>{};
    for (final part in _chunks(ids, 100)) {
      final rows = await SupabaseService.client
          .from('registrations')
          .select('student_user_id, events!inner(archived_at)')
          .in_('student_user_id', part)
          .not('events.archived_at', 'is', null);
      for (final r in rows as List) {
        final id = r['student_user_id'] as String;
        out[id] = (out[id] ?? 0) + 1;
      }
    }
    return out;
  }

  /// Archived events per organizer_id. Those accounts can only be
  /// deactivated: deleting them would delete archived records.
  static Future<Map<String, int>> archivedEventsByOrganizer(
      Iterable<String?> organizerIds) async {
    final ids = organizerIds.whereType<String>().toSet().toList();
    final out = <String, int>{};
    for (final part in _chunks(ids, 100)) {
      final rows = await SupabaseService.client
          .from('events')
          .select('organizer_id')
          .in_('organizer_id', part)
          .not('archived_at', 'is', null);
      for (final r in rows as List) {
        final id = r['organizer_id'] as String;
        out[id] = (out[id] ?? 0) + 1;
      }
    }
    return out;
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

/// Approved, not-yet-archived events with their registration counts (every
/// row, declined ones included) — enough to count the ones ready to archive
/// at any moment.
class ArchiveReadiness {
  final List<Map<String, dynamic>> events;
  final Map<String, int> registrations;
  const ArchiveReadiness(this.events, this.registrations);

  int readyCount({DateTime? now}) => events
      .where((e) =>
          archiveGroupOf(e, registrations: registrations[e['event_id']] ?? 0, now: now) ==
          ArchiveGroup.ready)
      .length;
}

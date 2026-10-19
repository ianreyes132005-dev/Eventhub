import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import 'audit_service.dart';
import '../friendly_error.dart';
import '../app_colors.dart';

// Generates a RFC-4122 v4 UUID using dart:math — no external package needed.
String _newUuid() {
  final rand  = Random.secure();
  final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant
  String h(int n) => n.toRadixString(16).padLeft(2, '0');
  return '${h(bytes[0])}${h(bytes[1])}${h(bytes[2])}${h(bytes[3])}-'
      '${h(bytes[4])}${h(bytes[5])}-'
      '${h(bytes[6])}${h(bytes[7])}-'
      '${h(bytes[8])}${h(bytes[9])}-'
      '${h(bytes[10])}${h(bytes[11])}${h(bytes[12])}'
      '${h(bytes[13])}${h(bytes[14])}${h(bytes[15])}';
}

/// All database operations for the event registration + check-in flow.
class RegistrationService {
  static SupabaseClient get _db => SupabaseService.client;

  /// Database rule violations (e.g. "Check-in opens 1 hour before the event
  /// starts.") arrive as PostgrestException(message: …, code: …). Re-throw
  /// them in plain words: rule messages as-is, database wording translated.
  static Future<T> _plainErrors<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on PostgrestException catch (e) {
      throw FriendlyException(friendlyError(e));
    }
  }

  // ──────────────────────────────────────────────────────────
  // Student operations
  // ──────────────────────────────────────────────────────────

  /// Register the currently signed-in student for [eventId].
  /// Automatically fetches the student's full_name and lrn from their
  /// pre-provisioned profile — no need to pass them as parameters.
  /// Returns the full registration row on success.
  static Future<Map<String, dynamic>> register({
    required String eventId,
    required String eventTitle,
  }) async {
    final user = SupabaseService.currentUser;
    if (user == null) throw Exception('Not authenticated');

    // Fetch the student's pre-provisioned profile to get name and LRN.
    final profile = await SupabaseService.getProfile();
    if (profile == null) {
      throw const FriendlyException(
          'We couldn’t find your student profile. Please contact the administrator.');
    }

    final studentName = profile['full_name'] as String? ?? '';
    final studentSchoolId = profile['lrn'] as String? ?? '';

    // Prevent duplicate registrations
    final existing = await _db
        .from('registrations')
        .select('id')
        .eq('event_id', eventId)
        .eq('student_user_id', user.id)
        .maybeSingle();
    if (existing != null) {
      throw const FriendlyException('You’re already registered for this event.');
    }

    // Validate approval, status and the registration window in a single
    // fetch. (No capacity check: capacity is every active student, and each
    // student registers once — see StudentCountService.)
    // maybeSingle(), not single() — a pending/rejected event is invisible to
    // students under RLS, so a stale event_id (e.g. a deep link held onto
    // from before an admin rejected it) must fail with a friendly message
    // here rather than a raw "JSON object requested, multiple (or no) rows
    // returned" Postgrest error.
    // All columns (schedule, deadline) so the shared rule below
    // sees the same data the server trigger checks.
    final eventRow = await _db
        .from('events')
        .select()
        .eq('event_id', eventId)
        .maybeSingle();
    if (eventRow == null) {
      throw Exception('This event is not available for registration.');
    }

    // Same rule as trg_enforce_registration_insert_rules — checked here first
    // only for a friendlier message; the server is the real gate.
    final closed = registrationClosedReason(
        registrationState(Map<String, dynamic>.from(eventRow)));
    if (closed != null) throw Exception(closed);

    // Generate the UUID client-side so id and qr_code are set atomically in one
    // insert — no race window where qr_code = 'PENDING' can be read or scanned.
    final id = _newUuid();
    final row = await _plainErrors(() => _db
        .from('registrations')
        .insert({
          'id':                id,
          'event_id':          eventId,
          'event_title':       eventTitle,
          'student_user_id':   user.id,
          'student_name':      studentName,
          'student_school_id': studentSchoolId,
          'qr_code':           id,
          'status':            'pending',
        })
        .select()
        .single());

    // The window, status and one-registration-per-student rule are
    // re-validated server-side by trg_enforce_registration_insert_rules, and
    // current_participants is maintained by trg_maintain_participant_count.

    return Map<String, dynamic>.from(row);
  }

  /// Returns all registrations for the current student (plain rows).
  static Future<List<Map<String, dynamic>>> getMyRegistrations() async {
    final user = SupabaseService.currentUser;
    if (user == null) return [];
    final rows = await _db
        .from('registrations')
        .select()
        .eq('student_user_id', user.id)
        .order('registered_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Returns registrations joined with their event details (event_date,
  /// start_time, end_time, location, event_status, event_image_url).
  /// Each row has a nested 'events' map with those fields.
  static Future<List<Map<String, dynamic>>> getMyRegistrationsWithEvents() async {
    final user = SupabaseService.currentUser;
    if (user == null) return [];
    final rows = await _db
        .from('registrations')
        .select(
          '*, events(event_date, start_time, end_time, location, event_status, event_image_url)',
        )
        .eq('student_user_id', user.id)
        .order('registered_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Upload a selfie for [registrationId] and flip status → photo_submitted.
  /// Returns the storage path (used later to generate a signed URL).
  static Future<String> uploadSelfie({
    required String registrationId,
    required Uint8List imageBytes,
  }) async {
    final user = SupabaseService.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final path = '${user.id}/$registrationId.jpg';

    await _db.storage.from('selfies').uploadBinary(
      path,
      imageBytes,
      fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
    );

    await _plainErrors(() => _db.from('registrations').update({
      'selfie_url': path,
      'status': 'photo_submitted',
    }).eq('id', registrationId));

    return path;
  }

  // ──────────────────────────────────────────────────────────
  // Organizer operations
  // ──────────────────────────────────────────────────────────

  /// Deletes a registration. current_participants is decremented automatically
  /// by trg_maintain_participant_count.
  static Future<void> deleteRegistration(String registrationId) async {
    await _db.from('registrations').delete().eq('id', registrationId);
  }

  /// Returns all registrations scoped to [organizerId]'s events.
  /// Optionally further filtered by a single [eventId].
  /// Passing neither fetches all registrations in the system (use only when
  /// RLS policies enforce row-level isolation).
  static Future<List<Map<String, dynamic>>> getAllRegistrations({
    String? eventId,
    String? organizerId,
  }) async {
    // When an organizerId is provided, resolve the set of event IDs that
    // belong to that organizer and restrict the query to those rows only.
    List<String>? orgEventIds;
    if (organizerId != null) {
      final evRows = await _db
          .from('events')
          .select('event_id')
          .eq('organizer_id', organizerId);
      orgEventIds = (evRows as List)
          .map((e) => e['event_id'] as String)
          .toList();
      if (orgEventIds.isEmpty) return [];
    }

    dynamic query = _db
        .from('registrations')
        .select()
        .order('registered_at', ascending: false);

    if (eventId != null) {
      query = (query as dynamic).eq('event_id', eventId);
    } else if (orgEventIds != null) {
      query = (query as dynamic).in_('event_id', orgEventIds);
    }

    final rows = await query;
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Why check-in isn't possible for [eventId] right now (cancelled, or
  /// outside 1 h before start … 2 h after end), or null when it is.
  /// Same window the server enforces in enforce_registration_update_rules.
  static Future<String?> checkInProblem(String? eventId) async {
    if (eventId == null) return null;
    final ev = await _db.from('events').select().eq('event_id', eventId).maybeSingle();
    if (ev == null) return null;
    return checkInBlockedReason(Map<String, dynamic>.from(ev));
  }

  /// Look up a registration by its QR code value (= the registration UUID).
  static Future<Map<String, dynamic>?> getByQRCode(String qrCode) async {
    final row = await _db
        .from('registrations')
        .select()
        .eq('qr_code', qrCode)
        .maybeSingle();
    return row != null ? Map<String, dynamic>.from(row) : null;
  }

  /// Update the status of a registration.
  /// Automatically sets [checked_in_at] when status is 'checked_in'.
  ///
  /// [checked_in] and [rejected] are the two decision-terminal transitions —
  /// both record [reviewed_by] (the acting organizer) for the audit trail,
  /// and both write an entry to the Logs tab via [AuditService]. [rejected]
  /// requires [rejectionReason] to be meaningful; callers should collect it
  /// from the organizer before calling this (see the reason-prompt dialogs
  /// in organizer_registrations.dart / registrations_page.dart) rather than
  /// rejecting silently.
  static Future<void> updateStatus(
    String id,
    String status, {
    String? rejectionReason,
  }) async {
    final user = SupabaseService.currentUser;
    final data = <String, dynamic>{'status': status};
    if (status == 'checked_in') {
      data['checked_in_at'] = DateTime.now().toIso8601String();
    }
    if (status == 'checked_in' || status == 'rejected') {
      data['reviewed_by'] = user?.id;
    }
    if (status == 'rejected') {
      data['rejection_reason'] = rejectionReason;
    }

    final updated = await _plainErrors(() => _db
        .from('registrations')
        .update(data)
        .eq('id', id)
        .select('event_id, event_title, student_name, student_school_id')
        .maybeSingle());

    if (updated != null && (status == 'checked_in' || status == 'rejected')) {
      String? organizerName;
      if (user != null) {
        final orgRow = await _db
            .from('organizers')
            .select('full_name')
            .eq('user_id', user.id)
            .maybeSingle();
        organizerName = orgRow?['full_name'] as String?;
      }
      AuditService.logEvent(
        action: status == 'checked_in' ? 'checked_in' : 'registration_rejected',
        eventTitle: updated['event_title'] as String? ?? '—',
        eventId: updated['event_id'] as String?,
        organizerName: organizerName,
        details: 'Student: ${updated['student_name']} (${updated['student_school_id']})'
            '${status == 'rejected' && rejectionReason != null && rejectionReason.isNotEmpty ? ' — $rejectionReason' : ''}',
      );
    }
  }

  /// Generate a 1-hour signed URL so the organizer can view a private selfie.
  static Future<String> getSelfieSignedUrl(String storagePath) async {
    return _db.storage.from('selfies').createSignedUrl(storagePath, 3600);
  }

  // ──────────────────────────────────────────────────────────
  // Realtime subscriptions
  // ──────────────────────────────────────────────────────────

  /// Listens for UPDATE events on the current student's registrations.
  /// Call [Supabase.instance.client.removeChannel] on the returned channel
  /// when the listener is no longer needed (e.g., in dispose()).
  static RealtimeChannel subscribeToMyRegistrations(
    void Function(Map<String, dynamic> newRecord) onUpdate,
  ) {
    final userId = SupabaseService.currentUser?.id ?? '';
    final channel = _db.channel('student-reg-$userId');

    channel
        .on(
          RealtimeListenTypes.postgresChanges,
          ChannelFilter(
            event: 'UPDATE',
            schema: 'public',
            table: 'registrations',
            filter: 'student_user_id=eq.$userId',
          ),
          (payload, [ref]) {
            final rec = Map<String, dynamic>.from(
              (payload['new'] as Map?) ?? {},
            );
            onUpdate(rec);
          },
        )
        .subscribe();

    return channel;
  }

  /// Listens for INSERT, UPDATE, and DELETE events on registrations.
  ///
  /// [channelSuffix] scopes the channel per organizer to prevent cross-client
  /// collisions (pass the organizer_id). [allowedEventIds] provides a
  /// client-side filter so only events owned by the subscribing organizer are
  /// surfaced — events for other organizers are silently dropped.
  ///
  /// Call [Supabase.instance.client.removeChannel] on the returned channel
  /// when the listener is no longer needed.
  static RealtimeChannel subscribeToAllRegistrations(
    void Function(String eventType, Map<String, dynamic> record) onEvent, {
    String?       channelSuffix,
    List<String>? allowedEventIds,
  }) {
    final channel = _db.channel('organizer-reg-${channelSuffix ?? 'all'}');

    for (final evt in ['INSERT', 'UPDATE', 'DELETE']) {
      channel.on(
        RealtimeListenTypes.postgresChanges,
        ChannelFilter(event: evt, schema: 'public', table: 'registrations'),
        (payload, [ref]) {
          final raw = evt == 'DELETE'
              ? (payload['old'] as Map?) ?? {}
              : (payload['new'] as Map?) ?? {};
          final rec = Map<String, dynamic>.from(raw);

          // Drop events that don't belong to this organizer's events.
          if (allowedEventIds != null && allowedEventIds.isNotEmpty) {
            final evId = rec['event_id'] as String?;
            if (evId == null || !allowedEventIds.contains(evId)) return;
          }

          onEvent(evt, rec);
        },
      );
    }

    channel.subscribe();
    return channel;
  }
}

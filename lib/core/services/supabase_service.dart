import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';

class SupabaseService {
  SupabaseService._();

  static SupabaseClient get client => Supabase.instance.client;

  // Bumped by createAnnouncement / deleteAnnouncement so listeners reload.
  static final ValueNotifier<int> announcementsVersion = ValueNotifier<int>(0);

  // Set to true while _handleLogin() is running so setupAuthStateListener()
  // in app_router.dart does not race it to the navigator.
  static bool handlingAppLogin = false;

  static Future<void> ensureInitialized() async {
    try {
      final _ = Supabase.instance.client;
      return;
    } catch (_) {
      await Supabase.initialize(url: kSupabaseBaseUrl, anonKey: kSupabaseAnonKey);
    }
  }

  // ── Auth ─────────────────────────────────────────────────────────────────

  static Future<void> signOut() async {
    await ensureInitialized();
    await client.auth.signOut();
  }

  static User? get currentUser => client.auth.currentUser;

  // ── Profile ───────────────────────────────────────────────────────────────

  static Future<String?> getCurrentOrganizerId() async {
    await ensureInitialized();
    final user = currentUser;
    if (user == null) return null;

    final row = await client
        .from('organizers')
        .select('organizer_id')
        .eq('user_id', user.id)
        .maybeSingle();

    if (row == null) return null;
    return row['organizer_id'] as String?;
  }

  static Future<Map<String, dynamic>?> getProfile() async {
    await ensureInitialized();
    final user = currentUser;
    if (user == null) return null;
    final res = await client
        .from('students')
        .select()
        .eq('user_id', user.id)
        .maybeSingle();
    if (res == null) return null;
    return res is Map<String, dynamic>
        ? res
        : Map<String, dynamic>.from(res as Map);
  }

  static Future<bool> updateProfile(Map<String, dynamic> fields) async {
    await ensureInitialized();
    final user = currentUser;
    final id = user?.id ?? fields['user_id'] as String?;
    if (id == null) {
      return Future.error('No authenticated user; cannot update profile.');
    }
    final payload = {'user_id': id, ...fields};
    await client.from('students').upsert(payload).select();
    return true;
  }

  // ── Events ────────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getEvents({int limit = 100}) async {
    await ensureInitialized();
    final res = await client
        .from('events')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    if (res is List) {
      return List<Map<String, dynamic>>.from(
        res.map((e) => Map<String, dynamic>.from(e as Map)),
      );
    }
    return [];
  }

  // ── Announcements ─────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> createAnnouncement({
    required String title,
    required String message,
    String? organizerId,
  }) async {
    await ensureInitialized();
    final user = currentUser;
    if (user == null) return Future.error('User not authenticated');

    final currentOrganizerId = organizerId ?? await getCurrentOrganizerId() ?? user.id;
    final payloadCandidates = [
      {'title': title, 'message': message, 'created_by': user.id, 'organizer_id': currentOrganizerId},
      {'title': title, 'message': message, 'created_by': user.id},
      {'title': title, 'message': message, 'organizer_id': currentOrganizerId},
      {'title': title, 'content': message, 'created_by': user.id},
      {'title': title, 'content': message, 'organizer_id': currentOrganizerId},
    ];

    for (final payload in payloadCandidates) {
      try {
        final res = await client
            .from('announcements')
            .insert(payload)
            .select()
            .maybeSingle();
        try { announcementsVersion.value++; } catch (_) {}
        if (res == null) return {};
        return res is Map<String, dynamic>
            ? res
            : Map<String, dynamic>.from(res as Map);
      } catch (e) {
        final err = e.toString().toLowerCase();
        final isMissingColumn = err.contains('column') || err.contains('does not exist') || err.contains('42703') || err.contains('42p01');
        if (!isMissingColumn) rethrow;
      }
    }

    return Future.error('Unable to create announcement for the connected schema.');
  }

  static Future<List<Map<String, dynamic>>> getAnnouncements({
    int limit = 100,
    String? organizerId,
  }) async {
    await ensureInitialized();

    final user = currentUser;
    final currentOrganizerId = organizerId ?? await getCurrentOrganizerId() ?? user?.id;

    final candidateQueries = <Future<List<Map<String, dynamic>>> Function()>[];
    if (currentOrganizerId != null && currentOrganizerId.isNotEmpty) {
      candidateQueries.add(() async {
        final res = await client
            .from('announcements')
            .select()
            .eq('created_by', currentOrganizerId)
            .order('created_at', ascending: false)
            .limit(limit);
        return _announcementRowsFromList(res);
      });
      candidateQueries.add(() async {
        final res = await client
            .from('announcements')
            .select()
            .eq('organizer_id', currentOrganizerId)
            .order('created_at', ascending: false)
            .limit(limit);
        return _announcementRowsFromList(res);
      });
      candidateQueries.add(() async {
        final res = await client
            .from('announcements')
            .select()
            .eq('created_by', user?.id ?? currentOrganizerId)
            .order('created_at', ascending: false)
            .limit(limit);
        return _announcementRowsFromList(res);
      });
    }

    candidateQueries.add(() async {
      final res = await client
          .from('announcements')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);
      return _announcementRowsFromList(res);
    });

    for (final query in candidateQueries) {
      try {
        final rows = await query();
        if (rows.isNotEmpty || currentOrganizerId == null || currentOrganizerId.isEmpty) {
          return rows;
        }
      } catch (e) {
        final err = e.toString().toLowerCase();
        final isMissingColumn = err.contains('column') || err.contains('does not exist') || err.contains('42703') || err.contains('42p01');
        if (!isMissingColumn) rethrow;
      }
    }

    return [];
  }

  static Future<bool> deleteAnnouncement(int id, {String? organizerId}) async {
    await ensureInitialized();

    final user = currentUser;
    final currentOrganizerId = organizerId ?? await getCurrentOrganizerId() ?? user?.id;
    final candidateQueries = <Future<void> Function()>[];

    if (currentOrganizerId != null && currentOrganizerId.isNotEmpty) {
      candidateQueries.add(() async {
        await client.from('announcements').delete().eq('id', id).eq('created_by', currentOrganizerId);
      });
      candidateQueries.add(() async {
        await client.from('announcements').delete().eq('id', id).eq('organizer_id', currentOrganizerId);
      });
      candidateQueries.add(() async {
        await client.from('announcements').delete().eq('id', id).eq('created_by', user?.id ?? currentOrganizerId);
      });
    }

    candidateQueries.add(() async {
      await client.from('announcements').delete().eq('id', id);
    });

    for (final query in candidateQueries) {
      try {
        await query();
        try { announcementsVersion.value++; } catch (_) {}
        return true;
      } catch (e) {
        final err = e.toString().toLowerCase();
        final isMissingColumn = err.contains('column') || err.contains('does not exist') || err.contains('42703') || err.contains('42p01');
        if (!isMissingColumn) rethrow;
      }
    }

    return false;
  }

  static List<Map<String, dynamic>> _announcementRowsFromList(dynamic res) {
    if (res is List) {
      return List<Map<String, dynamic>>.from(
        res.map((e) => Map<String, dynamic>.from(e as Map)),
      );
    }
    return const [];
  }
}

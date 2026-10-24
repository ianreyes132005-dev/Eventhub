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

  // ── Events ────────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getEvents({int limit = 100}) async {
    await ensureInitialized();
    // Archived events are hidden from the Events tab — left out by the query,
    // so they don't use up the limit either.
    final res = await client
        .from('events')
        .select()
        .eq('approval_status', 'approved')
        .is_('archived_at', null)
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

    final row = await client
        .from('announcements')
        .insert({
          'title': title,
          'message': message,
          'created_by': user.id,
        })
        .select()
        .single();
    announcementsVersion.value++;
    return Map<String, dynamic>.from(row as Map);
  }

  static Future<List<Map<String, dynamic>>> getAnnouncements({
    int limit = 100,
    String? organizerId,
  }) async {
    await ensureInitialized();

    final user = currentUser;
    if (user == null) return [];

    final isOrganizer = organizerId != null || await getCurrentOrganizerId() != null;
    final rows = isOrganizer
      ? await client
        .from('announcements')
        .select()
        .eq('created_by', user.id)
        .order('created_at', ascending: false)
        .limit(limit)
      : await client
        .from('announcements')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return _announcementRowsFromList(rows);
  }

  static Future<bool> deleteAnnouncement(int id, {String? organizerId}) async {
    await ensureInitialized();

    final user = currentUser;
    if (user == null) return false;

    if (organizerId != null || await getCurrentOrganizerId() != null) {
      final deleted = await client
          .from('announcements')
          .delete()
          .eq('id', id)
          .eq('created_by', user.id)
          .select('id');
      if ((deleted as List).isEmpty) return false;
    } else {
      final deleted = await client
          .from('announcements')
          .delete()
          .eq('id', id)
          .select('id');
      if ((deleted as List).isEmpty) return false;
    }
    announcementsVersion.value++;
    return true;
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

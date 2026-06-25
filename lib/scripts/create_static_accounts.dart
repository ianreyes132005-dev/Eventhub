import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:eventhub/core/services/supabase_config.dart';

/// Development helper: create two static accounts (student + organizer)
/// Usage:
/// 1. Set `kSupabaseBaseUrl` and `kSupabaseServiceRoleKey` in
///    `lib/core/services/supabase_config.dart` (service role key required).
/// 2. Run: `dart run lib/scripts/create_static_accounts.dart`
///
/// NOTE: This script is intended for local/dev use only. Do NOT commit
/// service role keys to public repositories.

Future<void> main() async {
  if (kSupabaseBaseUrl.isEmpty || kSupabaseServiceRoleKey.isEmpty) {
    print(
      'Please set kSupabaseBaseUrl and kSupabaseServiceRoleKey in lib/services/supabase_config.dart',
    );
    return;
  }

  // Edit these credentials if you prefer different emails/passwords.
  const studentEmail = 'student@example.com';
  const studentPassword = 'StudentPass123!';
  const studentName = 'Static Student';

  const organizerEmail = 'organizer@example.com';
  const organizerPassword = 'OrganizerPass123!';
  const organizerName = 'Static Organizer';

  print('Creating static accounts using service role key...');

  final student = await _createAdminUser(
    studentEmail,
    studentPassword,
    studentName,
  );
  if (student != null) {
    final id = student['id'] as String?;
    if (id != null) {
      final ok = await _createStudentProfile(id, studentEmail, studentName);
      print('Student profile inserted: $ok');
    }
  }

  final organizer = await _createAdminUser(
    organizerEmail,
    organizerPassword,
    organizerName,
  );
  if (organizer != null) {
    final id = organizer['id'] as String?;
    if (id != null) {
      final ok = await _createOrganizerProfile(
        id,
        organizerEmail,
        organizerName,
      );
      print('Organizer profile inserted: $ok');
    }
  }

  print('Finished. Review output above for success/failure messages.');
}

Future<Map<String, dynamic>?> _createAdminUser(
  String email,
  String password,
  String fullName,
) async {
  final uri = Uri.parse('$kSupabaseBaseUrl/auth/v1/admin/users');
  final headers = {
    'Content-Type': 'application/json',
    'apikey': kSupabaseServiceRoleKey,
    'Authorization': 'Bearer $kSupabaseServiceRoleKey',
  };

  final body = json.encode({
    'email': email,
    'password': password,
    'user_metadata': {'full_name': fullName},
  });

  try {
    final resp = await http.post(uri, headers: headers, body: body);
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final jsonResp = json.decode(resp.body) as Map<String, dynamic>;
      print('Created auth user: ${jsonResp['id']} ($email)');
      return jsonResp;
    } else {
      print(
        'Failed to create auth user ($email): ${resp.statusCode} ${resp.body}',
      );
      return null;
    }
  } catch (e) {
    print('Exception creating auth user ($email): $e');
    return null;
  }
}

Future<bool> _createStudentProfile(
  String userId,
  String email,
  String fullName,
) async {
  final uri = Uri.parse('$kSupabaseBaseUrl/rest/v1/students');
  final headers = {
    'Content-Type': 'application/json',
    'apikey': kSupabaseServiceRoleKey,
    'Authorization': 'Bearer $kSupabaseServiceRoleKey',
    'Prefer': 'return=representation',
  };

  final body = json.encode([
    {
      'user_id': userId,
      'email': email,
      'full_name': fullName,
      'is_active': true,
    },
  ]);

  try {
    final resp = await http.post(uri, headers: headers, body: body);
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      print('Inserted student profile: ${resp.body}');
      return true;
    } else {
      print(
        'Failed to insert student profile: ${resp.statusCode} ${resp.body}',
      );
      return false;
    }
  } catch (e) {
    print('Exception inserting student profile: $e');
    return false;
  }
}

Future<bool> _createOrganizerProfile(
  String userId,
  String email,
  String fullName,
) async {
  final uri = Uri.parse('$kSupabaseBaseUrl/rest/v1/organizers');
  final headers = {
    'Content-Type': 'application/json',
    'apikey': kSupabaseServiceRoleKey,
    'Authorization': 'Bearer $kSupabaseServiceRoleKey',
    'Prefer': 'return=representation',
  };

  final body = json.encode([
    {
      'organizer_id': userId,
      'email': email,
      'full_name': fullName,
      'is_active': true,
    },
  ]);

  try {
    final resp = await http.post(uri, headers: headers, body: body);
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      print('Inserted organizer profile: ${resp.body}');
      return true;
    } else {
      print(
        'Failed to insert organizer profile: ${resp.statusCode} ${resp.body}',
      );
      return false;
    }
  } catch (e) {
    print('Exception inserting organizer profile: $e');
    return false;
  }
}

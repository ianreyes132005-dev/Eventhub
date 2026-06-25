import 'dart:convert';

import 'package:http/http.dart' as http;

// Usage: dart run lib/scripts/supabase_auth_test.dart <SUPABASE_URL> <ANON_KEY> <email> <password>
// Example:
// dart run lib/scripts/supabase_auth_test.dart https://xyz.supabase.co YOUR_ANON_KEY test+123@example.com TestPass123!

Future<void> main(List<String> args) async {
  if (args.length < 4) {
    return;
  }

  final url = args[0].trim().replaceAll(RegExp(r'\/$'), '');
  final anon = args[1].trim();
  final email = args[2].trim();
  final password = args[3];

  final signupUri = Uri.parse('$url/auth/v1/signup');
  final tokenUri = Uri.parse('$url/auth/v1/token');

  final headers = {
    'apikey': anon,
    'Authorization': 'Bearer $anon',
    'Content-Type': 'application/json',
  };
  try {
    final res = await http.post(
      signupUri,
      headers: headers,
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (res.statusCode == 429) {
      return;
    }
    if (res.statusCode >= 400) {
      return;
    }
    final loginRes = await http.post(
      tokenUri,
      headers: headers,
      body: jsonEncode({
        'grant_type': 'password',
        'email': email,
        'password': password,
      }),
    );
  } catch (e) {
  }
}

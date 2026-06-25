import 'package:http/http.dart' as http;

// Usage:
// dart run lib/scripts/supabase_check.dart <SUPABASE_URL> <ANON_KEY>
// Example:
// dart run lib/scripts/supabase_check.dart https://xyz.supabase.co YOUR_ANON_KEY

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    return;
  }

  final url = args[0].trim().replaceAll(RegExp(r'\/$'), '');
  final anonKey = args[1].trim();

  final restRoot = Uri.parse('$url/rest/v1/');
  try {
    final res = await http.get(
      restRoot,
      headers: {'apikey': anonKey, 'Authorization': 'Bearer $anonKey'},
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
    } else if (res.statusCode == 401 || res.statusCode == 403) {
    } else {
    }
  } catch (e) {
  }
}

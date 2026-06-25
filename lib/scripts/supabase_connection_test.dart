import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:eventhub/core/services/supabase_config.dart';

/// Simple test script to verify Supabase connection
Future<void> testSupabaseConnection() async {
  try {
    await Supabase.initialize(url: kSupabaseBaseUrl, anonKey: kSupabaseAnonKey);

    final client = Supabase.instance.client;
    // Test basic connection by trying to get the current user (should be null for anon)
    final currentUser = client.auth.currentUser;
    // Test a simple query to verify database connection
    final response = await client.from('students').select('count').limit(1);
  } catch (e) {
  }
}

void main() {
  testSupabaseConnection();
}

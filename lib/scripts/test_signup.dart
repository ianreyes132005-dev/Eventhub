import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:eventhub/core/services/supabase_config.dart';

/// Test script to verify sign-up functionality
Future<void> testSignUpProcess() async {
  try {
    await Supabase.initialize(url: kSupabaseBaseUrl, anonKey: kSupabaseAnonKey);

    final client = Supabase.instance.client;
    // Test sign-up (replace with a test email)
    final testEmail =
        'test${DateTime.now().millisecondsSinceEpoch}@example.com';
    final testPassword = 'testpassword123';
    final testName = 'Test User';
    // This will send a confirmation email
    final response = await client.auth.signUp(
      email: testEmail,
      password: testPassword,
      data: {'full_name': testName},
    );

    if (response.user != null) {
    } else {
    }
  } catch (e) {
  }
}

void main() {
  testSignUpProcess();
}

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/services/supabase_config.dart';
import 'core/services/notif_read_store.dart';
import 'core/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: kSupabaseBaseUrl, anonKey: kSupabaseAnonKey);

  if (kIsWeb) {
    runApp(const JirehEventHubWebApp());
  } else {
    await NotifReadStore.init();
    runApp(const JirehEventHubApp());
    setupAppLinks();
    setupAuthStateListener();
  }
}

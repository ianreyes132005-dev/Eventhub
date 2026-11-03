import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/services/supabase_config.dart';
import 'core/services/notif_read_store.dart';
import 'core/theme_store.dart';
import 'core/app_router.dart';
import 'core/services/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: kSupabaseBaseUrl, anonKey: kSupabaseAnonKey);
  await PushNotificationService.initialize();

  if (kIsWeb) {
    await ThemeStore.init();
    runApp(const JirehEventHubWebApp());
  } else {
    await NotifReadStore.init();
    await ThemeStore.init();
    runApp(const JirehEventHubApp());
    setupAppLinks();
    setupAuthStateListener();
  }
}

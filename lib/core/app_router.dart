import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/supabase_service.dart';
import 'theme_store.dart';

// Exposed so MaterialApp widgets in app.dart can reference it.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Listens for Supabase auth events (e.g. deep-link sign-in after email
/// confirmation) and routes the user to the correct dashboard.
/// Only active on mobile — on web, WebAuthScreen owns auth routing.
void setupAuthStateListener() {
  if (kIsWeb) return;

  // When Supabase restores a persisted session on startup it fires a signedIn
  // event immediately after the listener subscribes. We must skip that event
  // or the app navigates to the dashboard without the user entering a password.
  // A genuine deep-link sign-in has no pre-existing session, so it is unaffected.
  bool skipRestore = Supabase.instance.client.auth.currentSession != null;

  Supabase.instance.client.auth.onAuthStateChange.listen((event) async {
    if (event.event != AuthChangeEvent.signedIn) return;

    if (skipRestore) {
      skipRestore = false;
      return;
    }

    // _handleLogin() in auth_screen.dart owns this sign-in — it performs the
    // role gate and navigates itself. Skip here to avoid a race condition.
    if (SupabaseService.handlingAppLogin) return;

    final user = event.session?.user;
    if (user == null) return;

    try {
      final organizerRow = await SupabaseService.client
          .from('organizers')
          .select('organizer_id')
          .eq('user_id', user.id)
          .maybeSingle();
      final isOrg = organizerRow != null;
      final route = isOrg ? '/organizer' : '/student';

      await ThemeStore.loadForUser(user.id, isOrg ? 'organizer' : 'student');

      if (navigatorKey.currentContext != null) {
        navigatorKey.currentState?.pushNamedAndRemoveUntil(route, (r) => false);
      }
    } catch (e, stack) {
      debugPrint('Auth state listener error: $e\n$stack');
    }
  });
}

void setupAppLinks() async {
  final appLinks = AppLinks();

  Future<void> handleUri(Uri? uri) async {
    if (uri == null) return;
    if ((uri.scheme == 'eventhub' && uri.path == '/auth-callback') ||
        uri.host == 'auth-callback') {
      final user = SupabaseService.client.auth.currentUser;
      if (user == null) return;
      try {
        final organizerRow = await SupabaseService.client
            .from('organizers')
            .select('organizer_id')
            .eq('user_id', user.id)
            .maybeSingle();
        final route = organizerRow != null ? '/organizer' : '/student';
        navigatorKey.currentState?.pushNamedAndRemoveUntil(route, (r) => false);
      } catch (_) {}
    }
  }

  try {
    final initial = await appLinks.getInitialAppLink();
    await handleUri(initial);
  } catch (_) {}

  appLinks.uriLinkStream.listen(
    (uri) async => handleUri(uri),
    onError: (_) {},
  );
}

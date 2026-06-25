import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/supabase_service.dart';

// Exposed so MaterialApp widgets in app.dart can reference it.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Listens for Supabase auth events (e.g. deep-link sign-in after email
/// confirmation) and routes the user to the correct dashboard.
/// Only active on mobile — on web, WebAuthScreen owns auth routing.
void setupAuthStateListener() {
  if (kIsWeb) return;

  Supabase.instance.client.auth.onAuthStateChange.listen((event) async {
    if (event.event != AuthChangeEvent.signedIn) return;

    // _handleLogin() in auth_screen.dart owns this sign-in — it performs the
    // role gate and navigates itself. Skip here to avoid a race condition.
    if (SupabaseService.handlingAppLogin) return;

    final user = event.session?.user;
    if (user == null) return;

    try {
      final adminRow = await SupabaseService.client
          .from('admins')
          .select('admin_id')
          .eq('user_id', user.id)
          .maybeSingle();

      String route;
      if (adminRow != null) {
        route = '/admin';
      } else {
        final organizerRow = await SupabaseService.client
            .from('organizers')
            .select('organizer_id')
            .eq('user_id', user.id)
            .maybeSingle();
        route = organizerRow != null ? '/organizer' : '/student';
      }

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
        final adminRow = await SupabaseService.client
            .from('admins')
            .select('admin_id')
            .eq('user_id', user.id)
            .maybeSingle();

        String route;
        if (adminRow != null) {
          route = '/admin';
        } else {
          final organizerRow = await SupabaseService.client
              .from('organizers')
              .select('organizer_id')
              .eq('user_id', user.id)
              .maybeSingle();
          route = organizerRow != null ? '/organizer' : '/student';
        }
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

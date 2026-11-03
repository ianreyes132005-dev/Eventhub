import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_router.dart';

enum PushSetupResult {
  enabled,
  denied,
  notConfigured,
  unavailable,
  notSupported,
}

class PushNotificationService {
  PushNotificationService._();

  static const _channelId = 'eventhub_notifications';
  static const _channelName = 'EventHub notifications';

  static final _localNotifications = FlutterLocalNotificationsPlugin();
  static StreamSubscription<String>? _tokenRefreshSubscription;
  static StreamSubscription<RemoteMessage>? _messageSubscription;
  static StreamSubscription<RemoteMessage>? _openedSubscription;
  static Future<bool>? _initializing;
  static String? lastSetupError;
  static String? _initializationError;

  static Future<bool> initialize() => _initializing ??= _initialize();

  static Future<bool> _initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      _initializationError = null;
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();

      await _localNotifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_eventhub'),
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload == null || payload.isEmpty) {
            unawaited(_openDashboard());
            return;
          }
          try {
            final decoded = jsonDecode(payload);
            final data = decoded is Map
                ? Map<String, dynamic>.from(decoded)
                : const <String, dynamic>{};
            unawaited(_openDashboard(data));
          } catch (error, stack) {
            debugPrint(
              'Could not read notification destination: $error\n$stack',
            );
            unawaited(_openDashboard());
          }
        },
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              _channelName,
              description: 'Updates about EventHub events and announcements.',
              importance: Importance.high,
            ),
          );

      _messageSubscription ??= FirebaseMessaging.onMessage.listen(
        _showForegroundNotification,
        onError: (Object error, StackTrace stack) {
          debugPrint('Foreground push listener failed: $error\n$stack');
        },
      );
      _openedSubscription ??= FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _openDashboard(message.data),
        onError: (Object error, StackTrace stack) {
          debugPrint('Push notification open handler failed: $error\n$stack');
        },
      );
      // The push sender needs FCM tokens; onRegistered now emits an FID.
      _tokenRefreshSubscription ??=
          // ignore: deprecated_member_use
          FirebaseMessaging.instance.onTokenRefresh.listen(
            _onTokenRefresh,
            onError: (Object error, StackTrace stack) {
              debugPrint('FCM token refresh listener failed: $error\n$stack');
            },
          );

      final initialMessage = await FirebaseMessaging.instance
          .getInitialMessage();
      if (initialMessage != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _openDashboard(initialMessage.data),
        );
      }
      return true;
    } catch (error, stack) {
      _initializationError = error.toString();
      debugPrint(
        'Push notifications could not initialize. Check android/app/google-services.json: '
        '$error\n$stack',
      );
      return false;
    }
  }

  static Future<PushSetupResult> enableForUser(String userId) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return PushSetupResult.notSupported;
    }
    lastSetupError = null;
    if (!await initialize()) {
      lastSetupError =
          _initializationError ??
          'Firebase initialization failed. Check the Android Firebase config.';
      return PushSetupResult.notConfigured;
    }

    try {
      final messaging = FirebaseMessaging.instance;
      var settings = await messaging.getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        final prefs = await SharedPreferences.getInstance();
        final promptKey = 'push_permission_prompted_$userId';
        if (prefs.getBool(promptKey) == true) return PushSetupResult.denied;
        settings = await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
        await prefs.setBool(promptKey, true);
      }
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        debugPrint(
          'Push notification permission was not granted: '
          '${settings.authorizationStatus.name}',
        );
        return PushSetupResult.denied;
      }

      // The push sender requires an FCM registration token, not a Firebase
      // Installation ID emitted by register()/onRegistered.
      // ignore: deprecated_member_use
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) {
        throw StateError('Firebase did not return an FCM registration token.');
      }
      await _registerToken(userId, token);
      return PushSetupResult.enabled;
    } catch (error, stack) {
      lastSetupError = error.toString();
      debugPrint('Could not enable push notifications: $error\n$stack');
      return PushSetupResult.unavailable;
    }
  }

  static Future<void> disableForCurrentDevice() async {
    if (!await initialize()) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('eventhub_push_token');
      if (token != null) {
        await Supabase.instance.client.rpc(
          'unregister_push_token',
          params: {'p_token': token},
        );
        await prefs.remove('eventhub_push_token');
      }
    } catch (error, stack) {
      debugPrint('Could not unregister this device for push: $error\n$stack');
    }
  }

  static Future<void> _registerToken(String userId, String token) async {
    if (Supabase.instance.client.auth.currentUser?.id != userId) return;
    await Supabase.instance.client.rpc(
      'register_push_token',
      params: {'p_token': token},
    );
    if (Supabase.instance.client.auth.currentUser?.id != userId) {
      await Supabase.instance.client.rpc(
        'unregister_push_token',
        params: {'p_token': token},
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('eventhub_push_token', token);
  }

  static void _onTokenRefresh(String token) {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    unawaited(
      _registerToken(userId, token).catchError((
        Object error,
        StackTrace stack,
      ) {
        debugPrint('Could not save FCM registration: $error\n$stack');
      }),
    );
  }

  static Future<void> _showForegroundNotification(RemoteMessage message) async {
    try {
      final title = message.notification?.title ?? 'EventHub update';
      final body = message.notification?.body ?? '';
      await _localNotifications.show(
        id:
            message.messageId?.hashCode ??
            DateTime.now().millisecondsSinceEpoch,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription:
                'Updates about EventHub events and announcements.',
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_stat_eventhub',
          ),
        ),
        payload: jsonEncode(message.data),
      );
    } catch (error, stack) {
      debugPrint(
        'Could not display foreground push notification: $error\n$stack',
      );
    }
  }

  static Future<void> _openDashboard([
    Map<String, dynamic> data = const {},
  ]) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final organizer = await Supabase.instance.client
          .from('organizers')
          .select('organizer_id')
          .eq('user_id', user.id)
          .maybeSingle();
      final route = organizer == null ? '/student' : '/organizer';
      final eventId = data['event_id']?.toString();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigatorKey.currentState?.pushNamedAndRemoveUntil(
          route,
          (route) => false,
          arguments: organizer == null && eventId != null
              ? {'event_id': eventId}
              : null,
        );
      });
    } catch (error, stack) {
      debugPrint('Could not route from push notification: $error\n$stack');
    }
  }
}

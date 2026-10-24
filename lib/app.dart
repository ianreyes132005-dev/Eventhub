import 'package:flutter/material.dart';
import 'features/auth/auth_screen.dart';
import 'features/student/dashboard/student_dashboard.dart';
import 'features/organizer/mobile/dashboard/organizer_dashboard.dart';
import 'features/organizer/web/web_shell.dart';
import 'features/auth/web_auth_screen.dart';
import 'core/app_theme.dart';
import 'core/theme_store.dart';
import 'core/app_router.dart';

class JirehEventHubApp extends StatelessWidget {
  const JirehEventHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeStore.notifier,
      builder: (_, mode, _) => MaterialApp(
        title: 'J-Jireh EventHub',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: mode,
        initialRoute: '/',
        routes: {
          '/': (context) => Theme(
            data: AppTheme.lightTheme,
            child: const AuthScreen(),
          ),
          '/student': (context) => const StudentDashboard(),
          '/organizer': (context) => const OrganizerDashboardScreen(),
        },
      ),
    );
  }
}

class JirehEventHubWebApp extends StatelessWidget {
  const JirehEventHubWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeStore.notifier,
      builder: (_, mode, _) => MaterialApp(
        title: 'J-Jireh EventHub — Organizer',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: mode,
        initialRoute: '/',
        routes: {
          '/': (context) => const WebAuthScreen(),
          '/organizer': (context) => const OrganizerWebDashboard(),
        },
      ),
    );
  }
}

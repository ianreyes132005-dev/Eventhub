import 'package:flutter/material.dart';
import 'features/auth/auth_screen.dart';
import 'features/student/dashboard/student_dashboard.dart';
import 'features/organizer/mobile/dashboard/organizer_dashboard.dart';
import 'features/organizer/web/web_shell.dart';
import 'features/admin/admin_dashboard.dart';
import 'features/auth/web_auth_screen.dart';
import 'core/app_theme.dart';
import 'core/app_router.dart';

const String kSupabaseSignupRedirect = 'eventhub://auth-callback';

class JirehEventHubApp extends StatelessWidget {
  const JirehEventHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'J-Jireh EventHub',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: AppTheme.lightTheme,
      initialRoute: '/',
      routes: {
        '/': (context) => const AuthScreen(),
        '/student': (context) => const StudentDashboard(),
        '/organizer': (context) => const OrganizerDashboardScreen(),
        '/admin': (context) => const AdminDashboard(),
      },
    );
  }
}

class JirehEventHubWebApp extends StatelessWidget {
  const JirehEventHubWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'J-Jireh EventHub — Organizer',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: AppTheme.lightTheme,
      initialRoute: '/',
      routes: {
        '/': (context) => const WebAuthScreen(),
        '/organizer': (context) => const OrganizerWebDashboard(),
      },
    );
  }
}

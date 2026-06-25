import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/services/supabase_service.dart';

// Admin panel is web-only. This screen appears when an admin logs in on mobile.
class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  Future<void> _signOut(BuildContext context) async {
    await SupabaseService.client.auth.signOut();
    if (context.mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F3EC),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  gradient: kGoldGradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.admin_panel_settings_rounded,
                    color: Colors.white, size: 36),
              ),
              const SizedBox(height: 24),
              const Text(
                'Admin Panel',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'The admin panel is only available\non the desktop web version.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 28),
              TextButton.icon(
                onPressed: () => _signOut(context),
                icon: const Icon(Icons.logout_rounded,
                    size: 16, color: Color(0xFFEF4444)),
                label: const Text(
                  'Sign Out',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFEF4444),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

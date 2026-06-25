import 'package:flutter/material.dart';
import 'app_colors.dart';

const Color _kBurntOrange = Color(0xFFD97706);

/// AppTheme provides a ready-to-use Material 3 ThemeData.
/// Plug via: MaterialApp(theme: AppTheme.lightTheme)
class AppTheme {
  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    fontFamily: 'Poppins',
    scaffoldBackgroundColor: kBackground,

    colorScheme: const ColorScheme(
      brightness: Brightness.light,
      primary: kGold,
      onPrimary: Colors.white,
      secondary: _kBurntOrange,
      onSecondary: Colors.white,
      error: Colors.red,
      onError: Colors.white,
      surface: Colors.white,
      onSurface: kText,
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: kBackground,
      elevation: 0,
      iconTheme: IconThemeData(color: kText),
      titleTextStyle: TextStyle(
        fontFamily: 'Poppins',
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: kText,
      ),
      centerTitle: true,
    ),

    textTheme: const TextTheme(
      displayLarge:  TextStyle(fontFamily: 'Poppins', fontSize: 48, fontWeight: FontWeight.w700, color: kText),
      displayMedium: TextStyle(fontFamily: 'Poppins', fontSize: 40, fontWeight: FontWeight.w700, color: kText),
      displaySmall:  TextStyle(fontFamily: 'Poppins', fontSize: 32, fontWeight: FontWeight.w700, color: kText),
      headlineLarge: TextStyle(fontFamily: 'Poppins', fontSize: 24, fontWeight: FontWeight.w700, color: kText),
      headlineMedium:TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w600, color: kText),
      titleLarge:    TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w700, color: kText),
      titleMedium:   TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w600, color: kText),
      titleSmall:    TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w600, color: kText),
      bodyLarge:     TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w400, color: kText),
      bodyMedium:    TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w400, color: kText),
      bodySmall:     TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w400, color: kText),
    ),

    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: const EdgeInsets.all(8),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kGold,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
        elevation: 2,
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _kBurntOrange,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: Colors.transparent),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: kGold.withValues(alpha: 0.9), width: 1.5),
      ),
      hintStyle: TextStyle(fontFamily: 'Poppins', color: Colors.grey.shade500),
    ),

    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: kGold,
      unselectedItemColor: Colors.grey.shade600,
      showSelectedLabels: true,
      showUnselectedLabels: true,
      elevation: 4,
    ),

    iconTheme: const IconThemeData(color: kText),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kGold,
      foregroundColor: Colors.white,
    ),

    dividerColor: Colors.grey.withValues(alpha: 0.12),
  );
}

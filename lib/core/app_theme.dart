import 'package:flutter/material.dart';
import 'app_colors.dart';

const Color _kBurntOrange = Color(0xFFD97706);

// Dark-mode token aliases — mirrors AppTk dark getters
const Color _kDarkBg      = Color(0xFF18140F);
const Color _kDarkCard    = Color(0xFF231E17);
const Color _kDarkBorder  = Color(0xFF352D20);
const Color _kDarkText    = Color(0xFFF2EAD8);
const Color _kDarkSub     = Color(0xFFB8A880);
const Color _kDarkMuted   = Color(0xFF7A6E55);
const Color _kDarkDivider = Color(0xFF2C2518);
const Color _kDarkInputBg = Color(0xFF1E1912);
const Color _kDarkNav     = Color(0xFF1C1814);

/// AppTheme provides ready-to-use Material 3 ThemeDatas.
/// Plug via: MaterialApp(theme: AppTheme.lightTheme, darkTheme: AppTheme.darkTheme)
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

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    fontFamily: 'Poppins',
    scaffoldBackgroundColor: _kDarkBg,

    colorScheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: kGold,
      onPrimary: Colors.white,
      secondary: _kBurntOrange,
      onSecondary: Colors.white,
      error: Color(0xFFEF4444),
      onError: Colors.white,
      surface: _kDarkCard,
      onSurface: _kDarkText,
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: _kDarkBg,
      elevation: 0,
      iconTheme: IconThemeData(color: _kDarkText),
      titleTextStyle: TextStyle(
        fontFamily: 'Poppins',
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: _kDarkText,
      ),
      centerTitle: true,
    ),

    textTheme: const TextTheme(
      displayLarge:   TextStyle(fontFamily: 'Poppins', fontSize: 48, fontWeight: FontWeight.w700, color: _kDarkText),
      displayMedium:  TextStyle(fontFamily: 'Poppins', fontSize: 40, fontWeight: FontWeight.w700, color: _kDarkText),
      displaySmall:   TextStyle(fontFamily: 'Poppins', fontSize: 32, fontWeight: FontWeight.w700, color: _kDarkText),
      headlineLarge:  TextStyle(fontFamily: 'Poppins', fontSize: 24, fontWeight: FontWeight.w700, color: _kDarkText),
      headlineMedium: TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w600, color: _kDarkText),
      titleLarge:     TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w700, color: _kDarkText),
      titleMedium:    TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w600, color: _kDarkText),
      titleSmall:     TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w600, color: _kDarkText),
      bodyLarge:      TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w400, color: _kDarkText),
      bodyMedium:     TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w400, color: _kDarkText),
      bodySmall:      TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w400, color: _kDarkText),
    ),

    cardTheme: CardThemeData(
      color: _kDarkCard,
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
      fillColor: _kDarkInputBg,
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: _kDarkBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: _kDarkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: kGold.withValues(alpha: 0.9), width: 1.5),
      ),
      hintStyle: const TextStyle(fontFamily: 'Poppins', color: _kDarkMuted),
      labelStyle: const TextStyle(fontFamily: 'Poppins', color: _kDarkSub),
    ),

    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: _kDarkNav,
      selectedItemColor: kGold,
      unselectedItemColor: _kDarkMuted,
      showSelectedLabels: true,
      showUnselectedLabels: true,
      elevation: 4,
    ),

    iconTheme: const IconThemeData(color: _kDarkText),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kGold,
      foregroundColor: Colors.white,
    ),

    dividerColor: _kDarkDivider,
  );
}

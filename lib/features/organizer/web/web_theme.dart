import 'package:flutter/material.dart';
import 'web_layout.dart';

enum SidebarVariant { inset, floating, minimal }

/// Live app theme — held in web_shell, propagated to all web page children.
///
/// [dark] is NOT a persisted preference — it's the app's current ThemeMode
/// (from ThemeStore / Theme.of(context).brightness), merged in at render time
/// via `copyWith(dark: ...)` right before building the sidebar. When true, it
/// hard-overrides the sidebar to the same graphite palette the admin
/// dashboard's sidebar uses, so both web dashboards match in dark mode —
/// the organizer's custom secondary color is a LIGHT-mode-only preference.
class AppTheme {
  final Color          primaryColor;
  final Color          secondaryColor;
  final SidebarVariant variant;
  final bool           dark;

  const AppTheme({
    this.primaryColor   = kWebLightGold,
    this.secondaryColor = const Color(0xFFFFFFFF),
    this.variant        = SidebarVariant.inset,
    this.dark           = false,
  });

  AppTheme copyWith({
    Color?          primaryColor,
    Color?          secondaryColor,
    SidebarVariant? variant,
    bool?           dark,
  }) => AppTheme(
    primaryColor:   primaryColor   ?? this.primaryColor,
    secondaryColor: secondaryColor ?? this.secondaryColor,
    variant:        variant        ?? this.variant,
    dark:           dark           ?? this.dark,
  );

  // ── Dark-mode graphite palette — identical to the admin dashboard's
  // sidebar tokens, a shade darker than the WebTk content canvas for the
  // same layered nav → page → card hierarchy. ────────────────────────────────
  static const _darkTop      = Color(0xFF080A0E);
  static const _darkMid      = Color(0xFF0A0C11);
  static const _darkBot      = Color(0xFF0D0F15);
  static const _darkBorder   = Color(0xFF1C212B);
  static const _darkNavText  = Color(0xFFE4E7EC);
  static const _darkNavIcon  = Color(0xFF7E8695);
  static const _darkNavLabel = Color(0xFF565E6C);

  bool get _isDark =>
    ThemeData.estimateBrightnessForColor(secondaryColor) == Brightness.dark;

  // Near-white sidebars (e.g. the Pure White default) need solid fills:
  // white-alpha overlays and computed shades vanish on a white panel.
  bool get _nearWhite =>
    HSLColor.fromColor(secondaryColor).lightness >= 0.97;

  LinearGradient get sideGradient {
    if (dark) {
      return const LinearGradient(
        colors: [_darkTop, _darkMid, _darkBot],
        begin: Alignment.topCenter,
        end:   Alignment.bottomCenter,
      );
    }
    if (_nearWhite) {
      return LinearGradient(
        colors: [secondaryColor, secondaryColor],
        begin: Alignment.topCenter,
        end:   Alignment.bottomCenter,
      );
    }
    final hsl = HSLColor.fromColor(secondaryColor);
    final l   = hsl.lightness;
    return LinearGradient(
      colors: [
        hsl.withLightness((l + 0.035).clamp(0.0, 1.0)).toColor(),
        secondaryColor,
        hsl.withLightness((l - 0.035).clamp(0.0, 1.0)).toColor(),
      ],
      begin: Alignment.topCenter,
      end:   Alignment.bottomCenter,
    );
  }

  Color get navActiveColor {
    if (dark) return primaryColor;
    final hsl = HSLColor.fromColor(secondaryColor);
    return _isDark
      ? hsl.withLightness((hsl.lightness + 0.18).clamp(0.0, 1.0)).toColor()
      : hsl.withLightness((hsl.lightness - 0.075).clamp(0.0, 1.0)).toColor();
  }

  Color get navHoverColor {
    if (dark) return Colors.white.withValues(alpha: 0.06);
    return _isDark
      ? Colors.white.withValues(alpha: 0.12)
      : _nearWhite
        ? const Color(0xFFF1F5F9)
        : Colors.white.withValues(alpha: 0.46);
  }

  Color get userCardFill {
    if (dark) return Colors.white.withValues(alpha: 0.06);
    return !_isDark && _nearWhite
      ? const Color(0xFFF8FAFC)
      : Colors.white.withValues(alpha: 0.58);
  }

  Color get sideBorder {
    if (dark) return _darkBorder;
    if (_nearWhite) return const Color(0xFFCBD5E1);
    final hsl = HSLColor.fromColor(secondaryColor);
    return hsl.withLightness((hsl.lightness - 0.12).clamp(0.0, 1.0)).toColor();
  }

  Color get navText  => dark ? _darkNavText  : (_isDark ? const Color(0xFFF1F5F9) : kNavText);
  Color get navIcon  => dark ? _darkNavIcon  : (_isDark ? const Color(0xFFCBD5E1) : kNavIcon);
  Color get navLabel => dark ? _darkNavLabel : (_isDark ? const Color(0xFF94A3B8) : const Color(0xFF7A6A52));
  Color get logoText => dark ? const Color(0xFFF5D78A) : (_isDark ? const Color(0xFFF5D78A) : const Color(0xFF3A3324));
  Color get logoSub  => dark ? primaryColor.withValues(alpha: 0.75) : (_isDark ? const Color(0xFFD4AF67) : const Color(0xFF7A6A52));

  LinearGradient get avatarGradient {
    final hsl = HSLColor.fromColor(primaryColor);
    final l   = hsl.lightness;
    return LinearGradient(
      colors: [
        hsl.withLightness((l - 0.08).clamp(0.0, 1.0)).toColor(),
        primaryColor,
        hsl.withLightness((l + 0.10).clamp(0.0, 1.0)).toColor(),
      ],
      begin: Alignment.topLeft,
      end:   Alignment.bottomRight,
    );
  }

  @override
  bool operator ==(Object other) =>
    other is AppTheme &&
    primaryColor   == other.primaryColor   &&
    secondaryColor == other.secondaryColor &&
    variant        == other.variant        &&
    dark           == other.dark;

  @override
  int get hashCode => Object.hash(primaryColor, secondaryColor, variant, dark);
}

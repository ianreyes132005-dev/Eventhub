import 'package:flutter/material.dart';
import 'web_layout.dart';

enum SidebarVariant { inset, floating, minimal }

/// Live app theme — held in web_shell, propagated to all web page children.
class AppTheme {
  final Color          primaryColor;
  final Color          secondaryColor;
  final SidebarVariant variant;

  const AppTheme({
    this.primaryColor   = kWebLightGold,
    this.secondaryColor = const Color(0xFFFFFFFF),
    this.variant        = SidebarVariant.inset,
  });

  AppTheme copyWith({
    Color?          primaryColor,
    Color?          secondaryColor,
    SidebarVariant? variant,
  }) => AppTheme(
    primaryColor:   primaryColor   ?? this.primaryColor,
    secondaryColor: secondaryColor ?? this.secondaryColor,
    variant:        variant        ?? this.variant,
  );

  bool get _isDark =>
    ThemeData.estimateBrightnessForColor(secondaryColor) == Brightness.dark;

  // Near-white sidebars (e.g. the Pure White default) need solid fills:
  // white-alpha overlays and computed shades vanish on a white panel.
  bool get _nearWhite =>
    HSLColor.fromColor(secondaryColor).lightness >= 0.97;

  LinearGradient get sideGradient {
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
    final hsl = HSLColor.fromColor(secondaryColor);
    return _isDark
      ? hsl.withLightness((hsl.lightness + 0.18).clamp(0.0, 1.0)).toColor()
      : hsl.withLightness((hsl.lightness - 0.075).clamp(0.0, 1.0)).toColor();
  }

  Color get navHoverColor => _isDark
    ? Colors.white.withValues(alpha: 0.12)
    : _nearWhite
      ? const Color(0xFFF1F5F9)
      : Colors.white.withValues(alpha: 0.46);

  Color get userCardFill => !_isDark && _nearWhite
    ? const Color(0xFFF8FAFC)
    : Colors.white.withValues(alpha: 0.58);

  Color get sideBorder {
    if (_nearWhite) return const Color(0xFFCBD5E1);
    final hsl = HSLColor.fromColor(secondaryColor);
    return hsl.withLightness((hsl.lightness - 0.12).clamp(0.0, 1.0)).toColor();
  }

  Color get navText  => _isDark ? const Color(0xFFF1F5F9) : kNavText;
  Color get navIcon  => _isDark ? const Color(0xFFCBD5E1) : kNavIcon;
  Color get navLabel => _isDark ? const Color(0xFF94A3B8) : const Color(0xFF7A6A52);
  Color get logoText => _isDark ? const Color(0xFFF5D78A) : const Color(0xFF3A3324);
  Color get logoSub  => _isDark ? const Color(0xFFD4AF67) : const Color(0xFF7A6A52);

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
    variant        == other.variant;

  @override
  int get hashCode => Object.hash(primaryColor, secondaryColor, variant);
}

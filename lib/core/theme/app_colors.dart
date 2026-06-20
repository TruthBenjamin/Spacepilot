import 'package:flutter/material.dart';

abstract final class AppColors {
  static const brand = Color(0xFF2F6BFF);
  static const brandDark = Color(0xFF7EA2FF);
  static const success = Color(0xFF18A77A);
  static const warning = Color(0xFFF4A62A);
  static const danger = Color(0xFFE85D75);
  static const info = Color(0xFF41A5F5);

  static const lightBackground = Color(0xFFF6F8FB);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceVariant = Color(0xFFE8ECF4);
  static const lightTextPrimary = Color(0xFF101828);
  static const lightTextSecondary = Color(0xFF667085);
  static const lightOutline = Color(0xFFD0D5DD);

  static const darkBackground = Color(0xFF0E1118);
  static const darkSurface = Color(0xFF171C27);
  static const darkSurfaceVariant = Color(0xFF202838);
  static const darkTextPrimary = Color(0xFFF6F8FB);
  static const darkTextSecondary = Color(0xFFA7B0C0);
  static const darkOutline = Color(0xFF30384A);

  static const lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: brand,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFDCE6FF),
    onPrimaryContainer: Color(0xFF001A4D),
    secondary: Color(0xFF52617A),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFDCE5F8),
    onSecondaryContainer: Color(0xFF0E1A2E),
    tertiary: success,
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFC8F4E5),
    onTertiaryContainer: Color(0xFF002117),
    error: danger,
    onError: Colors.white,
    errorContainer: Color(0xFFFFD9DF),
    onErrorContainer: Color(0xFF41000D),
    surface: lightSurface,
    onSurface: lightTextPrimary,
    surfaceContainerHighest: lightSurfaceVariant,
    onSurfaceVariant: lightTextSecondary,
    outline: lightOutline,
    outlineVariant: Color(0xFFE1E5EC),
    shadow: Color(0x1F101828),
    scrim: Color(0x99000000),
    inverseSurface: Color(0xFF202938),
    onInverseSurface: Color(0xFFF2F4F7),
    inversePrimary: brandDark,
  );

  static const darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: brandDark,
    onPrimary: Color(0xFF001A4D),
    primaryContainer: Color(0xFF123D9E),
    onPrimaryContainer: Color(0xFFDCE6FF),
    secondary: Color(0xFFB5C4DF),
    onSecondary: Color(0xFF1F2A3D),
    secondaryContainer: Color(0xFF2F3B52),
    onSecondaryContainer: Color(0xFFDCE5F8),
    tertiary: Color(0xFF55D6BE),
    onTertiary: Color(0xFF00382C),
    tertiaryContainer: Color(0xFF005144),
    onTertiaryContainer: Color(0xFFC8F4E5),
    error: Color(0xFFFFB2C0),
    onError: Color(0xFF680019),
    errorContainer: Color(0xFF93002A),
    onErrorContainer: Color(0xFFFFD9DF),
    surface: darkSurface,
    onSurface: darkTextPrimary,
    surfaceContainerHighest: darkSurfaceVariant,
    onSurfaceVariant: darkTextSecondary,
    outline: darkOutline,
    outlineVariant: Color(0xFF252C3B),
    shadow: Color(0x66000000),
    scrim: Color(0xCC000000),
    inverseSurface: Color(0xFFE8ECF4),
    onInverseSurface: Color(0xFF101828),
    inversePrimary: brand,
  );
}

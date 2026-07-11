import 'package:flutter/material.dart';

abstract final class AppColors {
  static const brand = Color(0xFF406DFF);
  static const brandDark = Color(0xFF7FA8FF);
  static const success = Color(0xFF3ED9A1);
  static const warning = Color(0xFFFAA63F);
  static const danger = Color(0xFFEA5E7B);
  static const info = Color(0xFF4D8CFF);

  static const lightBackground = Color(0xFFFAFCFF);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceVariant = Color(0xFFF2F7FF);
  static const lightTextPrimary = Color(0xFF111B3A);
  static const lightTextSecondary = Color(0xFF5F6F90);
  static const lightOutline = Color(0xFFD7E3F9);

  static const darkBackground = Color(0xFF0A1124);
  static const darkSurface = Color(0xFF101A36);
  static const darkSurfaceVariant = Color(0xFF161F3B);
  static const darkTextPrimary = Color(0xFFF3F7FF);
  static const darkTextSecondary = Color(0xFFB1B9D3);
  static const darkOutline = Color(0xFF1D2955);

  static const lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: brand,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFD5E2FF),
    onPrimaryContainer: Color(0xFF002969),
    secondary: Color(0xFF476FB8),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFD8E6FF),
    onSecondaryContainer: Color(0xFF0F2145),
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
    outlineVariant: Color(0xFFE7EEF9),
    shadow: Color(0x14000000),
    scrim: Color(0x66000000),
    inverseSurface: Color(0xFFF4F8FF),
    onInverseSurface: Color(0xFF111B3A),
    inversePrimary: brandDark,
  );

  static const darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF7FA8FF),
    onPrimary: Colors.white,
    primaryContainer: Color(0xFF223A72),
    onPrimaryContainer: Color(0xFFE6EEFF),
    secondary: Color(0xFF4FD6FF),
    onSecondary: Color(0xFF002731),
    secondaryContainer: Color(0xFF0E4163),
    onSecondaryContainer: Color(0xFFC8F6FF),
    tertiary: success,
    onTertiary: Color(0xFF002F19),
    tertiaryContainer: Color(0xFF144332),
    onTertiaryContainer: Color(0xFFC8F4E5),
    error: danger,
    onError: Colors.white,
    errorContainer: Color(0xFF8F192D),
    onErrorContainer: Color(0xFFFFD9DF),
    surface: darkSurface,
    onSurface: darkTextPrimary,
    surfaceContainerHighest: darkSurfaceVariant,
    onSurfaceVariant: darkTextSecondary,
    outline: darkOutline,
    outlineVariant: Color(0xFF2A3A60),
    shadow: Color(0x66000000),
    scrim: Color(0xCC000000),
    inverseSurface: Color(0xFFE8ECF4),
    onInverseSurface: Color(0xFF101828),
    inversePrimary: brand,
  );
}

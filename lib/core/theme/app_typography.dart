import 'package:flutter/material.dart';

abstract final class AppTypography {
  static const _fontFamily = 'Roboto';

  static TextTheme textTheme(ColorScheme colorScheme) {
    final baseColor = colorScheme.onSurface;
    final mutedColor = colorScheme.onSurfaceVariant;

    return TextTheme(
      displayLarge: _style(57, 64, FontWeight.w700, baseColor),
      displayMedium: _style(45, 52, FontWeight.w700, baseColor),
      displaySmall: _style(36, 44, FontWeight.w700, baseColor),
      headlineLarge: _style(32, 40, FontWeight.w700, baseColor),
      headlineMedium: _style(28, 36, FontWeight.w700, baseColor),
      headlineSmall: _style(24, 32, FontWeight.w700, baseColor),
      titleLarge: _style(22, 30, FontWeight.w700, baseColor),
      titleMedium: _style(16, 24, FontWeight.w700, baseColor),
      titleSmall: _style(14, 20, FontWeight.w700, baseColor),
      bodyLarge: _style(16, 24, FontWeight.w400, baseColor),
      bodyMedium: _style(14, 20, FontWeight.w400, baseColor),
      bodySmall: _style(12, 16, FontWeight.w400, mutedColor),
      labelLarge: _style(14, 20, FontWeight.w700, baseColor),
      labelMedium: _style(12, 16, FontWeight.w700, baseColor),
      labelSmall: _style(11, 16, FontWeight.w700, mutedColor),
    );
  }

  static TextStyle _style(
    double size,
    double height,
    FontWeight weight,
    Color color,
  ) {
    return TextStyle(
      fontFamily: _fontFamily,
      fontSize: size,
      height: height / size,
      fontWeight: weight,
      color: color,
      letterSpacing: 0,
    );
  }
}

import 'package:flutter/material.dart';

import 'app_radii.dart';

abstract final class AppComponentThemes {
  static AppBarTheme appBar(ColorScheme colorScheme, TextTheme textTheme) {
    return AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: colorScheme.onSurface,
      titleTextStyle: textTheme.titleLarge,
    );
  }

  static CardThemeData card(ColorScheme colorScheme) {
    return CardThemeData(
      elevation: 0,
      color: colorScheme.surface.withValues(alpha: 0.96),
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(22),
      ),
    );
  }

  static FilledButtonThemeData filledButton(ColorScheme colorScheme) {
    return FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        disabledBackgroundColor: colorScheme.onSurface.withValues(alpha: 0.12),
        disabledForegroundColor: colorScheme.onSurface.withValues(alpha: 0.38),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.15,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(AppRadii.standard.pill),
          ),
        ),
      ),
    );
  }

  static OutlinedButtonThemeData outlinedButton(ColorScheme colorScheme) {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        foregroundColor: colorScheme.onSurface,
        side: BorderSide(color: colorScheme.primaryContainer),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.15,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(AppRadii.standard.pill),
          ),
        ),
      ),
    );
  }

  static InputDecorationThemeData inputDecoration(ColorScheme colorScheme) {
    final radius = BorderRadius.all(Radius.circular(AppRadii.standard.md));

    return InputDecorationThemeData(
      filled: true,
      fillColor: colorScheme.primaryContainer.withValues(alpha: 0.12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colorScheme.error),
      ),
    );
  }

  static NavigationBarThemeData navigationBar(ColorScheme colorScheme) {
    return NavigationBarThemeData(
      elevation: 0,
      backgroundColor: colorScheme.surface,
      indicatorColor: colorScheme.primaryContainer,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  static ChipThemeData chip(ColorScheme colorScheme, TextTheme textTheme) {
    return ChipThemeData(
      backgroundColor: colorScheme.surfaceContainerHighest,
      selectedColor: colorScheme.primaryContainer,
      disabledColor: colorScheme.onSurface.withValues(alpha: 0.08),
      labelStyle: textTheme.labelMedium,
      secondaryLabelStyle: textTheme.labelMedium?.copyWith(
        color: colorScheme.onPrimaryContainer,
      ),
      side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.16)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.standard.pill),
      ),
    );
  }
}

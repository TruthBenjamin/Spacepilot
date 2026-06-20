import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_component_themes.dart';
import 'app_radii.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

abstract final class AppTheme {
  static ThemeData get light {
    return _base(
      colorScheme: AppColors.lightScheme,
      scaffoldBackgroundColor: AppColors.lightBackground,
    );
  }

  static ThemeData get dark {
    return _base(
      colorScheme: AppColors.darkScheme,
      scaffoldBackgroundColor: AppColors.darkBackground,
    );
  }

  static ThemeData _base({
    required ColorScheme colorScheme,
    required Color scaffoldBackgroundColor,
  }) {
    final textTheme = AppTypography.textTheme(colorScheme);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackgroundColor,
      textTheme: textTheme,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppComponentThemes.appBar(colorScheme, textTheme),
      cardTheme: AppComponentThemes.card(colorScheme),
      filledButtonTheme: AppComponentThemes.filledButton(colorScheme),
      outlinedButtonTheme: AppComponentThemes.outlinedButton(colorScheme),
      inputDecorationTheme: AppComponentThemes.inputDecoration(colorScheme),
      navigationBarTheme: AppComponentThemes.navigationBar(colorScheme),
      chipTheme: AppComponentThemes.chip(colorScheme, textTheme),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      extensions: const [AppSpacing.standard, AppRadii.standard],
    );
  }
}

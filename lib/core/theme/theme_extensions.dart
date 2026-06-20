import 'package:flutter/material.dart';

import 'app_radii.dart';
import 'app_spacing.dart';

extension ThemeTokens on BuildContext {
  AppSpacing get spacing => Theme.of(this).extension<AppSpacing>()!;
  AppRadii get radii => Theme.of(this).extension<AppRadii>()!;
}

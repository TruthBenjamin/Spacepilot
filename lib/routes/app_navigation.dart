import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'app_routes.dart';

extension AppNavigation on BuildContext {
  void goToSplash() => goNamed(AppRouteNames.splash);

  void goToOnboarding() => goNamed(AppRouteNames.onboarding);

  void goToDashboard() => goNamed(AppRouteNames.dashboard);

  void goToScanResults() => goNamed(AppRouteNames.scanResults);

  void goToLargeFiles() => goNamed(AppRouteNames.largeFiles);

  void goToDuplicates() => goNamed(AppRouteNames.duplicates);

  void goToSettings() => goNamed(AppRouteNames.settings);

  Future<T?> pushScanResults<T extends Object?>() {
    return pushNamed<T>(AppRouteNames.scanResults);
  }

  Future<T?> pushLargeFiles<T extends Object?>() {
    return pushNamed<T>(AppRouteNames.largeFiles);
  }

  Future<T?> pushDuplicates<T extends Object?>() {
    return pushNamed<T>(AppRouteNames.duplicates);
  }

  Future<T?> pushSettings<T extends Object?>() {
    return pushNamed<T>(AppRouteNames.settings);
  }
}

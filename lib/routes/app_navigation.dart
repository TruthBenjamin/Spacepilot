import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'app_routes.dart';

extension AppNavigation on BuildContext {
  void goToSplash() => goNamed(AppRouteNames.splash);

  void goToOnboarding() => goNamed(AppRouteNames.onboarding);

  void goToDashboard() => goNamed(AppRouteNames.dashboard);

  void goToRecommendations() => goNamed(AppRouteNames.recommendations);

  void goToDeviceHealth() => goNamed(AppRouteNames.deviceHealth);

  void goToStorageOverview() => goNamed(AppRouteNames.storageOverview);

  void goToScanResults() => goNamed(AppRouteNames.scanResults);

  void goToLargeFiles() => goNamed(AppRouteNames.largeFiles);

  void goToDuplicates() => goNamed(AppRouteNames.duplicates);

  void goToSimilarImages() => goNamed(AppRouteNames.similarImages);

  void goToAppAnalyzer() => goNamed(AppRouteNames.appAnalyzer);

  void goToTools() => goNamed(AppRouteNames.tools);

  void goToStorageTimeline() => goNamed(AppRouteNames.storageTimeline);

  void goToAutomation() => goNamed(AppRouteNames.automation);

  void goToRecoveryBin() => goNamed(AppRouteNames.recoveryBin);

  void goToPrivacyCenter() => goNamed(AppRouteNames.privacyCenter);

  void goToSettings() => goNamed(AppRouteNames.settings);

  void goToBooster() => goNamed(AppRouteNames.booster);

  void goToCooling() => goNamed(AppRouteNames.cooling);

  void goToBatteryOptimization() => goNamed(AppRouteNames.batteryOptimization);
  void goToJunkCleaner() => goNamed(AppRouteNames.junkCleaner);

  void goToNetworkAssistant() => goNamed(AppRouteNames.networkAssistant);

  Future<T?> pushScanResults<T extends Object?>({bool showResults = false}) {
    return pushNamed<T>(
      AppRouteNames.scanResults,
      queryParameters: showResults ? const {'view': 'results'} : const {},
    );
  }

  Future<T?> pushStorageOverview<T extends Object?>() {
    return pushNamed<T>(AppRouteNames.storageOverview);
  }

  Future<T?> pushDeviceHealth<T extends Object?>() {
    return pushNamed<T>(AppRouteNames.deviceHealth);
  }

  Future<T?> pushStorageFiles<T extends Object?>({String? category}) {
    final queryParameters = <String, String>{};
    if (category != null) {
      queryParameters['category'] = category;
    }

    return pushNamed<T>(
      AppRouteNames.storageFiles,
      queryParameters: queryParameters,
    );
  }

  Future<T?> pushLargeFiles<T extends Object?>() {
    return pushNamed<T>(AppRouteNames.largeFiles);
  }

  Future<T?> pushDuplicates<T extends Object?>() {
    return pushNamed<T>(AppRouteNames.duplicates);
  }

  Future<T?> pushSimilarImages<T extends Object?>() {
    return pushNamed<T>(AppRouteNames.similarImages);
  }

  Future<T?> pushAppAnalyzer<T extends Object?>() {
    return pushNamed<T>(AppRouteNames.appAnalyzer);
  }

  Future<T?> pushTools<T extends Object?>() {
    return pushNamed<T>(AppRouteNames.tools);
  }

  Future<T?> pushStorageTimeline<T extends Object?>() {
    return pushNamed<T>(AppRouteNames.storageTimeline);
  }

  Future<T?> pushAutomation<T extends Object?>() {
    return pushNamed<T>(AppRouteNames.automation);
  }

  Future<T?> pushRecoveryBin<T extends Object?>() {
    return pushNamed<T>(AppRouteNames.recoveryBin);
  }

  Future<T?> pushPrivacyCenter<T extends Object?>() {
    return pushNamed<T>(AppRouteNames.privacyCenter);
  }

  Future<T?> pushSettings<T extends Object?>() {
    return pushNamed<T>(AppRouteNames.settings);
  }

  Future<T?> pushBooster<T extends Object?>() {
    return pushNamed<T>(AppRouteNames.booster);
  }

  Future<T?> pushCooling<T extends Object?>() {
    return pushNamed<T>(AppRouteNames.cooling);
  }

  Future<T?> pushBatteryOptimization<T extends Object?>() {
    return pushNamed<T>(AppRouteNames.batteryOptimization);
  }

  Future<T?> pushJunkCleaner<T extends Object?>() =>
      pushNamed<T>(AppRouteNames.junkCleaner);

  Future<T?> pushNetworkAssistant<T extends Object?>() {
    return pushNamed<T>(AppRouteNames.networkAssistant);
  }
}

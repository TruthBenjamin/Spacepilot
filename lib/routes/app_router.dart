import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/battery_optimization/presentation/pages/battery_optimization_page.dart';
import '../features/app_analyzer/presentation/pages/app_analyzer_page.dart';
import '../features/auto_clean/presentation/pages/automation_page.dart';
import '../features/booster/presentation/pages/booster_page.dart';
import '../features/cooling/presentation/pages/cooling_page.dart';
import '../features/cleanup/presentation/pages/junk_cleaner_page.dart';
import '../features/cleanup/presentation/pages/junk_review_page.dart';
import '../features/dashboard/presentation/pages/dashboard_page.dart';
import '../features/device_health/presentation/pages/device_health_page.dart';
import '../features/duplicates/presentation/pages/duplicates_page.dart';
import '../features/duplicates/presentation/pages/similar_images_page.dart';
import '../features/large_files/presentation/pages/large_files_page.dart';
import '../features/network_assistant/presentation/pages/network_assistant_page.dart';
import '../features/onboarding/presentation/pages/onboarding_page.dart';
import '../features/privacy/presentation/pages/privacy_center_page.dart';
import '../features/recommendations/presentation/pages/recommendations_page.dart';
import '../features/recovery/presentation/pages/recovery_bin_page.dart';
import '../features/scan_results/presentation/pages/scan_results_page.dart';
import '../features/settings/presentation/pages/settings_page.dart';
import '../features/splash/presentation/pages/splash_page.dart';
import '../features/storage/presentation/pages/storage_category_file_browser_page.dart';
import '../features/storage/presentation/pages/storage_overview_page.dart';
import '../features/storage/presentation/pages/storage_timeline_page.dart';
import '../features/tools/presentation/pages/tools_page.dart';
import 'app_routes.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        name: AppRouteNames.splash,
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        name: AppRouteNames.onboarding,
        builder: (context, state) => const OnboardingPage(),
      ),
      GoRoute(
        path: AppRoutes.dashboard,
        name: AppRouteNames.dashboard,
        builder: (context, state) => const DashboardPage(),
      ),
      GoRoute(
        path: AppRoutes.recommendations,
        name: AppRouteNames.recommendations,
        builder: (context, state) => const RecommendationsPage(),
      ),
      GoRoute(
        path: AppRoutes.deviceHealth,
        name: AppRouteNames.deviceHealth,
        builder: (context, state) => const DeviceHealthPage(),
      ),
      GoRoute(
        path: AppRoutes.storageOverview,
        name: AppRouteNames.storageOverview,
        builder: (context, state) => const StorageOverviewPage(),
      ),
      GoRoute(
        path: AppRoutes.storageFiles,
        name: AppRouteNames.storageFiles,
        builder: (context, state) => StorageCategoryFileBrowserPage(
          categoryName: state.uri.queryParameters['category'],
        ),
      ),
      GoRoute(
        path: AppRoutes.scanResults,
        name: AppRouteNames.scanResults,
        builder: (context, state) => ScanResultsPage(
          showResults: state.uri.queryParameters['view'] == 'results',
        ),
      ),
      GoRoute(
        path: AppRoutes.largeFiles,
        name: AppRouteNames.largeFiles,
        builder: (context, state) => const LargeFilesPage(),
      ),
      GoRoute(
        path: AppRoutes.duplicates,
        name: AppRouteNames.duplicates,
        builder: (context, state) => const DuplicatesPage(),
      ),
      GoRoute(
        path: AppRoutes.similarImages,
        name: AppRouteNames.similarImages,
        builder: (context, state) => const SimilarImagesPage(),
      ),
      GoRoute(
        path: AppRoutes.appAnalyzer,
        name: AppRouteNames.appAnalyzer,
        builder: (context, state) => const AppAnalyzerPage(),
      ),
      GoRoute(
        path: AppRoutes.tools,
        name: AppRouteNames.tools,
        builder: (context, state) => const ToolsPage(),
      ),
      GoRoute(
        path: AppRoutes.storageTimeline,
        name: AppRouteNames.storageTimeline,
        builder: (context, state) => const StorageTimelinePage(),
      ),
      GoRoute(
        path: AppRoutes.automation,
        name: AppRouteNames.automation,
        builder: (context, state) => const AutomationPage(),
      ),
      GoRoute(
        path: AppRoutes.recoveryBin,
        name: AppRouteNames.recoveryBin,
        builder: (context, state) => const RecoveryBinPage(),
      ),
      GoRoute(
        path: AppRoutes.privacyCenter,
        name: AppRouteNames.privacyCenter,
        builder: (context, state) => const PrivacyCenterPage(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        name: AppRouteNames.settings,
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: AppRoutes.booster,
        name: AppRouteNames.booster,
        builder: (context, state) => const BoosterPage(),
      ),
      GoRoute(
        path: AppRoutes.cooling,
        name: AppRouteNames.cooling,
        builder: (context, state) => const CoolingPage(),
      ),
      GoRoute(
        path: AppRoutes.batteryOptimization,
        name: AppRouteNames.batteryOptimization,
        builder: (context, state) => const BatteryOptimizationPage(),
      ),
      GoRoute(
        path: AppRoutes.junkCleaner,
        name: AppRouteNames.junkCleaner,
        builder: (context, state) => const JunkCleanerPage(),
      ),
      GoRoute(
        path: AppRoutes.junkReview,
        name: AppRouteNames.junkReview,
        builder: (context, state) =>
            JunkReviewPage(categoryId: state.uri.queryParameters['category']),
      ),
      GoRoute(
        path: AppRoutes.networkAssistant,
        name: AppRouteNames.networkAssistant,
        builder: (context, state) => const NetworkAssistantPage(),
      ),
    ],
  );
});

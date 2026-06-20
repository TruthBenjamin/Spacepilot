import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/dashboard/presentation/pages/dashboard_page.dart';
import '../features/duplicates/presentation/pages/duplicates_page.dart';
import '../features/large_files/presentation/pages/large_files_page.dart';
import '../features/onboarding/presentation/pages/onboarding_page.dart';
import '../features/scan_results/presentation/pages/scan_results_page.dart';
import '../features/settings/presentation/pages/settings_page.dart';
import '../features/splash/presentation/pages/splash_page.dart';
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
        path: AppRoutes.scanResults,
        name: AppRouteNames.scanResults,
        builder: (context, state) => const ScanResultsPage(),
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
        path: AppRoutes.settings,
        name: AppRouteNames.settings,
        builder: (context, state) => const SettingsPage(),
      ),
    ],
  );
});

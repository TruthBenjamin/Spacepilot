import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../data/services/services.dart';
import '../../domain/models/models.dart';

enum AppAnalyzerSort {
  size('Largest'),
  name('Name'),
  recentlyUsed('Recently used'),
  rarelyUsed('Rarely used'),
  recentlyUpdated('Recently updated');

  const AppAnalyzerSort(this.label);

  final String label;
}

enum AppAnalyzerFilter {
  all('All apps'),
  user('User apps'),
  system('System apps'),
  measurableSize('Size known'),
  usageKnown('Usage known');

  const AppAnalyzerFilter(this.label);

  final String label;
}

final appAnalyzerServiceProvider = Provider<AppAnalyzerService>((ref) {
  return AppAnalyzerService();
});

final appAnalyzerSearchProvider = StateProvider<String>((ref) => '');

final appAnalyzerSortProvider = StateProvider<AppAnalyzerSort>((ref) {
  return AppAnalyzerSort.size;
});

final appAnalyzerFilterProvider = StateProvider<AppAnalyzerFilter>((ref) {
  return AppAnalyzerFilter.all;
});

final installedAppsReportProvider = FutureProvider<InstalledAppsReport>((
  ref,
) async {
  return ref.read(appAnalyzerServiceProvider).analyzeInstalledApps();
});

final filteredInstalledAppsProvider = Provider<AsyncValue<List<InstalledApp>>>((
  ref,
) {
  final report = ref.watch(installedAppsReportProvider);
  final query = ref.watch(appAnalyzerSearchProvider).trim().toLowerCase();
  final sort = ref.watch(appAnalyzerSortProvider);
  final filter = ref.watch(appAnalyzerFilterProvider);

  return report.whenData((report) {
    final apps = report.apps
        .where((app) {
          final matchesQuery =
              query.isEmpty ||
              app.appName.toLowerCase().contains(query) ||
              app.packageName.toLowerCase().contains(query);
          if (!matchesQuery) return false;

          return switch (filter) {
            AppAnalyzerFilter.all => true,
            AppAnalyzerFilter.user => !app.isSystemApp,
            AppAnalyzerFilter.system => app.isSystemApp,
            AppAnalyzerFilter.measurableSize => app.hasSizeData,
            AppAnalyzerFilter.usageKnown => app.hasUsageData,
          };
        })
        .toList(growable: false);

    apps.sort(
      (a, b) => switch (sort) {
        AppAnalyzerSort.size => _sizeOf(b).compareTo(_sizeOf(a)),
        AppAnalyzerSort.name => a.appName.toLowerCase().compareTo(
          b.appName.toLowerCase(),
        ),
        AppAnalyzerSort.recentlyUsed => _lastUsedOf(
          b,
        ).compareTo(_lastUsedOf(a)),
        AppAnalyzerSort.rarelyUsed => _lastUsedOf(a).compareTo(_lastUsedOf(b)),
        AppAnalyzerSort.recentlyUpdated => _updatedOf(
          b,
        ).compareTo(_updatedOf(a)),
      },
    );

    return apps;
  });
});

int _sizeOf(InstalledApp app) => app.totalSizeBytes ?? app.appSizeBytes ?? 0;

DateTime _lastUsedOf(InstalledApp app) {
  return app.lastUsedTime ?? DateTime.fromMillisecondsSinceEpoch(0);
}

DateTime _updatedOf(InstalledApp app) {
  return app.lastUpdateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
}

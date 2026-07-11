import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/features/auto_clean/domain/models/auto_clean_rules.dart';
import 'package:spacepilot/features/auto_clean/presentation/providers/auto_clean_provider.dart';
import 'package:spacepilot/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:spacepilot/features/device_health/domain/models/device_health_report.dart';
import 'package:spacepilot/features/device_health/presentation/providers/device_health_provider.dart';
import 'package:spacepilot/features/duplicates/presentation/providers/duplicate_groups_provider.dart';
import 'package:spacepilot/features/recommendations/presentation/providers/recommendations_provider.dart';
import 'package:spacepilot/features/storage/domain/models/storage_stats.dart';
import 'package:spacepilot/features/storage/presentation/providers/device_storage_provider.dart';
import 'package:spacepilot/features/storage/presentation/providers/storage_scan_provider.dart';
import 'package:spacepilot/routes/app_router.dart';
import 'package:spacepilot/routes/app_routes.dart';

void main() {
  testWidgets('storage loading state stays subtle and product-focused', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageScanProvider.overrideWithBuild(
            (ref, controller) =>
                const StorageScanState(files: [], hasScanned: false),
          ),
          deviceStorageStatsWithHealthProvider.overrideWith(
            (ref) => Completer<StorageStats>().future,
          ),
        ],
        child: const MaterialApp(home: DashboardPage()),
      ),
    );
    await tester.pump();

    expect(find.text('Storage Overview'), findsOneWidget);
    expect(find.text('Getting your overview ready'), findsOneWidget);
    expect(find.text('Reading device storage'), findsNothing);
    expect(
      find.byKey(const ValueKey('storage-overview-loading-progress')),
      findsOneWidget,
    );
  });

  testWidgets('dashboard renders after onboarding without layout exceptions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageScanProvider.overrideWithBuild(
            (ref, controller) =>
                const StorageScanState(files: [], hasScanned: false),
          ),
          deviceStorageStatsWithHealthProvider.overrideWith(
            (ref) async => StorageStats(
              totalBytes: 128 * 1024 * 1024 * 1024,
              usedBytes: 72 * 1024 * 1024 * 1024,
              freeBytes: 56 * 1024 * 1024 * 1024,
              deviceHealthScore: 88,
              lastUpdated: DateTime(2026),
            ),
          ),
          deviceHealthReportProvider.overrideWith((ref) async => _health()),
          duplicateGroupsProvider.overrideWith((ref) async => const []),
          similarImageGroupsProvider.overrideWith((ref) async => const []),
          recommendationsProvider.overrideWith((ref) async => const []),
          autoCleanPlanProvider.overrideWith(
            (ref) async => const AutoCleanPlan(
              ruleCount: 0,
              fileCount: 0,
              estimatedSavingsBytes: 0,
            ),
          ),
        ],
        child: const MaterialApp(home: DashboardPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Storage Overview'), findsOneWidget);
    expect(find.text('Device Health'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Large Files'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Large Files'), findsOneWidget);
    expect(find.text('Duplicate Cleaner'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard exposes the production dashboard actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageScanProvider.overrideWithBuild(
            (ref, controller) =>
                const StorageScanState(files: [], hasScanned: false),
          ),
          deviceStorageStatsWithHealthProvider.overrideWith(
            (ref) async => StorageStats(
              totalBytes: 128 * 1024 * 1024 * 1024,
              usedBytes: 72 * 1024 * 1024 * 1024,
              freeBytes: 56 * 1024 * 1024 * 1024,
              deviceHealthScore: 88,
              lastUpdated: DateTime(2026),
            ),
          ),
          deviceHealthReportProvider.overrideWith((ref) async => _health()),
          duplicateGroupsProvider.overrideWith((ref) async => const []),
          similarImageGroupsProvider.overrideWith((ref) async => const []),
          recommendationsProvider.overrideWith((ref) async => const []),
          autoCleanPlanProvider.overrideWith(
            (ref) async => const AutoCleanPlan(
              ruleCount: 0,
              fileCount: 0,
              estimatedSavingsBytes: 0,
            ),
          ),
        ],
        child: const MaterialApp(home: DashboardPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.scrollUntilVisible(
      find.text('Large Files'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Large Files'), findsOneWidget);
    expect(find.text('Duplicate Cleaner'), findsOneWidget);
    expect(find.text('App Analyzer'), findsOneWidget);
    expect(find.text('Smart Cleanup'), findsOneWidget);
    expect(find.text('Similar Images'), findsOneWidget);
    expect(find.text('Storage Timeline'), findsOneWidget);
    expect(find.text('Automation'), findsOneWidget);
    expect(find.text('Recovery Bin'), findsOneWidget);
  });

  testWidgets('dashboard cards open dedicated feature pages', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageScanProvider.overrideWithBuild(
            (ref, controller) =>
                const StorageScanState(files: [], hasScanned: false),
          ),
          deviceStorageStatsWithHealthProvider.overrideWith(
            (ref) async => StorageStats(
              totalBytes: 128 * 1024 * 1024 * 1024,
              usedBytes: 72 * 1024 * 1024 * 1024,
              freeBytes: 56 * 1024 * 1024 * 1024,
              deviceHealthScore: 88,
              lastUpdated: DateTime(2026),
            ),
          ),
          deviceHealthReportProvider.overrideWith((ref) async => _health()),
          duplicateGroupsProvider.overrideWith((ref) async => const []),
          similarImageGroupsProvider.overrideWith((ref) async => const []),
          recommendationsProvider.overrideWith((ref) async => const []),
          autoCleanPlanProvider.overrideWith(
            (ref) async => const AutoCleanPlan(
              ruleCount: 0,
              fileCount: 0,
              estimatedSavingsBytes: 0,
            ),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return MaterialApp.router(
              routerConfig: ref.watch(appRouterProvider),
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final router = container.read(appRouterProvider);
    router.goNamed(AppRouteNames.dashboard);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await tester.scrollUntilVisible(
      find.text('Smart Cleanup'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Smart Cleanup'));
    await tester.pump();
    await tester.tap(find.text('Smart Cleanup').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Smart Scan'), findsOneWidget);
  });
}

DeviceHealthReport _health() {
  return const DeviceHealthReport(
    score: 88,
    category: DeviceHealthCategory.excellent,
    breakdown: DeviceHealthScoreBreakdown(
      storageUsagePenalty: 0,
      duplicateFilesPenalty: 0,
      unusedAppsPenalty: 0,
      junkFilesPenalty: 0,
      oldDownloadsPenalty: 0,
      emptyFoldersPenalty: 0,
    ),
    suggestions: ['Your device health looks good.'],
    explanation: 'Test health report.',
  );
}

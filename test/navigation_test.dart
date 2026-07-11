import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/features/permissions/data/services/permission_service.dart';
import 'package:spacepilot/features/permissions/presentation/providers/permission_service_provider.dart';
import 'package:spacepilot/features/app_analyzer/data/services/app_analyzer_service.dart';
import 'package:spacepilot/features/app_analyzer/presentation/providers/app_analyzer_provider.dart';
import 'package:spacepilot/features/storage/data/services/storage_scanner_service.dart';
import 'package:spacepilot/features/storage/domain/models/storage_stats.dart';
import 'package:spacepilot/features/storage/presentation/providers/device_storage_provider.dart';
import 'package:spacepilot/features/storage/presentation/providers/storage_scan_provider.dart';
import 'package:spacepilot/routes/app_router.dart';
import 'package:spacepilot/routes/app_routes.dart';

void main() {
  testWidgets('router opens every primary destination by route name', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final channel = MethodChannel(
      'spacepilot/navigation-test-${DateTime.now()}',
    );
    final permissionChannel = MethodChannel(
      'spacepilot/permissions-test-${DateTime.now()}',
    );
    final appAnalyzerChannel = MethodChannel(
      'spacepilot/app-analyzer-test-${DateTime.now()}',
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      permissionChannel,
      (call) async => true,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method != 'scanStorageIntelligence') return null;

      final now = DateTime(2026).millisecondsSinceEpoch;
      return {
        'completedAt': now,
        'storageStats': {
          'totalBytes': 128 * 1024 * 1024 * 1024,
          'usedBytes': 72 * 1024 * 1024 * 1024,
          'freeBytes': 56 * 1024 * 1024 * 1024,
          'capturedAt': now,
        },
        'files': [
          {
            'filename': 'movie.mp4',
            'path': '/storage/emulated/0/Movies/movie.mp4',
            'size': 800 * 1024 * 1024,
            'lastModified': now,
            'categories': ['video'],
          },
          {
            'filename': 'archive.zip',
            'path': '/storage/emulated/0/Download/archive.zip',
            'size': 250 * 1024 * 1024,
            'lastModified': now,
            'categories': ['zip', 'download'],
          },
        ],
        'largestFolders': const [],
        'emptyFolders': const [],
        'categorySummaries': const [],
        'scannedRootPaths': const ['/storage/emulated/0/Download'],
      };
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      appAnalyzerChannel,
      (call) async {
        if (call.method != 'analyzeInstalledApps') return null;
        return {
          'apps': const [],
          'hasUsageAccess': false,
          'generatedAt': 0,
          'limitations': const ['Usage access is off.'],
        };
      },
    );

    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageScannerServiceProvider.overrideWithValue(
            StorageScannerService(channel: channel),
          ),
          permissionServiceProvider.overrideWithValue(
            PermissionService(channel: permissionChannel),
          ),
          appAnalyzerServiceProvider.overrideWithValue(
            AppAnalyzerService(channel: appAnalyzerChannel),
          ),
          deviceStorageStatsProvider.overrideWith(
            (ref) async => _storageStats(),
          ),
          deviceStorageStatsWithHealthProvider.overrideWith(
            (ref) async => _storageStats(),
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

    final router = container.read(appRouterProvider);

    router.goNamed(AppRouteNames.splash);
    await tester.pump();
    expect(find.text('Your AI Storage Assistant'), findsOneWidget);

    router.goNamed(AppRouteNames.onboarding);
    await _pumpRoute(tester);
    expect(find.text('Real Storage Access'), findsOneWidget);

    router.goNamed(AppRouteNames.dashboard);
    await _pumpRoute(tester);
    expect(find.text('Storage Overview'), findsOneWidget);

    router.goNamed(AppRouteNames.deviceHealth);
    await _pumpRoute(tester);
    expect(find.text('Device Health'), findsWidgets);

    router.goNamed(AppRouteNames.scanResults);
    await _pumpRoute(tester);
    expect(find.text('Smart Scan'), findsOneWidget);

    router.go('${AppRoutes.scanResults}?view=results');
    await _pumpRoute(tester);
    expect(find.text('AI Cleanup Scan'), findsOneWidget);
    expect(find.text('Cleanup review ready'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;

    router.goNamed(AppRouteNames.largeFiles);
    await _pumpRoute(tester);
    expect(find.text('Large File Hunter'), findsOneWidget);

    router.goNamed(AppRouteNames.duplicates);
    await _pumpRoute(tester);
    expect(find.text('Duplicate Files'), findsOneWidget);

    router.goNamed(AppRouteNames.similarImages);
    await _pumpRoute(tester);
    expect(find.text('Similar Images'), findsOneWidget);

    router.goNamed(AppRouteNames.appAnalyzer);
    await _pumpRoute(tester);
    expect(find.text('App Analyzer'), findsOneWidget);

    router.goNamed(AppRouteNames.storageTimeline);
    await _pumpRoute(tester);
    expect(find.text('Storage Timeline'), findsOneWidget);

    router.goNamed(AppRouteNames.automation);
    await _pumpRoute(tester);
    expect(find.text('Automation'), findsOneWidget);

    router.goNamed(AppRouteNames.settings);
    await _pumpRoute(tester);
    expect(find.text('Settings'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 600));
}

StorageStats _storageStats() {
  return StorageStats(
    totalBytes: 128 * 1024 * 1024 * 1024,
    usedBytes: 72 * 1024 * 1024 * 1024,
    freeBytes: 56 * 1024 * 1024 * 1024,
    deviceHealthScore: 88,
    lastUpdated: DateTime(2026),
  );
}

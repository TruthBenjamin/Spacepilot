import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/features/storage/domain/models/scanned_file.dart';
import 'package:spacepilot/features/storage/domain/models/storage_history_entry.dart';
import 'package:spacepilot/features/storage/domain/models/storage_intelligence_report.dart';
import 'package:spacepilot/features/storage/domain/models/storage_stats.dart';
import 'package:spacepilot/features/storage/presentation/pages/storage_category_file_browser_page.dart';
import 'package:spacepilot/features/storage/presentation/providers/device_storage_provider.dart';
import 'package:spacepilot/features/storage/presentation/providers/storage_history_provider.dart';
import 'package:spacepilot/features/storage/presentation/providers/storage_scan_provider.dart';
import 'package:spacepilot/routes/app_router.dart';
import 'package:spacepilot/routes/app_routes.dart';

void main() {
  testWidgets(
    'storage overview renders cached intelligence and opens category files',
    (tester) async {
      late ProviderContainer container;

      await tester.pumpWidget(
        _TestScope(
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

      container.read(appRouterProvider).goNamed(AppRouteNames.storageOverview);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Storage Intelligence'), findsOneWidget);
      expect(find.text('Storage Overview'), findsOneWidget);
      expect(find.text('Category Breakdown'), findsOneWidget);
      expect(find.text('Last scan 2026-01-02 03:04'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Largest Folders'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Largest Folders'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Recent Storage Changes'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Recent Storage Changes'), findsOneWidget);

      await tester.drag(find.byType(Scrollable).first, const Offset(0, 900));
      await tester.pumpAndSettle();
      final categoryDropdown = find.byWidgetPredicate(
        (widget) => widget is PopupMenuButton,
      );
      await tester.ensureVisible(categoryDropdown);
      await tester.pumpAndSettle();
      await tester.tap(categoryDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Images').last);
      await tester.pumpAndSettle();
      final imagesTile = find.widgetWithText(ListTile, 'Images').last;
      await tester.ensureVisible(imagesTile);
      await tester.pumpAndSettle();
      await tester.tap(imagesTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Images'), findsWidgets);
      expect(find.text('photo.jpg'), findsOneWidget);
      expect(find.text('movie.mp4'), findsNothing);
    },
  );

  testWidgets('category browser filters cached files by category', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestScope(
        child: const MaterialApp(
          home: StorageCategoryFileBrowserPage(categoryName: 'download'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Downloads'), findsWidgets);
    expect(find.text('installer.apk'), findsOneWidget);
    expect(find.text('photo.jpg'), findsNothing);
  });
}

class _TestScope extends StatelessWidget {
  const _TestScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final report = _report();
    return ProviderScope(
      overrides: [
        storageScanProvider.overrideWithBuild(
          (ref, controller) => StorageScanState(
            hasScanned: true,
            files: report.files,
            intelligenceReport: report,
          ),
        ),
        deviceStorageStatsProvider.overrideWith(
          (ref) async => report.storageStats,
        ),
        deviceStorageStatsWithHealthProvider.overrideWith(
          (ref) async => report.storageStats,
        ),
        storageHistoryProvider.overrideWith(
          (ref) async => [
            StorageHistoryEntry.fromReport(report),
            StorageHistoryEntry(
              timestamp: DateTime(2026, 1, 1, 3, 4),
              totalBytes: 1000,
              usedBytes: 500,
              freeBytes: 500,
              emptyFolderCount: 0,
              downloadFileCount: 1,
              downloadBytes: 150,
              largestFolders: const [],
            ),
          ],
        ),
      ],
      child: child,
    );
  }
}

StorageIntelligenceReport _report() {
  final completedAt = DateTime(2026, 1, 2, 3, 4);
  final files = [
    StorageFileInsight(
      file: _file('photo.jpg', '/storage/DCIM/photo.jpg', 200),
      categories: const [StorageFileCategory.image],
    ),
    StorageFileInsight(
      file: _file('movie.mp4', '/storage/Movies/movie.mp4', 300),
      categories: const [StorageFileCategory.video],
    ),
    StorageFileInsight(
      file: _file('installer.apk', '/storage/Download/installer.apk', 150),
      categories: const [StorageFileCategory.apk, StorageFileCategory.download],
    ),
  ];

  return StorageIntelligenceReport(
    storageStats: StorageStats(
      totalBytes: 1000,
      usedBytes: 700,
      freeBytes: 300,
      deviceHealthScore: 90,
      lastUpdated: completedAt,
    ),
    fileInsights: files,
    largestFolders: const [
      StorageFolderSummary(
        path: '/storage/Download',
        sizeBytes: 150,
        fileCount: 1,
        lastModified: null,
      ),
    ],
    emptyFolders: const [],
    categorySummaries: const [
      StorageCategorySummary(
        category: StorageFileCategory.image,
        fileCount: 1,
        totalBytes: 200,
      ),
      StorageCategorySummary(
        category: StorageFileCategory.video,
        fileCount: 1,
        totalBytes: 300,
      ),
      StorageCategorySummary(
        category: StorageFileCategory.apk,
        fileCount: 1,
        totalBytes: 150,
      ),
      StorageCategorySummary(
        category: StorageFileCategory.download,
        fileCount: 1,
        totalBytes: 150,
      ),
    ],
    scannedRootPaths: const ['/storage'],
    completedAt: completedAt,
  );
}

ScannedFile _file(String filename, String path, int size) {
  return ScannedFile(
    filename: filename,
    path: path,
    size: size,
    lastModified: DateTime(2026, 1, 2),
  );
}

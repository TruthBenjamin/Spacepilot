import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/features/duplicates/presentation/providers/duplicate_groups_provider.dart';
import 'package:spacepilot/features/duplicates/data/services/similar_image_detector_service.dart';
import 'package:spacepilot/features/large_files/presentation/providers/large_file_hunter_provider.dart';
import 'package:spacepilot/features/permissions/data/services/permission_service.dart';
import 'package:spacepilot/features/permissions/presentation/providers/permission_service_provider.dart';
import 'package:spacepilot/features/recommendations/domain/models/models.dart';
import 'package:spacepilot/features/recommendations/presentation/providers/recommendations_provider.dart';
import 'package:spacepilot/features/storage/data/services/storage_scanner_service.dart';
import 'package:spacepilot/features/storage/domain/models/scanned_file.dart';
import 'package:spacepilot/features/storage/domain/models/storage_stats.dart';
import 'package:spacepilot/features/storage/presentation/providers/device_storage_provider.dart';
import 'package:spacepilot/features/storage/presentation/providers/storage_scan_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('largeFileHunterProvider filters by threshold and sorts descending', () {
    final files = [
      _file('small.zip', '/downloads/small.zip', 99 * 1024 * 1024),
      _file('quarter.zip', '/downloads/quarter.zip', 250 * 1024 * 1024 + 1),
      _file('medium.zip', '/downloads/medium.zip', 500 * 1024 * 1024 + 1),
      _file('huge.zip', '/downloads/huge.zip', 1024 * 1024 * 1024 + 1),
    ];
    final container = _containerWithScan(files);
    addTearDown(container.dispose);

    container.read(largeFileThresholdProvider.notifier).state =
        LargeFileThreshold.mb500;

    final largeFiles = container.read(largeFileHunterProvider).requireValue;
    expect(largeFiles.map((file) => file.filename), ['huge.zip', 'medium.zip']);
  });

  test('largeFileHunterProvider supports 250 MB threshold accurately', () {
    final files = [
      _file('at-limit.zip', '/downloads/at-limit.zip', 250 * 1024 * 1024),
      _file(
        'over-limit.zip',
        '/downloads/over-limit.zip',
        250 * 1024 * 1024 + 1,
      ),
      _file('largest.zip', '/downloads/largest.zip', 600 * 1024 * 1024),
    ];
    final container = _containerWithScan(files);
    addTearDown(container.dispose);

    container.read(largeFileThresholdProvider.notifier).state =
        LargeFileThreshold.mb250;

    final largeFiles = container.read(largeFileHunterProvider).requireValue;
    expect(largeFiles.map((file) => file.filename), [
      'largest.zip',
      'over-limit.zip',
    ]);
  });

  test('pagedLargeFileHunterProvider returns fixed-size pages', () {
    final files = [
      for (var index = 0; index < 75; index++)
        _file(
          'large-$index.bin',
          '/downloads/large-$index.bin',
          (200 + index) * 1024 * 1024,
        ),
    ];
    final container = _containerWithScan(files);
    addTearDown(container.dispose);

    final firstPage = container.read(pagedLargeFileHunterProvider).requireValue;
    expect(firstPage.files, hasLength(largeFilePageSize));
    expect(firstPage.totalFiles, 75);
    expect(firstPage.hasNextPage, isTrue);

    container.read(largeFilePageProvider.notifier).state = 1;

    final secondPage = container
        .read(pagedLargeFileHunterProvider)
        .requireValue;
    expect(secondPage.files, hasLength(25));
    expect(secondPage.hasNextPage, isFalse);
  });

  test('duplicateGroupsProvider returns empty before any scan', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await expectLater(
      container.read(duplicateGroupsProvider.future),
      completion(isEmpty),
    );
  });

  test(
    'duplicateGroupsProvider detects duplicates from scanned files',
    () async {
      final root = await Directory.systemTemp.createTemp('provider_dupes_');
      addTearDown(() => root.delete(recursive: true));
      final original = await File('${root.path}/a.txt').writeAsString('same');
      final copy = await File('${root.path}/b.txt').writeAsString('same');
      final container = _containerWithScan([
        _file('a.txt', original.path, await original.length()),
        _file('b.txt', copy.path, await copy.length()),
      ]);
      addTearDown(container.dispose);

      final groups = await container.read(duplicateGroupsProvider.future);

      expect(groups, hasLength(1));
      expect(groups.single.files.map((file) => file.name), ['a.txt', 'b.txt']);
    },
  );

  test('recommendationsProvider is empty until a scan exists', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await expectLater(
      container.read(recommendationsProvider.future),
      completion(isEmpty),
    );
  });

  test(
    'recommendationsProvider builds duplicate and APK recommendations',
    () async {
      final root = await Directory.systemTemp.createTemp('provider_recs_');
      addTearDown(() => root.delete(recursive: true));
      final original = await File(
        '${root.path}/duplicate-a.txt',
      ).writeAsString('same');
      final copy = await File(
        '${root.path}/duplicate-b.txt',
      ).writeAsString('same');
      final installer = await File('${root.path}/app.apk').writeAsString('apk');
      final container = _containerWithScan([
        _file('duplicate-a.txt', original.path, await original.length()),
        _file('duplicate-b.txt', copy.path, await copy.length()),
        _file('app.apk', installer.path, 50),
      ]);
      addTearDown(container.dispose);

      final recommendations = await container.read(
        recommendationsProvider.future,
      );

      expect(
        recommendations.map((item) => item.type),
        containsAll([
          StorageRecommendationType.apkInstallers,
          StorageRecommendationType.duplicateMedia,
        ]),
      );
    },
  );

  test(
    'recommendationsProvider includes similar image savings when available',
    () async {
      final root = await Directory.systemTemp.createTemp('provider_similar_');
      addTearDown(() => root.delete(recursive: true));
      final first = await File('${root.path}/photo-a.jpg').writeAsString('a');
      final second = await File('${root.path}/photo-b.jpg').writeAsString('b');
      final container = _containerWithScan(
        [
          _file('photo-a.jpg', first.path, 100),
          _file('photo-b.jpg', second.path, 80),
        ],
        similarImageDetectorService: SimilarImageDetectorService(
          hashOverrides: {first.path: 0x1, second.path: 0x1},
          ),
      );
      addTearDown(container.dispose);

      final recommendations = await container.read(
        recommendationsProvider.future,
      );

      final duplicateMedia = recommendations.firstWhere(
        (item) => item.type == StorageRecommendationType.duplicateMedia,
      );
      expect(duplicateMedia.storageSavingsBytes, 80);
      expect(duplicateMedia.description, contains('perceptual hashing'));
    },
  );

  test('storageScanProvider prevents simultaneous native scans', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    var scanCalls = 0;
    final scannerChannel = MethodChannel(
      'spacepilot/provider-scan-test-${DateTime.now()}',
    );
    final permissionChannel = MethodChannel(
      'spacepilot/provider-permission-test-${DateTime.now()}',
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, (_) async => true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(scannerChannel, (call) async {
          if (call.method != 'scanStorageIntelligence') return null;
          scanCalls += 1;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          final now = DateTime(2026).millisecondsSinceEpoch;
          return {
            'completedAt': now,
            'storageStats': {
              'totalBytes': 128 * 1024 * 1024 * 1024,
              'usedBytes': 64 * 1024 * 1024 * 1024,
              'freeBytes': 64 * 1024 * 1024 * 1024,
              'capturedAt': now,
            },
            'files': const <Object?>[],
            'largestFolders': const <Object?>[],
            'emptyFolders': const <Object?>[],
            'categorySummaries': const <Object?>[],
            'scannedRootPaths': const <Object?>[],
          };
        });

    final container = ProviderContainer(
      overrides: [
        storageScannerServiceProvider.overrideWithValue(
          StorageScannerService(channel: scannerChannel),
        ),
        permissionServiceProvider.overrideWithValue(
          PermissionService(channel: permissionChannel),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(storageScanProvider.notifier);
    final firstScan = controller.scanIntelligence();
    final secondScan = controller.scanIntelligence();

    await Future.wait([firstScan, secondScan]);

    expect(scanCalls, 1);
    expect(container.read(storageScanProvider).requireValue.hasScanned, isTrue);
    expect(
      container.read(storageScanProgressProvider).stage,
      StorageScanStage.complete,
    );
  });
}

ProviderContainer _containerWithScan(
  List<ScannedFile> files, {
  SimilarImageDetectorService? similarImageDetectorService,
}) {
  return ProviderContainer(
    overrides: [
      storageScanProvider.overrideWithBuild(
        (ref, controller) => StorageScanState(hasScanned: true, files: files),
      ),
      deviceStorageStatsProvider.overrideWith((ref) async => _storageStats()),
      if (similarImageDetectorService != null)
        similarImageDetectorServiceProvider.overrideWithValue(
          similarImageDetectorService,
        ),
    ],
  );
}

ScannedFile _file(String filename, String path, int size) {
  return ScannedFile(
    filename: filename,
    path: path,
    size: size,
    lastModified: DateTime(2025),
  );
}

StorageStats _storageStats() {
  return StorageStats(
    totalBytes: 128 * 1024 * 1024 * 1024,
    usedBytes: 64 * 1024 * 1024 * 1024,
    freeBytes: 64 * 1024 * 1024 * 1024,
    deviceHealthScore: 0,
    lastUpdated: DateTime(2026),
  );
}

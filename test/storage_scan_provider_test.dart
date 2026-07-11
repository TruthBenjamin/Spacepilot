import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/features/permissions/data/services/permission_service.dart';
import 'package:spacepilot/features/permissions/presentation/providers/permission_service_provider.dart';
import 'package:spacepilot/features/storage/data/services/storage_scanner_service.dart';
import 'package:spacepilot/features/storage/domain/models/scanned_file.dart';
import 'package:spacepilot/features/storage/domain/models/storage_intelligence_report.dart';
import 'package:spacepilot/features/storage/domain/models/storage_stats.dart';
import 'package:spacepilot/features/storage/presentation/providers/storage_scan_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const scannerChannel = MethodChannel('test/storage_scan/scanner');
  const permissionChannel = MethodChannel('test/storage_scan/permissions');

  ProviderContainer buildContainer() {
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
    return container;
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(scannerChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('scan requests access, stores files, and marks scan complete', () async {
    final permissionCalls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, (call) async {
          permissionCalls.add(call.method);
          return true;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(scannerChannel, (call) async {
          return [
            {
              'filename': 'clip.mp4',
              'path': '/storage/emulated/0/Movies/clip.mp4',
              'size': 4096,
              'lastModified': 1767225600000,
            },
          ];
        });
    final container = buildContainer();

    final files = await container.read(storageScanProvider.notifier).scan();
    final state = container.read(storageScanProvider).requireValue;

    expect(permissionCalls, ['hasStorageAccess', 'hasMediaAccess']);
    expect(files.single.filename, 'clip.mp4');
    expect(state.hasScanned, isTrue);
    expect(state.totalBytes, 4096);
  });

  test(
    'scan surfaces permission denial and leaves provider in error',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(permissionChannel, (call) async => false);
      final container = buildContainer();

      await expectLater(
        container.read(storageScanProvider.notifier).scan(),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'PERMISSION_DENIED',
          ),
        ),
      );

      expect(container.read(storageScanProvider).hasError, isTrue);
    },
  );

  test(
    'removeDeletedPaths removes deleted files but preserves scan status',
    () {
      final container = ProviderContainer(
        overrides: [
          storageScanProvider.overrideWithBuild(
            (ref, controller) => StorageScanState(
              hasScanned: true,
              files: [
                _file('keep.txt', '/downloads/keep.txt', 10),
                _file('delete.txt', '/downloads/delete.txt', 20),
              ],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(storageScanProvider.notifier).removeDeletedPaths([
        '/downloads/delete.txt',
      ]);

      final state = container.read(storageScanProvider).requireValue;
      expect(state.hasScanned, isTrue);
      expect(state.files.map((file) => file.path), ['/downloads/keep.txt']);
      expect(state.totalBytes, 10);
    },
  );

  test('removeDeletedPaths rebuilds intelligence report summaries', () {
    final keep = _file('keep.mp4', '/storage/emulated/0/Movies/keep.mp4', 10);
    final deleted = _file(
      'delete.mp4',
      '/storage/emulated/0/Movies/delete.mp4',
      20,
    );
    final emptyFolder = EmptyFolder(
      path: '/storage/emulated/0/Download/old-empty',
      lastModified: DateTime(2026),
    );
    final container = ProviderContainer(
      overrides: [
        storageScanProvider.overrideWithBuild(
          (ref, controller) => StorageScanState(
            hasScanned: true,
            files: [keep, deleted],
            intelligenceReport: _report(
              [keep, deleted],
              emptyFolders: [emptyFolder],
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(storageScanProvider.notifier).removeDeletedPaths([
      deleted.path,
    ]);

    final report = container
        .read(storageScanProvider)
        .requireValue
        .intelligenceReport!;
    expect(report.files.map((file) => file.path), [keep.path]);
    expect(report.summaryFor(StorageFileCategory.video).fileCount, 1);
    expect(report.summaryFor(StorageFileCategory.video).totalBytes, 10);
    expect(report.largestFolders.single.sizeBytes, 10);
    expect(report.storageStats.usedBytes, 80);
    expect(report.storageStats.freeBytes, 20);
    expect(report.emptyFolders.map((folder) => folder.path), [
      emptyFolder.path,
    ]);
  });

  test(
    'removeDeletedPaths removes deleted empty folders from cached report',
    () {
      final keepFolder = EmptyFolder(
        path: '/storage/emulated/0/Download/keep-empty',
        lastModified: DateTime(2026),
      );
      final deletedFolder = EmptyFolder(
        path: r'/storage/emulated/0/Download/delete-empty',
        lastModified: DateTime(2026),
      );
      final container = ProviderContainer(
        overrides: [
          storageScanProvider.overrideWithBuild(
            (ref, controller) => StorageScanState(
              hasScanned: true,
              files: const [],
              intelligenceReport: _report(
                const [],
                emptyFolders: [keepFolder, deletedFolder],
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(storageScanProvider.notifier).removeDeletedPaths([
        r'\storage\emulated\0\Download\delete-empty',
      ]);

      final report = container
          .read(storageScanProvider)
          .requireValue
          .intelligenceReport!;
      expect(report.emptyFolders.map((folder) => folder.path), [
        keepFolder.path,
      ]);
    },
  );

  test('moveFilePath updates scanned files and intelligence report paths', () {
    final file = _file('clip.mp4', '/storage/emulated/0/Download/clip.mp4', 10);
    final container = ProviderContainer(
      overrides: [
        storageScanProvider.overrideWithBuild(
          (ref, controller) => StorageScanState(
            hasScanned: true,
            files: [file],
            intelligenceReport: _report([file]),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container
        .read(storageScanProvider.notifier)
        .moveFilePath(
          fromPath: file.path,
          toPath: '/storage/emulated/0/Movies/clip.mp4',
          filename: 'clip.mp4',
        );

    final state = container.read(storageScanProvider).requireValue;
    expect(state.files.single.path, '/storage/emulated/0/Movies/clip.mp4');
    expect(
      state.intelligenceReport!.files.single.path,
      '/storage/emulated/0/Movies/clip.mp4',
    );
    expect(
      state.intelligenceReport!.largestFolders.single.path,
      '/storage/emulated/0/Movies',
    );
  });
}

ScannedFile _file(String filename, String path, int size) {
  return ScannedFile(
    filename: filename,
    path: path,
    size: size,
    lastModified: DateTime(2026),
  );
}

StorageIntelligenceReport _report(
  List<ScannedFile> files, {
  List<EmptyFolder> emptyFolders = const [],
}) {
  return StorageIntelligenceReport(
    storageStats: StorageStats(
      totalBytes: 100,
      usedBytes: 100,
      freeBytes: 0,
      deviceHealthScore: 0,
      lastUpdated: DateTime(2026),
    ),
    fileInsights: [
      for (final file in files)
        StorageFileInsight(
          file: file,
          categories: const [StorageFileCategory.video],
        ),
    ],
    largestFolders: const [],
    emptyFolders: emptyFolders,
    categorySummaries: [
      StorageCategorySummary(
        category: StorageFileCategory.video,
        fileCount: files.length,
        totalBytes: files.fold<int>(0, (total, file) => total + file.size),
      ),
    ],
    scannedRootPaths: const ['/storage/emulated/0'],
    completedAt: DateTime(2026),
  );
}

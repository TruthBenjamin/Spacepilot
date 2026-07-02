import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/features/duplicates/presentation/providers/duplicate_groups_provider.dart';
import 'package:spacepilot/features/large_files/presentation/providers/large_file_hunter_provider.dart';
import 'package:spacepilot/features/recommendations/domain/models/models.dart';
import 'package:spacepilot/features/recommendations/presentation/providers/recommendations_provider.dart';
import 'package:spacepilot/features/storage/domain/models/scanned_file.dart';
import 'package:spacepilot/features/storage/presentation/providers/storage_scan_provider.dart';

void main() {
  test('largeFileHunterProvider filters by threshold and sorts descending', () {
    final files = [
      _file('small.zip', '/downloads/small.zip', 99 * 1024 * 1024),
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
        '${root.path}/photo-a.jpg',
      ).writeAsString('same');
      final copy = await File('${root.path}/photo-b.jpg').writeAsString('same');
      final installer = await File('${root.path}/app.apk').writeAsString('apk');
      final container = _containerWithScan([
        _file('photo-a.jpg', original.path, await original.length()),
        _file('photo-b.jpg', copy.path, await copy.length()),
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
          StorageRecommendationType.duplicateFiles,
        ]),
      );
    },
  );
}

ProviderContainer _containerWithScan(List<ScannedFile> files) {
  return ProviderContainer(
    overrides: [
      storageScanProvider.overrideWithBuild(
        (ref, controller) => StorageScanState(hasScanned: true, files: files),
      ),
    ],
  );
}

ScannedFile _file(String filename, String path, int size) {
  return ScannedFile(
    filename: filename,
    path: path,
    size: size,
    lastModified: DateTime(2026),
  );
}

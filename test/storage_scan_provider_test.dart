import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/features/permissions/data/services/permission_service.dart';
import 'package:spacepilot/features/permissions/presentation/providers/permission_service_provider.dart';
import 'package:spacepilot/features/storage/data/services/storage_scanner_service.dart';
import 'package:spacepilot/features/storage/domain/models/scanned_file.dart';
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
}

ScannedFile _file(String filename, String path, int size) {
  return ScannedFile(
    filename: filename,
    path: path,
    size: size,
    lastModified: DateTime(2026),
  );
}

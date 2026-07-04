import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/features/storage/data/services/storage_scanner_service.dart';
import 'package:spacepilot/features/storage/domain/models/storage_intelligence_report.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/storage_scanner');
  late StorageScannerService service;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    service = StorageScannerService(channel: channel);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('scan maps valid platform payloads and drops malformed rows', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'scanStorageIntelligence');
          return [
            {
              'filename': 'movie.mp4',
              'path': '/storage/emulated/0/Movies/movie.mp4',
              'size': 2048,
              'lastModified': 1767225600000,
              'previewPath': '/storage/emulated/0/Movies/movie.mp4',
              'previewType': 'video',
            },
            {
              'filename': 'bad.txt',
              'path': '/storage/emulated/0/Download/bad.txt',
              'size': 'not-a-number',
              'lastModified': 1767225600000,
            },
            {
              'filename': 'negative.bin',
              'path': '/storage/emulated/0/Download/negative.bin',
              'size': -99,
              'lastModified': 1767225600000,
            },
          ];
        });

    final files = await service.scan();

    expect(files, hasLength(2));
    expect(files.first.filename, 'movie.mp4');
    expect(files.first.size, 2048);
    expect(files.first.previewPath, '/storage/emulated/0/Movies/movie.mp4');
    expect(files.first.previewType, 'video');
    expect(
      files.first.lastModified,
      DateTime.fromMillisecondsSinceEpoch(1767225600000),
    );
    expect(files.last.filename, 'negative.bin');
    expect(files.last.size, 0);
  });

  test('scanIntelligence maps storage totals and detected categories', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'scanStorageIntelligence');
          return {
            'storageStats': {
              'totalBytes': 10000,
              'usedBytes': 7000,
              'freeBytes': 3000,
              'capturedAt': 1767225600000,
            },
            'files': [
              {
                'filename': 'song.mp3',
                'path': '/storage/emulated/0/Music/song.mp3',
                'size': 1024,
                'lastModified': 1767225600000,
                'categories': ['audio'],
              },
              {
                'filename': 'app.apk',
                'path': '/storage/emulated/0/Download/app.apk',
                'size': 2048,
                'lastModified': 1767225600000,
                'categories': ['apk', 'download'],
              },
            ],
            'largestFolders': [
              {
                'path': '/storage/emulated/0/Download',
                'sizeBytes': 2048,
                'fileCount': 1,
                'lastModified': 1767225600000,
              },
            ],
            'emptyFolders': [
              {
                'path': '/storage/emulated/0/Download/empty',
                'lastModified': 1767225600000,
              },
            ],
            'categorySummaries': [
              {'category': 'audio', 'fileCount': 1, 'totalBytes': 1024},
              {'category': 'apk', 'fileCount': 1, 'totalBytes': 2048},
              {'category': 'download', 'fileCount': 1, 'totalBytes': 2048},
            ],
            'scannedRootPaths': ['/storage/emulated/0'],
            'completedAt': 1767225600000,
          };
        });

    final report = await service.scanIntelligence();

    expect(report.storageStats.totalBytes, 10000);
    expect(report.storageStats.usedBytes, 7000);
    expect(report.storageStats.freeBytes, 3000);
    expect(report.files.map((file) => file.filename), ['song.mp3', 'app.apk']);
    expect(report.fileInsights.last.categories, containsAll([
      StorageFileCategory.apk,
      StorageFileCategory.download,
    ]));
    expect(report.largestFolders.single.sizeBytes, 2048);
    expect(report.emptyFolders.single.path, endsWith('/empty'));
    expect(
      report.summaryFor(StorageFileCategory.audio).totalBytes,
      1024,
    );
  });

  test('scan returns an empty list for a null platform result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    await expectLater(service.scan(), completion(isEmpty));
  });

  test('scan rejects unsupported platforms before using the channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var channelCalled = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          channelCalled = true;
          return const [];
        });

    await expectLater(service.scan(), throwsA(isA<UnsupportedError>()));
    expect(channelCalled, isFalse);
  });
}

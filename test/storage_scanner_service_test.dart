import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/features/storage/data/services/storage_scanner_service.dart';

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
          expect(call.method, 'scanStorage');
          return [
            {
              'filename': 'movie.mp4',
              'path': '/storage/emulated/0/Movies/movie.mp4',
              'size': 2048,
              'lastModified': 1767225600000,
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
    expect(
      files.first.lastModified,
      DateTime.fromMillisecondsSinceEpoch(1767225600000),
    );
    expect(files.last.filename, 'negative.bin');
    expect(files.last.size, 0);
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

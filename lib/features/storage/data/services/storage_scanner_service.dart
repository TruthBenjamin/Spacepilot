import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/models/scanned_file.dart';

/// Scans shared storage folders through the Android platform channel.
final class StorageScannerService {
  StorageScannerService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'ai.spacepilot.app/storage_scanner';
  final MethodChannel _channel;

  /// Returns files in Downloads, DCIM, Movies, and Pictures.
  ///
  /// Storage read access (all-files access on Android 11+) must be granted
  /// before calling this method.
  Future<List<ScannedFile>> scan() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('StorageScannerService is Android-only.');
    }

    final files = await _channel.invokeListMethod<Object?>('scanStorage');
    if (files == null) return const [];

    return files
        .whereType<Map<Object?, Object?>>()
        .map((file) {
          try {
            return _scannedFileFromMap(file);
          } on FormatException {
            return null;
          }
        })
        .nonNulls
        .toList(growable: false);
  }
}

ScannedFile _scannedFileFromMap(Map<Object?, Object?> map) {
  final filename = map['filename'];
  final path = map['path'];
  final size = map['size'];
  final lastModified = map['lastModified'];

  if (filename is! String ||
      path is! String ||
      size is! num ||
      lastModified is! num) {
    throw const FormatException('Invalid scanned file payload.');
  }

  final safeSize = size.toInt();

  return ScannedFile(
    filename: filename,
    path: path,
    size: safeSize < 0 ? 0 : safeSize,
    lastModified: DateTime.fromMillisecondsSinceEpoch(lastModified.toInt()),
  );
}

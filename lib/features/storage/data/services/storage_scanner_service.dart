import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

@immutable
final class ScannedFile {
  const ScannedFile({
    required this.filename,
    required this.path,
    required this.size,
    required this.lastModified,
  });

  factory ScannedFile.fromMap(Map<Object?, Object?> map) {
    return ScannedFile(
      filename: map['filename']! as String,
      path: map['path']! as String,
      size: map['size']! as int,
      lastModified: DateTime.fromMillisecondsSinceEpoch(
        map['lastModified']! as int,
      ),
    );
  }

  final String filename;
  final String path;
  final int size;
  final DateTime lastModified;
}

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
        .map((file) => ScannedFile.fromMap(file! as Map<Object?, Object?>))
        .toList(growable: false);
  }
}

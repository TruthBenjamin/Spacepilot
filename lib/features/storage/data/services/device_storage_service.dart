import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/models/storage_stats.dart';

final class DeviceStorageService {
  DeviceStorageService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'ai.spacepilot.app/storage_stats';
  final MethodChannel _channel;

  Future<StorageStats> getStats() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('Device storage stats are Android-only.');
    }

    final stats = await _channel.invokeMapMethod<String, Object?>(
      'getStorageStats',
    );
    if (stats == null) {
      throw StateError('Device storage stats were unavailable.');
    }

    final reportedTotalBytes = (stats['totalBytes'] as num?)?.toInt() ?? 0;
    final totalBytes = reportedTotalBytes < 0 ? 0 : reportedTotalBytes;
    final reportedFreeBytes = (stats['freeBytes'] as num?)?.toInt() ?? 0;
    final freeBytes = reportedFreeBytes.clamp(0, totalBytes).toInt();
    final reportedUsedBytes =
        (stats['usedBytes'] as num?)?.toInt() ?? totalBytes - freeBytes;
    final usedBytes = reportedUsedBytes
        .clamp(0, totalBytes - freeBytes)
        .toInt();
    final capturedAt = (stats['capturedAt'] as num?)?.toInt();

    return StorageStats(
      totalBytes: totalBytes,
      usedBytes: usedBytes,
      freeBytes: freeBytes,
      deviceHealthScore: 0,
      lastUpdated: capturedAt == null
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(capturedAt),
    );
  }
}

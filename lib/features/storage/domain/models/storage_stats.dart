import 'package:flutter/foundation.dart';

@immutable
final class StorageStats {
  const StorageStats({
    required this.totalBytes,
    required this.usedBytes,
    required this.freeBytes,
    required this.deviceHealthScore,
    required this.lastUpdated,
  }) : assert(
         usedBytes + freeBytes <= totalBytes,
         'Used and free storage cannot exceed total storage.',
       );

  final int totalBytes;
  final int usedBytes;
  final int freeBytes;
  final int deviceHealthScore;
  final DateTime lastUpdated;

  double get usedPercent {
    if (totalBytes == 0) {
      return 0;
    }

    return usedBytes / totalBytes;
  }

  double get freePercent {
    if (totalBytes == 0) {
      return 0;
    }

    return freeBytes / totalBytes;
  }

  double get totalGigabytes => totalBytes / 1024 / 1024 / 1024;
  double get usedGigabytes => usedBytes / 1024 / 1024 / 1024;
  double get freeGigabytes => freeBytes / 1024 / 1024 / 1024;

  StorageStats copyWith({
    int? totalBytes,
    int? usedBytes,
    int? freeBytes,
    int? deviceHealthScore,
    DateTime? lastUpdated,
  }) {
    return StorageStats(
      totalBytes: totalBytes ?? this.totalBytes,
      usedBytes: usedBytes ?? this.usedBytes,
      freeBytes: freeBytes ?? this.freeBytes,
      deviceHealthScore: deviceHealthScore ?? this.deviceHealthScore,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is StorageStats &&
            other.totalBytes == totalBytes &&
            other.usedBytes == usedBytes &&
            other.freeBytes == freeBytes &&
            other.deviceHealthScore == deviceHealthScore &&
            other.lastUpdated == lastUpdated;
  }

  @override
  int get hashCode => Object.hash(
    totalBytes,
    usedBytes,
    freeBytes,
    deviceHealthScore,
    lastUpdated,
  );
}

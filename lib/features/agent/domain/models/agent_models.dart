import 'package:flutter/foundation.dart';

@immutable
final class StorageSnapshot {
  const StorageSnapshot({
    required this.capturedAt,
    required this.totalBytes,
    required this.freeBytes,
    required this.usedBytes,
  });

  factory StorageSnapshot.fromMap(Map<Object?, Object?> map) {
    final totalBytes = (map['totalBytes'] as num?)?.toInt() ?? 0;
    final freeBytes = (map['freeBytes'] as num?)?.toInt() ?? 0;
    return StorageSnapshot(
      capturedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['capturedAt'] as num?)?.toInt() ?? 0,
      ),
      totalBytes: totalBytes,
      freeBytes: freeBytes,
      usedBytes: (map['usedBytes'] as num?)?.toInt() ?? totalBytes - freeBytes,
    );
  }

  final DateTime capturedAt;
  final int totalBytes;
  final int freeBytes;
  final int usedBytes;

  double get freeRatio => totalBytes == 0 ? 0 : freeBytes / totalBytes;
}

@immutable
final class StorageGrowthTrend {
  const StorageGrowthTrend({
    required this.bytesPerDay,
    required this.sampleCount,
    required this.isGrowing,
  });

  final double bytesPerDay;
  final int sampleCount;
  final bool isGrowing;
}

@immutable
final class StorageShortagePrediction {
  const StorageShortagePrediction({
    required this.willRunShort,
    required this.daysUntilShortage,
    required this.shortageThresholdBytes,
  });

  final bool willRunShort;
  final int? daysUntilShortage;
  final int shortageThresholdBytes;
}

@immutable
final class AgentCleanupSuggestion {
  const AgentCleanupSuggestion({
    required this.title,
    required this.reason,
    required this.estimatedSavingsBytes,
    required this.priority,
  });

  final String title;
  final String reason;
  final int estimatedSavingsBytes;
  final AgentSuggestionPriority priority;
}

enum AgentSuggestionPriority {
  low,
  medium,
  high,
}

@immutable
final class AgentReport {
  const AgentReport({
    required this.generatedAt,
    required this.isLocalOnly,
    required this.latestSnapshot,
    required this.growthTrend,
    required this.shortagePrediction,
    required this.cleanupSuggestions,
  });

  final DateTime generatedAt;
  final bool isLocalOnly;
  final StorageSnapshot latestSnapshot;
  final StorageGrowthTrend growthTrend;
  final StorageShortagePrediction shortagePrediction;
  final List<AgentCleanupSuggestion> cleanupSuggestions;
}

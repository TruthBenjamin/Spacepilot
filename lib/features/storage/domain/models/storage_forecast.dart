import 'package:flutter/foundation.dart';

import 'storage_history_entry.dart';
import 'storage_intelligence_report.dart';

@immutable
final class StorageFolderGrowth {
  const StorageFolderGrowth({
    required this.path,
    required this.previousSize,
    required this.currentSize,
    required this.growthBytes,
  });

  final String path;
  final int previousSize;
  final int currentSize;
  final int growthBytes;
}

@immutable
final class StorageAppGrowth {
  const StorageAppGrowth({
    required this.appId,
    required this.label,
    required this.previousSize,
    required this.currentSize,
    required this.growthBytes,
  });

  final String appId;
  final String label;
  final int previousSize;
  final int currentSize;
  final int growthBytes;
}

@immutable
final class StorageForecast {
  const StorageForecast({
    required this.daysUntilFull,
    required this.weeklyGrowthBytes,
    required this.largestGrowingFolders,
    required this.largestGrowingApps,
    required this.recommendations,
  });

  final double? daysUntilFull;
  final int weeklyGrowthBytes;
  final List<StorageFolderGrowth> largestGrowingFolders;
  final List<StorageAppGrowth> largestGrowingApps;
  final List<String> recommendations;
}

@immutable
final class StorageForecastSnapshot {
  const StorageForecastSnapshot({
    required this.history,
    required this.currentReport,
  });

  final List<StorageHistoryEntry> history;
  final StorageIntelligenceReport currentReport;
}

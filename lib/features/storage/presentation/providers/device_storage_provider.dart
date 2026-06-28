import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../analytics/presentation/providers/analytics_provider.dart';
import '../../../device_health/data/services/device_health_calculator.dart';
import '../../data/services/device_storage_service.dart';
import '../../domain/models/storage_stats.dart';

final deviceStorageServiceProvider = Provider<DeviceStorageService>((ref) {
  return DeviceStorageService();
});

final deviceStorageStatsProvider = FutureProvider<StorageStats>((ref) async {
  return ref.read(deviceStorageServiceProvider).getStats();
});

final deviceHealthScoreProvider = FutureProvider<int>((ref) async {
  final stats = await ref.watch(deviceStorageStatsProvider.future);
  final analytics = await ref.watch(storageAnalyticsProvider.future);

  return const DeviceHealthCalculator().calculateScore(
    totalBytes: stats.totalBytes,
    freeBytes: stats.freeBytes,
    duplicateCount: analytics.duplicateGroups,
    junkFileCount: analytics.junkFileCount,
    unusedFileCount: analytics.unusedFileCount,
  );
});

final deviceStorageStatsWithHealthProvider = FutureProvider<StorageStats>((
  ref,
) async {
  final stats = await ref.watch(deviceStorageStatsProvider.future);
  final score = await ref.watch(deviceHealthScoreProvider.future);
  return stats.copyWith(deviceHealthScore: score);
});

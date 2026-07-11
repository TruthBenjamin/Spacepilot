import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../analytics/presentation/providers/analytics_provider.dart';
import '../../../auto_clean/presentation/providers/auto_clean_provider.dart';
import '../../../device_health/presentation/providers/device_health_provider.dart';
import '../../../duplicates/presentation/providers/duplicate_groups_provider.dart';
import '../../../large_files/presentation/providers/large_file_hunter_provider.dart';
import '../../../recommendations/presentation/providers/recommendations_provider.dart';
import '../../../storage/presentation/providers/device_storage_provider.dart';
import '../../../storage/presentation/providers/storage_history_provider.dart';
import '../../../storage/presentation/providers/storage_scan_provider.dart';
import '../../../storage/domain/models/storage_history_entry.dart';
import 'cleanup_center_provider.dart';

final deletionSyncProvider = Provider<DeletionSync>((ref) {
  return DeletionSync(ref);
});

final class DeletionSync {
  const DeletionSync(this._ref);

  final Ref _ref;

  void applyDeletedPaths(Iterable<String> paths) {
    final deletedPaths = paths.toSet();
    if (deletedPaths.isEmpty) return;

    final currentFiles =
        _ref.read(storageScanProvider).value?.files ?? const [];
    final normalizedPaths = deletedPaths.map(_normalizePath).toSet();
    final removedBytes = currentFiles
        .where((file) => normalizedPaths.contains(_normalizePath(file.path)))
        .fold<int>(0, (total, file) => total + file.size);
    _ref.read(storageScanProvider.notifier).removeDeletedPaths(deletedPaths);
    final updatedReport = _ref
        .read(storageScanProvider)
        .value
        ?.intelligenceReport;
    if (updatedReport != null) {
      unawaited(
        _ref
            .read(storageHistoryServiceProvider)
            .appendEntry(
              StorageHistoryEntry.fromReport(
                updatedReport,
                eventType: StorageHistoryEventType.cleanup,
                affectedBytes: removedBytes,
                timestamp: DateTime.now(),
              ),
            )
            .then((_) => _ref.invalidate(storageHistoryProvider)),
      );
    }
    refreshDerivedState();
  }

  void refreshDerivedState() {
    _ref
      ..invalidate(cleanupCenterReportProvider)
      ..invalidate(duplicateGroupsProvider)
      ..invalidate(similarImageGroupsProvider)
      ..invalidate(deviceStorageStatsProvider)
      ..invalidate(deviceStorageStatsWithHealthProvider)
      ..invalidate(deviceHealthScoreProvider)
      ..invalidate(deviceHealthReportProvider)
      ..invalidate(storageAnalyticsProvider)
      ..invalidate(recommendationsProvider)
      ..invalidate(largeFileHunterProvider)
      ..invalidate(pagedLargeFileHunterProvider)
      ..invalidate(autoCleanPlanProvider)
      ..invalidate(automationPlanProvider)
      ..invalidate(storageHistoryProvider);
  }
}

String _normalizePath(String path) => path.replaceAll('\\', '/');

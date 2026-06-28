import '../../../analytics/domain/models/storage_analytics.dart';
import '../../../auto_clean/domain/models/auto_clean_rules.dart';
import '../../domain/models/agent_models.dart';

final class AgentEngine {
  const AgentEngine();

  AgentReport generateReport({
    required List<StorageSnapshot> snapshots,
    required StorageAnalytics analytics,
    required AutoCleanPlan autoCleanPlan,
    DateTime? now,
  }) {
    final generatedAt = now ?? DateTime.now();
    final sortedSnapshots = [...snapshots]
      ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    final latestSnapshot = sortedSnapshots.isEmpty
        ? StorageSnapshot(
            capturedAt: generatedAt,
            totalBytes: analytics.totalBytes,
            freeBytes: 0,
            usedBytes: analytics.totalBytes,
          )
        : sortedSnapshots.last;
    final trend = detectGrowthTrend(sortedSnapshots);
    final prediction = predictStorageShortage(latestSnapshot, trend);
    final suggestions = generateCleanupSuggestions(
      analytics: analytics,
      autoCleanPlan: autoCleanPlan,
      prediction: prediction,
    );

    return AgentReport(
      generatedAt: generatedAt,
      isLocalOnly: true,
      latestSnapshot: latestSnapshot,
      growthTrend: trend,
      shortagePrediction: prediction,
      cleanupSuggestions: suggestions,
    );
  }

  StorageGrowthTrend detectGrowthTrend(List<StorageSnapshot> snapshots) {
    if (snapshots.length < 2) {
      return const StorageGrowthTrend(
        bytesPerDay: 0,
        sampleCount: 0,
        isGrowing: false,
      );
    }

    final first = snapshots.first;
    final last = snapshots.last;
    final elapsedHours = last.capturedAt.difference(first.capturedAt).inHours;
    if (elapsedHours <= 0) {
      return StorageGrowthTrend(
        bytesPerDay: 0,
        sampleCount: snapshots.length,
        isGrowing: false,
      );
    }

    final growthBytes = last.usedBytes - first.usedBytes;
    final bytesPerDay = growthBytes / (elapsedHours / 24);

    return StorageGrowthTrend(
      bytesPerDay: bytesPerDay,
      sampleCount: snapshots.length,
      isGrowing: bytesPerDay > 0,
    );
  }

  StorageShortagePrediction predictStorageShortage(
    StorageSnapshot snapshot,
    StorageGrowthTrend trend,
  ) {
    final thresholdBytes = (snapshot.totalBytes * 0.10).round();
    if (!trend.isGrowing || snapshot.freeBytes <= 0) {
      return StorageShortagePrediction(
        willRunShort: snapshot.freeBytes <= thresholdBytes,
        daysUntilShortage: snapshot.freeBytes <= thresholdBytes ? 0 : null,
        shortageThresholdBytes: thresholdBytes,
      );
    }

    final usableBytes = snapshot.freeBytes - thresholdBytes;
    if (usableBytes <= 0) {
      return StorageShortagePrediction(
        willRunShort: true,
        daysUntilShortage: 0,
        shortageThresholdBytes: thresholdBytes,
      );
    }

    final days = (usableBytes / trend.bytesPerDay).ceil();
    return StorageShortagePrediction(
      willRunShort: days <= 30,
      daysUntilShortage: days,
      shortageThresholdBytes: thresholdBytes,
    );
  }

  List<AgentCleanupSuggestion> generateCleanupSuggestions({
    required StorageAnalytics analytics,
    required AutoCleanPlan autoCleanPlan,
    required StorageShortagePrediction prediction,
  }) {
    final suggestions = <AgentCleanupSuggestion>[
      if (analytics.duplicateBytes > 0)
        AgentCleanupSuggestion(
          title: 'Review duplicate copies',
          reason: '${analytics.duplicateGroups} duplicate groups found locally',
          estimatedSavingsBytes: analytics.duplicateBytes,
          priority: AgentSuggestionPriority.high,
        ),
      if (autoCleanPlan.estimatedSavingsBytes > 0)
        AgentCleanupSuggestion(
          title: 'Apply auto-clean review rules',
          reason: '${autoCleanPlan.fileCount} files match your local rules',
          estimatedSavingsBytes: autoCleanPlan.estimatedSavingsBytes,
          priority: prediction.willRunShort
              ? AgentSuggestionPriority.high
              : AgentSuggestionPriority.medium,
        ),
      if (analytics.junkBytes > 0)
        AgentCleanupSuggestion(
          title: 'Clear junk files',
          reason: '${analytics.junkFileCount} cache, temp, or log files found',
          estimatedSavingsBytes: analytics.junkBytes,
          priority: AgentSuggestionPriority.medium,
        ),
      if (analytics.unusedBytes > 0)
        AgentCleanupSuggestion(
          title: 'Review old unused files',
          reason: '${analytics.unusedFileCount} files are older than 180 days',
          estimatedSavingsBytes: analytics.unusedBytes,
          priority: AgentSuggestionPriority.low,
        ),
    ]..sort((a, b) {
        final priority = b.priority.index.compareTo(a.priority.index);
        if (priority != 0) return priority;
        return b.estimatedSavingsBytes.compareTo(a.estimatedSavingsBytes);
      });

    return suggestions;
  }
}

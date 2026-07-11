import '../../domain/models/device_health_report.dart';
import '../../../analytics/domain/models/storage_analytics.dart';
import '../../../storage/domain/models/storage_stats.dart';

final class DeviceHealthEngine {
  const DeviceHealthEngine();

  DeviceHealthReport evaluate({
    required StorageStats stats,
    required StorageAnalytics analytics,
    required int emptyFolderCount,
    required int oldDownloadCount,
    required int unusedAppCount,
    int? thermalStatus,
    int? batteryLevel,
    bool scheduledScanningEnabled = false,
  }) {
    final breakdown = _calculateBreakdown(
      totalBytes: stats.totalBytes,
      freeBytes: stats.freeBytes,
      duplicateCount: analytics.duplicateGroups,
      junkFileCount: analytics.junkFileCount,
      unusedFileCount: analytics.unusedFileCount,
      unusedAppCount: unusedAppCount,
      oldDownloadCount: oldDownloadCount,
      emptyFolderCount: emptyFolderCount,
      thermalStatus: thermalStatus,
      batteryLevel: batteryLevel,
      scheduledScanningEnabled: scheduledScanningEnabled,
    );
    final score = (100 - breakdown.totalPenalty).clamp(0, 100);

    final category = _categoryForScore(score);
    final suggestions = _buildSuggestions(
      stats: stats,
      analytics: analytics,
      oldDownloadCount: oldDownloadCount,
      unusedAppCount: unusedAppCount,
      emptyFolderCount: emptyFolderCount,
      thermalStatus: thermalStatus,
      batteryLevel: batteryLevel,
      scheduledScanningEnabled: scheduledScanningEnabled,
    );
    final explanation = _buildExplanation(
      score: score,
      stats: stats,
      analytics: analytics,
      breakdown: breakdown,
      oldDownloadCount: oldDownloadCount,
      unusedAppCount: unusedAppCount,
      emptyFolderCount: emptyFolderCount,
    );

    return DeviceHealthReport(
      score: score,
      category: category,
      breakdown: breakdown,
      suggestions: suggestions,
      explanation: explanation,
    );
  }

  DeviceHealthScoreBreakdown _calculateBreakdown({
    required int totalBytes,
    required int freeBytes,
    required int duplicateCount,
    required int junkFileCount,
    required int unusedFileCount,
    required int unusedAppCount,
    required int oldDownloadCount,
    required int emptyFolderCount,
    int? thermalStatus,
    int? batteryLevel,
    required bool scheduledScanningEnabled,
  }) {
    final normalizedTotal = totalBytes < 0 ? 0 : totalBytes;
    final normalizedFree = freeBytes.clamp(0, normalizedTotal).toInt();
    final freeRatio = normalizedTotal == 0
        ? 0.0
        : normalizedFree / normalizedTotal;

    return DeviceHealthScoreBreakdown(
      storageUsagePenalty: _storageUsagePenalty(freeRatio).round(),
      duplicateFilesPenalty: _duplicatePenalty(duplicateCount),
      unusedAppsPenalty: _unusedAppsPenalty(unusedAppCount),
      junkFilesPenalty: _junkPenalty(junkFileCount, unusedFileCount),
      oldDownloadsPenalty: _oldDownloadsPenalty(oldDownloadCount),
      emptyFoldersPenalty: _emptyFolderPenalty(emptyFolderCount),
      thermalPenalty: thermalStatus == null
          ? 0
          : thermalStatus >= 5
          ? 10
          : thermalStatus >= 3
          ? 5
          : 0,
      powerConfigurationPenalty:
          batteryLevel != null && batteryLevel <= 20 && scheduledScanningEnabled
          ? 3
          : 0,
    );
  }

  double _storageUsagePenalty(double freeRatio) {
    const healthy = 0.30;
    const critical = 0.08;
    const maxPenalty = 40.0;

    if (freeRatio >= healthy) return 0;
    if (freeRatio <= critical) return maxPenalty;

    final pressure = (healthy - freeRatio) / (healthy - critical);
    return pressure * maxPenalty;
  }

  int _duplicatePenalty(int duplicateCount) {
    final normalized = duplicateCount < 0 ? 0 : duplicateCount;
    return (normalized * 2).clamp(0, 18).toInt();
  }

  int _unusedAppsPenalty(int unusedAppCount) {
    final normalized = unusedAppCount < 0 ? 0 : unusedAppCount;
    return (normalized * 3).clamp(0, 14).toInt();
  }

  int _junkPenalty(int junkFileCount, int unusedFileCount) {
    final junk = junkFileCount < 0 ? 0 : junkFileCount;
    final staleFiles = unusedFileCount < 0 ? 0 : unusedFileCount;
    return (junk + staleFiles ~/ 4).clamp(0, 14).toInt();
  }

  int _oldDownloadsPenalty(int oldDownloadCount) {
    final normalized = oldDownloadCount < 0 ? 0 : oldDownloadCount;
    return (normalized).clamp(0, 9).toInt();
  }

  int _emptyFolderPenalty(int emptyFolderCount) {
    final normalized = emptyFolderCount < 0 ? 0 : emptyFolderCount;
    return (normalized / 4).clamp(0, 5).toInt();
  }

  DeviceHealthCategory _categoryForScore(int score) {
    if (score >= 85) return DeviceHealthCategory.excellent;
    if (score >= 70) return DeviceHealthCategory.good;
    if (score >= 50) return DeviceHealthCategory.fair;
    return DeviceHealthCategory.poor;
  }

  List<String> _buildSuggestions({
    required StorageStats stats,
    required StorageAnalytics analytics,
    required int oldDownloadCount,
    required int unusedAppCount,
    required int emptyFolderCount,
    int? thermalStatus,
    int? batteryLevel,
    required bool scheduledScanningEnabled,
  }) {
    final suggestions = <String>[];

    if (stats.freePercent < 0.15) {
      suggestions.add(
        'Free up space by deleting old downloads and large unused files.',
      );
    }
    if (analytics.duplicateGroups > 0) {
      suggestions.add(
        'Review duplicate files and remove copies to recover storage.',
      );
    }
    if (analytics.junkFileCount > 0) {
      suggestions.add(
        'Clear junk files such as cache, logs, and temporary files.',
      );
    }
    if (analytics.unusedFileCount > 0) {
      suggestions.add(
        'Remove old files that have not been modified in over 180 days.',
      );
    }
    if (oldDownloadCount > 0) {
      suggestions.add('Clean downloads that have not changed in over 90 days.');
    }
    if (unusedAppCount > 0) {
      suggestions.add('Uninstall apps you have not opened recently.');
    }
    if (emptyFolderCount > 0) {
      suggestions.add(
        'Remove empty folders left behind by old apps and downloads.',
      );
    }
    if (thermalStatus != null && thermalStatus >= 3) {
      suggestions.add(
        'Pause intensive work while Android reports high thermal pressure.',
      );
    }
    if (batteryLevel != null &&
        batteryLevel <= 20 &&
        scheduledScanningEnabled) {
      suggestions.add(
        'Postpone scheduled scans until charging or battery conditions improve.',
      );
    }
    if (suggestions.isEmpty) {
      suggestions.add(
        'Your device health looks good. Keep monitoring storage growth and clean regularly.',
      );
    }

    return suggestions;
  }

  String _buildExplanation({
    required int score,
    required StorageStats stats,
    required StorageAnalytics analytics,
    required DeviceHealthScoreBreakdown breakdown,
    required int oldDownloadCount,
    required int unusedAppCount,
    required int emptyFolderCount,
  }) {
    final freePercent = (stats.freePercent * 100).toStringAsFixed(1);
    return 'Score starts at 100 and subtracts ${breakdown.totalPenalty} points: '
        '${breakdown.storageUsagePenalty} for storage usage ($freePercent% free), '
        '${breakdown.duplicateFilesPenalty} for ${analytics.duplicateGroups} duplicate groups, '
        '${breakdown.unusedAppsPenalty} for $unusedAppCount unused apps, '
        '${breakdown.junkFilesPenalty} for ${analytics.junkFileCount} junk files and ${analytics.unusedFileCount} stale files, '
        '${breakdown.oldDownloadsPenalty} for $oldDownloadCount old downloads, and '
        '${breakdown.emptyFoldersPenalty} for $emptyFolderCount empty folders. '
        '${breakdown.thermalPenalty} for reported thermal pressure and '
        '${breakdown.powerConfigurationPenalty} for scheduled scans during low battery. '
        'Final score: $score/100.';
  }
}

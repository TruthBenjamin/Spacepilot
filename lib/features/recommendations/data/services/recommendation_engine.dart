import '../../../duplicates/domain/models/duplicate_group.dart';
import '../../../duplicates/domain/models/similar_image_group.dart';
import '../../../storage/domain/models/scanned_file.dart';
import '../../../storage/domain/models/storage_stats.dart';
import '../../domain/models/storage_recommendation.dart';

final class RecommendationEngine {
  const RecommendationEngine();

  List<StorageRecommendation> buildRecommendations({
    required Iterable<ScannedFile> files,
    required Iterable<DuplicateGroup> duplicateGroups,
    Iterable<SimilarImageGroup> similarImageGroups = const [],
    Iterable<String> emptyFolderPaths = const [],
    StorageStats? storageStats,
    DateTime? now,
  }) {
    final referenceDate = now ?? DateTime.now();
    final screenshotsBefore = referenceDate.subtract(const Duration(days: 90));
    final unusedBefore = referenceDate.subtract(const Duration(days: 180));
    final oldApkBefore = referenceDate.subtract(const Duration(days: 30));

    var oldScreenshotBytes = 0;
    var unusedFileBytes = 0;
    var apkBytes = 0;
    var downloadBytes = 0;

    for (final file in files) {
      final isScreenshot = _isScreenshot(file);
      final isApk = _isApk(file);
      final isDownload = _isDownload(file);

      if (isDownload) {
        downloadBytes += file.size;
      }

      if (isScreenshot && file.lastModified.isBefore(screenshotsBefore)) {
        oldScreenshotBytes += file.size;
      }

      if (isApk && file.lastModified.isBefore(oldApkBefore)) {
        apkBytes += file.size;
      }

      if (!isScreenshot && !isApk && file.lastModified.isBefore(unusedBefore)) {
        unusedFileBytes += file.size;
      }
    }

    final duplicateBytes = duplicateGroups.fold<int>(
      0,
      (total, group) => total + group.recoverableBytes,
    );
    final similarImageBytes = similarImageGroups.fold<int>(
      0,
      (total, group) => total + group.recoverableBytes,
    );
    final duplicateMediaBytes = duplicateBytes + similarImageBytes;
    final lowStorageTargetBytes = _lowStorageTargetBytes(storageStats);

    final recommendations =
        <StorageRecommendation>[
          if (lowStorageTargetBytes > 0)
            StorageRecommendation(
              type: StorageRecommendationType.lowStorage,
              title: 'Storage below 15%',
              description:
                  'Free space is under the healthy threshold. Start with the largest safe cleanup opportunities.',
              storageSavingsBytes: lowStorageTargetBytes,
              priority: RecommendationPriority.critical,
              riskLevel: RecommendationRiskLevel.low,
              action: RecommendationAction.scan,
              actionTarget: RecommendationActionTarget.scanResults,
            ),
          if (downloadBytes > _threeGigabytes)
            StorageRecommendation(
              type: StorageRecommendationType.largeDownloads,
              title: 'Downloads exceed 3 GB',
              description:
                  'Downloads are using ${_formatBytes(downloadBytes)}. Review installers, archives, and temporary files first.',
              storageSavingsBytes: downloadBytes,
              priority: RecommendationPriority.high,
              riskLevel: RecommendationRiskLevel.medium,
              action: RecommendationAction.reviewDownloads,
              actionTarget: RecommendationActionTarget.scanResults,
            ),
          if (oldScreenshotBytes > 0)
            StorageRecommendation(
              type: StorageRecommendationType.oldScreenshots,
              title: 'Review screenshots older than 90 days',
              description:
                  'Old screenshots are often safe to remove after you confirm they are no longer needed.',
              storageSavingsBytes: oldScreenshotBytes,
              priority: RecommendationPriority.low,
              riskLevel: RecommendationRiskLevel.low,
              action: RecommendationAction.review,
              actionTarget: RecommendationActionTarget.scanResults,
            ),
          if (unusedFileBytes > 0)
            StorageRecommendation(
              type: StorageRecommendationType.unusedFiles,
              title: 'Review unused files older than 180 days',
              description:
                  'These files have not changed recently. Review them before deleting anything important.',
              storageSavingsBytes: unusedFileBytes,
              priority: RecommendationPriority.medium,
              riskLevel: RecommendationRiskLevel.medium,
              action: RecommendationAction.review,
              actionTarget: RecommendationActionTarget.scanResults,
            ),
          if (duplicateMediaBytes > 0)
            StorageRecommendation(
              type: StorageRecommendationType.duplicateMedia,
              title: 'Remove duplicate media',
              description: _duplicateMediaDescription(
                exactDuplicateBytes: duplicateBytes,
                similarImageGroups: similarImageGroups,
              ),
              storageSavingsBytes: duplicateMediaBytes,
              priority: RecommendationPriority.high,
              riskLevel: RecommendationRiskLevel.low,
              action: RecommendationAction.reviewDuplicates,
              actionTarget: RecommendationActionTarget.duplicates,
            ),
          if (apkBytes > 0)
            StorageRecommendation(
              type: StorageRecommendationType.apkInstallers,
              title: 'Delete APK installers after installation',
              description:
                  'Downloaded APK installers are often no longer needed after the app is installed.',
              storageSavingsBytes: apkBytes,
              priority: RecommendationPriority.medium,
              riskLevel: RecommendationRiskLevel.medium,
              action: RecommendationAction.review,
              actionTarget: RecommendationActionTarget.scanResults,
            ),
          if (emptyFolderPaths.isNotEmpty)
            StorageRecommendation(
              type: StorageRecommendationType.emptyFolders,
              title: 'Remove empty folders',
              description:
                  'Empty folders from scanned storage can be removed after you confirm they are not used by an app workflow.',
              storageSavingsBytes: 0,
              priority: RecommendationPriority.low,
              riskLevel: RecommendationRiskLevel.low,
              action: RecommendationAction.reviewFolders,
              actionTarget: RecommendationActionTarget.scanResults,
            ),
        ]..sort((a, b) {
          final impact = b.storageSavingsBytes.compareTo(a.storageSavingsBytes);
          if (impact != 0) return impact;
          return b.priority.index.compareTo(a.priority.index);
        });

    return recommendations;
  }

  int _lowStorageTargetBytes(StorageStats? storageStats) {
    if (storageStats == null || storageStats.totalBytes <= 0) return 0;
    if (storageStats.freePercent >= 0.15) return 0;

    final healthyFreeBytes = (storageStats.totalBytes * 0.15).ceil();
    return healthyFreeBytes - storageStats.freeBytes;
  }

  String _duplicateMediaDescription({
    required int exactDuplicateBytes,
    required Iterable<SimilarImageGroup> similarImageGroups,
  }) {
    final similarGroups = similarImageGroups.toList(growable: false);
    if (similarGroups.isEmpty) {
      return 'Exact duplicate files were found locally. Keep one copy from each group.';
    }

    final bestScore = similarGroups
        .map((group) => group.strongestSimilarityScore)
        .reduce((a, b) => a > b ? a : b);
    final exactText = exactDuplicateBytes > 0
        ? '${_formatBytes(exactDuplicateBytes)} in exact duplicates plus '
        : '';
    return '${exactText}visually similar photos were found using perceptual hashing. Best similarity: ${bestScore.toStringAsFixed(0)}%.';
  }

  bool _isScreenshot(ScannedFile file) {
    final name = file.filename.toLowerCase();
    final path = file.path.toLowerCase().replaceAll('\\', '/');

    return name.contains('screenshot') ||
        path.contains('/screenshots/') ||
        path.endsWith('/screenshots/${name.toLowerCase()}');
  }

  bool _isApk(ScannedFile file) {
    return file.filename.toLowerCase().endsWith('.apk') ||
        file.path.toLowerCase().endsWith('.apk');
  }

  bool _isDownload(ScannedFile file) {
    final normalizedPath = file.path.toLowerCase().replaceAll('\\', '/');
    return normalizedPath.contains('/download/') ||
        normalizedPath.contains('/downloads/');
  }

  List<StorageRecommendation> buildDeviceCareRecommendations({
    int? thermalStatus,
    required bool scanActive,
    int? batteryLevel,
    required bool scheduledScanning,
    required int cleanupBytes,
  }) {
    return [
      if (thermalStatus != null && thermalStatus >= 1 && scanActive)
        const StorageRecommendation(
          type: StorageRecommendationType.thermalPressure,
          title: 'Pause Deep Scan',
          description:
              'Your device reports elevated thermal conditions while SpacePilot is performing intensive storage analysis.',
          storageSavingsBytes: 0,
          priority: RecommendationPriority.high,
          riskLevel: RecommendationRiskLevel.low,
          action: RecommendationAction.pauseAndReview,
          actionTarget: RecommendationActionTarget.cooling,
        ),
      if (batteryLevel != null && batteryLevel <= 20 && scheduledScanning)
        const StorageRecommendation(
          type: StorageRecommendationType.lowBatteryScan,
          title: 'Postpone Background Scan',
          description:
              'Your battery is low. Delaying non-essential scans can reduce SpacePilot power usage.',
          storageSavingsBytes: 0,
          priority: RecommendationPriority.high,
          riskLevel: RecommendationRiskLevel.low,
          action: RecommendationAction.openAdvisor,
          actionTarget: RecommendationActionTarget.battery,
        ),
      if (cleanupBytes > 0)
        StorageRecommendation(
          type: StorageRecommendationType.cleanupOpportunity,
          title: 'Review Cleanup Opportunities',
          description:
              'SpacePilot found ${_formatBytes(cleanupBytes)} of accessible files that may no longer be needed.',
          storageSavingsBytes: cleanupBytes,
          priority: RecommendationPriority.medium,
          riskLevel: RecommendationRiskLevel.medium,
          action: RecommendationAction.review,
          actionTarget: RecommendationActionTarget.junkCleaner,
        ),
    ];
  }
}

String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;

  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }

  final decimals = unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(decimals)} ${units[unit]}';
}

const _threeGigabytes = 3 * 1024 * 1024 * 1024;

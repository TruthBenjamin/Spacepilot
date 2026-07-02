import '../../../duplicates/domain/models/duplicate_group.dart';
import '../../../storage/domain/models/scanned_file.dart';
import '../../domain/models/storage_recommendation.dart';

final class RecommendationEngine {
  const RecommendationEngine();

  List<StorageRecommendation> buildRecommendations({
    required Iterable<ScannedFile> files,
    required Iterable<DuplicateGroup> duplicateGroups,
    DateTime? now,
  }) {
    final referenceDate = now ?? DateTime.now();
    final screenshotsBefore = referenceDate.subtract(const Duration(days: 90));
    final unusedBefore = referenceDate.subtract(const Duration(days: 180));

    var oldScreenshotBytes = 0;
    var unusedFileBytes = 0;
    var apkBytes = 0;

    for (final file in files) {
      final isScreenshot = _isScreenshot(file);
      final isApk = _isApk(file);

      if (isScreenshot && file.lastModified.isBefore(screenshotsBefore)) {
        oldScreenshotBytes += file.size;
      }

      if (isApk) {
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

    final recommendations = <StorageRecommendation>[
      if (oldScreenshotBytes > 0)
        StorageRecommendation(
          type: StorageRecommendationType.oldScreenshots,
          title: 'Review screenshots older than 90 days',
          storageSavingsBytes: oldScreenshotBytes,
          actionLabel: 'Review',
          actionTarget: RecommendationActionTarget.scanResults,
        ),
      if (unusedFileBytes > 0)
        StorageRecommendation(
          type: StorageRecommendationType.unusedFiles,
          title: 'Review unused files older than 180 days',
          storageSavingsBytes: unusedFileBytes,
          actionLabel: 'Review',
          actionTarget: RecommendationActionTarget.scanResults,
        ),
      if (duplicateBytes > 0)
        StorageRecommendation(
          type: StorageRecommendationType.duplicateFiles,
          title: 'Remove duplicate files',
          storageSavingsBytes: duplicateBytes,
          actionLabel: 'Review duplicates',
          actionTarget: RecommendationActionTarget.duplicates,
        ),
      if (apkBytes > 0)
        StorageRecommendation(
          type: StorageRecommendationType.apkInstallers,
          title: 'Delete APK installers after installation',
          storageSavingsBytes: apkBytes,
          actionLabel: 'Review',
          actionTarget: RecommendationActionTarget.scanResults,
        ),
    ]..sort((a, b) => b.storageSavingsBytes.compareTo(a.storageSavingsBytes));

    return recommendations;
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
}

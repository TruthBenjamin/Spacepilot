import '../../../duplicates/domain/models/duplicate_group.dart';
import '../../../storage/domain/models/scanned_file.dart';
import '../../domain/models/auto_clean_rules.dart';

final class AutoCleanRuleEngine {
  const AutoCleanRuleEngine();

  AutoCleanPlan buildPlan({
    required AutoCleanRules rules,
    required Iterable<ScannedFile> files,
    required Iterable<DuplicateGroup> duplicateGroups,
    DateTime? now,
  }) {
    if (!rules.enabled) {
      return const AutoCleanPlan(
        ruleCount: 0,
        fileCount: 0,
        estimatedSavingsBytes: 0,
      );
    }

    final referenceDate = now ?? DateTime.now();
    final unusedBefore = referenceDate.subtract(
      Duration(days: rules.unusedFileAgeDays),
    );
    final screenshotsBefore = referenceDate.subtract(
      Duration(days: rules.screenshotAgeDays),
    );

    var ruleCount = 0;
    var fileCount = 0;
    var estimatedSavingsBytes = 0;

    if (rules.includeDuplicateCopies) {
      ruleCount++;
      for (final group in duplicateGroups) {
        fileCount += group.files.length - 1;
        estimatedSavingsBytes += group.recoverableBytes;
      }
    }

    for (final file in files) {
      final isApk = _isApk(file);
      final isScreenshot = _isScreenshot(file);

      if (rules.includeApkInstallers && isApk) {
        estimatedSavingsBytes += file.size;
        fileCount++;
        continue;
      }

      if (rules.includeOldScreenshots &&
          isScreenshot &&
          file.lastModified.isBefore(screenshotsBefore)) {
        estimatedSavingsBytes += file.size;
        fileCount++;
        continue;
      }

      if (rules.includeUnusedFiles &&
          !isApk &&
          !isScreenshot &&
          file.lastModified.isBefore(unusedBefore)) {
        estimatedSavingsBytes += file.size;
        fileCount++;
      }
    }

    if (rules.includeApkInstallers) ruleCount++;
    if (rules.includeOldScreenshots) ruleCount++;
    if (rules.includeUnusedFiles) ruleCount++;
    if (rules.includeEmptyFolders) ruleCount++;

    return AutoCleanPlan(
      ruleCount: ruleCount,
      fileCount: fileCount,
      estimatedSavingsBytes: estimatedSavingsBytes,
    );
  }

  bool _isApk(ScannedFile file) {
    return file.filename.toLowerCase().endsWith('.apk') ||
        file.path.toLowerCase().endsWith('.apk');
  }

  bool _isScreenshot(ScannedFile file) {
    final name = file.filename.toLowerCase();
    final path = file.path.toLowerCase().replaceAll('\\', '/');

    return name.contains('screenshot') || path.contains('/screenshots/');
  }
}

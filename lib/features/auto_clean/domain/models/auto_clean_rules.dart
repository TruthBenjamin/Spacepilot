import 'package:flutter/foundation.dart';

@immutable
final class AutoCleanRules {
  const AutoCleanRules({
    required this.enabled,
    required this.includeDuplicateCopies,
    required this.includeApkInstallers,
    required this.includeOldScreenshots,
    required this.includeUnusedFiles,
    required this.includeEmptyFolders,
    required this.unusedFileAgeDays,
    required this.screenshotAgeDays,
  });

  const AutoCleanRules.defaults()
    : enabled = false,
      includeDuplicateCopies = true,
      includeApkInstallers = true,
      includeOldScreenshots = true,
      includeUnusedFiles = false,
      includeEmptyFolders = true,
      unusedFileAgeDays = 180,
      screenshotAgeDays = 90;

  final bool enabled;
  final bool includeDuplicateCopies;
  final bool includeApkInstallers;
  final bool includeOldScreenshots;
  final bool includeUnusedFiles;
  final bool includeEmptyFolders;
  final int unusedFileAgeDays;
  final int screenshotAgeDays;

  AutoCleanRules copyWith({
    bool? enabled,
    bool? includeDuplicateCopies,
    bool? includeApkInstallers,
    bool? includeOldScreenshots,
    bool? includeUnusedFiles,
    bool? includeEmptyFolders,
    int? unusedFileAgeDays,
    int? screenshotAgeDays,
  }) {
    return AutoCleanRules(
      enabled: enabled ?? this.enabled,
      includeDuplicateCopies:
          includeDuplicateCopies ?? this.includeDuplicateCopies,
      includeApkInstallers: includeApkInstallers ?? this.includeApkInstallers,
      includeOldScreenshots:
          includeOldScreenshots ?? this.includeOldScreenshots,
      includeUnusedFiles: includeUnusedFiles ?? this.includeUnusedFiles,
      includeEmptyFolders: includeEmptyFolders ?? this.includeEmptyFolders,
      unusedFileAgeDays: unusedFileAgeDays ?? this.unusedFileAgeDays,
      screenshotAgeDays: screenshotAgeDays ?? this.screenshotAgeDays,
    );
  }
}

@immutable
final class AutoCleanPlan {
  const AutoCleanPlan({
    required this.ruleCount,
    required this.fileCount,
    required this.estimatedSavingsBytes,
  });

  final int ruleCount;
  final int fileCount;
  final int estimatedSavingsBytes;
}

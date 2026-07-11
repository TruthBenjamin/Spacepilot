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

  Map<String, Object> toJson() => {
    'enabled': enabled,
    'includeDuplicateCopies': includeDuplicateCopies,
    'includeApkInstallers': includeApkInstallers,
    'includeOldScreenshots': includeOldScreenshots,
    'includeUnusedFiles': includeUnusedFiles,
    'includeEmptyFolders': includeEmptyFolders,
    'unusedFileAgeDays': unusedFileAgeDays,
    'screenshotAgeDays': screenshotAgeDays,
  };

  static AutoCleanRules fromJson(Object? value) {
    if (value is! Map<String, Object?>) return const AutoCleanRules.defaults();
    return AutoCleanRules(
      enabled: value['enabled'] == true,
      includeDuplicateCopies: value['includeDuplicateCopies'] != false,
      includeApkInstallers: value['includeApkInstallers'] != false,
      includeOldScreenshots: value['includeOldScreenshots'] != false,
      includeUnusedFiles: value['includeUnusedFiles'] == true,
      includeEmptyFolders: value['includeEmptyFolders'] != false,
      unusedFileAgeDays: value['unusedFileAgeDays'] is num
          ? (value['unusedFileAgeDays'] as num).round().clamp(30, 730)
          : 180,
      screenshotAgeDays: value['screenshotAgeDays'] is num
          ? (value['screenshotAgeDays'] as num).round().clamp(7, 365)
          : 90,
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

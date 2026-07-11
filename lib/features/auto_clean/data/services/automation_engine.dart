import '../../../storage/domain/models/scanned_file.dart';
import '../../domain/models/automation_rule.dart';

final class AutomationEngine {
  const AutomationEngine();

  List<AutomationRule> defaultRules({DateTime? now}) {
    final createdAt = now ?? DateTime.now();
    return [
      AutomationRule.deleteScreenshotsAfter(
        id: 'delete_screenshots_90_days',
        days: 90,
        enabled: false,
        createdAt: createdAt,
      ),
      AutomationRule.deleteApkInstallers(
        id: 'delete_apk_installers',
        enabled: false,
        createdAt: createdAt,
      ),
      AutomationRule.weeklyScan(
        id: 'weekly_scan',
        enabled: false,
        createdAt: createdAt,
      ),
      AutomationRule.monthlyReport(
        id: 'monthly_report',
        enabled: false,
        createdAt: createdAt,
      ),
      AutomationRule.storageWarning(
        id: 'storage_warning_10_percent',
        freePercent: 10,
        enabled: false,
        createdAt: createdAt,
      ),
    ];
  }

  AutomationRule createRule({
    required AutomationRuleType type,
    required String id,
    int? ageThresholdDays,
    int? storageWarningFreePercent,
    bool enabled = true,
    DateTime? now,
  }) {
    final createdAt = now ?? DateTime.now();
    return switch (type) {
      AutomationRuleType.deleteScreenshots =>
        AutomationRule.deleteScreenshotsAfter(
          id: id,
          days: _positiveOrDefault(ageThresholdDays, 90),
          enabled: enabled,
          createdAt: createdAt,
        ),
      AutomationRuleType.deleteApkInstallers =>
        AutomationRule.deleteApkInstallers(
          id: id,
          enabled: enabled,
          createdAt: createdAt,
        ),
      AutomationRuleType.weeklyScan => AutomationRule.weeklyScan(
        id: id,
        enabled: enabled,
        createdAt: createdAt,
      ),
      AutomationRuleType.monthlyReport => AutomationRule.monthlyReport(
        id: id,
        enabled: enabled,
        createdAt: createdAt,
      ),
      AutomationRuleType.storageWarning => AutomationRule.storageWarning(
        id: id,
        freePercent: _percentOrDefault(storageWarningFreePercent, 10),
        enabled: enabled,
        createdAt: createdAt,
      ),
    };
  }

  AutomationPlan buildPlan({
    required Iterable<AutomationRule> rules,
    required Iterable<ScannedFile> files,
    DateTime? now,
  }) {
    final ruleList = rules.toList(growable: false);
    final enabledRules = ruleList.where((rule) => rule.enabled).toList();
    final referenceDate = now ?? DateTime.now();
    final matchedPaths = <String>{};
    var estimatedSavingsBytes = 0;

    for (final file in files) {
      for (final rule in enabledRules) {
        if (!_fileMatches(rule, file, referenceDate)) continue;
        if (matchedPaths.add(file.path)) {
          estimatedSavingsBytes += file.size;
        }
        break;
      }
    }

    return AutomationPlan(
      enabledRules: enabledRules.length,
      disabledRules: ruleList.length - enabledRules.length,
      matchedFileCount: matchedPaths.length,
      estimatedSavingsBytes: estimatedSavingsBytes,
      scheduledTaskCount: enabledRules.length,
    );
  }

  bool _fileMatches(AutomationRule rule, ScannedFile file, DateTime now) {
    return switch (rule.type) {
      AutomationRuleType.deleteScreenshots =>
        _isScreenshot(file) &&
            file.lastModified.isBefore(
              now.subtract(Duration(days: rule.ageThresholdDays ?? 90)),
            ),
      AutomationRuleType.deleteApkInstallers => _isApk(file),
      AutomationRuleType.weeklyScan ||
      AutomationRuleType.monthlyReport ||
      AutomationRuleType.storageWarning => false,
    };
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

  int _positiveOrDefault(int? value, int fallback) {
    if (value == null || value <= 0) return fallback;
    return value;
  }

  int _percentOrDefault(int? value, int fallback) {
    if (value == null) return fallback;
    return value.clamp(1, 100).toInt();
  }
}

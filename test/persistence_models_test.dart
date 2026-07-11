import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/features/auto_clean/domain/models/automation_rule.dart';
import 'package:spacepilot/features/auto_clean/domain/models/auto_clean_rules.dart';
import 'package:spacepilot/features/scheduled_scans/domain/models/scheduled_scan_config.dart';
import 'package:spacepilot/features/storage/domain/models/storage_history_entry.dart';
import 'package:spacepilot/features/storage/domain/models/storage_intelligence_report.dart';

void main() {
  test('storage history preserves categories and cleanup events', () {
    final entry = StorageHistoryEntry(
      timestamp: DateTime(2026, 7, 10),
      totalBytes: 1000,
      usedBytes: 600,
      freeBytes: 400,
      emptyFolderCount: 2,
      downloadFileCount: 3,
      downloadBytes: 120,
      largestFolders: const [],
      categoryBytes: const {
        StorageFileCategory.image: 240,
        StorageFileCategory.download: 120,
      },
      eventType: StorageHistoryEventType.cleanup,
      affectedBytes: 80,
    );

    final restored = StorageHistoryEntry.fromJson(entry.toJson());

    expect(restored.eventType, StorageHistoryEventType.cleanup);
    expect(restored.affectedBytes, 80);
    expect(restored.categoryBytes[StorageFileCategory.image], 240);
  });

  test('legacy storage history remains readable', () {
    final restored = StorageHistoryEntry.fromJson({
      'timestamp': 1,
      'totalBytes': 1000,
      'usedBytes': 600,
      'freeBytes': 400,
      'emptyFolderCount': 0,
      'downloadFileCount': 1,
      'downloadBytes': 120,
      'largestFolders': <Object?>[],
    });

    expect(restored.eventType, StorageHistoryEventType.scan);
    expect(restored.categoryBytes[StorageFileCategory.download], 120);
  });

  test('scheduled scan configuration round trips', () {
    final config = ScheduledScanConfig(
      enabled: true,
      frequency: ScheduledScanFrequency.monthly,
      minutesAfterMidnight: 615,
      lastRunAt: DateTime(2026, 7, 1),
    );

    final restored = ScheduledScanConfig.fromJson(config.toJson());

    expect(restored.enabled, isTrue);
    expect(restored.frequency, ScheduledScanFrequency.monthly);
    expect(restored.minutesAfterMidnight, 615);
    expect(restored.lastRunAt, DateTime(2026, 7, 1));
  });

  test('automation rule configuration round trips', () {
    final rule = AutomationRule.storageWarning(
      id: 'warning',
      freePercent: 15,
      enabled: true,
      createdAt: DateTime(2026, 7, 10),
    ).copyWith(cadence: AutomationRuleCadence.weekly);

    final restored = AutomationRule.fromJson(rule.toJson());

    expect(restored, isNotNull);
    expect(restored!.enabled, isTrue);
    expect(restored.cadence, AutomationRuleCadence.weekly);
    expect(restored.storageWarningFreePercent, 15);
  });

  test('review-only cleanup defaults round trip', () {
    final rules = const AutoCleanRules.defaults().copyWith(
      enabled: true,
      includeUnusedFiles: true,
      unusedFileAgeDays: 240,
    );

    final restored = AutoCleanRules.fromJson(rules.toJson());

    expect(restored.enabled, isTrue);
    expect(restored.includeUnusedFiles, isTrue);
    expect(restored.unusedFileAgeDays, 240);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/features/analytics/domain/models/storage_analytics.dart';
import 'package:spacepilot/features/device_health/data/services/services.dart';
import 'package:spacepilot/features/device_health/domain/models/device_health_report.dart';
import 'package:spacepilot/features/storage/domain/models/storage_stats.dart';

void main() {
  const engine = DeviceHealthEngine();

  test('scores health from every cleanup factor and explains calculation', () {
    final report = engine.evaluate(
      stats: StorageStats(
        totalBytes: 100,
        usedBytes: 92,
        freeBytes: 8,
        deviceHealthScore: 0,
        lastUpdated: DateTime(2026),
      ),
      analytics: const StorageAnalytics(
        totalFiles: 20,
        totalBytes: 92,
        duplicateGroups: 4,
        duplicateBytes: 10,
        junkFileCount: 6,
        junkBytes: 6,
        unusedFileCount: 8,
        unusedBytes: 8,
        categories: [],
        largestFiles: [],
      ),
      emptyFolderCount: 8,
      oldDownloadCount: 5,
      unusedAppCount: 3,
    );

    expect(report.score, 28);
    expect(report.category, DeviceHealthCategory.poor);
    expect(report.breakdown.storageUsagePenalty, 40);
    expect(report.breakdown.duplicateFilesPenalty, 8);
    expect(report.breakdown.unusedAppsPenalty, 9);
    expect(report.breakdown.junkFilesPenalty, 8);
    expect(report.breakdown.oldDownloadsPenalty, 5);
    expect(report.breakdown.emptyFoldersPenalty, 2);
    expect(report.explanation, contains('Final score: 28/100'));
    expect(
      report.suggestions,
      contains('Uninstall apps you have not opened recently.'),
    );
  });
}

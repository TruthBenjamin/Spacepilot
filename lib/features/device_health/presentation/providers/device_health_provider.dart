import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../analytics/presentation/providers/analytics_provider.dart';
import '../../../storage/domain/models/storage_intelligence_report.dart';
import '../../../storage/presentation/providers/device_storage_provider.dart';
import '../../../storage/presentation/providers/storage_scan_provider.dart';
import '../../../power/presentation/providers/power_thermal_provider.dart';
import '../../../scheduled_scans/presentation/providers/scheduled_scan_provider.dart';
import '../../data/services/device_health_engine.dart';
import '../../domain/models/device_health_report.dart';

final deviceHealthEngineProvider = Provider<DeviceHealthEngine>((ref) {
  return const DeviceHealthEngine();
});

final deviceHealthReportProvider = FutureProvider<DeviceHealthReport>((
  ref,
) async {
  final stats = await ref.watch(deviceStorageStatsProvider.future);
  final analytics = await ref.watch(storageAnalyticsProvider.future);
  final scan = await ref.watch(storageScanProvider.future);
  final report = scan.intelligenceReport;
  final emptyFolderCount = report?.emptyFolders.length ?? 0;
  final oldDownloadCount = _oldDownloadCount(report);
  final power = ref.watch(powerThermalSnapshotProvider).value;
  final scheduledScanning = ref.watch(scheduledScanProvider).enabled;

  return ref
      .read(deviceHealthEngineProvider)
      .evaluate(
        stats: stats,
        analytics: analytics,
        emptyFolderCount: emptyFolderCount,
        oldDownloadCount: oldDownloadCount,
        unusedAppCount: 0,
        thermalStatus: power?.thermalStatus,
        batteryLevel: power?.batteryLevel,
        scheduledScanningEnabled: scheduledScanning,
      );
});

int _oldDownloadCount(StorageIntelligenceReport? report) {
  if (report == null) return 0;

  final cutoff = DateTime.now().subtract(const Duration(days: 90));
  return report.fileInsights.where((insight) {
    return insight.hasCategory(StorageFileCategory.download) &&
        insight.file.lastModified.isBefore(cutoff);
  }).length;
}

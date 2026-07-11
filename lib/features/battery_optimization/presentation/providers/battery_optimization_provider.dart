import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../power/presentation/providers/power_thermal_provider.dart';
import '../../../scheduled_scans/presentation/providers/scheduled_scan_provider.dart';
import '../../../storage/presentation/providers/storage_scan_provider.dart';
import '../../domain/models/power_advice.dart';

final batteryRecommendationsProvider =
    FutureProvider<List<PowerRecommendation>>((ref) async {
      final snapshot = await ref.watch(powerThermalSnapshotProvider.future);
      final scan = ref.watch(storageScanProgressProvider);
      final scheduled = ref.watch(scheduledScanProvider);
      return buildPowerRecommendations(
        snapshot,
        scanActive: scan.stage == StorageScanStage.scanning,
        scheduledScanning: scheduled.enabled,
      );
    });

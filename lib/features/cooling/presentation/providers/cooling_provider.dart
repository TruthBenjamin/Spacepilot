import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../power/presentation/providers/power_thermal_provider.dart';
import '../../../storage/presentation/providers/storage_scan_provider.dart';
import '../../domain/models/thermal_advice.dart';

final coolingAdviceProvider = FutureProvider<ThermalAdvice>((ref) async {
  final snapshot = await ref.watch(powerThermalSnapshotProvider.future);
  final progress = ref.watch(storageScanProgressProvider);
  return buildThermalAdvice(
    snapshot,
    scanActive: progress.stage == StorageScanStage.scanning,
  );
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/power_thermal_service.dart';
import '../../domain/models/power_thermal_snapshot.dart';

final powerThermalServiceProvider = Provider<PowerThermalService>(
  (ref) => PowerThermalService(),
);

final powerThermalSnapshotProvider = FutureProvider<PowerThermalSnapshot>((
  ref,
) {
  return ref.watch(powerThermalServiceProvider).getSnapshot();
});

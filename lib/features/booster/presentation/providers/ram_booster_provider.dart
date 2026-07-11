import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/ram_booster_service.dart';

final ramBoosterServiceProvider = Provider<RamBoosterService>((ref) {
  return RamBoosterService();
});

final ramSnapshotProvider = FutureProvider<RamSnapshot>((ref) async {
  return ref.read(ramBoosterServiceProvider).getMemorySnapshot();
});

final ramBoostProvider =
    AsyncNotifierProvider<RamBoostController, RamBoostResult?>(
      RamBoostController.new,
    );

final class RamBoostController extends AsyncNotifier<RamBoostResult?> {
  @override
  Future<RamBoostResult?> build() async => null;

  Future<RamBoostResult> boost() async {
    state = const AsyncLoading();
    final result = await ref.read(ramBoosterServiceProvider).boost();
    ref.invalidate(ramSnapshotProvider);
    state = AsyncData(result);
    return result;
  }
}

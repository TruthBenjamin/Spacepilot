import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../storage/data/services/storage_scanner_service.dart';
import '../../../storage/presentation/providers/storage_scan_provider.dart';

enum LargeFileThreshold {
  mb100('100MB', 100 * 1024 * 1024),
  mb500('500MB', 500 * 1024 * 1024),
  gb1('1GB', 1024 * 1024 * 1024);

  const LargeFileThreshold(this.label, this.bytes);

  final String label;
  final int bytes;
}

final largeFileThresholdProvider = StateProvider<LargeFileThreshold>((ref) {
  return LargeFileThreshold.mb100;
});

final largeFileHunterProvider = Provider<AsyncValue<List<ScannedFile>>>((ref) {
  final threshold = ref.watch(largeFileThresholdProvider);
  final scan = ref.watch(storageScanProvider);

  return scan.whenData((state) {
    final files = state.files
        .where((file) => file.size > threshold.bytes)
        .toList(growable: false)
      ..sort((a, b) => b.size.compareTo(a.size));

    return files;
  });
});

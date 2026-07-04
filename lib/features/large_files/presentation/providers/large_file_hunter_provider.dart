import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../storage/domain/models/scanned_file.dart';
import '../../../storage/presentation/providers/storage_scan_provider.dart';

enum LargeFileThreshold {
  mb100('100 MB', 100 * 1024 * 1024),
  mb250('250 MB', 250 * 1024 * 1024),
  mb500('500 MB', 500 * 1024 * 1024),
  gb1('1 GB', 1024 * 1024 * 1024);

  const LargeFileThreshold(this.label, this.bytes);

  final String label;
  final int bytes;
}

final largeFileThresholdProvider = StateProvider<LargeFileThreshold>((ref) {
  return LargeFileThreshold.mb100;
});

final largeFilePageProvider = StateProvider<int>((ref) => 0);

const largeFilePageSize = 50;

final largeFileHunterProvider = Provider<AsyncValue<List<ScannedFile>>>((ref) {
  final threshold = ref.watch(largeFileThresholdProvider);
  final scannedFiles = ref.watch(
    storageScanProvider.select((scan) => scan.whenData((state) => state.files)),
  );

  return scannedFiles.whenData((scannedFiles) {
    final files =
        scannedFiles
            .where((file) => file.size > threshold.bytes)
            .toList(growable: false)
          ..sort((a, b) => b.size.compareTo(a.size));

    return files;
  });
});

final pagedLargeFileHunterProvider =
    Provider<AsyncValue<LargeFileHunterPage>>((ref) {
      final page = ref.watch(largeFilePageProvider);
      final largeFiles = ref.watch(largeFileHunterProvider);

      return largeFiles.whenData((files) {
        final start = page * largeFilePageSize;
        if (start >= files.length) {
          return LargeFileHunterPage(
            files: const [],
            page: page,
            pageSize: largeFilePageSize,
            totalFiles: files.length,
          );
        }

        final end = (start + largeFilePageSize).clamp(0, files.length).toInt();
        return LargeFileHunterPage(
          files: files.sublist(start, end),
          page: page,
          pageSize: largeFilePageSize,
          totalFiles: files.length,
        );
      });
    });

final class LargeFileHunterPage {
  const LargeFileHunterPage({
    required this.files,
    required this.page,
    required this.pageSize,
    required this.totalFiles,
  });

  final List<ScannedFile> files;
  final int page;
  final int pageSize;
  final int totalFiles;

  int get displayedCount => files.length;
  bool get hasNextPage => (page + 1) * pageSize < totalFiles;
}

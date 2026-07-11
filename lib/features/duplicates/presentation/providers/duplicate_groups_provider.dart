import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../storage/presentation/providers/storage_scan_provider.dart';
import '../../data/services/duplicate_detector_service.dart';
import '../../data/services/similar_image_detector_service.dart';
import '../../domain/models/models.dart';

final duplicateDetectorServiceProvider = Provider<DuplicateDetectorService>(
  (ref) => const DuplicateDetectorService(),
);

final similarImageDetectorServiceProvider =
    Provider<SimilarImageDetectorService>(
      (ref) => const SimilarImageDetectorService(),
    );

final duplicateGroupsProvider = FutureProvider<List<DuplicateGroup>>((
  ref,
) async {
  final scan = await ref.watch(storageScanProvider.future);
  if (!scan.hasScanned || scan.files.isEmpty) return const [];

  return ref
      .read(duplicateDetectorServiceProvider)
      .findDuplicatesInScannedFiles(scan.files);
});

final similarImageGroupsProvider = FutureProvider<List<SimilarImageGroup>>((
  ref,
) async {
  final scan = await ref.watch(storageScanProvider.future);
  if (!scan.hasScanned || scan.files.isEmpty) return const [];

  return ref
      .read(similarImageDetectorServiceProvider)
      .findSimilarImagesInScannedFiles(scan.files);
});

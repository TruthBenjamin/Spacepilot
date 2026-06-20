import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../storage/presentation/providers/storage_scan_provider.dart';
import '../../data/services/duplicate_detector_service.dart';
import '../../domain/models/duplicate_group.dart';

final duplicateDetectorServiceProvider = Provider<DuplicateDetectorService>(
  (ref) => const DuplicateDetectorService(),
);

final duplicateGroupsProvider = FutureProvider<List<DuplicateGroup>>((ref) async {
  final scan = await ref.watch(storageScanProvider.future);
  if (!scan.hasScanned || scan.files.isEmpty) return const [];

  return ref
      .read(duplicateDetectorServiceProvider)
      .findDuplicates(scan.files.map((file) => File(file.path)));
});

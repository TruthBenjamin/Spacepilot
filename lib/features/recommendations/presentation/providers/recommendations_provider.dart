import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../duplicates/presentation/providers/duplicate_groups_provider.dart';
import '../../../storage/presentation/providers/storage_scan_provider.dart';
import '../../data/services/recommendation_engine.dart';
import '../../domain/models/storage_recommendation.dart';

final recommendationEngineProvider = Provider<RecommendationEngine>(
  (ref) => const RecommendationEngine(),
);

final recommendationsProvider = FutureProvider<List<StorageRecommendation>>((
  ref,
) async {
  final scan = await ref.watch(storageScanProvider.future);
  if (!scan.hasScanned || scan.files.isEmpty) return const [];

  final duplicateGroups = await ref.watch(duplicateGroupsProvider.future);

  return ref
      .read(recommendationEngineProvider)
      .buildRecommendations(
        files: scan.files,
        duplicateGroups: duplicateGroups,
      );
});

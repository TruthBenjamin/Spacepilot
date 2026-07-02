import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../duplicates/presentation/providers/duplicate_groups_provider.dart';
import '../../../storage/presentation/providers/storage_scan_provider.dart';
import '../../data/services/analytics_engine.dart';
import '../../domain/models/storage_analytics.dart';

final analyticsEngineProvider = Provider<AnalyticsEngine>(
  (ref) => const AnalyticsEngine(),
);

final storageAnalyticsProvider = FutureProvider<StorageAnalytics>((ref) async {
  final scan = await ref.watch(storageScanProvider.future);
  final duplicateGroups = await ref.watch(duplicateGroupsProvider.future);

  return ref
      .read(analyticsEngineProvider)
      .analyze(files: scan.files, duplicateGroups: duplicateGroups);
});

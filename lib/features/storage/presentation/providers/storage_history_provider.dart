import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/storage_history_service.dart';
import '../../domain/models/storage_history_entry.dart';

final storageHistoryServiceProvider = Provider<StorageHistoryService>((ref) {
  return StorageHistoryService();
});

final storageHistoryProvider = FutureProvider<List<StorageHistoryEntry>>((ref) {
  return ref.read(storageHistoryServiceProvider).loadHistory();
});

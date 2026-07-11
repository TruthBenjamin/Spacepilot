import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/cleanup_service.dart';
import '../../domain/models/cleanup_candidate.dart';
import 'cleanup_service_provider.dart';
import 'deletion_sync_provider.dart';

final junkSelectionProvider =
    NotifierProvider<JunkSelectionController, Set<String>>(
      JunkSelectionController.new,
    );

final class JunkSelectionController extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};
  void toggle(String id) =>
      state = state.contains(id) ? ({...state}..remove(id)) : {...state, id};
  void setCategory(CleanupCategory category, bool selected) {
    final ids = category.candidates.map((item) => item.id);
    state = selected ? {...state, ...ids} : ({...state}..removeAll(ids));
  }

  void clear() => state = <String>{};
}

final junkCleanupProvider =
    AsyncNotifierProvider<JunkCleanupController, CleanupResult?>(
      JunkCleanupController.new,
    );

final class JunkCleanupController extends AsyncNotifier<CleanupResult?> {
  @override
  Future<CleanupResult?> build() async => null;

  Future<CleanupResult> clean(
    CleanupSelectionSummary selection, {
    required bool userConfirmed,
  }) async {
    state = const AsyncLoading();
    final service = ref.read(cleanupServiceProvider);
    final fileResult = await service.deleteFiles(
      selection.files.map((file) => File(file.path)),
      userConfirmed: userConfirmed,
    );
    final folderResult = await service.deleteEmptyFolders(
      selection.emptyFolders.map((folder) => Directory(folder.path)),
      userConfirmed: userConfirmed,
    );
    final result = CleanupResult(
      deletedPaths: [...fileResult.deletedPaths, ...folderResult.deletedPaths],
      skippedPaths: [...fileResult.skippedPaths, ...folderResult.skippedPaths],
      failures: {...fileResult.failures, ...folderResult.failures},
    );
    ref.read(deletionSyncProvider).applyDeletedPaths(result.deletedPaths);
    ref.read(junkSelectionProvider.notifier).clear();
    state = AsyncData(result);
    return result;
  }
}

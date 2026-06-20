import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/storage_scanner_service.dart';

final storageScannerServiceProvider = Provider<StorageScannerService>((ref) {
  return StorageScannerService();
});

final storageScanProvider =
    AsyncNotifierProvider<StorageScanController, StorageScanState>(
      StorageScanController.new,
    );

final class StorageScanState {
  const StorageScanState({
    required this.files,
    required this.hasScanned,
  });

  const StorageScanState.initial() : files = const [], hasScanned = false;

  final List<ScannedFile> files;
  final bool hasScanned;

  int get totalBytes => files.fold<int>(0, (total, file) => total + file.size);
}

final class StorageScanController extends AsyncNotifier<StorageScanState> {
  @override
  FutureOr<StorageScanState> build() => const StorageScanState.initial();

  Future<List<ScannedFile>> scan() async {
    state = const AsyncLoading();

    try {
      final files = await ref.read(storageScannerServiceProvider).scan();
      state = AsyncData(StorageScanState(files: files, hasScanned: true));
      return files;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

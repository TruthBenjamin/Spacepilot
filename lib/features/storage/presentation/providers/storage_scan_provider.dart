import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../permissions/presentation/providers/permission_service_provider.dart';
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

  void removeDeletedPaths(Iterable<String> paths) {
    final current = state.value;
    if (current == null || paths.isEmpty) return;

    final deletedPaths = paths.toSet();
    state = AsyncData(
      StorageScanState(
        files: current.files
            .where((file) => !deletedPaths.contains(file.path))
            .toList(growable: false),
        hasScanned: current.hasScanned,
      ),
    );
  }

  Future<List<ScannedFile>> scan() async {
    state = const AsyncLoading();

    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final hasAccess = await ref
            .read(permissionServiceProvider)
            .requestRequiredAccess();
        if (!hasAccess) {
          throw PlatformException(
            code: 'PERMISSION_DENIED',
            message: 'Storage and media access were not granted.',
          );
        }
      }

      final files = await ref.read(storageScannerServiceProvider).scan();
      state = AsyncData(StorageScanState(files: files, hasScanned: true));
      return files;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

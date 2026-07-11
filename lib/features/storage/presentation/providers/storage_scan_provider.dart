import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../permissions/presentation/providers/permission_service_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../data/services/storage_scanner_service.dart';
import '../../domain/models/storage_intelligence_report.dart';
import '../../domain/models/scanned_file.dart';
import '../../domain/models/storage_history_entry.dart';
import '../../domain/models/storage_stats.dart';
import 'storage_history_provider.dart';

final storageScannerServiceProvider = Provider<StorageScannerService>((ref) {
  return StorageScannerService();
});

final storageScanProvider =
    AsyncNotifierProvider<StorageScanController, StorageScanState>(
      StorageScanController.new,
    );

final storageScanProgressProvider = StateProvider<StorageScanProgress>((ref) {
  return const StorageScanProgress.idle();
});

enum StorageScanStage {
  idle,
  verifyingPermissions,
  scanning,
  savingHistory,
  complete,
  failed,
}

final class StorageScanProgress {
  const StorageScanProgress({
    required this.stage,
    this.startedAt,
    this.completedAt,
    this.filesAnalyzed,
    this.bytesAnalyzed,
    this.scannedRootCount,
    this.fraction,
    this.errorMessage,
    this.supportsCancellation = false,
    this.supportsGranularProgress = false,
  });

  const StorageScanProgress.idle()
    : stage = StorageScanStage.idle,
      startedAt = null,
      completedAt = null,
      filesAnalyzed = null,
      bytesAnalyzed = null,
      scannedRootCount = null,
      fraction = null,
      errorMessage = null,
      supportsCancellation = false,
      supportsGranularProgress = false;

  final StorageScanStage stage;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int? filesAnalyzed;
  final int? bytesAnalyzed;
  final int? scannedRootCount;
  final double? fraction;
  final String? errorMessage;
  final bool supportsCancellation;
  final bool supportsGranularProgress;

  bool get isScanning =>
      stage == StorageScanStage.verifyingPermissions ||
      stage == StorageScanStage.scanning ||
      stage == StorageScanStage.savingHistory;

  Duration elapsed(DateTime now) {
    final started = startedAt;
    if (started == null) return Duration.zero;
    return (completedAt ?? now).difference(started);
  }

  StorageScanProgress copyWith({
    StorageScanStage? stage,
    DateTime? startedAt,
    DateTime? completedAt,
    int? filesAnalyzed,
    int? bytesAnalyzed,
    int? scannedRootCount,
    double? fraction,
    String? errorMessage,
    bool? supportsCancellation,
    bool? supportsGranularProgress,
  }) {
    return StorageScanProgress(
      stage: stage ?? this.stage,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      filesAnalyzed: filesAnalyzed ?? this.filesAnalyzed,
      bytesAnalyzed: bytesAnalyzed ?? this.bytesAnalyzed,
      scannedRootCount: scannedRootCount ?? this.scannedRootCount,
      fraction: fraction ?? this.fraction,
      errorMessage: errorMessage,
      supportsCancellation: supportsCancellation ?? this.supportsCancellation,
      supportsGranularProgress:
          supportsGranularProgress ?? this.supportsGranularProgress,
    );
  }
}

final class StorageScanState {
  const StorageScanState({
    required this.files,
    required this.hasScanned,
    this.intelligenceReport,
    this.progress = const StorageScanProgress.idle(),
  });

  const StorageScanState.initial()
    : files = const [],
      hasScanned = false,
      intelligenceReport = null,
      progress = const StorageScanProgress.idle();

  final List<ScannedFile> files;
  final bool hasScanned;
  final StorageIntelligenceReport? intelligenceReport;
  final StorageScanProgress progress;

  int get totalBytes => files.fold<int>(0, (total, file) => total + file.size);

  StorageScanState copyWith({
    List<ScannedFile>? files,
    bool? hasScanned,
    StorageIntelligenceReport? intelligenceReport,
    StorageScanProgress? progress,
  }) {
    return StorageScanState(
      files: files ?? this.files,
      hasScanned: hasScanned ?? this.hasScanned,
      intelligenceReport: intelligenceReport ?? this.intelligenceReport,
      progress: progress ?? this.progress,
    );
  }
}

final class StorageScanController extends AsyncNotifier<StorageScanState> {
  Future<StorageIntelligenceReport>? _activeScan;

  @override
  FutureOr<StorageScanState> build() => const StorageScanState.initial();

  void removeDeletedPaths(Iterable<String> paths) {
    final current = state.value;
    if (current == null || paths.isEmpty) return;

    final deletedPaths = paths.map(_normalizePath).toSet();
    final deletedBytes = current.files
        .where((file) => deletedPaths.contains(_normalizePath(file.path)))
        .fold<int>(0, (total, file) => total + file.size);
    final report = current.intelligenceReport;
    final updatedInsights = report?.fileInsights
        .where(
          (insight) =>
              !deletedPaths.contains(_normalizePath(insight.file.path)),
        )
        .toList(growable: false);
    final updatedEmptyFolders = report?.emptyFolders
        .where((folder) => !deletedPaths.contains(_normalizePath(folder.path)))
        .toList(growable: false);

    state = AsyncData(
      StorageScanState(
        files: current.files
            .where((file) => !deletedPaths.contains(_normalizePath(file.path)))
            .toList(growable: false),
        hasScanned: current.hasScanned,
        intelligenceReport:
            report == null ||
                updatedInsights == null ||
                updatedEmptyFolders == null
            ? null
            : _rebuildReport(
                report,
                updatedInsights,
                emptyFolders: updatedEmptyFolders,
                freedBytes: deletedBytes,
              ),
        progress: current.progress,
      ),
    );
  }

  void moveFilePath({
    required String fromPath,
    required String toPath,
    required String filename,
  }) {
    final current = state.value;
    if (current == null || fromPath == toPath) return;

    ScannedFile moveFile(ScannedFile file) {
      if (file.path != fromPath) return file;
      return ScannedFile(
        filename: filename,
        path: toPath,
        size: file.size,
        lastModified: file.lastModified,
        previewPath: file.previewPath == file.path ? toPath : file.previewPath,
        previewType: file.previewType,
      );
    }

    final updatedFiles = current.files.map(moveFile).toList(growable: false);
    final report = current.intelligenceReport;
    final updatedInsights = report?.fileInsights
        .map(
          (insight) => StorageFileInsight(
            file: moveFile(insight.file),
            categories: insight.categories,
          ),
        )
        .toList(growable: false);

    state = AsyncData(
      StorageScanState(
        files: updatedFiles,
        hasScanned: current.hasScanned,
        intelligenceReport: report == null || updatedInsights == null
            ? null
            : _rebuildReport(report, updatedInsights),
        progress: current.progress,
      ),
    );
  }

  Future<List<ScannedFile>> scan() async {
    final report = await scanIntelligence();
    return report.files;
  }

  Future<StorageIntelligenceReport> scanIntelligence() async {
    final activeScan = _activeScan;
    if (activeScan != null) return activeScan;

    final scan = _scanIntelligence();
    _activeScan = scan;

    try {
      return await scan;
    } finally {
      _activeScan = null;
    }
  }

  Future<StorageScanState?> cancelScan() async {
    final activeScan = _activeScan;
    if (activeScan == null) return state.value;

    await ref.read(storageScannerServiceProvider).cancelScan();
    await activeScan;
    return state.value;
  }

  Future<StorageIntelligenceReport> _scanIntelligence() async {
    final startedAt = DateTime.now();
    _setProgress(
      StorageScanProgress(
        stage: StorageScanStage.verifyingPermissions,
        startedAt: startedAt,
      ),
    );

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

      _setProgress(
        StorageScanProgress(
          stage: StorageScanStage.scanning,
          startedAt: startedAt,
          supportsCancellation: defaultTargetPlatform == TargetPlatform.android,
        ),
      );
      final report = await ref
          .read(storageScannerServiceProvider)
          .scanIntelligence(
            includeHidden: ref.read(scannerIncludeHiddenProvider),
            onProgress: (nativeProgress) {
              final current = ref.read(storageScanProgressProvider);
              if (current.stage != StorageScanStage.scanning) return;
              ref.read(storageScanProgressProvider.notifier).state = current
                  .copyWith(
                    fraction: nativeProgress.fraction,
                    filesAnalyzed: nativeProgress.filesAnalyzed,
                    bytesAnalyzed: nativeProgress.bytesAnalyzed,
                    scannedRootCount: nativeProgress.scannedRootCount,
                    supportsGranularProgress: true,
                  );
            },
          );
      _setProgress(
        StorageScanProgress(
          stage: StorageScanStage.savingHistory,
          startedAt: startedAt,
          filesAnalyzed: report.files.length,
          bytesAnalyzed: report.files.fold<int>(
            0,
            (total, file) => total + file.size,
          ),
          scannedRootCount: report.scannedRootPaths.length,
          fraction: 0.96,
          supportsGranularProgress: true,
        ),
      );
      final entry = StorageHistoryEntry.fromReport(report);
      await ref.read(storageHistoryServiceProvider).appendEntry(entry);
      final completedProgress = StorageScanProgress(
        stage: StorageScanStage.complete,
        startedAt: startedAt,
        completedAt: DateTime.now(),
        filesAnalyzed: report.files.length,
        bytesAnalyzed: report.files.fold<int>(
          0,
          (total, file) => total + file.size,
        ),
        scannedRootCount: report.scannedRootPaths.length,
        fraction: 1,
        supportsGranularProgress: true,
      );
      ref.read(storageScanProgressProvider.notifier).state = completedProgress;
      state = AsyncData(
        StorageScanState(
          files: report.files,
          hasScanned: true,
          intelligenceReport: report,
          progress: completedProgress,
        ),
      );
      return report;
    } catch (error, stackTrace) {
      _setProgress(
        StorageScanProgress(
          stage: StorageScanStage.failed,
          startedAt: startedAt,
          completedAt: DateTime.now(),
          errorMessage: error.toString(),
        ),
      );
      state = AsyncError<StorageScanState>(error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  void _setProgress(StorageScanProgress progress) {
    ref.read(storageScanProgressProvider.notifier).state = progress;
    state = const AsyncLoading<StorageScanState>();
  }
}

StorageIntelligenceReport _rebuildReport(
  StorageIntelligenceReport report,
  List<StorageFileInsight> insights, {
  List<EmptyFolder>? emptyFolders,
  int freedBytes = 0,
}) {
  return StorageIntelligenceReport(
    storageStats: _storageStatsAfterFreeing(report, freedBytes),
    fileInsights: insights,
    largestFolders: _deriveLargestFolders(insights),
    emptyFolders: emptyFolders ?? report.emptyFolders,
    categorySummaries: _deriveCategorySummaries(insights),
    scannedRootPaths: report.scannedRootPaths,
    completedAt: report.completedAt,
  );
}

StorageStats _storageStatsAfterFreeing(
  StorageIntelligenceReport report,
  int freedBytes,
) {
  if (freedBytes <= 0) return report.storageStats;

  final stats = report.storageStats;
  final usedBytes = (stats.usedBytes - freedBytes).clamp(0, stats.totalBytes);
  final freeBytes = (stats.freeBytes + freedBytes).clamp(
    0,
    stats.totalBytes - usedBytes,
  );

  return stats.copyWith(
    usedBytes: usedBytes.toInt(),
    freeBytes: freeBytes.toInt(),
    lastUpdated: DateTime.now(),
  );
}

List<StorageFolderSummary> _deriveLargestFolders(
  Iterable<StorageFileInsight> insights,
) {
  final sizes = <String, int>{};
  final counts = <String, int>{};
  final modified = <String, DateTime>{};

  for (final insight in insights) {
    final file = insight.file;
    final folder = _parentDirectory(file.path);
    sizes[folder] = (sizes[folder] ?? 0) + file.size;
    counts[folder] = (counts[folder] ?? 0) + 1;
    final currentModified = modified[folder];
    if (currentModified == null || file.lastModified.isAfter(currentModified)) {
      modified[folder] = file.lastModified;
    }
  }

  final folders = [
    for (final entry in sizes.entries)
      StorageFolderSummary(
        path: entry.key,
        sizeBytes: entry.value,
        fileCount: counts[entry.key] ?? 0,
        lastModified: modified[entry.key],
      ),
  ]..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));

  return folders.take(50).toList(growable: false);
}

List<StorageCategorySummary> _deriveCategorySummaries(
  Iterable<StorageFileInsight> insights,
) {
  final bytes = <StorageFileCategory, int>{};
  final counts = <StorageFileCategory, int>{};

  for (final insight in insights) {
    for (final category in insight.categories) {
      bytes[category] = (bytes[category] ?? 0) + insight.file.size;
      counts[category] = (counts[category] ?? 0) + 1;
    }
  }

  return [
    for (final category in StorageFileCategory.values)
      StorageCategorySummary(
        category: category,
        fileCount: counts[category] ?? 0,
        totalBytes: bytes[category] ?? 0,
      ),
  ];
}

String _parentDirectory(String path) {
  final normalized = path.replaceAll('\\', '/');
  final lastSeparator = normalized.lastIndexOf('/');
  if (lastSeparator <= 0) return path;
  return normalized.substring(0, lastSeparator);
}

String _normalizePath(String path) {
  return path.replaceAll('\\', '/');
}

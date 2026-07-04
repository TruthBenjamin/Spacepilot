import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'scanned_file.dart';
import 'storage_stats.dart';

enum StorageFileCategory {
  image,
  video,
  audio,
  document,
  apk,
  zip,
  download,
  other,
}

@immutable
final class StorageFileInsight {
  StorageFileInsight({
    required this.file,
    required Iterable<StorageFileCategory> categories,
  }) : categories = UnmodifiableListView<StorageFileCategory>(categories);

  final ScannedFile file;
  final UnmodifiableListView<StorageFileCategory> categories;

  bool hasCategory(StorageFileCategory category) {
    return categories.contains(category);
  }
}

@immutable
final class StorageCategorySummary {
  const StorageCategorySummary({
    required this.category,
    required this.fileCount,
    required this.totalBytes,
  });

  final StorageFileCategory category;
  final int fileCount;
  final int totalBytes;
}

@immutable
final class StorageFolderSummary {
  const StorageFolderSummary({
    required this.path,
    required this.sizeBytes,
    required this.fileCount,
    required this.lastModified,
  });

  final String path;
  final int sizeBytes;
  final int fileCount;
  final DateTime? lastModified;
}

@immutable
final class EmptyFolder {
  const EmptyFolder({required this.path, required this.lastModified});

  final String path;
  final DateTime? lastModified;
}

@immutable
final class StorageIntelligenceReport {
  StorageIntelligenceReport({
    required this.storageStats,
    required Iterable<StorageFileInsight> fileInsights,
    required Iterable<StorageFolderSummary> largestFolders,
    required Iterable<EmptyFolder> emptyFolders,
    required Iterable<StorageCategorySummary> categorySummaries,
    required Iterable<String> scannedRootPaths,
    required this.completedAt,
  }) : fileInsights = UnmodifiableListView<StorageFileInsight>(fileInsights),
       largestFolders = UnmodifiableListView<StorageFolderSummary>(
         largestFolders,
       ),
       emptyFolders = UnmodifiableListView<EmptyFolder>(emptyFolders),
       categorySummaries = UnmodifiableListView<StorageCategorySummary>(
         categorySummaries,
       ),
       scannedRootPaths = UnmodifiableListView<String>(scannedRootPaths);

  StorageIntelligenceReport.empty({DateTime? completedAt})
    : this(
        storageStats: StorageStats(
          totalBytes: 0,
          usedBytes: 0,
          freeBytes: 0,
          deviceHealthScore: 0,
          lastUpdated: completedAt ?? DateTime.now(),
        ),
        fileInsights: const [],
        largestFolders: const [],
        emptyFolders: const [],
        categorySummaries: const [],
        scannedRootPaths: const [],
        completedAt: completedAt ?? DateTime.now(),
      );

  final StorageStats storageStats;
  final UnmodifiableListView<StorageFileInsight> fileInsights;
  final UnmodifiableListView<StorageFolderSummary> largestFolders;
  final UnmodifiableListView<EmptyFolder> emptyFolders;
  final UnmodifiableListView<StorageCategorySummary> categorySummaries;
  final UnmodifiableListView<String> scannedRootPaths;
  final DateTime completedAt;

  List<ScannedFile> get files {
    return UnmodifiableListView(fileInsights.map((insight) => insight.file));
  }

  List<ScannedFile> get largestFiles {
    final sorted = fileInsights.map((insight) => insight.file).toList()
      ..sort((a, b) => b.size.compareTo(a.size));
    return UnmodifiableListView(sorted);
  }

  StorageCategorySummary summaryFor(StorageFileCategory category) {
    return categorySummaries.firstWhere(
      (summary) => summary.category == category,
      orElse: () => StorageCategorySummary(
        category: category,
        fileCount: 0,
        totalBytes: 0,
      ),
    );
  }
}

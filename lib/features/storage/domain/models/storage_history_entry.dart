import 'package:flutter/foundation.dart';

import 'storage_intelligence_report.dart';

@immutable
final class StorageHistoryEntry {
  const StorageHistoryEntry({
    required this.timestamp,
    required this.totalBytes,
    required this.usedBytes,
    required this.freeBytes,
    required this.emptyFolderCount,
    required this.downloadFileCount,
    required this.downloadBytes,
    required this.largestFolders,
    this.categoryBytes = const {},
    this.eventType = StorageHistoryEventType.scan,
    this.affectedBytes = 0,
  });

  factory StorageHistoryEntry.fromReport(
    StorageIntelligenceReport report, {
    StorageHistoryEventType eventType = StorageHistoryEventType.scan,
    int affectedBytes = 0,
    DateTime? timestamp,
  }) {
    final downloadSummary = report.categorySummaries.firstWhere(
      (summary) => summary.category == StorageFileCategory.download,
      orElse: () => const StorageCategorySummary(
        category: StorageFileCategory.download,
        fileCount: 0,
        totalBytes: 0,
      ),
    );

    return StorageHistoryEntry(
      timestamp: timestamp ?? report.completedAt,
      totalBytes: report.storageStats.totalBytes,
      usedBytes: report.storageStats.usedBytes,
      freeBytes: report.storageStats.freeBytes,
      emptyFolderCount: report.emptyFolders.length,
      downloadFileCount: downloadSummary.fileCount,
      downloadBytes: downloadSummary.totalBytes,
      largestFolders: report.largestFolders,
      categoryBytes: {
        for (final summary in report.categorySummaries)
          summary.category: summary.totalBytes,
      },
      eventType: eventType,
      affectedBytes: affectedBytes,
    );
  }

  final DateTime timestamp;
  final int totalBytes;
  final int usedBytes;
  final int freeBytes;
  final int emptyFolderCount;
  final int downloadFileCount;
  final int downloadBytes;
  final List<StorageFolderSummary> largestFolders;
  final Map<StorageFileCategory, int> categoryBytes;
  final StorageHistoryEventType eventType;
  final int affectedBytes;

  double get usedPercent {
    if (totalBytes == 0) return 0;
    return usedBytes / totalBytes;
  }

  double get freePercent {
    if (totalBytes == 0) return 0;
    return freeBytes / totalBytes;
  }

  Map<String, Object?> toJson() {
    return {
      'timestamp': timestamp.millisecondsSinceEpoch,
      'totalBytes': totalBytes,
      'usedBytes': usedBytes,
      'freeBytes': freeBytes,
      'emptyFolderCount': emptyFolderCount,
      'downloadFileCount': downloadFileCount,
      'downloadBytes': downloadBytes,
      'largestFolders': [
        for (final folder in largestFolders)
          {
            'path': folder.path,
            'sizeBytes': folder.sizeBytes,
            'fileCount': folder.fileCount,
            'lastModified': folder.lastModified?.millisecondsSinceEpoch,
          },
      ],
      'categoryBytes': {
        for (final entry in categoryBytes.entries) entry.key.name: entry.value,
      },
      'eventType': eventType.name,
      'affectedBytes': affectedBytes,
    };
  }

  static StorageHistoryEntry fromJson(Map<String, Object?> json) {
    final timestamp = json['timestamp'];
    final totalBytes = json['totalBytes'];
    final usedBytes = json['usedBytes'];
    final freeBytes = json['freeBytes'];
    final emptyFolderCount = json['emptyFolderCount'];
    final downloadFileCount = json['downloadFileCount'];
    final downloadBytes = json['downloadBytes'];
    final largestFolders = json['largestFolders'];
    final rawCategoryBytes = json['categoryBytes'];

    if (timestamp is! num ||
        totalBytes is! num ||
        usedBytes is! num ||
        freeBytes is! num ||
        emptyFolderCount is! num ||
        downloadFileCount is! num ||
        downloadBytes is! num ||
        largestFolders is! List<Object?>) {
      throw const FormatException('Invalid storage history entry JSON.');
    }

    return StorageHistoryEntry(
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp.toInt()),
      totalBytes: totalBytes.toInt(),
      usedBytes: usedBytes.toInt(),
      freeBytes: freeBytes.toInt(),
      emptyFolderCount: emptyFolderCount.toInt(),
      downloadFileCount: downloadFileCount.toInt(),
      downloadBytes: downloadBytes.toInt(),
      largestFolders: largestFolders
          .whereType<Map<Object?, Object?>>()
          .map((folder) {
            final path = folder['path'];
            final sizeBytes = folder['sizeBytes'];
            final fileCount = folder['fileCount'];
            final lastModified = folder['lastModified'];

            if (path is! String || sizeBytes is! num || fileCount is! num) {
              throw const FormatException('Invalid folder summary JSON.');
            }

            return StorageFolderSummary(
              path: path,
              sizeBytes: sizeBytes.toInt(),
              fileCount: fileCount.toInt(),
              lastModified: lastModified is num
                  ? DateTime.fromMillisecondsSinceEpoch(lastModified.toInt())
                  : null,
            );
          })
          .toList(growable: false),
      categoryBytes: _categoryBytesFromJson(
        rawCategoryBytes,
        fallbackDownloadBytes: downloadBytes.toInt(),
      ),
      eventType: StorageHistoryEventType.values.firstWhere(
        (type) => type.name == json['eventType'],
        orElse: () => StorageHistoryEventType.scan,
      ),
      affectedBytes: json['affectedBytes'] is num
          ? (json['affectedBytes'] as num).toInt()
          : 0,
    );
  }

  static Map<StorageFileCategory, int> _categoryBytesFromJson(
    Object? value, {
    required int fallbackDownloadBytes,
  }) {
    final result = <StorageFileCategory, int>{};
    if (value is Map<Object?, Object?>) {
      for (final entry in value.entries) {
        if (entry.key is! String || entry.value is! num) continue;
        for (final category in StorageFileCategory.values) {
          if (category.name == entry.key) {
            result[category] = (entry.value as num).toInt();
            break;
          }
        }
      }
    }
    if (result.isEmpty && fallbackDownloadBytes > 0) {
      result[StorageFileCategory.download] = fallbackDownloadBytes;
    }
    return Map.unmodifiable(result);
  }
}

enum StorageHistoryEventType { scan, cleanup }

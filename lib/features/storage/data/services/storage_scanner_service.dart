import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/models/scanned_file.dart';
import '../../domain/models/storage_intelligence_report.dart';
import '../../domain/models/storage_stats.dart';

/// Scans user-accessible Android storage through the platform channel.
final class StorageScannerService {
  StorageScannerService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'ai.spacepilot.app/storage_scanner';
  final MethodChannel _channel;

  /// Returns every file discovered by the storage intelligence scan.
  ///
  /// Prefer [scanIntelligence] for new features.
  Future<List<ScannedFile>> scan() async {
    final report = await scanIntelligence();
    return report.files;
  }

  /// Returns a full storage intelligence report.
  ///
  /// Storage read access (all-files access on Android 11+) must be granted
  /// before calling this method.
  Future<StorageIntelligenceReport> scanIntelligence() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('StorageScannerService is Android-only.');
    }

    final result = await _channel.invokeMethod<Object?>(
      'scanStorageIntelligence',
    );
    if (result == null) return StorageIntelligenceReport.empty();

    if (result is List<Object?>) {
      return _reportFromLegacyFiles(result);
    }
    if (result is Map<Object?, Object?>) {
      return _reportFromMap(result);
    }

    throw StateError('Storage scanner returned an invalid payload.');
  }
}

StorageIntelligenceReport _reportFromLegacyFiles(List<Object?> files) {
  final insights = files
      .whereType<Map<Object?, Object?>>()
      .map((file) {
        try {
          final scannedFile = _scannedFileFromMap(file);
          return StorageFileInsight(
            file: scannedFile,
            categories: _categoriesForFile(scannedFile),
          );
        } on FormatException {
          return null;
        }
      })
      .nonNulls
      .toList(growable: false);
  final completedAt = DateTime.now();

  return StorageIntelligenceReport(
    storageStats: StorageStats(
      totalBytes: 0,
      usedBytes: 0,
      freeBytes: 0,
      deviceHealthScore: 0,
      lastUpdated: completedAt,
    ),
    fileInsights: insights,
    largestFolders: _deriveLargestFolders(insights),
    emptyFolders: const [],
    categorySummaries: _deriveCategorySummaries(insights),
    scannedRootPaths: const [],
    completedAt: completedAt,
  );
}

StorageIntelligenceReport _reportFromMap(Map<Object?, Object?> map) {
  final completedAt = _dateTimeFromMilliseconds(map['completedAt']);
  final stats = map['storageStats'];
  final files = map['files'];
  final largestFolders = map['largestFolders'];
  final emptyFolders = map['emptyFolders'];
  final categorySummaries = map['categorySummaries'];
  final scannedRootPaths = map['scannedRootPaths'];

  final insights = files is List<Object?>
      ? files
            .whereType<Map<Object?, Object?>>()
            .map((file) {
              try {
                return _fileInsightFromMap(file);
              } on FormatException {
                return null;
              }
            })
            .nonNulls
            .toList(growable: false)
      : const <StorageFileInsight>[];

  return StorageIntelligenceReport(
    storageStats: stats is Map<Object?, Object?>
        ? _storageStatsFromMap(stats, completedAt)
        : StorageStats(
            totalBytes: 0,
            usedBytes: 0,
            freeBytes: 0,
            deviceHealthScore: 0,
            lastUpdated: completedAt,
          ),
    fileInsights: insights,
    largestFolders: largestFolders is List<Object?>
        ? largestFolders
              .whereType<Map<Object?, Object?>>()
              .map((folder) {
                try {
                  return _folderSummaryFromMap(folder);
                } on FormatException {
                  return null;
                }
              })
              .nonNulls
              .toList(growable: false)
        : _deriveLargestFolders(insights),
    emptyFolders: emptyFolders is List<Object?>
        ? emptyFolders
              .whereType<Map<Object?, Object?>>()
              .map((folder) {
                try {
                  return _emptyFolderFromMap(folder);
                } on FormatException {
                  return null;
                }
              })
              .nonNulls
              .toList(growable: false)
        : const [],
    categorySummaries: categorySummaries is List<Object?>
        ? categorySummaries
              .whereType<Map<Object?, Object?>>()
              .map((summary) {
                try {
                  return _categorySummaryFromMap(summary);
                } on FormatException {
                  return null;
                }
              })
              .nonNulls
              .toList(growable: false)
        : _deriveCategorySummaries(insights),
    scannedRootPaths: scannedRootPaths is List<Object?>
        ? scannedRootPaths.whereType<String>().toList(growable: false)
        : const [],
    completedAt: completedAt,
  );
}

StorageFileInsight _fileInsightFromMap(Map<Object?, Object?> map) {
  final file = _scannedFileFromMap(map);
  final categories = map['categories'];

  return StorageFileInsight(
    file: file,
    categories: categories is List<Object?>
        ? categories
              .whereType<String>()
              .map(_categoryFromString)
              .nonNulls
              .toSet()
        : _categoriesForFile(file),
  );
}

ScannedFile _scannedFileFromMap(Map<Object?, Object?> map) {
  final filename = map['filename'];
  final path = map['path'];
  final size = map['size'];
  final lastModified = map['lastModified'];
  final previewPath = map['previewPath'];
  final previewType = map['previewType'];

  if (filename is! String ||
      path is! String ||
      size is! num ||
      lastModified is! num) {
    throw const FormatException('Invalid scanned file payload.');
  }

  final safeSize = size.toInt();

  return ScannedFile(
    filename: filename,
    path: path,
    size: safeSize < 0 ? 0 : safeSize,
    lastModified: DateTime.fromMillisecondsSinceEpoch(lastModified.toInt()),
    previewPath: previewPath is String && previewPath.isNotEmpty
        ? previewPath
        : null,
    previewType: previewType is String && previewType.isNotEmpty
        ? previewType
        : null,
  );
}

StorageStats _storageStatsFromMap(
  Map<Object?, Object?> map,
  DateTime fallbackDate,
) {
  final totalBytes = _safeBytes(map['totalBytes']);
  final freeBytes = _safeBytes(map['freeBytes']).clamp(0, totalBytes).toInt();
  final reportedUsedBytes = _safeBytes(map['usedBytes']);
  final usedBytes = reportedUsedBytes
      .clamp(0, totalBytes - freeBytes)
      .toInt();
  final capturedAt = _dateTimeFromMilliseconds(map['capturedAt'], fallbackDate);

  return StorageStats(
    totalBytes: totalBytes,
    usedBytes: usedBytes,
    freeBytes: freeBytes,
    deviceHealthScore: 0,
    lastUpdated: capturedAt,
  );
}

StorageFolderSummary _folderSummaryFromMap(Map<Object?, Object?> map) {
  final path = map['path'];
  final sizeBytes = map['sizeBytes'];
  final fileCount = map['fileCount'];

  if (path is! String || sizeBytes is! num || fileCount is! num) {
    throw const FormatException('Invalid folder summary payload.');
  }

  return StorageFolderSummary(
    path: path,
    sizeBytes: _safeBytes(sizeBytes),
    fileCount: fileCount.toInt().clamp(0, 1 << 62).toInt(),
    lastModified: _optionalDateTimeFromMilliseconds(map['lastModified']),
  );
}

EmptyFolder _emptyFolderFromMap(Map<Object?, Object?> map) {
  final path = map['path'];
  if (path is! String) {
    throw const FormatException('Invalid empty folder payload.');
  }

  return EmptyFolder(
    path: path,
    lastModified: _optionalDateTimeFromMilliseconds(map['lastModified']),
  );
}

StorageCategorySummary _categorySummaryFromMap(Map<Object?, Object?> map) {
  final category = map['category'];
  final fileCount = map['fileCount'];
  final totalBytes = map['totalBytes'];
  final parsedCategory = category is String ? _categoryFromString(category) : null;

  if (parsedCategory == null || fileCount is! num || totalBytes is! num) {
    throw const FormatException('Invalid category summary payload.');
  }

  return StorageCategorySummary(
    category: parsedCategory,
    fileCount: fileCount.toInt().clamp(0, 1 << 62).toInt(),
    totalBytes: _safeBytes(totalBytes),
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

  return folders.take(20).toList(growable: false);
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

Set<StorageFileCategory> _categoriesForFile(ScannedFile file) {
  final extension = _extension(file.filename);
  final path = file.path.replaceAll('\\', '/').toLowerCase();
  final categories = <StorageFileCategory>{};

  if (_imageExtensions.contains(extension)) {
    categories.add(StorageFileCategory.image);
  }
  if (_videoExtensions.contains(extension)) {
    categories.add(StorageFileCategory.video);
  }
  if (_audioExtensions.contains(extension)) {
    categories.add(StorageFileCategory.audio);
  }
  if (_documentExtensions.contains(extension)) {
    categories.add(StorageFileCategory.document);
  }
  if (extension == 'apk') categories.add(StorageFileCategory.apk);
  if (_zipExtensions.contains(extension)) categories.add(StorageFileCategory.zip);
  if (path.contains('/download/')) categories.add(StorageFileCategory.download);
  if (categories.isEmpty) categories.add(StorageFileCategory.other);

  return categories;
}

StorageFileCategory? _categoryFromString(String value) {
  return switch (value) {
    'image' => StorageFileCategory.image,
    'video' => StorageFileCategory.video,
    'audio' => StorageFileCategory.audio,
    'document' => StorageFileCategory.document,
    'apk' => StorageFileCategory.apk,
    'zip' => StorageFileCategory.zip,
    'download' => StorageFileCategory.download,
    'other' => StorageFileCategory.other,
    _ => null,
  };
}

DateTime _dateTimeFromMilliseconds(Object? value, [DateTime? fallback]) {
  return _optionalDateTimeFromMilliseconds(value) ?? fallback ?? DateTime.now();
}

DateTime? _optionalDateTimeFromMilliseconds(Object? value) {
  if (value is! num) return null;
  return DateTime.fromMillisecondsSinceEpoch(value.toInt());
}

int _safeBytes(Object? value) {
  if (value is! num) return 0;
  final bytes = value.toInt();
  return bytes < 0 ? 0 : bytes;
}

String _parentDirectory(String path) {
  final normalized = path.replaceAll('\\', '/');
  final lastSeparator = normalized.lastIndexOf('/');
  if (lastSeparator <= 0) return path;
  return normalized.substring(0, lastSeparator);
}

String _extension(String filename) {
  final dotIndex = filename.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == filename.length - 1) return '';
  return filename.substring(dotIndex + 1).toLowerCase();
}

const Set<String> _imageExtensions = {
  'gif',
  'heic',
  'jpeg',
  'jpg',
  'png',
  'raw',
  'webp',
};

const Set<String> _videoExtensions = {
  '3gp',
  'avi',
  'm4v',
  'mkv',
  'mov',
  'mp4',
  'webm',
};

const Set<String> _audioExtensions = {
  'aac',
  'flac',
  'm4a',
  'mp3',
  'ogg',
  'opus',
  'wav',
  'wma',
};

const Set<String> _documentExtensions = {
  'csv',
  'doc',
  'docx',
  'epub',
  'odp',
  'ods',
  'odt',
  'pdf',
  'ppt',
  'pptx',
  'rtf',
  'txt',
  'xls',
  'xlsx',
};

const Set<String> _zipExtensions = {'7z', 'gz', 'rar', 'tar', 'zip'};

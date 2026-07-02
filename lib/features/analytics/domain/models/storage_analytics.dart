import 'package:flutter/foundation.dart';

import '../../../storage/domain/models/scanned_file.dart';

@immutable
final class StorageAnalytics {
  const StorageAnalytics({
    required this.totalFiles,
    required this.totalBytes,
    required this.duplicateGroups,
    required this.duplicateBytes,
    required this.junkFileCount,
    required this.junkBytes,
    required this.unusedFileCount,
    required this.unusedBytes,
    required this.categories,
    required this.largestFiles,
  });

  final int totalFiles;
  final int totalBytes;
  final int duplicateGroups;
  final int duplicateBytes;
  final int junkFileCount;
  final int junkBytes;
  final int unusedFileCount;
  final int unusedBytes;
  final List<FileCategoryBreakdown> categories;
  final List<ScannedFile> largestFiles;
}

@immutable
final class FileCategoryBreakdown {
  const FileCategoryBreakdown({
    required this.category,
    required this.fileCount,
    required this.bytes,
  });

  final FileAnalyticsCategory category;
  final int fileCount;
  final int bytes;
}

enum FileAnalyticsCategory {
  images('Images'),
  videos('Videos'),
  audio('Audio'),
  documents('Documents'),
  archives('Archives'),
  installers('Installers'),
  other('Other');

  const FileAnalyticsCategory(this.label);

  final String label;
}

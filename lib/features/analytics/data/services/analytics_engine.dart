import '../../../duplicates/domain/models/duplicate_group.dart';
import '../../../storage/domain/models/scanned_file.dart';
import '../../domain/models/storage_analytics.dart';

final class AnalyticsEngine {
  const AnalyticsEngine();

  StorageAnalytics analyze({
    required Iterable<ScannedFile> files,
    required Iterable<DuplicateGroup> duplicateGroups,
    DateTime? now,
  }) {
    final scannedFiles = files.toList(growable: false);
    final referenceDate = now ?? DateTime.now();
    final unusedBefore = referenceDate.subtract(const Duration(days: 180));

    final categoryStats = <FileAnalyticsCategory, _CategoryAccumulator>{};
    var junkFileCount = 0;
    var junkBytes = 0;
    var unusedFileCount = 0;
    var unusedBytes = 0;

    for (final file in scannedFiles) {
      final category = _categoryFor(file);
      categoryStats
          .putIfAbsent(category, _CategoryAccumulator.new)
          .add(file.size);

      if (_isJunk(file)) {
        junkFileCount++;
        junkBytes += file.size;
      }

      if (file.lastModified.isBefore(unusedBefore)) {
        unusedFileCount++;
        unusedBytes += file.size;
      }
    }

    final categories = categoryStats.entries
        .map(
          (entry) => FileCategoryBreakdown(
            category: entry.key,
            fileCount: entry.value.fileCount,
            bytes: entry.value.bytes,
          ),
        )
        .toList(growable: false)
      ..sort((a, b) => b.bytes.compareTo(a.bytes));

    final duplicates = duplicateGroups.toList(growable: false);
    final largestFiles = [...scannedFiles]
      ..sort((a, b) => b.size.compareTo(a.size));

    return StorageAnalytics(
      totalFiles: scannedFiles.length,
      totalBytes: scannedFiles.fold<int>(0, (total, file) => total + file.size),
      duplicateGroups: duplicates.length,
      duplicateBytes: duplicates.fold<int>(
        0,
        (total, group) => total + group.recoverableBytes,
      ),
      junkFileCount: junkFileCount,
      junkBytes: junkBytes,
      unusedFileCount: unusedFileCount,
      unusedBytes: unusedBytes,
      categories: categories,
      largestFiles: largestFiles.take(5).toList(growable: false),
    );
  }

  FileAnalyticsCategory _categoryFor(ScannedFile file) {
    final extension = _extension(file);

    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'].contains(extension)) {
      return FileAnalyticsCategory.images;
    }
    if (['mp4', 'mov', 'mkv', 'avi', 'webm'].contains(extension)) {
      return FileAnalyticsCategory.videos;
    }
    if (['mp3', 'wav', 'm4a', 'aac', 'ogg'].contains(extension)) {
      return FileAnalyticsCategory.audio;
    }
    if (['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt'].contains(
      extension,
    )) {
      return FileAnalyticsCategory.documents;
    }
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(extension)) {
      return FileAnalyticsCategory.archives;
    }
    if (extension == 'apk') return FileAnalyticsCategory.installers;

    return FileAnalyticsCategory.other;
  }

  bool _isJunk(ScannedFile file) {
    final name = file.filename.toLowerCase();
    final path = file.path.toLowerCase().replaceAll('\\', '/');

    return name.endsWith('.tmp') ||
        name.endsWith('.log') ||
        name.endsWith('.bak') ||
        path.contains('/cache/') ||
        path.contains('/temp/');
  }

  String _extension(ScannedFile file) {
    final name = file.filename.toLowerCase();
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1);
  }
}

final class _CategoryAccumulator {
  int fileCount = 0;
  int bytes = 0;

  void add(int fileBytes) {
    fileCount++;
    bytes += fileBytes;
  }
}

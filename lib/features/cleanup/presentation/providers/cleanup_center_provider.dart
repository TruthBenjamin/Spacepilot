import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../duplicates/domain/models/duplicate_group.dart';
import '../../../duplicates/presentation/providers/duplicate_groups_provider.dart';
import '../../../storage/domain/models/scanned_file.dart';
import '../../../storage/domain/models/storage_intelligence_report.dart';
import '../../../storage/presentation/providers/storage_scan_provider.dart';
import '../../domain/models/cleanup_candidate.dart';

final cleanupCenterReportProvider = FutureProvider<CleanupCenterReport>((
  ref,
) async {
  final scan = await ref.watch(storageScanProvider.future);
  if (!scan.hasScanned) return const CleanupCenterReport.empty();

  final duplicateGroups = ref
      .watch(duplicateGroupsProvider)
      .maybeWhen(
        data: (groups) => groups,
        orElse: () => const <DuplicateGroup>[],
      );
  return buildCleanupCenterReport(
    files: scan.files,
    report: scan.intelligenceReport,
    duplicateGroups: duplicateGroups,
    now: DateTime.now(),
  );
});

CleanupCenterReport buildCleanupCenterReport({
  required Iterable<ScannedFile> files,
  required StorageIntelligenceReport? report,
  required Iterable<DuplicateGroup> duplicateGroups,
  required DateTime now,
}) {
  final scannedFiles = files.toList(growable: false);
  final duplicateCategory = _duplicateCategory(duplicateGroups);
  final duplicatePaths = duplicateCategory?.candidates
      .map((candidate) => candidate.path)
      .toSet();
  final categories =
      <CleanupCategory>[
            ?duplicateCategory,
            ..._fileCategories(
              scannedFiles,
              now,
              excludedPaths: duplicatePaths ?? const {},
            ),
            _emptyFolderCategory(report?.emptyFolders ?? const []),
          ]
          .where((category) => category.candidates.isNotEmpty)
          .toList(growable: false)
        ..sort((a, b) {
          final priority = a.priority.compareTo(b.priority);
          if (priority != 0) return priority;
          return b.recoverableBytes.compareTo(a.recoverableBytes);
        });

  return CleanupCenterReport(
    hasScanned: true,
    completedAt: report?.completedAt,
    categories: categories,
    scannedFileCount: scannedFiles.length,
    emptyFolderCount: report?.emptyFolders.length ?? 0,
  );
}

CleanupSelectionSummary summarizeCleanupSelection({
  required CleanupCenterReport report,
  required Set<String> selectedIds,
}) {
  final selectedFilesByPath = <String, ScannedFile>{};
  final selectedEmptyFolders = <EmptyFolder>[];
  final duplicateGroupsByHash = <String, DuplicateGroup>{};
  var selectedBytes = 0;

  for (final category in report.categories) {
    for (final candidate in category.candidates) {
      if (!selectedIds.contains(candidate.id)) continue;

      switch (candidate.type) {
        case CleanupCandidateType.file:
        case CleanupCandidateType.duplicateCopy:
          final file = candidate.file;
          if (file == null) continue;
          if (!selectedFilesByPath.containsKey(file.path)) {
            selectedFilesByPath[file.path] = file;
            selectedBytes += file.size;
          }
          final group = candidate.duplicateGroup;
          if (group != null) duplicateGroupsByHash[group.sha256Hash] = group;
          break;
        case CleanupCandidateType.emptyFolder:
          selectedEmptyFolders.add(
            EmptyFolder(
              path: candidate.path,
              lastModified: candidate.lastModified,
            ),
          );
          break;
      }
    }
  }

  return CleanupSelectionSummary(
    files: selectedFilesByPath.values.toList(growable: false),
    emptyFolders: selectedEmptyFolders,
    duplicateGroups: duplicateGroupsByHash.values.toList(growable: false),
    selectedBytes: selectedBytes,
  );
}

CleanupSelectionSummary summarizeAutomaticJunkSelection({
  required CleanupCenterReport report,
}) {
  final automaticIds = <String>{
    for (final category in report.categories)
      if (category.id == _CleanupRule.junk.name)
        for (final candidate in category.candidates)
          if (candidate.riskLevel == CleanupRiskLevel.usuallyRemovable)
            candidate.id,
  };

  return summarizeCleanupSelection(report: report, selectedIds: automaticIds);
}

CleanupCategory? _duplicateCategory(Iterable<DuplicateGroup> groups) {
  final candidates = <CleanupCandidate>[];
  for (final group in groups) {
    if (group.files.length < 2) continue;
    final keeper = group.files.reduce((a, b) {
      final modified = b.lastModified.compareTo(a.lastModified);
      if (modified != 0) return modified > 0 ? b : a;
      return a.path.compareTo(b.path) <= 0 ? a : b;
    });

    for (final file in group.files) {
      if (file.path == keeper.path) continue;
      candidates.add(
        CleanupCandidate.duplicateCopy(
          id: 'duplicate:${group.sha256Hash}:${file.path}',
          title: file.name,
          path: file.path,
          bytes: file.sizeBytes,
          lastModified: file.lastModified,
          riskLevel: CleanupRiskLevel.keepOneCopy,
          reason:
              'Exact duplicate by size and SHA-256 hash. SpacePilot keeps one copy in each group.',
          duplicateGroup: group,
          file: ScannedFile(
            filename: file.name,
            path: file.path,
            size: file.sizeBytes,
            lastModified: file.lastModified,
          ),
        ),
      );
    }
  }

  if (candidates.isEmpty) return null;
  candidates.sort((a, b) => b.bytes.compareTo(a.bytes));
  return CleanupCategory(
    id: 'duplicates',
    title: 'Exact duplicate copies',
    description:
        'Only extra copies are selected. One copy from every duplicate group is preserved.',
    riskLevel: CleanupRiskLevel.keepOneCopy,
    priority: 0,
    candidates: candidates,
  );
}

List<CleanupCategory> _fileCategories(
  List<ScannedFile> files,
  DateTime now, {
  required Set<String> excludedPaths,
}) {
  final oldScreenshotBefore = now.subtract(const Duration(days: 90));
  final oldFileBefore = now.subtract(const Duration(days: 180));
  final oldApkBefore = now.subtract(const Duration(days: 30));
  final grouped = <_CleanupRule, List<CleanupCandidate>>{
    for (final rule in _CleanupRule.values) rule: [],
  };
  final assignedPaths = <String>{};

  for (final file in files) {
    if (excludedPaths.contains(file.path)) continue;
    final rule = _ruleForFile(
      file,
      oldScreenshotBefore: oldScreenshotBefore,
      oldFileBefore: oldFileBefore,
      oldApkBefore: oldApkBefore,
    );
    if (rule == null || !assignedPaths.add(file.path)) continue;

    grouped[rule]!.add(
      CleanupCandidate.file(
        id: 'file:${rule.name}:${file.path}',
        title: file.filename,
        path: file.path,
        bytes: file.size,
        lastModified: file.lastModified,
        riskLevel: rule.riskLevel,
        reason: rule.reason,
        file: file,
      ),
    );
  }

  return [
    for (final rule in _CleanupRule.values)
      if (grouped[rule]!.isNotEmpty)
        CleanupCategory(
          id: rule.name,
          title: rule.title,
          description: rule.description,
          riskLevel: rule.riskLevel,
          priority: rule.priority,
          candidates: grouped[rule]!
            ..sort((a, b) => b.bytes.compareTo(a.bytes)),
        ),
  ];
}

CleanupCategory _emptyFolderCategory(Iterable<EmptyFolder> folders) {
  final candidates = [
    for (final folder in folders)
      CleanupCandidate.emptyFolder(
        id: 'folder:${folder.path}',
        title: _basename(folder.path),
        path: folder.path,
        lastModified: folder.lastModified,
        riskLevel: CleanupRiskLevel.reviewRecommended,
        reason:
            'The storage scan reported this folder as empty. Review before removal if an app may recreate it.',
      ),
  ]..sort((a, b) => a.path.compareTo(b.path));

  return CleanupCategory(
    id: 'emptyFolders',
    title: 'Empty folders',
    description:
        'Folders with no files from the last scan. They free little space but reduce clutter.',
    riskLevel: CleanupRiskLevel.reviewRecommended,
    priority: 7,
    candidates: candidates,
  );
}

_CleanupRule? _ruleForFile(
  ScannedFile file, {
  required DateTime oldScreenshotBefore,
  required DateTime oldFileBefore,
  required DateTime oldApkBefore,
}) {
  final extension = _extension(file.filename);
  final normalizedPath = file.path.toLowerCase().replaceAll('\\', '/');
  final name = file.filename.toLowerCase();

  if (_isJunk(name, normalizedPath)) return _CleanupRule.junk;
  if (extension == 'apk' && file.lastModified.isBefore(oldApkBefore)) {
    return _CleanupRule.oldApks;
  }
  if (_isScreenshot(name, normalizedPath) &&
      file.lastModified.isBefore(oldScreenshotBefore)) {
    return _CleanupRule.oldScreenshots;
  }
  if (_isDownload(normalizedPath)) return _CleanupRule.downloads;
  if (file.size >= 100 * 1024 * 1024) return _CleanupRule.largeFiles;
  if (file.lastModified.isBefore(oldFileBefore)) return _CleanupRule.oldFiles;
  return null;
}

bool _isJunk(String name, String path) {
  return name.endsWith('.tmp') ||
      name.endsWith('.temp') ||
      name.endsWith('.log') ||
      name.endsWith('.bak') ||
      name.endsWith('.dmp') ||
      name.endsWith('.crash') ||
      name == 'thumbs.db' ||
      name == '.ds_store' ||
      path.contains('/.cache/') ||
      path.contains('/cache/') ||
      path.contains('/cached/') ||
      path.contains('/logs/') ||
      path.contains('/temp/') ||
      path.contains('/tmp/');
}

bool _isDownload(String path) {
  return path.contains('/download/') || path.contains('/downloads/');
}

bool _isScreenshot(String name, String path) {
  return name.contains('screenshot') || path.contains('/screenshots/');
}

String _extension(String filename) {
  final dotIndex = filename.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == filename.length - 1) return '';
  return filename.substring(dotIndex + 1).toLowerCase();
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final trimmed = normalized.replaceFirst(RegExp(r'/+$'), '');
  final index = trimmed.lastIndexOf('/');
  if (index < 0 || index == trimmed.length - 1) return trimmed;
  return trimmed.substring(index + 1);
}

enum _CleanupRule {
  junk(
    title: 'Temp, cache, and log files',
    description:
        'Matched deterministic temp/cache/log filename or folder rules.',
    reason:
        'Matched deterministic temp, cache, log, or backup filename/folder rules.',
    riskLevel: CleanupRiskLevel.usuallyRemovable,
    priority: 1,
  ),
  oldApks(
    title: 'Old APK installers',
    description:
        'APK installer files older than 30 days. Review before deleting sideloaded installers.',
    reason:
        'APK installer older than 30 days. Review if you need to reinstall it.',
    riskLevel: CleanupRiskLevel.reviewRecommended,
    priority: 2,
  ),
  downloads(
    title: 'Downloads',
    description:
        'Files in Download folders. These are common cleanup candidates, but content should be reviewed.',
    reason: 'Located in a Download folder. Review recommended.',
    riskLevel: CleanupRiskLevel.reviewRecommended,
    priority: 3,
  ),
  oldScreenshots(
    title: 'Screenshots older than 90 days',
    description:
        'Screenshot files older than 90 days. Review because some screenshots may still matter.',
    reason: 'Screenshot older than 90 days. Review recommended.',
    riskLevel: CleanupRiskLevel.reviewRecommended,
    priority: 4,
  ),
  largeFiles(
    title: 'Large files',
    description:
        'Files larger than 100 MB. High impact, but not automatically safe.',
    reason: 'File is larger than 100 MB. Review recommended.',
    riskLevel: CleanupRiskLevel.reviewRecommended,
    priority: 5,
  ),
  oldFiles(
    title: 'Files older than 180 days',
    description:
        'Files not modified in more than 180 days. Age alone does not make them safe to delete.',
    reason: 'Not modified in more than 180 days. Review recommended.',
    riskLevel: CleanupRiskLevel.reviewRecommended,
    priority: 6,
  );

  const _CleanupRule({
    required this.title,
    required this.description,
    required this.reason,
    required this.riskLevel,
    required this.priority,
  });

  final String title;
  final String description;
  final String reason;
  final CleanupRiskLevel riskLevel;
  final int priority;
}

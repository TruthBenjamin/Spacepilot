import 'package:flutter/foundation.dart';

import '../../../duplicates/domain/models/duplicate_group.dart';
import '../../../storage/domain/models/scanned_file.dart';
import '../../../storage/domain/models/storage_intelligence_report.dart';

enum CleanupCandidateType { file, duplicateCopy, emptyFolder }

enum CleanupRiskLevel {
  usuallyRemovable('Usually removable'),
  reviewRecommended('Review recommended'),
  keepOneCopy('Keep one copy');

  const CleanupRiskLevel(this.label);

  final String label;
}

@immutable
final class CleanupCandidate {
  const CleanupCandidate.file({
    required this.id,
    required this.title,
    required this.path,
    required this.bytes,
    required this.lastModified,
    required this.riskLevel,
    required this.reason,
    this.file,
    this.duplicateGroup,
  }) : type = CleanupCandidateType.file;

  const CleanupCandidate.duplicateCopy({
    required this.id,
    required this.title,
    required this.path,
    required this.bytes,
    required this.lastModified,
    required this.riskLevel,
    required this.reason,
    required this.duplicateGroup,
    this.file,
  }) : type = CleanupCandidateType.duplicateCopy;

  const CleanupCandidate.emptyFolder({
    required this.id,
    required this.title,
    required this.path,
    required this.lastModified,
    required this.riskLevel,
    required this.reason,
  }) : type = CleanupCandidateType.emptyFolder,
       bytes = 0,
       file = null,
       duplicateGroup = null;

  final String id;
  final String title;
  final String path;
  final int bytes;
  final DateTime? lastModified;
  final CleanupCandidateType type;
  final CleanupRiskLevel riskLevel;
  final String reason;
  final ScannedFile? file;
  final DuplicateGroup? duplicateGroup;
}

@immutable
final class CleanupCategory {
  const CleanupCategory({
    required this.id,
    required this.title,
    required this.description,
    required this.riskLevel,
    required this.priority,
    required this.candidates,
  });

  final String id;
  final String title;
  final String description;
  final CleanupRiskLevel riskLevel;
  final int priority;
  final List<CleanupCandidate> candidates;

  int get recoverableBytes {
    final paths = <String>{};
    var total = 0;
    for (final candidate in candidates) {
      if (candidate.type == CleanupCandidateType.emptyFolder) continue;
      if (paths.add(candidate.path)) total += candidate.bytes;
    }
    return total;
  }

  int get actionableCount => candidates.length;
}

@immutable
final class CleanupCenterReport {
  const CleanupCenterReport({
    required this.hasScanned,
    required this.completedAt,
    required this.categories,
    required this.scannedFileCount,
    required this.emptyFolderCount,
  });

  const CleanupCenterReport.empty()
    : hasScanned = false,
      completedAt = null,
      categories = const [],
      scannedFileCount = 0,
      emptyFolderCount = 0;

  final bool hasScanned;
  final DateTime? completedAt;
  final List<CleanupCategory> categories;
  final int scannedFileCount;
  final int emptyFolderCount;

  int get recoverableBytes {
    final paths = <String>{};
    var total = 0;
    for (final category in categories) {
      for (final candidate in category.candidates) {
        if (candidate.type == CleanupCandidateType.emptyFolder) continue;
        if (paths.add(candidate.path)) total += candidate.bytes;
      }
    }
    return total;
  }

  int get candidateCount {
    return categories.fold<int>(
      0,
      (total, category) => total + category.actionableCount,
    );
  }
}

@immutable
final class CleanupSelectionSummary {
  const CleanupSelectionSummary({
    required this.files,
    required this.emptyFolders,
    required this.duplicateGroups,
    required this.selectedBytes,
  });

  final List<ScannedFile> files;
  final List<EmptyFolder> emptyFolders;
  final List<DuplicateGroup> duplicateGroups;
  final int selectedBytes;

  int get fileCount => files.length;
  int get emptyFolderCount => emptyFolders.length;
  bool get isEmpty => fileCount == 0 && emptyFolderCount == 0;
}

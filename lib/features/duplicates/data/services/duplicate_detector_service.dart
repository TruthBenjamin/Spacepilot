import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../domain/models/models.dart';

final class DuplicateDetectorService {
  const DuplicateDetectorService();

  Future<List<DuplicateGroup>> findDuplicatesInDirectory(
    Directory root, {
    bool recursive = true,
    bool followLinks = false,
    int minSizeBytes = 0,
  }) async {
    final files = <File>[];

    try {
      await for (final entity in root.list(
        recursive: recursive,
        followLinks: followLinks,
      )) {
        if (entity is File) {
          files.add(entity);
        }
      }
    } on FileSystemException {
      return const [];
    }

    return findDuplicates(files, minSizeBytes: minSizeBytes);
  }

  Future<List<DuplicateGroup>> findDuplicates(
    Iterable<File> files, {
    int minSizeBytes = 0,
  }) async {
    final candidatesBySize = <int, List<_FileCandidate>>{};

    for (final file in files) {
      final candidate = await _candidateFor(file);
      if (candidate == null || candidate.sizeBytes < minSizeBytes) continue;

      candidatesBySize
          .putIfAbsent(candidate.sizeBytes, () => <_FileCandidate>[])
          .add(candidate);
    }

    final groups = <DuplicateGroup>[];

    for (final sameSizeFiles in candidatesBySize.values) {
      if (sameSizeFiles.length < 2) continue;

      final candidatesByHash = <String, List<_FileCandidate>>{};
      for (final candidate in sameSizeFiles) {
        final hash = await _sha256Hash(candidate.file);
        if (hash == null) continue;
        candidatesByHash
            .putIfAbsent(hash, () => <_FileCandidate>[])
            .add(candidate);
      }

      for (final entry in candidatesByHash.entries) {
        final duplicates = entry.value;
        if (duplicates.length < 2) continue;

        duplicates.sort((a, b) => a.path.compareTo(b.path));
        groups.add(
          DuplicateGroup(
            sha256Hash: entry.key,
            sizeBytes: duplicates.first.sizeBytes,
            files: duplicates.map(_toDuplicateFile).toList(growable: false),
          ),
        );
      }
    }

    groups.sort((a, b) {
      final recoverableComparison = b.recoverableBytes.compareTo(
        a.recoverableBytes,
      );
      if (recoverableComparison != 0) return recoverableComparison;

      return a.sha256Hash.compareTo(b.sha256Hash);
    });

    return groups;
  }

  Future<_FileCandidate?> _candidateFor(File file) async {
    try {
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) return null;

      return _FileCandidate(
        file: file,
        path: file.absolute.path,
        sizeBytes: stat.size,
        lastModified: stat.modified,
      );
    } on FileSystemException {
      return null;
    } on Exception {
      return null;
    }
  }

  Future<String?> _sha256Hash(File file) async {
    try {
      final digest = await sha256.bind(file.openRead()).first;
      return digest.toString();
    } on FileSystemException {
      return null;
    } on Exception {
      return null;
    }
  }

  DuplicateFile _toDuplicateFile(_FileCandidate candidate) {
    return DuplicateFile(
      name: p.basename(candidate.path),
      path: candidate.path,
      sizeBytes: candidate.sizeBytes,
      lastModified: candidate.lastModified,
    );
  }
}

final class _FileCandidate {
  const _FileCandidate({
    required this.file,
    required this.path,
    required this.sizeBytes,
    required this.lastModified,
  });

  final File file;
  final String path;
  final int sizeBytes;
  final DateTime lastModified;
}

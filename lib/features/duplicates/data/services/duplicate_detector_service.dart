import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../storage/domain/models/scanned_file.dart';
import '../../domain/models/models.dart';

final class DuplicateDetectorService {
  const DuplicateDetectorService();

  Future<List<DuplicateGroup>> findDuplicatesInDirectory(
    Directory root, {
    bool recursive = true,
    bool followLinks = false,
    int minSizeBytes = 0,
  }) async {
    final candidatesBySize = <int, List<_FileCandidate>>{};

    try {
      await for (final entity in root.list(
        recursive: recursive,
        followLinks: followLinks,
      )) {
        if (entity is! File) continue;
        final candidate = await _candidateFor(entity);
        if (candidate == null || candidate.sizeBytes < minSizeBytes) continue;
        candidatesBySize
            .putIfAbsent(candidate.sizeBytes, () => <_FileCandidate>[])
            .add(candidate);
      }
    } on FileSystemException {
      return const [];
    }

    return _findDuplicateGroups(candidatesBySize);
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

    return _findDuplicateGroups(candidatesBySize);
  }

  Future<List<DuplicateGroup>> findDuplicatesInScannedFiles(
    Iterable<ScannedFile> files, {
    int minSizeBytes = 0,
  }) async {
    final candidatesBySize = <int, List<_FileCandidate>>{};

    for (final file in files) {
      final candidate = _candidateForScannedFile(file);
      if (candidate == null || candidate.sizeBytes < minSizeBytes) continue;
      candidatesBySize
          .putIfAbsent(candidate.sizeBytes, () => <_FileCandidate>[])
          .add(candidate);
    }

    return _findDuplicateGroups(candidatesBySize);
  }

  Future<List<DuplicateGroup>> _findDuplicateGroups(
    Map<int, List<_FileCandidate>> candidatesBySize,
  ) async {
    final groups = <DuplicateGroup>[];

    for (final sameSizeFiles in candidatesBySize.values) {
      if (sameSizeFiles.length < 2) continue;

      final candidatesByHash = <String, List<_FileCandidate>>{};
      for (final candidate in sameSizeFiles) {
        final hash = await _sha256Hash(candidate);
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
      final path = file.absolute.path;
      if (!_isSupportedDuplicateFile(path)) return null;

      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) return null;

      return _FileCandidate(
        name: p.basename(path),
        path: path,
        sizeBytes: stat.size,
        lastModified: stat.modified,
      );
    } on FileSystemException {
      return null;
    } on Exception {
      return null;
    }
  }

  _FileCandidate? _candidateForScannedFile(ScannedFile file) {
    if (!_isSupportedDuplicateFile(file.filename) &&
        !_isSupportedDuplicateFile(file.path)) {
      return null;
    }

    return _FileCandidate(
      name: file.filename,
      path: file.path,
      sizeBytes: file.size,
      lastModified: file.lastModified,
    );
  }

  Future<String?> _sha256Hash(_FileCandidate candidate) async {
    try {
      final file = File(candidate.path);
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file ||
          stat.size != candidate.sizeBytes) {
        return null;
      }

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
      name: candidate.name,
      path: candidate.path,
      sizeBytes: candidate.sizeBytes,
      lastModified: candidate.lastModified,
    );
  }

  bool _isSupportedDuplicateFile(String path) {
    final extension = p.extension(path).replaceFirst('.', '').toLowerCase();
    return _imageExtensions.contains(extension) ||
        _videoExtensions.contains(extension) ||
        _documentExtensions.contains(extension) ||
        _audioExtensions.contains(extension);
  }
}

final class _FileCandidate {
  const _FileCandidate({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.lastModified,
  });

  final String name;
  final String path;
  final int sizeBytes;
  final DateTime lastModified;
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

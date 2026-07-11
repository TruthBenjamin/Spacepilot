import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../duplicates/domain/models/duplicate_group.dart';

final class CleanupService {
  const CleanupService({this._allowedRootPaths});

  static const List<String> _androidCleanupRootPaths = [
    '/storage/emulated/0/Download',
    '/storage/emulated/0/DCIM',
    '/storage/emulated/0/Movies',
    '/storage/emulated/0/Pictures',
  ];
  static const String _confirmationRequiredMessage =
      'Deletion requires explicit user confirmation.';
  static const String _outsideAllowedRootsMessage =
      'Path is outside allowed cleanup folders.';
  static const String _protectedPathMessage =
      'Path is protected and cannot be deleted.';

  final List<String>? _allowedRootPaths;

  Future<CleanupResult> deleteFiles(
    Iterable<File> files, {
    required bool userConfirmed,
  }) async {
    final result = _CleanupResultBuilder();
    final paths = files.map((file) => file.absolute.path).toSet();

    if (!userConfirmed) {
      for (final path in paths) {
        result.failures[path] = _confirmationRequiredMessage;
      }
      return result.build();
    }

    for (final path in paths) {
      final file = File(path);
      try {
        if (!await file.exists()) {
          result.skipped.add(path);
          continue;
        }

        final safePath = await _safeFilePath(file);
        if (safePath == null) {
          result.failures[path] = _outsideAllowedRootsMessage;
          continue;
        }
        if (_isProtectedPath(safePath) || _isProtectedPath(path)) {
          result.failures[path] = _protectedPathMessage;
          continue;
        }

        await File(safePath).delete();
        result.deleted.add(safePath);
      } on FileSystemException catch (error) {
        result.failures[path] = _fileSystemErrorMessage(error);
      } on Exception catch (error) {
        result.failures[path] = error.toString();
      }
    }

    return result.build();
  }

  Future<CleanupResult> deleteDuplicates(
    Iterable<DuplicateGroup> groups, {
    required Set<String> selectedPaths,
    required bool userConfirmed,
  }) {
    final duplicateCopies = <File>[];
    final result = _CleanupResultBuilder();

    for (final group in groups) {
      final selectedInGroup = group.files
          .where((file) => selectedPaths.contains(file.path))
          .toList(growable: false);
      if (selectedInGroup.isEmpty) continue;

      if (selectedInGroup.length >= group.files.length) {
        for (final file in selectedInGroup) {
          result.failures[file.path] =
              'At least one copy from each duplicate group must be kept.';
        }
        continue;
      }

      duplicateCopies.addAll(selectedInGroup.map((file) => File(file.path)));
    }

    if (result.failures.isEmpty) {
      return deleteFiles(duplicateCopies, userConfirmed: userConfirmed);
    }

    return deleteFiles(duplicateCopies, userConfirmed: userConfirmed).then((
      cleanup,
    ) {
      result.deleted.addAll(cleanup.deletedPaths);
      result.skipped.addAll(cleanup.skippedPaths);
      result.failures.addAll(cleanup.failures);
      return result.build();
    });
  }

  Future<CleanupResult> deleteEmptyFolders(
    Iterable<Directory> folders, {
    required bool userConfirmed,
  }) async {
    final result = _CleanupResultBuilder();
    final paths = folders.map((folder) => folder.absolute.path).toSet().toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    if (!userConfirmed) {
      for (final path in paths) {
        result.failures[path] = _confirmationRequiredMessage;
      }
      return result.build();
    }

    for (final path in paths) {
      final directory = Directory(path);
      try {
        if (!await directory.exists()) {
          result.skipped.add(path);
          continue;
        }

        final safePath = await _safeDirectoryPath(directory);
        if (safePath == null) {
          result.failures[path] = _outsideAllowedRootsMessage;
          continue;
        }
        if (_isProtectedPath(safePath) ||
            _isProtectedPath(path) ||
            _isCleanupRoot(safePath) ||
            _isCleanupRoot(path)) {
          result.failures[path] = _protectedPathMessage;
          continue;
        }

        final safeDirectory = Directory(safePath);
        if (await safeDirectory.list(followLinks: false).isEmpty) {
          await safeDirectory.delete();
          result.deleted.add(safePath);
        } else {
          result.skipped.add(safePath);
        }
      } on FileSystemException catch (error) {
        result.failures[path] = _fileSystemErrorMessage(error);
      } on Exception catch (error) {
        result.failures[path] = error.toString();
      }
    }

    return result.build();
  }

  Future<String?> _safeFilePath(File file) async {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.file) return null;

    final resolved = await file.resolveSymbolicLinks();
    if (!_isAllowedCleanupPath(resolved) &&
        !_isAllowedCleanupPath(file.absolute.path)) {
      return null;
    }
    return resolved;
  }

  Future<String?> _safeDirectoryPath(Directory directory) async {
    final type = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (type != FileSystemEntityType.directory) return null;

    final resolved = await directory.resolveSymbolicLinks();
    if (!_isAllowedCleanupPath(resolved) &&
        !_isAllowedCleanupPath(directory.absolute.path)) {
      return null;
    }
    return resolved;
  }

  bool _isCleanupRoot(String path) {
    final normalizedPath = _normalizePath(path);
    return _cleanupRoots().any((root) => normalizedPath == root);
  }

  bool _isAllowedCleanupPath(String path) {
    if (_allowedRootPaths == null &&
        defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }

    final normalizedPath = _normalizePath(path);
    return _cleanupRoots().any((root) {
      return normalizedPath == root || normalizedPath.startsWith('$root/');
    });
  }

  List<String> _cleanupRoots() {
    return (_allowedRootPaths ?? _androidCleanupRootPaths)
        .map(_normalizePath)
        .toList(growable: false);
  }

  bool _isProtectedPath(String path) {
    final normalizedPath = _normalizePath(path).toLowerCase();
    if (_protectedPathPrefixes.any(
      (prefix) =>
          normalizedPath == prefix || normalizedPath.startsWith('$prefix/'),
    )) {
      return true;
    }

    return _protectedPathSegments.any(normalizedPath.contains);
  }

  String _fileSystemErrorMessage(FileSystemException error) {
    final message = error.message.trim();
    return message.isEmpty ? 'File operation failed.' : message;
  }

  String _normalizePath(String path) {
    return path.replaceAll('\\', '/').replaceFirst(RegExp(r'/+$'), '');
  }
}

const Set<String> _protectedPathPrefixes = {
  '/system',
  '/data',
  '/proc',
  '/dev',
  '/vendor',
  '/apex',
  '/product',
  '/sys',
  '/acct',
};

const Set<String> _protectedPathSegments = {
  '/android/data/',
  '/android/obb/',
  '/android/media/',
  '/.android_secure/',
};

final class CleanupResult {
  CleanupResult({
    required List<String> deletedPaths,
    required List<String> skippedPaths,
    required Map<String, String> failures,
  }) : deletedPaths = UnmodifiableListView(deletedPaths),
       skippedPaths = UnmodifiableListView(skippedPaths),
       failures = UnmodifiableMapView(failures);

  final UnmodifiableListView<String> deletedPaths;
  final UnmodifiableListView<String> skippedPaths;
  final UnmodifiableMapView<String, String> failures;

  int get deletedCount => deletedPaths.length;
  bool get hasFailures => failures.isNotEmpty;
}

final class _CleanupResultBuilder {
  final List<String> deleted = [];
  final List<String> skipped = [];
  final Map<String, String> failures = {};

  CleanupResult build() => CleanupResult(
    deletedPaths: deleted,
    skippedPaths: skipped,
    failures: failures,
  );
}

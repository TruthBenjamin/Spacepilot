import 'dart:collection';
import 'dart:io';

import '../../../duplicates/domain/models/duplicate_group.dart';

final class CleanupService {
  const CleanupService();

  Future<CleanupResult> deleteFiles(Iterable<File> files) async {
    final result = _CleanupResultBuilder();
    final paths = files.map((file) => file.absolute.path).toSet();

    for (final path in paths) {
      final file = File(path);
      try {
        if (!await file.exists()) {
          result.skipped.add(path);
          continue;
        }

        await file.delete();
        result.deleted.add(path);
      } on FileSystemException catch (error) {
        result.failures[path] = error.message;
      }
    }

    return result.build();
  }

  Future<CleanupResult> deleteDuplicates(
    Iterable<DuplicateGroup> groups, {
    required Set<String> selectedPaths,
  }) {
    final duplicateCopies = <File>[];

    for (final group in groups) {
      // The first file is the retained original and is never deleted here.
      duplicateCopies.addAll(
        group.files
            .skip(1)
            .where((file) => selectedPaths.contains(file.path))
            .map((file) => File(file.path)),
      );
    }

    return deleteFiles(duplicateCopies);
  }

  Future<CleanupResult> deleteEmptyFolders(Iterable<Directory> folders) async {
    final result = _CleanupResultBuilder();
    final paths = folders.map((folder) => folder.absolute.path).toSet().toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final path in paths) {
      final directory = Directory(path);
      try {
        if (!await directory.exists()) {
          result.skipped.add(path);
          continue;
        }

        if (await directory.list(followLinks: false).isEmpty) {
          await directory.delete();
          result.deleted.add(path);
        } else {
          result.skipped.add(path);
        }
      } on FileSystemException catch (error) {
        result.failures[path] = error.message;
      }
    }

    return result.build();
  }
}

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

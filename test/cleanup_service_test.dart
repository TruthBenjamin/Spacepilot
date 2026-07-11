import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/features/cleanup/data/services/services.dart';
import 'package:spacepilot/features/duplicates/domain/models/models.dart';

void main() {
  test('deleteFiles deletes only explicitly supplied files', () async {
    final root = await Directory.systemTemp.createTemp('cleanup_files_');
    addTearDown(() => root.delete(recursive: true));
    final selected = await File('${root.path}/selected.txt').writeAsString('x');
    final untouched = await File(
      '${root.path}/untouched.txt',
    ).writeAsString('y');
    final service = CleanupService(allowedRootPaths: [root.absolute.path]);

    final result = await service.deleteFiles([selected], userConfirmed: true);

    expect(result.deletedCount, 1);
    expect(await selected.exists(), isFalse);
    expect(await untouched.exists(), isTrue);
  });

  test('deleteFiles rejects files outside configured cleanup roots', () async {
    final allowedRoot = await Directory.systemTemp.createTemp(
      'cleanup_allowed_',
    );
    final outsideRoot = await Directory.systemTemp.createTemp(
      'cleanup_outside_',
    );
    addTearDown(() => allowedRoot.delete(recursive: true));
    addTearDown(() => outsideRoot.delete(recursive: true));

    final allowed = await File(
      '${allowedRoot.path}/allowed.txt',
    ).writeAsString('safe');
    final outside = await File(
      '${outsideRoot.path}/outside.txt',
    ).writeAsString('unsafe');
    final guardedService = CleanupService(
      allowedRootPaths: [allowedRoot.absolute.path],
    );

    final result = await guardedService.deleteFiles([
      allowed,
      outside,
    ], userConfirmed: true);

    expect(result.deletedPaths, contains(_pathEndingWith('/allowed.txt')));
    expect(
      result.failures,
      containsPair(
        outside.absolute.path,
        'Path is outside allowed cleanup folders.',
      ),
    );
    expect(await allowed.exists(), isFalse);
    expect(await outside.exists(), isTrue);
  });

  test('deleteFiles refuses to delete without explicit confirmation', () async {
    final root = await Directory.systemTemp.createTemp('cleanup_confirm_');
    addTearDown(() => root.delete(recursive: true));
    final selected = await File('${root.path}/selected.txt').writeAsString('x');
    final service = CleanupService(allowedRootPaths: [root.absolute.path]);

    final result = await service.deleteFiles([selected], userConfirmed: false);

    expect(result.deletedCount, 0);
    expect(
      result.failures,
      containsPair(
        selected.absolute.path,
        'Deletion requires explicit user confirmation.',
      ),
    );
    expect(await selected.exists(), isTrue);
  });

  test('deleteFiles refuses protected Android application folders', () async {
    final root = await Directory.systemTemp.createTemp('cleanup_protected_');
    addTearDown(() => root.delete(recursive: true));
    final protectedDirectory = await Directory(
      '${root.path}/Android/data/ai.spacepilot.app',
    ).create(recursive: true);
    final protectedFile = await File(
      '${protectedDirectory.path}/critical.db',
    ).writeAsString('critical');
    final guardedService = CleanupService(
      allowedRootPaths: [root.absolute.path],
    );

    final result = await guardedService.deleteFiles([
      protectedFile,
    ], userConfirmed: true);

    expect(result.deletedCount, 0);
    expect(
      result.failures,
      containsPair(
        protectedFile.absolute.path,
        'Path is protected and cannot be deleted.',
      ),
    );
    expect(await protectedFile.exists(), isTrue);
  });

  test('deleteDuplicates deletes selected copies while preserving one file', () async {
    final root = await Directory.systemTemp.createTemp('cleanup_duplicates_');
    addTearDown(() => root.delete(recursive: true));
    final original = await File(
      '${root.path}/original.txt',
    ).writeAsString('same');
    final copy = await File('${root.path}/copy.txt').writeAsString('same');
    final group = DuplicateGroup(
      sha256Hash: 'hash',
      sizeBytes: 4,
      files: [_duplicateFile(original), _duplicateFile(copy)],
    );
    final service = CleanupService(allowedRootPaths: [root.absolute.path]);

    final result = await service.deleteDuplicates(
      [group],
      selectedPaths: {original.path},
      userConfirmed: true,
    );

    expect(result.deletedCount, 1);
    expect(await original.exists(), isFalse);
    expect(await copy.exists(), isTrue);
  });

  test('deleteDuplicates refuses to delete every copy in a group', () async {
    final root = await Directory.systemTemp.createTemp('cleanup_duplicates_');
    addTearDown(() => root.delete(recursive: true));
    final original = await File(
      '${root.path}/original.txt',
    ).writeAsString('same');
    final copy = await File('${root.path}/copy.txt').writeAsString('same');
    final group = DuplicateGroup(
      sha256Hash: 'hash',
      sizeBytes: 4,
      files: [_duplicateFile(original), _duplicateFile(copy)],
    );
    final service = CleanupService(allowedRootPaths: [root.absolute.path]);

    final result = await service.deleteDuplicates(
      [group],
      selectedPaths: {original.path, copy.path},
      userConfirmed: true,
    );

    expect(result.deletedCount, 0);
    expect(result.failures.length, 2);
    expect(await original.exists(), isTrue);
    expect(await copy.exists(), isTrue);
  });

  test('deleteEmptyFolders skips non-empty folders', () async {
    final root = await Directory.systemTemp.createTemp('cleanup_folders_');
    addTearDown(() => root.delete(recursive: true));
    final empty = await Directory('${root.path}/empty').create();
    final nonEmpty = await Directory('${root.path}/non-empty').create();
    await File('${nonEmpty.path}/file.txt').writeAsString('content');
    final service = CleanupService(allowedRootPaths: [root.absolute.path]);

    final result = await service.deleteEmptyFolders([
      empty,
      nonEmpty,
    ], userConfirmed: true);

    expect(result.deletedPaths, contains(_pathEndingWith('/empty')));
    expect(result.skippedPaths, contains(_pathEndingWith('/non-empty')));
    expect(await empty.exists(), isFalse);
    expect(await nonEmpty.exists(), isTrue);
  });

  test('deleteEmptyFolders refuses cleanup roots', () async {
    final root = await Directory.systemTemp.createTemp('cleanup_root_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final guardedService = CleanupService(
      allowedRootPaths: [root.absolute.path],
    );

    final result = await guardedService.deleteEmptyFolders([
      root,
    ], userConfirmed: true);

    expect(result.deletedCount, 0);
    expect(
      result.failures,
      containsPair(
        root.absolute.path,
        'Path is protected and cannot be deleted.',
      ),
    );
    expect(await root.exists(), isTrue);
  });

  test('deleteFiles skips missing files without failing the cleanup', () async {
    final root = await Directory.systemTemp.createTemp('cleanup_missing_');
    addTearDown(() => root.delete(recursive: true));
    final missing = File('${root.path}/missing.txt');
    final service = CleanupService(allowedRootPaths: [root.absolute.path]);

    final result = await service.deleteFiles([missing], userConfirmed: true);

    expect(result.deletedCount, 0);
    expect(result.skippedPaths, contains(missing.absolute.path));
    expect(result.failures, isEmpty);
  });
}

DuplicateFile _duplicateFile(File file) {
  return DuplicateFile(
    name: file.uri.pathSegments.last,
    path: file.path,
    sizeBytes: file.lengthSync(),
    lastModified: file.lastModifiedSync(),
  );
}

Matcher _pathEndingWith(String suffix) {
  return predicate<String>(
    (path) => path.replaceAll('\\', '/').endsWith(suffix),
    'path ending with $suffix',
  );
}

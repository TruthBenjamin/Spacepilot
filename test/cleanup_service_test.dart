import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/features/cleanup/data/services/services.dart';
import 'package:spacepilot/features/duplicates/domain/models/models.dart';

void main() {
  const service = CleanupService();

  test('deleteFiles deletes only explicitly supplied files', () async {
    final root = await Directory.systemTemp.createTemp('cleanup_files_');
    addTearDown(() => root.delete(recursive: true));
    final selected = await File('${root.path}/selected.txt').writeAsString('x');
    final untouched = await File(
      '${root.path}/untouched.txt',
    ).writeAsString('y');

    final result = await service.deleteFiles([selected]);

    expect(result.deletedCount, 1);
    expect(await selected.exists(), isFalse);
    expect(await untouched.exists(), isTrue);
  });

  test('deleteDuplicates always keeps the first file in a group', () async {
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

    final result = await service.deleteDuplicates(
      [group],
      selectedPaths: {original.path, copy.path},
    );

    expect(result.deletedCount, 1);
    expect(await original.exists(), isTrue);
    expect(await copy.exists(), isFalse);
  });

  test('deleteEmptyFolders skips non-empty folders', () async {
    final root = await Directory.systemTemp.createTemp('cleanup_folders_');
    addTearDown(() => root.delete(recursive: true));
    final empty = await Directory('${root.path}/empty').create();
    final nonEmpty = await Directory('${root.path}/non-empty').create();
    await File('${nonEmpty.path}/file.txt').writeAsString('content');

    final result = await service.deleteEmptyFolders([empty, nonEmpty]);

    expect(result.deletedPaths, contains(empty.absolute.path));
    expect(result.skippedPaths, contains(nonEmpty.absolute.path));
    expect(await empty.exists(), isFalse);
    expect(await nonEmpty.exists(), isTrue);
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

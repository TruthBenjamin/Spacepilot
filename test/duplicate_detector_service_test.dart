import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/features/duplicates/data/services/services.dart';

void main() {
  test('findDuplicates returns files grouped by SHA256 hash', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'duplicate_detector_test_',
    );

    try {
      final first = File('${tempDir.path}/first.txt');
      final second = File('${tempDir.path}/second.txt');
      final different = File('${tempDir.path}/different.txt');

      await first.writeAsString('same file contents');
      await second.writeAsString('same file contents');
      await different.writeAsString('different file contents');

      final service = DuplicateDetectorService();

      final groups = await service.findDuplicatesInDirectory(tempDir);

      expect(groups, hasLength(1));
      expect(groups.single.files, hasLength(2));
      expect(groups.single.sha256Hash, hasLength(64));
      expect(
        groups.single.files.map((file) => file.name),
        containsAll(<String>['first.txt', 'second.txt']),
      );
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('findDuplicates ignores same-sized files with different hashes', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'duplicate_detector_test_',
    );

    try {
      final first = File('${tempDir.path}/first.txt');
      final second = File('${tempDir.path}/second.txt');

      await first.writeAsString('abc');
      await second.writeAsString('xyz');

      final service = DuplicateDetectorService();

      final groups = await service.findDuplicates(<File>[first, second]);

      expect(groups, isEmpty);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}

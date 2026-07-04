import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/features/duplicates/data/services/services.dart';
import 'package:spacepilot/features/storage/domain/models/scanned_file.dart';

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

  test(
    'findDuplicates ignores same-sized files with different hashes',
    () async {
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
    },
  );

  test('findDuplicates respects the minimum size threshold', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'duplicate_detector_test_',
    );

    try {
      final first = File('${tempDir.path}/first.txt');
      final second = File('${tempDir.path}/second.txt');

      await first.writeAsString('same');
      await second.writeAsString('same');

      final service = DuplicateDetectorService();

      final groups = await service.findDuplicates(<File>[
        first,
        second,
      ], minSizeBytes: 5);

      expect(groups, isEmpty);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('findDuplicates sorts groups by recoverable bytes', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'duplicate_detector_test_',
    );

    try {
      final smallA = File('${tempDir.path}/small-a.txt');
      final smallB = File('${tempDir.path}/small-b.txt');
      final largeA = File('${tempDir.path}/large-a.txt');
      final largeB = File('${tempDir.path}/large-b.txt');

      await smallA.writeAsString('aa');
      await smallB.writeAsString('aa');
      await largeA.writeAsString('larger-contents');
      await largeB.writeAsString('larger-contents');

      final service = DuplicateDetectorService();

      final groups = await service.findDuplicates([
        smallA,
        smallB,
        largeA,
        largeB,
      ]);

      expect(groups, hasLength(2));
      expect(groups.first.sizeBytes, greaterThan(groups.last.sizeBytes));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('findDuplicates ignores unsupported file categories', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'duplicate_detector_test_',
    );

    try {
      final first = File('${tempDir.path}/first.exe');
      final second = File('${tempDir.path}/second.exe');

      await first.writeAsString('same executable contents');
      await second.writeAsString('same executable contents');

      final service = DuplicateDetectorService();

      final groups = await service.findDuplicates(<File>[first, second]);

      expect(groups, isEmpty);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('findDuplicatesInScannedFiles groups supported scanned files', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'duplicate_detector_test_',
    );

    try {
      final first = File('${tempDir.path}/first.jpg');
      final second = File('${tempDir.path}/second.jpg');
      final ignored = File('${tempDir.path}/ignored.bin');
      final modified = DateTime(2026, 1, 1);

      await first.writeAsString('same image contents');
      await second.writeAsString('same image contents');
      await ignored.writeAsString('same image contents');

      final service = DuplicateDetectorService();

      final groups = await service.findDuplicatesInScannedFiles([
        ScannedFile(
          filename: 'first.jpg',
          path: first.path,
          size: await first.length(),
          lastModified: modified,
        ),
        ScannedFile(
          filename: 'second.jpg',
          path: second.path,
          size: await second.length(),
          lastModified: modified,
        ),
        ScannedFile(
          filename: 'ignored.bin',
          path: ignored.path,
          size: await ignored.length(),
          lastModified: modified,
        ),
      ]);

      expect(groups, hasLength(1));
      expect(groups.single.recoverableBytes, await first.length());
      expect(
        groups.single.files.map((file) => file.name),
        containsAll(<String>['first.jpg', 'second.jpg']),
      );
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}

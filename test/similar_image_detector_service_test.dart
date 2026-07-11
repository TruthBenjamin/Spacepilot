import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/features/duplicates/data/services/services.dart';
import 'package:spacepilot/features/storage/domain/models/scanned_file.dart';

void main() {
  test('perceptual hash ignores metadata and compares image pixels', () {
    final leftBright = _rgbaGradient(reverse: false);
    final rightBright = _rgbaGradient(reverse: true);

    final firstHash = SimilarImageDetectorService.perceptualHashFromRgba(
      leftBright,
      9,
      8,
    );
    final secondHash = SimilarImageDetectorService.perceptualHashFromRgba(
      Uint8List.fromList(leftBright),
      9,
      8,
    );
    final differentHash = SimilarImageDetectorService.perceptualHashFromRgba(
      rightBright,
      9,
      8,
    );

    expect(firstHash, secondHash);
    expect(
      SimilarImageDetectorService.hammingDistance(firstHash, differentHash),
      greaterThan(40),
    );
  });

  test(
    'groups visually similar images and provides similarity score',
    () async {
      const baseHash = 0x00ff00ff00ff00ff;
      const nearHash = 0x00ff00ff00ff00f0;
      const farHash = 0xff00ff00ff00ff00;
      final now = DateTime(2026, 6, 28);

      const service = SimilarImageDetectorService(
        hashOverrides: {
          '/photos/a.jpg': baseHash,
          '/photos/a-edited.jpg': nearHash,
          '/photos/b.jpg': farHash,
        },
      );

      final groups = await service.findSimilarImagesInScannedFiles([
        _file('a.jpg', '/photos/a.jpg', 100, now),
        _file('a-edited.jpg', '/photos/a-edited.jpg', 80, now),
        _file('b.jpg', '/photos/b.jpg', 60, now),
      ], maxHammingDistance: 8);

      expect(groups, hasLength(1));
      expect(groups.single.files.map((file) => file.name), [
        'a.jpg',
        'a-edited.jpg',
      ]);
      expect(groups.single.recoverableBytes, 80);
      expect(groups.single.strongestSimilarityScore, greaterThan(90));
    },
  );
}

Uint8List _rgbaGradient({required bool reverse}) {
  final data = Uint8List(9 * 8 * 4);
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 9; x++) {
      final offset = (y * 9 + x) * 4;
      final value = reverse ? x * 24 : 255 - x * 24;
      data[offset] = value;
      data[offset + 1] = value;
      data[offset + 2] = value;
      data[offset + 3] = 255;
    }
  }
  return data;
}

ScannedFile _file(String filename, String path, int size, DateTime modified) {
  return ScannedFile(
    filename: filename,
    path: path,
    size: size,
    lastModified: modified,
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/features/duplicates/domain/models/models.dart';
import 'package:spacepilot/features/recommendations/data/services/services.dart';
import 'package:spacepilot/features/recommendations/domain/models/models.dart';
import 'package:spacepilot/features/storage/data/services/storage_scanner_service.dart';

void main() {
  const engine = RecommendationEngine();

  test('returns recommendations sorted by storage impact', () {
    final now = DateTime(2026, 6, 28);
    final recommendations = engine.buildRecommendations(
      now: now,
      files: [
        ScannedFile(
          filename: 'Screenshot_001.png',
          path: '/storage/Pictures/Screenshots/Screenshot_001.png',
          size: 5,
          lastModified: now.subtract(const Duration(days: 100)),
        ),
        ScannedFile(
          filename: 'archive.zip',
          path: '/storage/Downloads/archive.zip',
          size: 10,
          lastModified: now.subtract(const Duration(days: 200)),
        ),
        ScannedFile(
          filename: 'installer.apk',
          path: '/storage/Downloads/installer.apk',
          size: 20,
          lastModified: now,
        ),
      ],
      duplicateGroups: [
        DuplicateGroup(
          sha256Hash: 'hash',
          sizeBytes: 15,
          files: [
            DuplicateFile(
              name: 'a.jpg',
              path: '/storage/DCIM/a.jpg',
              sizeBytes: 15,
              lastModified: now,
            ),
            DuplicateFile(
              name: 'a-copy.jpg',
              path: '/storage/Downloads/a-copy.jpg',
              sizeBytes: 15,
              lastModified: now,
            ),
          ],
        ),
      ],
    );

    expect(
      recommendations.map((item) => item.type),
      [
        StorageRecommendationType.apkInstallers,
        StorageRecommendationType.duplicateFiles,
        StorageRecommendationType.unusedFiles,
        StorageRecommendationType.oldScreenshots,
      ],
    );
    expect(
      recommendations.map((item) => item.storageSavingsBytes),
      [20, 15, 10, 5],
    );
  });
}

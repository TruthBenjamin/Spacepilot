import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/features/duplicates/domain/models/models.dart';
import 'package:spacepilot/features/duplicates/presentation/pages/similar_images_page.dart';
import 'package:spacepilot/features/duplicates/presentation/providers/duplicate_groups_provider.dart';
import 'package:spacepilot/features/storage/presentation/providers/storage_scan_provider.dart';

void main() {
  final group = SimilarImageGroup(
    averageSimilarityScore: 94,
    strongestSimilarityScore: 97,
    files: [
      SimilarImageFile(
        name: 'photo.jpg',
        path: '/storage/emulated/0/Pictures/photo.jpg',
        sizeBytes: 5 * 1024 * 1024,
        lastModified: DateTime(2026, 1, 3),
        perceptualHash: 'a',
      ),
      SimilarImageFile(
        name: 'photo-edit.jpg',
        path: '/storage/emulated/0/Pictures/photo-edit.jpg',
        sizeBytes: 3 * 1024 * 1024,
        lastModified: DateTime(2026, 1, 4),
        perceptualHash: 'b',
      ),
    ],
  );

  Widget buildPage() {
    return ProviderScope(
      overrides: [
        storageScanProvider.overrideWithBuild(
          (ref, controller) =>
              const StorageScanState(files: [], hasScanned: true),
        ),
        similarImageGroupsProvider.overrideWith((ref) async => [group]),
      ],
      child: const MaterialApp(home: SimilarImagesPage()),
    );
  }

  testWidgets('selects similar images safely and asks before deleting', (
    tester,
  ) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.text('Similar Images'), findsOneWidget);
    expect(find.text('1 of 1 groups | 1 selected (3.0 MB)'), findsOneWidget);
    expect(find.text('photo-edit.jpg'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Review & delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete selected similar images?'), findsOneWidget);
    expect(find.text('Keep reviewing'), findsOneWidget);
    expect(find.text('Delete images'), findsOneWidget);
    expect(find.byTooltip('Preview image'), findsOneWidget);

    await tester.tap(find.text('Keep reviewing'));
    await tester.pumpAndSettle();

    expect(find.text('Delete selected similar images?'), findsNothing);
  });
}

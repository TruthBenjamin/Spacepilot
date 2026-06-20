import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spacepilot/features/duplicates/domain/models/models.dart';
import 'package:spacepilot/features/duplicates/presentation/pages/duplicates_page.dart';
import 'package:spacepilot/features/duplicates/presentation/providers/duplicate_groups_provider.dart';
import 'package:spacepilot/features/storage/presentation/providers/storage_scan_provider.dart';

void main() {
  final group = DuplicateGroup(
    sha256Hash: 'matching-content',
    sizeBytes: 2 * 1024 * 1024,
    files: [
      DuplicateFile(
        name: 'photo.jpg',
        path: '/pictures/photo.jpg',
        sizeBytes: 2 * 1024 * 1024,
        lastModified: DateTime(2026),
      ),
      DuplicateFile(
        name: 'photo-copy.jpg',
        path: '/downloads/photo-copy.jpg',
        sizeBytes: 2 * 1024 * 1024,
        lastModified: DateTime(2026),
      ),
      DuplicateFile(
        name: 'photo-backup.jpg',
        path: '/dcim/photo-backup.jpg',
        sizeBytes: 2 * 1024 * 1024,
        lastModified: DateTime(2026),
      ),
    ],
  );

  Widget buildPage() {
    return ProviderScope(
      overrides: [
        storageScanProvider.overrideWith(() => _ScannedStorage()),
        duplicateGroupsProvider.overrideWith((ref) async => [group]),
      ],
      child: const MaterialApp(home: DuplicatesPage()),
    );
  }

  testWidgets('shows duplicate totals and selects copies by default', (
    tester,
  ) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.text('Duplicate Files'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('4.0 MB'), findsNWidgets(2));
    expect(find.text('2 selected'), findsOneWidget);
    expect(find.text('KEEP'), findsOneWidget);
  });

  testWidgets('allows an individual duplicate to be deselected', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await tester.tap(find.text('photo-copy.jpg'));
    await tester.pump();

    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('1 selected for cleanup'), findsOneWidget);
    expect(find.text('2.0 MB'), findsOneWidget);
  });
}

class _ScannedStorage extends StorageScanController {
  @override
  Future<StorageScanState> build() async {
    return const StorageScanState(files: [], hasScanned: true);
  }
}

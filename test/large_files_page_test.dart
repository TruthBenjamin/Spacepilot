import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/features/large_files/presentation/pages/large_files_page.dart';
import 'package:spacepilot/features/storage/domain/models/scanned_file.dart';
import 'package:spacepilot/features/storage/presentation/providers/storage_scan_provider.dart';

void main() {
  Widget buildPage({List<ScannedFile>? files}) {
    return ProviderScope(
      overrides: [
        storageScanProvider.overrideWithBuild(
          (ref, controller) => StorageScanState(
            hasScanned: true,
            files:
                files ??
                [
                  _file('tiny.txt', '/downloads/tiny.txt', 10),
                  _file(
                    'movie.mp4',
                    '/storage/emulated/0/Movies/movie.mp4',
                    800 * 1024 * 1024,
                  ),
                  _file(
                    'archive.zip',
                    '/storage/emulated/0/Download/archive.zip',
                    250 * 1024 * 1024,
                  ),
                ],
          ),
        ),
      ],
      child: const MaterialApp(home: LargeFilesPage()),
    );
  }

  testWidgets('shows large files and tracks selected bytes', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.text('Large File Hunter'), findsOneWidget);
    expect(find.text('2 files found'), findsOneWidget);
    expect(find.text('0 selected'), findsOneWidget);
    expect(find.text('movie.mp4'), findsOneWidget);
    expect(find.text('tiny.txt'), findsNothing);

    await tester.tap(find.text('movie.mp4'));
    await tester.pump();

    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('800.0 MB'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('archive.zip'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('archive.zip'), findsOneWidget);
  });

  testWidgets('selects the visible review set in one action', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('2 ready to review'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('2 ready to review'), findsOneWidget);
    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'Select all'),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Select all'));
    await tester.pump();

    expect(find.textContaining('1.0 GB'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Review briefing'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Review briefing'), findsOneWidget);
    expect(find.text('2 selected for deletion'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.widgetWithText(TextButton, 'Clear'),
      -160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Clear'));
    await tester.pump();

    await tester.drag(find.byType(Scrollable).first, const Offset(0, 900));
    await tester.pumpAndSettle();
    expect(find.text('0 selected'), findsOneWidget);
  });

  testWidgets('asks for confirmation before deleting selected large files', (
    tester,
  ) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('archive.zip'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('archive.zip'));
    await tester.pump();
    final deleteButton = find.widgetWithText(FilledButton, 'Delete selected');
    await tester.scrollUntilVisible(
      deleteButton,
      250,
      scrollable: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    expect(find.text('Delete selected large files?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Delete files'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Delete selected large files?'), findsNothing);
    expect(find.text('1 selected for deletion'), findsOneWidget);
  });

  testWidgets('deletes only selected files visible under active filters', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildPage(
        files: [
          _file(
            'movie.mp4',
            '/storage/emulated/0/Movies/movie.mp4',
            800 * 1024 * 1024,
          ),
          _file(
            'archive.zip',
            '/storage/emulated/0/Download/archive.zip',
            250 * 1024 * 1024,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('movie.mp4'));
    await tester.pump();

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'archive');
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 900));
    await tester.pumpAndSettle();
    expect(find.text('archive.zip'), findsOneWidget);
    await tester.tap(find.text('archive.zip'));
    await tester.pump();

    final deleteButton = find.widgetWithText(FilledButton, 'Delete selected');
    await tester.scrollUntilVisible(
      deleteButton,
      250,
      scrollable: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();

    expect(find.textContaining('permanently delete 1 file'), findsOneWidget);
  });

  testWidgets('paginates large result sets to keep the page responsive', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildPage(
        files: [
          for (var index = 0; index < 75; index++)
            _file(
              'large-$index.bin',
              '/storage/emulated/0/Download/large-$index.bin',
              (200 + index) * 1024 * 1024,
            ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('75 files found'), findsOneWidget);
    expect(find.text('large-74.bin'), findsOneWidget);
    expect(find.text('large-24.bin'), findsNothing);

    final loadMore = find.widgetWithText(
      OutlinedButton,
      'Load more (50 of 75)',
    );
    await tester.scrollUntilVisible(
      loadMore,
      600,
      scrollable: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    await tester.tap(loadMore);
    await tester.pumpAndSettle();

    expect(find.text('large-24.bin'), findsOneWidget);
  });
}

ScannedFile _file(String filename, String path, int size) {
  return ScannedFile(
    filename: filename,
    path: path,
    size: size,
    lastModified: DateTime(2026),
  );
}

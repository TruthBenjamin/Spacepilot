import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/features/cleanup/domain/models/cleanup_candidate.dart';
import 'package:spacepilot/features/cleanup/presentation/providers/cleanup_center_provider.dart';
import 'package:spacepilot/features/duplicates/domain/models/duplicate_file.dart';
import 'package:spacepilot/features/duplicates/domain/models/duplicate_group.dart';
import 'package:spacepilot/features/duplicates/presentation/providers/duplicate_groups_provider.dart';
import 'package:spacepilot/features/storage/domain/models/scanned_file.dart';
import 'package:spacepilot/features/storage/presentation/providers/storage_scan_provider.dart';

void main() {
  final now = DateTime(2026, 7, 6);

  test(
    'aggregates deterministic categories without overlapping candidates',
    () {
      final old = now.subtract(const Duration(days: 120));
      final duplicate = DuplicateGroup(
        sha256Hash: 'exact-hash',
        sizeBytes: 20,
        files: [
          DuplicateFile(
            name: 'new-copy.zip',
            path: '/storage/emulated/0/Download/new-copy.zip',
            sizeBytes: 20,
            lastModified: now,
          ),
          DuplicateFile(
            name: 'old-copy.zip',
            path: '/storage/emulated/0/Download/old-copy.zip',
            sizeBytes: 20,
            lastModified: old,
          ),
        ],
      );
      final files = [
        ScannedFile(
          filename: 'old-copy.zip',
          path: '/storage/emulated/0/Download/old-copy.zip',
          size: 20,
          lastModified: old,
        ),
        ScannedFile(
          filename: 'Screenshot_1.png',
          path: '/storage/emulated/0/Download/Screenshots/Screenshot_1.png',
          size: 30,
          lastModified: old,
        ),
        ScannedFile(
          filename: 'trace.log',
          path: '/storage/emulated/0/Download/trace.log',
          size: 40,
          lastModified: now,
        ),
      ];

      final report = buildCleanupCenterReport(
        files: files,
        report: null,
        duplicateGroups: [duplicate],
        now: now,
      );

      expect(report.categories.map((category) => category.id), [
        'duplicates',
        'junk',
        'oldScreenshots',
      ]);
      expect(report.recoverableBytes, 90);
      expect(report.categories.first.riskLevel, CleanupRiskLevel.keepOneCopy);
      expect(
        report.categories.last.riskLevel,
        CleanupRiskLevel.reviewRecommended,
      );
    },
  );

  test(
    'selection summary deduplicates paths and preserves duplicate groups',
    () {
      final group = DuplicateGroup(
        sha256Hash: 'hash',
        sizeBytes: 10,
        files: [
          DuplicateFile(
            name: 'keep.txt',
            path: '/storage/emulated/0/Download/keep.txt',
            sizeBytes: 10,
            lastModified: now,
          ),
          DuplicateFile(
            name: 'copy.txt',
            path: '/storage/emulated/0/Download/copy.txt',
            sizeBytes: 10,
            lastModified: now.subtract(const Duration(days: 1)),
          ),
        ],
      );
      final report = buildCleanupCenterReport(
        files: const [],
        report: null,
        duplicateGroups: [group],
        now: now,
      );
      final candidate = report.categories.single.candidates.single;

      final selection = summarizeCleanupSelection(
        report: report,
        selectedIds: {candidate.id},
      );

      expect(selection.fileCount, 1);
      expect(selection.selectedBytes, 10);
      expect(selection.duplicateGroups, [group]);
      expect(selection.files.single.path, contains('copy.txt'));
    },
  );

  test(
    'automatic junk selection only includes usually removable temp files',
    () {
      final old = now.subtract(const Duration(days: 200));
      final report = buildCleanupCenterReport(
        files: [
          ScannedFile(
            filename: 'trace.log',
            path: '/storage/emulated/0/Download/trace.log',
            size: 40,
            lastModified: now,
          ),
          ScannedFile(
            filename: 'holiday.zip',
            path: '/storage/emulated/0/Download/holiday.zip',
            size: 80,
            lastModified: now,
          ),
          ScannedFile(
            filename: 'notes.pdf',
            path: '/storage/emulated/0/Download/notes.pdf',
            size: 120,
            lastModified: old,
          ),
        ],
        report: null,
        duplicateGroups: const [],
        now: now,
      );

      final selection = summarizeAutomaticJunkSelection(report: report);

      expect(selection.fileCount, 1);
      expect(selection.selectedBytes, 40);
      expect(selection.files.single.filename, 'trace.log');
    },
  );

  test(
    'cleanup report shows junk while duplicate detection is still loading',
    () async {
      final duplicateCompleter = Completer<List<DuplicateGroup>>();
      final container = ProviderContainer(
        overrides: [
          storageScanProvider.overrideWithBuild(
            (ref, controller) => StorageScanState(
              hasScanned: true,
              files: [
                ScannedFile(
                  filename: 'trace.log',
                  path: '/storage/emulated/0/Download/trace.log',
                  size: 40,
                  lastModified: now,
                ),
              ],
            ),
          ),
          duplicateGroupsProvider.overrideWith(
            (ref) => duplicateCompleter.future,
          ),
        ],
      );
      addTearDown(container.dispose);

      final report = await container.read(cleanupCenterReportProvider.future);

      expect(report.categories.map((category) => category.id), ['junk']);
      expect(report.recoverableBytes, 40);
      expect(container.read(duplicateGroupsProvider).isLoading, isTrue);

      duplicateCompleter.complete(const []);
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:spacepilot/features/storage/domain/models/storage_stats.dart';
import 'package:spacepilot/features/storage/presentation/providers/device_storage_provider.dart';
import 'package:spacepilot/features/storage/presentation/providers/storage_scan_provider.dart';

void main() {
  testWidgets('dashboard renders after onboarding without layout exceptions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageScanProvider.overrideWithBuild(
            (ref, controller) =>
                const StorageScanState(files: [], hasScanned: false),
          ),
          deviceStorageStatsWithHealthProvider.overrideWith(
            (ref) async => StorageStats(
              totalBytes: 128 * 1024 * 1024 * 1024,
              usedBytes: 72 * 1024 * 1024 * 1024,
              freeBytes: 56 * 1024 * 1024 * 1024,
              deviceHealthScore: 88,
              lastUpdated: DateTime(2026),
            ),
          ),
        ],
        child: const MaterialApp(home: DashboardPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Optimize'), findsOneWidget);
    expect(find.text('Storage Clean'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

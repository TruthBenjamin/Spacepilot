import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/features/app_analyzer/data/services/app_analyzer_service.dart';
import 'package:spacepilot/features/app_analyzer/presentation/providers/app_analyzer_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('app analyzer service parses installed app report', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final channel = MethodChannel(
      'spacepilot/app-analyzer-provider-${DateTime.now().microsecondsSinceEpoch}',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'analyzeInstalledApps') return null;
          return {
            'hasUsageAccess': true,
            'generatedAt': DateTime(2026).millisecondsSinceEpoch,
            'limitations': const [],
            'apps': [
              {
                'packageName': 'com.example.large',
                'appName': 'Large App',
                'versionName': '1.0',
                'versionCode': 1,
                'isSystemApp': false,
                'canLaunch': true,
                'hasUsageAccess': true,
                'totalSizeBytes': 600 * 1024 * 1024,
                'lastUsedTime': DateTime(2026, 1, 4).millisecondsSinceEpoch,
                'lastUpdateTime': DateTime(2026, 1, 5).millisecondsSinceEpoch,
              },
              {
                'packageName': 'android.system',
                'appName': 'System App',
                'versionCode': 2,
                'isSystemApp': true,
                'canLaunch': true,
                'hasUsageAccess': true,
                'totalSizeBytes': 100 * 1024 * 1024,
              },
            ],
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final container = ProviderContainer(
      overrides: [
        appAnalyzerServiceProvider.overrideWithValue(
          AppAnalyzerService(channel: channel),
        ),
      ],
    );
    addTearDown(container.dispose);

    final report = await container.read(installedAppsReportProvider.future);
    expect(report.apps, hasLength(2));
    expect(report.hasUsageAccess, isTrue);

    container.read(appAnalyzerFilterProvider.notifier).state =
        AppAnalyzerFilter.user;
    final filtered = container.read(filteredInstalledAppsProvider).requireValue;
    expect(filtered.map((app) => app.packageName), ['com.example.large']);
  });
}

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spacepilot/core/app/spacepilot_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const permissionsChannel = MethodChannel('ai.spacepilot.app/permissions');
  const preferencesChannel = MethodChannel('ai.spacepilot.app/preferences');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionsChannel, (call) async {
          return switch (call.method) {
            'hasStorageAccess' => true,
            'hasMediaAccess' => true,
            'requestStorageAccess' => true,
            'requestMediaAccess' => true,
            _ => false,
          };
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(preferencesChannel, (call) async {
          return switch (call.method) {
            'hasCompletedOnboarding' => false,
            'setOnboardingCompleted' => null,
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionsChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(preferencesChannel, null);
  });

  testWidgets('user can pass onboarding and open Large File Hunter', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: SpacePilotApp()));

    expect(find.text('Your AI Storage Assistant'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2700));
    await tester.pumpAndSettle();

    for (var index = 0; index < 3; index++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('Grant access'));
    await tester.pumpAndSettle();

    expect(find.text('Optimize'), findsOneWidget);

    await tester.tap(find.text('Large Files'));
    await tester.pumpAndSettle();

    expect(find.text('Large File Hunter'), findsOneWidget);
    expect(find.text('Run a scan to find large files'), findsOneWidget);
  });
}

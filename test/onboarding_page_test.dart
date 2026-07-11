import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:spacepilot/features/app_analyzer/data/services/app_analyzer_service.dart';
import 'package:spacepilot/features/app_analyzer/presentation/providers/app_analyzer_provider.dart';
import 'package:spacepilot/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:spacepilot/features/permissions/data/services/permission_service.dart';
import 'package:spacepilot/features/permissions/presentation/providers/permission_service_provider.dart';
import 'package:spacepilot/routes/app_routes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const preferencesChannel = MethodChannel('ai.spacepilot.app/preferences');
  late MethodChannel permissionChannel;
  late MethodChannel appAnalyzerChannel;
  late List<String> permissionCalls;
  late List<String> appAnalyzerCalls;
  late List<String> preferenceCalls;

  setUp(() {
    permissionChannel = MethodChannel(
      'spacepilot/onboarding-permissions-${DateTime.now().microsecondsSinceEpoch}',
    );
    appAnalyzerChannel = MethodChannel(
      'spacepilot/onboarding-app-analyzer-${DateTime.now().microsecondsSinceEpoch}',
    );
    permissionCalls = <String>[];
    appAnalyzerCalls = <String>[];
    preferenceCalls = <String>[];
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appAnalyzerChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(preferencesChannel, null);
  });

  Widget app(GoRouter router) {
    return ProviderScope(
      overrides: [
        permissionServiceProvider.overrideWithValue(
          PermissionService(channel: permissionChannel),
        ),
        appAnalyzerServiceProvider.overrideWithValue(
          AppAnalyzerService(channel: appAnalyzerChannel),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  GoRouter router() {
    return GoRouter(
      initialLocation: AppRoutes.onboarding,
      routes: [
        GoRoute(
          path: AppRoutes.onboarding,
          builder: (context, state) => const OnboardingPage(),
        ),
        GoRoute(
          path: AppRoutes.dashboard,
          builder: (context, state) => const Scaffold(body: Text('Dashboard')),
        ),
      ],
    );
  }

  testWidgets('changes grant access to continue after permission is granted', (
    tester,
  ) async {
    _setAndroidForTest();
    var granted = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, (call) async {
          permissionCalls.add(call.method);
          if (call.method == 'requestStorageAccess') {
            granted = true;
          }
          return granted;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appAnalyzerChannel, (call) async {
          appAnalyzerCalls.add(call.method);
          return call.method == 'hasUsageAccess';
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(preferencesChannel, (call) async {
          preferenceCalls.add(call.method);
          return null;
        });

    final testRouter = router();
    await tester.pumpWidget(app(testRouter));

    await _advanceToPermissionStep(tester);
    await tester.tap(find.text('Grant access'));
    await tester.pumpAndSettle();

    expect(find.text('Continue'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(permissionCalls, [
      'hasStorageAccess',
      'hasStorageAccess',
      'requestStorageAccess',
      'hasMediaAccess',
    ]);
    expect(appAnalyzerCalls, ['hasUsageAccess']);
    expect(preferenceCalls, ['setOnboardingCompleted']);
    expect(
      testRouter.routeInformationProvider.value.uri.path,
      AppRoutes.dashboard,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('stays on onboarding when permission is denied', (tester) async {
    _setAndroidForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, (call) async {
          permissionCalls.add(call.method);
          return false;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(preferencesChannel, (call) async {
          preferenceCalls.add(call.method);
          return null;
        });

    final testRouter = router();
    await tester.pumpWidget(app(testRouter));

    await _advanceToPermissionStep(tester);
    await tester.tap(find.text('Grant access'));
    await tester.pumpAndSettle();

    expect(permissionCalls, [
      'hasStorageAccess',
      'hasStorageAccess',
      'requestStorageAccess',
    ]);
    expect(appAnalyzerCalls, isEmpty);
    expect(preferenceCalls, isEmpty);
    expect(
      testRouter.routeInformationProvider.value.uri.path,
      AppRoutes.onboarding,
    );
    expect(
      find.text(
        'Storage and media access are required before SpacePilot can scan real files.',
      ),
      findsOneWidget,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('opens usage access settings before completing onboarding', (
    tester,
  ) async {
    _setAndroidForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, (call) async {
          permissionCalls.add(call.method);
          return true;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appAnalyzerChannel, (call) async {
          appAnalyzerCalls.add(call.method);
          if (call.method == 'hasUsageAccess') return false;
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(preferencesChannel, (call) async {
          preferenceCalls.add(call.method);
          return null;
        });

    final testRouter = router();
    await tester.pumpWidget(app(testRouter));

    await _advanceToPermissionStep(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(permissionCalls, ['hasStorageAccess', 'hasMediaAccess']);
    expect(appAnalyzerCalls, ['hasUsageAccess', 'openUsageAccessSettings']);
    expect(preferenceCalls, isEmpty);
    expect(
      testRouter.routeInformationProvider.value.uri.path,
      AppRoutes.onboarding,
    );
    expect(
      find.text(
        'Grant Usage Access to unlock app last-used and storage insights, then return to continue.',
      ),
      findsOneWidget,
    );
    debugDefaultTargetPlatformOverride = null;
  });
}

void _setAndroidForTest() {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
}

Future<void> _advanceToPermissionStep(WidgetTester tester) async {
  for (var index = 0; index < 4; index++) {
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
  }
  expect(
    find.text('Grant access').evaluate().length +
        find.text('Continue').evaluate().length,
    1,
  );
}

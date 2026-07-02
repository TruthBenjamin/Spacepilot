import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/routes/app_router.dart';
import 'package:spacepilot/routes/app_routes.dart';

void main() {
  testWidgets('router opens core destinations by route name', (tester) async {
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return MaterialApp.router(
              routerConfig: ref.watch(appRouterProvider),
            );
          },
        ),
      ),
    );

    final router = container.read(appRouterProvider);

    router.goNamed(AppRouteNames.largeFiles);
    await tester.pumpAndSettle();
    expect(find.text('Large File Hunter'), findsOneWidget);

    router.goNamed(AppRouteNames.duplicates);
    await tester.pumpAndSettle();
    expect(find.text('Duplicate Files'), findsOneWidget);

    router.goNamed(AppRouteNames.settings);
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
  });
}

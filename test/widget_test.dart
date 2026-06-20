import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spacepilot/core/app/spacepilot_app.dart';

void main() {
  testWidgets('shows the SpacePilot splash screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: SpacePilotApp()));

    await tester.pump();

    expect(find.text('SpacePilot AI'), findsOneWidget);
    expect(find.text('Optimizing storage signals...'), findsOneWidget);
  });
}

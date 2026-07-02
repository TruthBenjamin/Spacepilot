import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spacepilot/core/app/spacepilot_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('user can pass onboarding and reach dashboard', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SpacePilotApp()));

    expect(find.text('Your AI Storage Assistant'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2700));
    await tester.pumpAndSettle();
    expect(find.text('Skip'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('Run AI Scan'), findsOneWidget);
    expect(
      find.text('Your files stay private and are analyzed on this device.'),
      findsOneWidget,
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/features/battery_optimization/presentation/pages/battery_optimization_page.dart';
import 'package:spacepilot/features/booster/presentation/pages/booster_page.dart';
import 'package:spacepilot/features/cooling/presentation/pages/cooling_page.dart';
import 'package:spacepilot/features/network_assistant/presentation/pages/network_assistant_page.dart';
import 'package:spacepilot/features/power/domain/models/power_thermal_snapshot.dart';
import 'package:spacepilot/features/power/presentation/providers/power_thermal_provider.dart';

final _snapshot = PowerThermalSnapshot(
  capturedAt: DateTime(2026),
  thermalStatusSupported: true,
  charging: false,
  plugged: false,
  powerSource: PowerSource.battery,
  powerSaveMode: false,
  batteryLevel: 76,
  batteryTemperatureCelsius: 34,
  batteryHealth: 'good',
  thermalStatus: 0,
);

void main() {
  testWidgets('booster button shows feedback', (tester) async {
    const channel = MethodChannel('ai.spacepilot.app/ram_booster');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          const before = {
            'totalBytes': 4000,
            'availableBytes': 1000,
            'lowMemory': false,
            'thresholdBytes': 300,
            'capturedAt': 1,
          };
          if (call.method == 'getMemorySnapshot') return before;
          if (call.method == 'boostRam') {
            return {
              'before': before,
              'after': {...before, 'availableBytes': 1800},
              'optimizedAppCount': 2,
              'optimizedPackages': <String>['one', 'two'],
              'skippedPackages': <String>[],
              'limitations': <String>[],
            };
          }
          return null;
        });
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: BoosterPage())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Boost RAM now'));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();

    expect(find.textContaining('Reclaimed 800 B'), findsWidgets);
    expect(find.text('Boost summary'), findsOneWidget);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('cooling screen reports measured state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          powerThermalSnapshotProvider.overrideWith((ref) async => _snapshot),
        ],
        child: const MaterialApp(home: CoolingPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('NORMAL'), findsOneWidget);
    expect(find.text('Battery temperature: 34.0 °C'), findsOneWidget);
    expect(find.text('Optimize Thermal Conditions'), findsOneWidget);
  });

  testWidgets('battery screen reports Android state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          powerThermalSnapshotProvider.overrideWith((ref) async => _snapshot),
        ],
        child: const MaterialApp(home: BatteryOptimizationPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('76%'), findsOneWidget);
    expect(find.text('Battery Saver off'), findsOneWidget);
    expect(find.text('Review Power Optimization'), findsOneWidget);
  });

  testWidgets('network button shows feedback', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NetworkAssistantPage()));

    await tester.tap(find.text('Check connection health'));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();

    expect(
      find.text(
        'Connection check complete. Wi-Fi looks healthy and mobile data is stable.',
      ),
      findsOneWidget,
    );
  });
}

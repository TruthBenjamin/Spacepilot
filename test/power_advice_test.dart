import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/features/battery_optimization/domain/models/power_advice.dart';
import 'package:spacepilot/features/power/domain/models/power_thermal_snapshot.dart';

void main() {
  test('low battery recommendations derive from measurable state', () {
    final snapshot = PowerThermalSnapshot(
      capturedAt: DateTime(2026), thermalStatusSupported: true, charging: false, plugged: false,
      powerSource: PowerSource.battery, powerSaveMode: false, batteryLevel: 15, thermalStatus: 0,
    );
    final advice = buildPowerRecommendations(snapshot, scanActive: true, scheduledScanning: true);
    expect(advice.map((item) => item.title), containsAll(['Enable Battery Saver', 'Pause storage analysis', 'Postpone background scans']));
  });

  test('unavailable optional metrics do not create fake advice', () {
    final snapshot = PowerThermalSnapshot(
      capturedAt: DateTime(2026), thermalStatusSupported: false, charging: false, plugged: false,
      powerSource: PowerSource.unknown, powerSaveMode: false,
    );
    expect(buildPowerRecommendations(snapshot, scanActive: false, scheduledScanning: false), isEmpty);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/features/cooling/domain/models/thermal_advice.dart';
import 'package:spacepilot/features/power/domain/models/power_thermal_snapshot.dart';

void main() {
  PowerThermalSnapshot snapshot({int? status, double? temperature, int? level = 50, bool charging = false}) => PowerThermalSnapshot(
    capturedAt: DateTime(2026), thermalStatusSupported: status != null, charging: charging, plugged: charging,
    powerSource: charging ? PowerSource.usb : PowerSource.battery, powerSaveMode: false,
    batteryLevel: level, batteryTemperatureCelsius: temperature, thermalStatus: status,
  );

  test('Android thermal status takes precedence', () {
    expect(classifyThermal(snapshot(status: 3, temperature: 30)), ThermalClassification.high);
    expect(classifyThermal(snapshot(status: 5)), ThermalClassification.critical);
  });

  test('uses battery temperature fallback and exposes unavailable', () {
    expect(classifyThermal(snapshot(temperature: 42)), ThermalClassification.elevated);
    expect(classifyThermal(snapshot(level: null)), ThermalClassification.unavailable);
  });

  test('recommends pausing active scan under thermal pressure', () {
    final advice = buildThermalAdvice(snapshot(status: 3, charging: true), scanActive: true);
    expect(advice.recommendations.any((item) => item.contains('Pause')), isTrue);
    expect(advice.factors, hasLength(2));
  });
}

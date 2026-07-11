import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/models/power_thermal_snapshot.dart';

final class PowerThermalService {
  PowerThermalService({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('ai.spacepilot.app/power_thermal');

  final MethodChannel _channel;

  Future<PowerThermalSnapshot> getSnapshot() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('Power and thermal signals are Android-only.');
    }
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'getPowerThermalSnapshot',
    );
    if (value == null) {
      throw StateError('Power and thermal data was unavailable.');
    }
    return PowerThermalSnapshot(
      capturedAt: DateTime.fromMillisecondsSinceEpoch(
        (value['capturedAt'] as num?)?.toInt() ?? 0,
      ),
      batteryLevel: (value['batteryLevel'] as num?)
          ?.toInt()
          .clamp(0, 100)
          .toInt(),
      charging: value['charging'] == true,
      plugged: value['plugged'] == true,
      powerSource: _source(value['powerSource']),
      powerSaveMode: value['powerSaveMode'] == true,
      batteryTemperatureCelsius: (value['batteryTemperatureCelsius'] as num?)
          ?.toDouble(),
      batteryHealth: value['batteryHealth'] as String?,
      thermalStatus: (value['thermalStatus'] as num?)?.toInt(),
      thermalStatusSupported: value['thermalStatusSupported'] == true,
    );
  }

  Future<void> openBatterySaverSettings() =>
      _channel.invokeMethod('openBatterySaverSettings');
  Future<void> openBatteryUsageSettings() =>
      _channel.invokeMethod('openBatteryUsageSettings');
  Future<void> openDisplaySettings() =>
      _channel.invokeMethod('openDisplaySettings');
}

PowerSource _source(Object? value) => switch (value) {
  'ac' => PowerSource.ac,
  'usb' => PowerSource.usb,
  'wireless' => PowerSource.wireless,
  'battery' => PowerSource.battery,
  _ => PowerSource.unknown,
};

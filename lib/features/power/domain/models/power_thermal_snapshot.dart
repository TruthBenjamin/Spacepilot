import 'package:flutter/foundation.dart';

enum SignalAvailability { available, unavailable, unsupported }

enum PowerSource { battery, ac, usb, wireless, unknown }

@immutable
final class PowerThermalSnapshot {
  const PowerThermalSnapshot({
    required this.capturedAt,
    required this.thermalStatusSupported,
    required this.charging,
    required this.plugged,
    required this.powerSource,
    required this.powerSaveMode,
    this.batteryLevel,
    this.batteryTemperatureCelsius,
    this.batteryHealth,
    this.thermalStatus,
  });

  final DateTime capturedAt;
  final int? batteryLevel;
  final bool charging;
  final bool plugged;
  final PowerSource powerSource;
  final bool powerSaveMode;
  final double? batteryTemperatureCelsius;
  final String? batteryHealth;
  final int? thermalStatus;
  final bool thermalStatusSupported;

  SignalAvailability get thermalAvailability => thermalStatusSupported
      ? (thermalStatus == null
            ? SignalAvailability.unavailable
            : SignalAvailability.available)
      : SignalAvailability.unsupported;
}

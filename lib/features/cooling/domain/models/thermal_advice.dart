import 'package:flutter/foundation.dart';

import '../../../power/domain/models/power_thermal_snapshot.dart';

enum ThermalClassification { normal, elevated, high, critical, unavailable }

@immutable
final class ThermalAdvice {
  const ThermalAdvice({
    required this.snapshot,
    required this.classification,
    required this.factors,
    required this.recommendations,
  });
  final PowerThermalSnapshot snapshot;
  final ThermalClassification classification;
  final List<String> factors;
  final List<String> recommendations;
}

ThermalClassification classifyThermal(PowerThermalSnapshot value) {
  final status = value.thermalStatus;
  if (status != null) {
    if (status >= 5) return ThermalClassification.critical;
    if (status >= 3) return ThermalClassification.high;
    if (status >= 1) return ThermalClassification.elevated;
    return ThermalClassification.normal;
  }
  final temperature = value.batteryTemperatureCelsius;
  if (temperature == null) return ThermalClassification.unavailable;
  if (temperature >= 50) return ThermalClassification.critical;
  if (temperature >= 45) return ThermalClassification.high;
  if (temperature >= 40) return ThermalClassification.elevated;
  return ThermalClassification.normal;
}

ThermalAdvice buildThermalAdvice(
  PowerThermalSnapshot value, {
  required bool scanActive,
}) {
  final classification = classifyThermal(value);
  final factors = <String>[];
  final recommendations = <String>[];
  if (value.charging) {
    factors.add(
      'The device is currently charging (${value.powerSource.name}).',
    );
  }
  if (scanActive) {
    factors.add('SpacePilot is performing storage-intensive analysis.');
  }
  if ((value.batteryLevel ?? 100) <= 20 && !value.powerSaveMode) {
    factors.add('Battery is low and Battery Saver is off.');
  }
  if (classification == ThermalClassification.elevated ||
      classification == ThermalClassification.high ||
      classification == ThermalClassification.critical) {
    if (scanActive) {
      recommendations.add(
        'Pause the current SpacePilot scan until conditions improve.',
      );
    }
    if (value.charging) {
      recommendations.add(
        'If practical, disconnect charging and let the device rest.',
      );
    }
    recommendations.add('Reduce display brightness in Android settings.');
    recommendations.add(
      'Pause gaming, video processing, or other intensive activity manually.',
    );
    recommendations.add(
      'Move the device away from direct sunlight or another heat source.',
    );
  }
  if (!value.powerSaveMode && (value.batteryLevel ?? 100) <= 30) {
    recommendations.add('Consider enabling Battery Saver.');
  }
  if (recommendations.isEmpty) {
    recommendations.add(
      'No thermal intervention is indicated by the available signals.',
    );
  }
  return ThermalAdvice(
    snapshot: value,
    classification: classification,
    factors: factors,
    recommendations: recommendations,
  );
}

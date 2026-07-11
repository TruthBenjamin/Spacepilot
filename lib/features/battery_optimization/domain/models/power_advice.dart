import 'package:flutter/foundation.dart';

import '../../../power/domain/models/power_thermal_snapshot.dart';

enum PowerAdvicePriority { low, medium, high }

@immutable
final class PowerRecommendation {
  const PowerRecommendation({
    required this.title,
    required this.explanation,
    required this.reason,
    required this.priority,
    required this.actionLabel,
    required this.expectedBenefit,
  });
  final String title;
  final String explanation;
  final String reason;
  final PowerAdvicePriority priority;
  final String actionLabel;
  final String expectedBenefit;
}

List<PowerRecommendation> buildPowerRecommendations(
  PowerThermalSnapshot value, {
  required bool scanActive,
  required bool scheduledScanning,
}) {
  final output = <PowerRecommendation>[];
  if ((value.batteryLevel ?? 100) <= 20 && !value.powerSaveMode) {
    output.add(
      const PowerRecommendation(
        title: 'Enable Battery Saver',
        explanation: 'Use Android Battery Saver while charge is low.',
        reason: 'Battery is at or below 20% and Battery Saver is off.',
        priority: PowerAdvicePriority.high,
        actionLabel: 'Open Battery Saver',
        expectedBenefit:
            'May reduce non-essential background and display power use.',
      ),
    );
  }
  if ((value.batteryLevel ?? 100) <= 25 && scanActive) {
    output.add(
      const PowerRecommendation(
        title: 'Pause storage analysis',
        explanation: 'Resume the intensive scan while charging.',
        reason: 'A SpacePilot scan is active while battery is low.',
        priority: PowerAdvicePriority.high,
        actionLabel: 'Review scan',
        expectedBenefit:
            'Reduces SpacePilot’s current CPU and storage activity.',
      ),
    );
  }
  if ((value.batteryLevel ?? 0) >= 90 && value.charging) {
    output.add(
      const PowerRecommendation(
        title: 'Review prolonged charging',
        explanation:
            'Disconnect when convenient if the device is warm or will remain plugged in.',
        reason: 'Battery is charging at 90% or above.',
        priority: PowerAdvicePriority.medium,
        actionLabel: 'Battery settings',
        expectedBenefit: 'Can reduce time spent charging near full capacity.',
      ),
    );
  }
  if ((value.batteryLevel ?? 100) <= 30 && scheduledScanning) {
    output.add(
      const PowerRecommendation(
        title: 'Postpone background scans',
        explanation: 'Disable scheduled scans until power conditions improve.',
        reason: 'Scheduled scanning is enabled while battery is low.',
        priority: PowerAdvicePriority.medium,
        actionLabel: 'Adjust automation',
        expectedBenefit: 'Avoids non-essential SpacePilot work on low battery.',
      ),
    );
  }
  if ((value.batteryTemperatureCelsius ?? 0) >= 40) {
    output.add(
      const PowerRecommendation(
        title: 'Let the battery cool',
        explanation: 'Pause intensive use and charging where practical.',
        reason: 'Measured battery temperature is at least 40 °C.',
        priority: PowerAdvicePriority.high,
        actionLabel: 'Thermal advisor',
        expectedBenefit: 'Reduces additional heat-producing activity.',
      ),
    );
  }
  return output;
}

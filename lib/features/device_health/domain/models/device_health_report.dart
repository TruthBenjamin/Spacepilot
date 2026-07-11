import 'package:flutter/foundation.dart';

enum DeviceHealthCategory {
  excellent('Excellent'),
  good('Good'),
  fair('Fair'),
  poor('Poor');

  const DeviceHealthCategory(this.label);
  final String label;
}

@immutable
final class DeviceHealthReport {
  const DeviceHealthReport({
    required this.score,
    required this.category,
    required this.breakdown,
    required this.suggestions,
    required this.explanation,
  });

  final int score;
  final DeviceHealthCategory category;
  final DeviceHealthScoreBreakdown breakdown;
  final List<String> suggestions;
  final String explanation;
}

@immutable
final class DeviceHealthScoreBreakdown {
  const DeviceHealthScoreBreakdown({
    required this.storageUsagePenalty,
    required this.duplicateFilesPenalty,
    required this.unusedAppsPenalty,
    required this.junkFilesPenalty,
    required this.oldDownloadsPenalty,
    required this.emptyFoldersPenalty,
    this.thermalPenalty = 0,
    this.powerConfigurationPenalty = 0,
  });

  final int storageUsagePenalty;
  final int duplicateFilesPenalty;
  final int unusedAppsPenalty;
  final int junkFilesPenalty;
  final int oldDownloadsPenalty;
  final int emptyFoldersPenalty;
  final int thermalPenalty;
  final int powerConfigurationPenalty;

  int get totalPenalty =>
      storageUsagePenalty +
      duplicateFilesPenalty +
      unusedAppsPenalty +
      junkFilesPenalty +
      oldDownloadsPenalty +
      emptyFoldersPenalty +
      thermalPenalty +
      powerConfigurationPenalty;
}

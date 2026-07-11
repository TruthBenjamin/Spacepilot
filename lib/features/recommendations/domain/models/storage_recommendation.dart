import 'package:flutter/foundation.dart';

@immutable
final class StorageRecommendation {
  const StorageRecommendation({
    required this.type,
    required this.title,
    required this.description,
    required this.storageSavingsBytes,
    required this.priority,
    required this.riskLevel,
    required this.action,
    required this.actionTarget,
    this.evidence,
    this.recommendedAction,
  });

  final StorageRecommendationType type;
  final String title;
  final String description;
  final int storageSavingsBytes;
  final RecommendationPriority priority;
  final RecommendationRiskLevel riskLevel;
  final RecommendationAction action;
  final RecommendationActionTarget actionTarget;
  final String? evidence;
  final String? recommendedAction;

  String get actionLabel => action.label;
  String get stableId => type.name;
  String get evidenceText => evidence ?? description;
  String get recommendedActionText => recommendedAction ?? action.label;
}

enum StorageRecommendationType {
  lowStorage,
  largeDownloads,
  oldScreenshots,
  unusedFiles,
  duplicateMedia,
  apkInstallers,
  emptyFolders,
  thermalPressure,
  lowBatteryScan,
  cleanupOpportunity,
}

enum RecommendationPriority { low, medium, high, critical }

enum RecommendationRiskLevel { low, medium, high }

enum RecommendationAction {
  scan('Run scan'),
  review('Review'),
  reviewDownloads('Review downloads'),
  reviewDuplicates('Review duplicates'),
  reviewFolders('Review folders'),
  delete('Delete'),
  openAdvisor('Open advisor'),
  pauseAndReview('Pause and review');

  const RecommendationAction(this.label);

  final String label;
}

enum RecommendationActionTarget {
  scanResults,
  duplicates,
  cooling,
  battery,
  junkCleaner,
}

import 'package:flutter/foundation.dart';

@immutable
final class StorageRecommendation {
  const StorageRecommendation({
    required this.type,
    required this.title,
    required this.storageSavingsBytes,
    required this.actionLabel,
    required this.actionTarget,
  });

  final StorageRecommendationType type;
  final String title;
  final int storageSavingsBytes;
  final String actionLabel;
  final RecommendationActionTarget actionTarget;
}

enum StorageRecommendationType {
  oldScreenshots,
  unusedFiles,
  duplicateFiles,
  apkInstallers,
}

enum RecommendationActionTarget { scanResults, duplicates }

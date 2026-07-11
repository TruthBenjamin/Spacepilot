import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'similar_image_file.dart';

@immutable
final class SimilarImageGroup {
  SimilarImageGroup({
    required List<SimilarImageFile> files,
    required this.averageSimilarityScore,
    required this.strongestSimilarityScore,
  }) : files = UnmodifiableListView<SimilarImageFile>(files);

  final UnmodifiableListView<SimilarImageFile> files;
  final double averageSimilarityScore;
  final double strongestSimilarityScore;

  int get imageCount => files.length;

  int get recoverableBytes {
    if (files.length < 2) return 0;

    final sorted = files.map((file) => file.sizeBytes).toList()..sort();
    return sorted.take(sorted.length - 1).fold<int>(0, (a, b) => a + b);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SimilarImageGroup &&
            listEquals(other.files, files) &&
            other.averageSimilarityScore == averageSimilarityScore &&
            other.strongestSimilarityScore == strongestSimilarityScore;
  }

  @override
  int get hashCode {
    return Object.hash(
      Object.hashAll(files),
      averageSimilarityScore,
      strongestSimilarityScore,
    );
  }
}

import 'package:flutter/foundation.dart';

@immutable
final class SimilarImageFile {
  const SimilarImageFile({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.lastModified,
    required this.perceptualHash,
  });

  final String name;
  final String path;
  final int sizeBytes;
  final DateTime lastModified;
  final String perceptualHash;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SimilarImageFile &&
            other.name == name &&
            other.path == path &&
            other.sizeBytes == sizeBytes &&
            other.lastModified == lastModified &&
            other.perceptualHash == perceptualHash;
  }

  @override
  int get hashCode {
    return Object.hash(name, path, sizeBytes, lastModified, perceptualHash);
  }
}

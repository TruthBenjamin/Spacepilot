import 'package:flutter/foundation.dart';

@immutable
final class DuplicateFile {
  const DuplicateFile({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.lastModified,
  });

  final String name;
  final String path;
  final int sizeBytes;
  final DateTime lastModified;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is DuplicateFile &&
            other.name == name &&
            other.path == path &&
            other.sizeBytes == sizeBytes &&
            other.lastModified == lastModified;
  }

  @override
  int get hashCode => Object.hash(name, path, sizeBytes, lastModified);
}

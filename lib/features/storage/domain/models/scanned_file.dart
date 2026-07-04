import 'package:flutter/foundation.dart';

@immutable
final class ScannedFile {
  const ScannedFile({
    required this.filename,
    required this.path,
    required this.size,
    required this.lastModified,
    this.previewPath,
    this.previewType,
  });

  final String filename;
  final String path;
  final int size;
  final DateTime lastModified;
  final String? previewPath;
  final String? previewType;
}

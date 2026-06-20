import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'duplicate_file.dart';

@immutable
final class DuplicateGroup {
  DuplicateGroup({
    required this.sha256Hash,
    required this.sizeBytes,
    required List<DuplicateFile> files,
  }) : files = UnmodifiableListView<DuplicateFile>(files);

  final String sha256Hash;
  final int sizeBytes;
  final UnmodifiableListView<DuplicateFile> files;

  int get duplicateCount => files.length;
  int get recoverableBytes => sizeBytes * (files.length - 1);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is DuplicateGroup &&
            other.sha256Hash == sha256Hash &&
            other.sizeBytes == sizeBytes &&
            listEquals(other.files, files);
  }

  @override
  int get hashCode => Object.hash(
    sha256Hash,
    sizeBytes,
    Object.hashAll(files),
  );
}

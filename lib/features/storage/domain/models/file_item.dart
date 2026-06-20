import 'package:flutter/foundation.dart';

@immutable
final class FileItem {
  const FileItem({
    required this.id,
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.type,
    required this.lastModified,
    this.isSelected = false,
    this.isSafeToClean = false,
  });

  final String id;
  final String name;
  final String path;
  final int sizeBytes;
  final FileItemType type;
  final DateTime lastModified;
  final bool isSelected;
  final bool isSafeToClean;

  double get sizeMegabytes => sizeBytes / 1024 / 1024;
  double get sizeGigabytes => sizeBytes / 1024 / 1024 / 1024;

  FileItem copyWith({
    String? id,
    String? name,
    String? path,
    int? sizeBytes,
    FileItemType? type,
    DateTime? lastModified,
    bool? isSelected,
    bool? isSafeToClean,
  }) {
    return FileItem(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      type: type ?? this.type,
      lastModified: lastModified ?? this.lastModified,
      isSelected: isSelected ?? this.isSelected,
      isSafeToClean: isSafeToClean ?? this.isSafeToClean,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is FileItem &&
            other.id == id &&
            other.name == name &&
            other.path == path &&
            other.sizeBytes == sizeBytes &&
            other.type == type &&
            other.lastModified == lastModified &&
            other.isSelected == isSelected &&
            other.isSafeToClean == isSafeToClean;
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    path,
    sizeBytes,
    type,
    lastModified,
    isSelected,
    isSafeToClean,
  );
}

enum FileItemType {
  image,
  video,
  audio,
  document,
  archive,
  appCache,
  duplicate,
  other,
}

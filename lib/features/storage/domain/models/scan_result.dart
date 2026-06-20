import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'file_item.dart';

@immutable
final class ScanResult {
  ScanResult({
    required this.id,
    required this.startedAt,
    required this.completedAt,
    required this.status,
    required List<FileItem> files,
    required this.storageRecoverableBytes,
    required this.aiSummary,
  }) : files = UnmodifiableListView<FileItem>(files);

  final String id;
  final DateTime startedAt;
  final DateTime completedAt;
  final ScanStatus status;
  final UnmodifiableListView<FileItem> files;
  final int storageRecoverableBytes;
  final String aiSummary;

  int get fileCount => files.length;

  double get storageRecoverableMegabytes {
    return storageRecoverableBytes / 1024 / 1024;
  }

  double get storageRecoverableGigabytes {
    return storageRecoverableBytes / 1024 / 1024 / 1024;
  }

  List<FileItem> get safeToCleanFiles {
    return UnmodifiableListView(files.where((file) => file.isSafeToClean));
  }

  ScanResult copyWith({
    String? id,
    DateTime? startedAt,
    DateTime? completedAt,
    ScanStatus? status,
    List<FileItem>? files,
    int? storageRecoverableBytes,
    String? aiSummary,
  }) {
    return ScanResult(
      id: id ?? this.id,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      status: status ?? this.status,
      files: files ?? this.files,
      storageRecoverableBytes:
          storageRecoverableBytes ?? this.storageRecoverableBytes,
      aiSummary: aiSummary ?? this.aiSummary,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ScanResult &&
            other.id == id &&
            other.startedAt == startedAt &&
            other.completedAt == completedAt &&
            other.status == status &&
            listEquals(other.files, files) &&
            other.storageRecoverableBytes == storageRecoverableBytes &&
            other.aiSummary == aiSummary;
  }

  @override
  int get hashCode => Object.hash(
    id,
    startedAt,
    completedAt,
    status,
    Object.hashAll(files),
    storageRecoverableBytes,
    aiSummary,
  );
}

enum ScanStatus { idle, scanning, completed, failed }

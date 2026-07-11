import 'package:flutter/foundation.dart';

@immutable
final class RecoveryBinItem {
  const RecoveryBinItem({
    required this.id,
    required this.filename,
    required this.originalPath,
    required this.recoveryPath,
    required this.sizeBytes,
    required this.deletedAt,
    required this.expiresAt,
  });

  final String id;
  final String filename;
  final String originalPath;
  final String recoveryPath;
  final int sizeBytes;
  final DateTime deletedAt;
  final DateTime expiresAt;

  bool isExpired(DateTime now) => !expiresAt.isAfter(now);

  Map<String, Object> toJson() {
    return {
      'id': id,
      'filename': filename,
      'originalPath': originalPath,
      'recoveryPath': recoveryPath,
      'sizeBytes': sizeBytes,
      'deletedAt': deletedAt.millisecondsSinceEpoch,
      'expiresAt': expiresAt.millisecondsSinceEpoch,
    };
  }

  static RecoveryBinItem? fromJson(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final id = value['id'];
    final filename = value['filename'];
    final originalPath = value['originalPath'];
    final recoveryPath = value['recoveryPath'];
    final sizeBytes = value['sizeBytes'];
    final deletedAt = value['deletedAt'];
    final expiresAt = value['expiresAt'];
    if (id is! String ||
        filename is! String ||
        originalPath is! String ||
        recoveryPath is! String ||
        sizeBytes is! num ||
        deletedAt is! num ||
        expiresAt is! num) {
      return null;
    }

    return RecoveryBinItem(
      id: id,
      filename: filename,
      originalPath: originalPath,
      recoveryPath: recoveryPath,
      sizeBytes: sizeBytes.round(),
      deletedAt: DateTime.fromMillisecondsSinceEpoch(deletedAt.round()),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt.round()),
    );
  }
}

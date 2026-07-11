import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

final class LargeFileActionService {
  LargeFileActionService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'ai.spacepilot.app/file_actions';
  final MethodChannel _channel;

  bool get isSupported => defaultTargetPlatform == TargetPlatform.android;

  Future<void> open(String path) async {
    if (!isSupported) throw UnsupportedError('File preview is Android-only.');
    await _channel.invokeMethod<void>('openFile', {'path': path});
  }

  Future<void> share(String path) async {
    if (!isSupported) throw UnsupportedError('File sharing is Android-only.');
    await _channel.invokeMethod<void>('shareFile', {'path': path});
  }

  Future<LargeFileMoveResult> move({
    required String path,
    required LargeFileMoveDestination destination,
  }) async {
    if (!isSupported) throw UnsupportedError('File moving is Android-only.');

    final result = await _channel.invokeMethod<Object?>('moveFile', {
      'path': path,
      'destination': destination.platformValue,
    });
    if (result is! Map<Object?, Object?>) {
      throw StateError('File move returned an invalid payload.');
    }

    final newPath = result['path'];
    final filename = result['filename'];
    if (newPath is! String || filename is! String) {
      throw StateError('File move returned an invalid file path.');
    }

    return LargeFileMoveResult(path: newPath, filename: filename);
  }

  Future<LargeFileMoveResult> rename({
    required String path,
    required String filename,
  }) async {
    if (!isSupported) throw UnsupportedError('File renaming is Android-only.');

    final result = await _channel.invokeMethod<Object?>('renameFile', {
      'path': path,
      'filename': filename,
    });
    return LargeFileMoveResult.fromPlatform(result, action: 'rename');
  }

  Future<RecoverableFileResult> moveToRecovery({
    required String path,
    required int retentionDays,
  }) async {
    if (!isSupported) {
      throw UnsupportedError('Recoverable delete is Android-only.');
    }

    final result = await _channel.invokeMethod<Object?>('moveToRecovery', {
      'path': path,
      'retentionDays': retentionDays,
    });
    return RecoverableFileResult.fromPlatform(result);
  }

  Future<LargeFileMoveResult> restoreRecoveryItem({
    required String recoveryPath,
    required String originalPath,
  }) async {
    if (!isSupported) {
      throw UnsupportedError('Recovery restore is Android-only.');
    }

    final result = await _channel.invokeMethod<Object?>('restoreRecoveryItem', {
      'recoveryPath': recoveryPath,
      'originalPath': originalPath,
    });
    return LargeFileMoveResult.fromPlatform(result, action: 'restore');
  }

  Future<void> deleteRecoveryItem(String recoveryPath) async {
    if (!isSupported) {
      throw UnsupportedError('Recovery purge is Android-only.');
    }

    await _channel.invokeMethod<void>('deleteRecoveryItem', {
      'recoveryPath': recoveryPath,
    });
  }
}

enum LargeFileMoveDestination {
  downloads('Downloads', 'downloads'),
  dcim('DCIM', 'dcim'),
  movies('Movies', 'movies'),
  pictures('Pictures', 'pictures');

  const LargeFileMoveDestination(this.label, this.platformValue);

  final String label;
  final String platformValue;
}

@immutable
final class LargeFileMoveResult {
  const LargeFileMoveResult({required this.path, required this.filename});

  final String path;
  final String filename;

  static LargeFileMoveResult fromPlatform(
    Object? result, {
    required String action,
  }) {
    if (result is! Map<Object?, Object?>) {
      throw StateError('File $action returned an invalid payload.');
    }

    final newPath = result['path'];
    final filename = result['filename'];
    if (newPath is! String || filename is! String) {
      throw StateError('File $action returned an invalid file path.');
    }

    return LargeFileMoveResult(path: newPath, filename: filename);
  }
}

@immutable
final class RecoverableFileResult {
  const RecoverableFileResult({
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

  static RecoverableFileResult fromPlatform(Object? result) {
    if (result is! Map<Object?, Object?>) {
      throw StateError('Recoverable delete returned an invalid payload.');
    }

    final id = result['id'];
    final filename = result['filename'];
    final originalPath = result['originalPath'];
    final recoveryPath = result['recoveryPath'];
    final sizeBytes = result['sizeBytes'];
    final deletedAt = result['deletedAt'];
    final expiresAt = result['expiresAt'];
    if (id is! String ||
        filename is! String ||
        originalPath is! String ||
        recoveryPath is! String ||
        sizeBytes is! num ||
        deletedAt is! num ||
        expiresAt is! num) {
      throw StateError('Recoverable delete returned incomplete metadata.');
    }

    return RecoverableFileResult(
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

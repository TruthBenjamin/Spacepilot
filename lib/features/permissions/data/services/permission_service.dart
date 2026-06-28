import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

final class PermissionService {
  PermissionService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'ai.spacepilot.app/permissions';
  final MethodChannel _channel;

  Future<bool> hasStorageAccess() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    return await _channel.invokeMethod<bool>('hasStorageAccess') ?? false;
  }

  Future<bool> hasMediaAccess() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    return await _channel.invokeMethod<bool>('hasMediaAccess') ?? false;
  }

  Future<bool> requestStorageAccess() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    return await _channel.invokeMethod<bool>('requestStorageAccess') ?? false;
  }

  Future<bool> requestMediaAccess() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    return await _channel.invokeMethod<bool>('requestMediaAccess') ?? false;
  }

  Future<bool> requestRequiredAccess() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;

    final hasStorage = await hasStorageAccess() || await requestStorageAccess();
    if (!hasStorage) return false;

    return await hasMediaAccess() || await requestMediaAccess();
  }
}

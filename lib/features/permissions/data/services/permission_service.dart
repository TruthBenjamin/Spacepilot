import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

final class PermissionService {
  PermissionService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'ai.spacepilot.app/permissions';
  final MethodChannel _channel;

  Future<bool> hasStorageAccess() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    return _invokeBool('hasStorageAccess');
  }

  Future<bool> hasMediaAccess() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    return _invokeBool('hasMediaAccess');
  }

  Future<bool> requestStorageAccess() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    return _invokeBool('requestStorageAccess');
  }

  Future<bool> requestMediaAccess() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    return _invokeBool('requestMediaAccess');
  }

  Future<bool> requestRequiredAccess() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;

    final hasStorage = await hasStorageAccess() || await requestStorageAccess();
    if (!hasStorage) return false;

    return await hasMediaAccess() || await requestMediaAccess();
  }

  Future<bool> _invokeBool(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

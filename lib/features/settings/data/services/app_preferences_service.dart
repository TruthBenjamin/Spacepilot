import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

final class AppPreferencesService {
  AppPreferencesService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'ai.spacepilot.app/preferences';
  static final Map<String, String> _memoryStore = <String, String>{};

  final MethodChannel _channel;

  Future<String?> getString(String key) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return _memoryStore[key];
    }

    try {
      return await _channel.invokeMethod<String>('getString', {'key': key});
    } catch (_) {
      return _memoryStore[key];
    }
  }

  Future<void> setString(String key, String value) async {
    _memoryStore[key] = value;

    if (defaultTargetPlatform != TargetPlatform.android) return;

    try {
      await _channel.invokeMethod<void>('setString', {
        'key': key,
        'value': value,
      });
    } catch (_) {
      return;
    }
  }
}

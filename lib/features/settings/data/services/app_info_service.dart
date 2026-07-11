import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

final class AppInfoService {
  AppInfoService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'ai.spacepilot.app/app_info';
  final MethodChannel _channel;

  Future<String> version() async {
    if (defaultTargetPlatform != TargetPlatform.android) return 'Unavailable';
    try {
      return await _channel.invokeMethod<String>('getVersion') ?? 'Unavailable';
    } on PlatformException {
      return 'Unavailable';
    } on MissingPluginException {
      return 'Unavailable';
    }
  }
}

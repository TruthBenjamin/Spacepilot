import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

final class NotificationService {
  NotificationService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'ai.spacepilot.app/notifications';
  final MethodChannel _channel;

  Future<bool> requestPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on PlatformException {
      return false;
    }
  }
}

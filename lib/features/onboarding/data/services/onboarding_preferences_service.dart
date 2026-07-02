import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

final class OnboardingPreferencesService {
  OnboardingPreferencesService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'ai.spacepilot.app/preferences';
  final MethodChannel _channel;

  Future<bool> hasCompletedOnboarding() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>('hasCompletedOnboarding') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setOnboardingCompleted() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    try {
      await _channel.invokeMethod<void>('setOnboardingCompleted');
    } catch (_) {
      return;
    }
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/models/automation_rule.dart';
import '../../../scheduled_scans/domain/models/scheduled_scan_config.dart';

/// Bridges to AndroidX WorkManager. Workers emit notifications or purge only
/// expired files in SpacePilot's private recovery directory; they never scan or
/// delete arbitrary user files.
final class AutomationWorkmanagerService {
  AutomationWorkmanagerService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'ai.spacepilot.app/background_work';
  final MethodChannel _channel;

  Future<void> initialize() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _invoke('ensureRecoveryPurge');
  }

  Future<void> syncRules(Iterable<AutomationRule> rules) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    for (final rule in rules) {
      await _invoke('syncRule', {'rule': rule.toJson()});
    }
  }

  Future<void> cancelRule(AutomationRule rule) =>
      _invoke('cancel', {'workName': rule.workName});

  Future<void> syncScheduledScan(ScheduledScanConfig config) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final now = DateTime.now();
    await _invoke('syncScheduledScan', {
      'enabled': config.enabled,
      'frequencyDays': switch (config.frequency) {
        ScheduledScanFrequency.daily => 1,
        ScheduledScanFrequency.weekly => 7,
        ScheduledScanFrequency.monthly => 30,
      },
      'initialDelayMs': config
          .nextRunAfter(now)
          ?.difference(now)
          .inMilliseconds,
    });
  }

  Future<void> syncRecoveryPurge({required bool enabled}) =>
      _invoke('syncRecoveryPurge', {'enabled': enabled});

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel
          .invokeMethod<void>(method, arguments)
          .timeout(const Duration(seconds: 5));
    } on TimeoutException catch (error) {
      debugPrint('Background scheduling timed out: $error');
    } on PlatformException catch (error) {
      debugPrint('Background scheduling failed: ${error.message}');
    } on MissingPluginException catch (error) {
      debugPrint('Background scheduling is unavailable: $error');
    }
  }
}

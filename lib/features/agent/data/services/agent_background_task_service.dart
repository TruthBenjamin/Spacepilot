import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/models/agent_models.dart';

final class AgentBackgroundTaskService {
  AgentBackgroundTaskService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'ai.spacepilot.app/agent_background';
  final MethodChannel _channel;

  Future<bool> scheduleMonitoring() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    return _invokeBool('scheduleMonitoring');
  }

  Future<bool> cancelMonitoring() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    return _invokeBool('cancelMonitoring');
  }

  Future<List<StorageSnapshot>> loadSnapshots() async {
    if (defaultTargetPlatform != TargetPlatform.android) return const [];
    final List<Object?>? snapshots;
    try {
      snapshots = await _channel.invokeListMethod<Object?>('loadSnapshots');
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
    if (snapshots == null) return const [];

    return snapshots
        .whereType<Map<Object?, Object?>>()
        .map(StorageSnapshot.fromMap)
        .toList(growable: false);
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

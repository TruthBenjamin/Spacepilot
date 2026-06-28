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
    return await _channel.invokeMethod<bool>('scheduleMonitoring') ?? false;
  }

  Future<bool> cancelMonitoring() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    return await _channel.invokeMethod<bool>('cancelMonitoring') ?? false;
  }

  Future<List<StorageSnapshot>> loadSnapshots() async {
    if (defaultTargetPlatform != TargetPlatform.android) return const [];
    final snapshots = await _channel.invokeListMethod<Object?>('loadSnapshots');
    if (snapshots == null) return const [];

    return snapshots
        .whereType<Map<Object?, Object?>>()
        .map(StorageSnapshot.fromMap)
        .toList(growable: false);
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/models/models.dart';

final class AppAnalyzerService {
  AppAnalyzerService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'ai.spacepilot.app/app_analyzer';
  final MethodChannel _channel;

  bool get isSupported => defaultTargetPlatform == TargetPlatform.android;

  Future<InstalledAppsReport> analyzeInstalledApps() async {
    if (!isSupported) return const InstalledAppsReport.empty();

    final result = await _channel.invokeMethod<Object?>('analyzeInstalledApps');
    if (result is! Map<Object?, Object?>) {
      throw StateError('App analyzer returned an invalid payload.');
    }
    return _reportFromMap(result);
  }

  Future<bool> hasUsageAccess() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('hasUsageAccess') ?? false;
  }

  Future<void> openUsageAccessSettings() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('openUsageAccessSettings');
  }

  Future<void> openApp(String packageName) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('openApp', {'packageName': packageName});
  }

  Future<void> openAppInfo(String packageName) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('openAppInfo', {
      'packageName': packageName,
    });
  }

  Future<void> requestUninstall(String packageName) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('requestUninstall', {
      'packageName': packageName,
    });
  }
}

InstalledAppsReport _reportFromMap(Map<Object?, Object?> map) {
  final apps = map['apps'];
  final limitations = map['limitations'];
  return InstalledAppsReport(
    apps: apps is List<Object?>
        ? apps
              .whereType<Map<Object?, Object?>>()
              .map(_appFromMap)
              .toList(growable: false)
        : const [],
    hasUsageAccess: map['hasUsageAccess'] == true,
    generatedAt: _dateFromMillis(map['generatedAt']),
    limitations: limitations is List<Object?>
        ? limitations.whereType<String>().toList(growable: false)
        : const [],
  );
}

InstalledApp _appFromMap(Map<Object?, Object?> map) {
  final packageName = map['packageName'];
  final appName = map['appName'];
  if (packageName is! String || appName is! String) {
    throw const FormatException('Invalid installed app payload.');
  }

  return InstalledApp(
    packageName: packageName,
    appName: appName,
    versionName: map['versionName'] is String
        ? map['versionName'] as String
        : null,
    versionCode: _intOrNull(map['versionCode']),
    firstInstallTime: _dateFromMillis(map['firstInstallTime']),
    lastUpdateTime: _dateFromMillis(map['lastUpdateTime']),
    isSystemApp: map['isSystemApp'] == true,
    canLaunch: map['canLaunch'] == true,
    hasUsageAccess: map['hasUsageAccess'] == true,
    totalSizeBytes: _intOrNull(map['totalSizeBytes']),
    appSizeBytes: _intOrNull(map['appSizeBytes']),
    dataSizeBytes: _intOrNull(map['dataSizeBytes']),
    cacheSizeBytes: _intOrNull(map['cacheSizeBytes']),
    lastUsedTime: _dateFromMillis(map['lastUsedTime']),
    usageTimeMillis: _intOrNull(map['usageTimeMillis']),
  );
}

DateTime? _dateFromMillis(Object? value) {
  final millis = _intOrNull(value);
  if (millis == null || millis <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(millis);
}

int? _intOrNull(Object? value) {
  if (value is num) return value.toInt();
  return null;
}

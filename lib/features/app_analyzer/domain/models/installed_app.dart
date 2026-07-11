import 'package:flutter/foundation.dart';

@immutable
final class InstalledApp {
  const InstalledApp({
    required this.packageName,
    required this.appName,
    required this.versionName,
    required this.versionCode,
    required this.firstInstallTime,
    required this.lastUpdateTime,
    required this.isSystemApp,
    required this.canLaunch,
    required this.hasUsageAccess,
    this.totalSizeBytes,
    this.appSizeBytes,
    this.dataSizeBytes,
    this.cacheSizeBytes,
    this.lastUsedTime,
    this.usageTimeMillis,
  });

  final String packageName;
  final String appName;
  final String? versionName;
  final int? versionCode;
  final DateTime? firstInstallTime;
  final DateTime? lastUpdateTime;
  final bool isSystemApp;
  final bool canLaunch;
  final bool hasUsageAccess;
  final int? totalSizeBytes;
  final int? appSizeBytes;
  final int? dataSizeBytes;
  final int? cacheSizeBytes;
  final DateTime? lastUsedTime;
  final int? usageTimeMillis;

  bool get hasSizeData => totalSizeBytes != null || appSizeBytes != null;
  bool get hasUsageData => hasUsageAccess && lastUsedTime != null;

  InstalledApp copyWith({
    String? packageName,
    String? appName,
    String? versionName,
    int? versionCode,
    DateTime? firstInstallTime,
    DateTime? lastUpdateTime,
    bool? isSystemApp,
    bool? canLaunch,
    bool? hasUsageAccess,
    int? totalSizeBytes,
    int? appSizeBytes,
    int? dataSizeBytes,
    int? cacheSizeBytes,
    DateTime? lastUsedTime,
    int? usageTimeMillis,
  }) {
    return InstalledApp(
      packageName: packageName ?? this.packageName,
      appName: appName ?? this.appName,
      versionName: versionName ?? this.versionName,
      versionCode: versionCode ?? this.versionCode,
      firstInstallTime: firstInstallTime ?? this.firstInstallTime,
      lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
      isSystemApp: isSystemApp ?? this.isSystemApp,
      canLaunch: canLaunch ?? this.canLaunch,
      hasUsageAccess: hasUsageAccess ?? this.hasUsageAccess,
      totalSizeBytes: totalSizeBytes ?? this.totalSizeBytes,
      appSizeBytes: appSizeBytes ?? this.appSizeBytes,
      dataSizeBytes: dataSizeBytes ?? this.dataSizeBytes,
      cacheSizeBytes: cacheSizeBytes ?? this.cacheSizeBytes,
      lastUsedTime: lastUsedTime ?? this.lastUsedTime,
      usageTimeMillis: usageTimeMillis ?? this.usageTimeMillis,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is InstalledApp &&
            other.packageName == packageName &&
            other.appName == appName &&
            other.versionName == versionName &&
            other.versionCode == versionCode &&
            other.firstInstallTime == firstInstallTime &&
            other.lastUpdateTime == lastUpdateTime &&
            other.isSystemApp == isSystemApp &&
            other.canLaunch == canLaunch &&
            other.hasUsageAccess == hasUsageAccess &&
            other.totalSizeBytes == totalSizeBytes &&
            other.appSizeBytes == appSizeBytes &&
            other.dataSizeBytes == dataSizeBytes &&
            other.cacheSizeBytes == cacheSizeBytes &&
            other.lastUsedTime == lastUsedTime &&
            other.usageTimeMillis == usageTimeMillis;
  }

  @override
  int get hashCode {
    return Object.hash(
      packageName,
      appName,
      versionName,
      versionCode,
      firstInstallTime,
      lastUpdateTime,
      isSystemApp,
      canLaunch,
      hasUsageAccess,
      totalSizeBytes,
      appSizeBytes,
      dataSizeBytes,
      cacheSizeBytes,
      lastUsedTime,
      usageTimeMillis,
    );
  }
}

@immutable
final class InstalledAppsReport {
  const InstalledAppsReport({
    required this.apps,
    required this.hasUsageAccess,
    required this.generatedAt,
    required this.limitations,
  });

  const InstalledAppsReport.empty()
    : apps = const [],
      hasUsageAccess = false,
      generatedAt = null,
      limitations = const ['Installed app analysis is Android-only.'];

  final List<InstalledApp> apps;
  final bool hasUsageAccess;
  final DateTime? generatedAt;
  final List<String> limitations;

  int get measurableSizeBytes {
    return apps.fold<int>(
      0,
      (total, app) => total + (app.totalSizeBytes ?? app.appSizeBytes ?? 0),
    );
  }
}

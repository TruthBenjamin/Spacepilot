import 'package:flutter/foundation.dart';

enum AutomationRuleType {
  deleteScreenshots('Delete screenshots'),
  deleteApkInstallers('Delete APK installers'),
  weeklyScan('Weekly scan'),
  monthlyReport('Monthly report'),
  storageWarning('Storage warning');

  const AutomationRuleType(this.label);

  final String label;
}

enum AutomationRuleCadence {
  daily('Daily'),
  weekly('Weekly'),
  monthly('Monthly');

  const AutomationRuleCadence(this.label);

  final String label;
}

@immutable
final class AutomationRule {
  const AutomationRule({
    required this.id,
    required this.type,
    required this.name,
    required this.enabled,
    required this.cadence,
    this.ageThresholdDays,
    this.storageWarningFreePercent,
    this.createdAt,
  });

  factory AutomationRule.deleteScreenshotsAfter({
    required String id,
    required int days,
    bool enabled = true,
    DateTime? createdAt,
  }) {
    return AutomationRule(
      id: id,
      type: AutomationRuleType.deleteScreenshots,
      name: 'Delete screenshots after $days days',
      enabled: enabled,
      cadence: AutomationRuleCadence.daily,
      ageThresholdDays: days,
      createdAt: createdAt,
    );
  }

  factory AutomationRule.deleteApkInstallers({
    required String id,
    bool enabled = true,
    DateTime? createdAt,
  }) {
    return AutomationRule(
      id: id,
      type: AutomationRuleType.deleteApkInstallers,
      name: 'Delete APK installers',
      enabled: enabled,
      cadence: AutomationRuleCadence.daily,
      createdAt: createdAt,
    );
  }

  factory AutomationRule.weeklyScan({
    required String id,
    bool enabled = true,
    DateTime? createdAt,
  }) {
    return AutomationRule(
      id: id,
      type: AutomationRuleType.weeklyScan,
      name: 'Weekly scan',
      enabled: enabled,
      cadence: AutomationRuleCadence.weekly,
      createdAt: createdAt,
    );
  }

  factory AutomationRule.monthlyReport({
    required String id,
    bool enabled = true,
    DateTime? createdAt,
  }) {
    return AutomationRule(
      id: id,
      type: AutomationRuleType.monthlyReport,
      name: 'Monthly report',
      enabled: enabled,
      cadence: AutomationRuleCadence.monthly,
      createdAt: createdAt,
    );
  }

  factory AutomationRule.storageWarning({
    required String id,
    int freePercent = 10,
    bool enabled = true,
    DateTime? createdAt,
  }) {
    return AutomationRule(
      id: id,
      type: AutomationRuleType.storageWarning,
      name: 'Storage warning below $freePercent%',
      enabled: enabled,
      cadence: AutomationRuleCadence.daily,
      storageWarningFreePercent: freePercent,
      createdAt: createdAt,
    );
  }

  final String id;
  final AutomationRuleType type;
  final String name;
  final bool enabled;
  final AutomationRuleCadence cadence;
  final int? ageThresholdDays;
  final int? storageWarningFreePercent;
  final DateTime? createdAt;

  String get workName => 'automation_rule_$id';
  String get taskName => 'spacepilot.${type.name}';

  Duration get repeatInterval {
    return switch (cadence) {
      AutomationRuleCadence.daily => const Duration(days: 1),
      AutomationRuleCadence.weekly => const Duration(days: 7),
      AutomationRuleCadence.monthly => const Duration(days: 30),
    };
  }

  AutomationRule copyWith({
    String? id,
    AutomationRuleType? type,
    String? name,
    bool? enabled,
    AutomationRuleCadence? cadence,
    int? ageThresholdDays,
    int? storageWarningFreePercent,
    DateTime? createdAt,
  }) {
    return AutomationRule(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      cadence: cadence ?? this.cadence,
      ageThresholdDays: ageThresholdDays ?? this.ageThresholdDays,
      storageWarningFreePercent:
          storageWarningFreePercent ?? this.storageWarningFreePercent,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'name': name,
    'enabled': enabled,
    'cadence': cadence.name,
    'ageThresholdDays': ageThresholdDays,
    'storageWarningFreePercent': storageWarningFreePercent,
    'createdAt': createdAt?.millisecondsSinceEpoch,
  };

  static AutomationRule? fromJson(Object? value) {
    if (value is! Map<String, Object?> ||
        value['id'] is! String ||
        value['name'] is! String) {
      return null;
    }
    final type = AutomationRuleType.values
        .where((candidate) => candidate.name == value['type'])
        .firstOrNull;
    final cadence = AutomationRuleCadence.values
        .where((candidate) => candidate.name == value['cadence'])
        .firstOrNull;
    if (type == null || cadence == null) return null;
    final createdAt = value['createdAt'];
    return AutomationRule(
      id: value['id']! as String,
      type: type,
      name: value['name']! as String,
      enabled: value['enabled'] == true,
      cadence: cadence,
      ageThresholdDays: value['ageThresholdDays'] is num
          ? (value['ageThresholdDays'] as num).round()
          : null,
      storageWarningFreePercent: value['storageWarningFreePercent'] is num
          ? (value['storageWarningFreePercent'] as num).round().clamp(1, 100)
          : null,
      createdAt: createdAt is num
          ? DateTime.fromMillisecondsSinceEpoch(createdAt.round())
          : null,
    );
  }
}

@immutable
final class AutomationPlan {
  const AutomationPlan({
    required this.enabledRules,
    required this.disabledRules,
    required this.matchedFileCount,
    required this.estimatedSavingsBytes,
    required this.scheduledTaskCount,
  });

  final int enabledRules;
  final int disabledRules;
  final int matchedFileCount;
  final int estimatedSavingsBytes;
  final int scheduledTaskCount;
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../duplicates/presentation/providers/duplicate_groups_provider.dart';
import '../../../storage/presentation/providers/storage_scan_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../data/services/automation_engine.dart';
import '../../data/services/automation_workmanager_service.dart';
import '../../data/services/auto_clean_rule_engine.dart';
import '../../domain/models/automation_rule.dart';
import '../../domain/models/auto_clean_rules.dart';

final autoCleanRuleEngineProvider = Provider<AutoCleanRuleEngine>(
  (ref) => const AutoCleanRuleEngine(),
);

final automationEngineProvider = Provider<AutomationEngine>(
  (ref) => const AutomationEngine(),
);

final automationWorkmanagerServiceProvider =
    Provider<AutomationWorkmanagerService>(
      (ref) => AutomationWorkmanagerService(),
    );

final autoCleanRulesProvider =
    NotifierProvider<AutoCleanRulesController, AutoCleanRules>(
      AutoCleanRulesController.new,
    );

final automationRulesProvider =
    NotifierProvider<AutomationRulesController, List<AutomationRule>>(
      AutomationRulesController.new,
    );

final automationPlanProvider = FutureProvider<AutomationPlan>((ref) async {
  final rules = ref.watch(automationRulesProvider);
  final scan = await ref.watch(storageScanProvider.future);

  return ref
      .read(automationEngineProvider)
      .buildPlan(rules: rules, files: scan.files);
});

final automationExecutionHistoryProvider =
    NotifierProvider<
      AutomationExecutionHistoryController,
      List<AutomationExecutionEvent>
    >(AutomationExecutionHistoryController.new);

final autoCleanPlanProvider = FutureProvider<AutoCleanPlan>((ref) async {
  final rules = ref.watch(autoCleanRulesProvider);
  if (!rules.enabled) {
    return const AutoCleanPlan(
      ruleCount: 0,
      fileCount: 0,
      estimatedSavingsBytes: 0,
    );
  }

  final scan = await ref.watch(storageScanProvider.future);
  final duplicateGroups = await ref.watch(duplicateGroupsProvider.future);

  return ref
      .read(autoCleanRuleEngineProvider)
      .buildPlan(
        rules: rules,
        files: scan.files,
        duplicateGroups: duplicateGroups,
      );
});

final class AutoCleanRulesController extends Notifier<AutoCleanRules> {
  static const _prefsKey = 'auto_clean_rules_v1';
  bool _hasLocalUpdate = false;

  @override
  AutoCleanRules build() {
    unawaited(_load());
    return const AutoCleanRules.defaults();
  }

  void setEnabled(bool value) => _update(state.copyWith(enabled: value));

  void setDuplicateCopies(bool value) {
    _update(state.copyWith(includeDuplicateCopies: value));
  }

  void setApkInstallers(bool value) {
    _update(state.copyWith(includeApkInstallers: value));
  }

  void setOldScreenshots(bool value) {
    _update(state.copyWith(includeOldScreenshots: value));
  }

  void setUnusedFiles(bool value) {
    _update(state.copyWith(includeUnusedFiles: value));
  }

  void setEmptyFolders(bool value) {
    _update(state.copyWith(includeEmptyFolders: value));
  }

  Future<void> _load() async {
    final encoded = await ref
        .read(appPreferencesServiceProvider)
        .getString(_prefsKey);
    if (encoded == null || encoded.isEmpty || _hasLocalUpdate) return;
    try {
      state = AutoCleanRules.fromJson(jsonDecode(encoded));
    } catch (_) {
      return;
    }
  }

  void _update(AutoCleanRules next) {
    _hasLocalUpdate = true;
    state = next;
    unawaited(
      ref
          .read(appPreferencesServiceProvider)
          .setString(_prefsKey, jsonEncode(next.toJson())),
    );
  }
}

final class AutomationRulesController extends Notifier<List<AutomationRule>> {
  static const _prefsKey = 'automation_rules_v1';
  bool _hasLocalUpdate = false;

  @override
  List<AutomationRule> build() {
    final rules = ref.read(automationEngineProvider).defaultRules();
    unawaited(_load());
    return rules;
  }

  void addRule({
    required AutomationRuleType type,
    int? ageThresholdDays,
    int? storageWarningFreePercent,
  }) {
    final createdAt = DateTime.now();
    final rule = ref
        .read(automationEngineProvider)
        .createRule(
          type: type,
          id: '${type.name}_${createdAt.microsecondsSinceEpoch}',
          ageThresholdDays: ageThresholdDays,
          storageWarningFreePercent: storageWarningFreePercent,
          now: createdAt,
        );
    state = [...state, rule];
    _persist();
    _sync(state);
  }

  void setRuleEnabled(String id, bool enabled) {
    state = [
      for (final rule in state)
        if (rule.id == id) rule.copyWith(enabled: enabled) else rule,
    ];
    _persist();
    _sync(state);
  }

  void updateRule(
    String id, {
    AutomationRuleCadence? cadence,
    int? ageThresholdDays,
    int? storageWarningFreePercent,
  }) {
    state = [
      for (final rule in state)
        if (rule.id == id)
          rule.copyWith(
            name: switch (rule.type) {
              AutomationRuleType.deleteScreenshots =>
                'Delete screenshots after ${ageThresholdDays ?? rule.ageThresholdDays ?? 90} days',
              AutomationRuleType.storageWarning =>
                'Storage warning below ${storageWarningFreePercent ?? rule.storageWarningFreePercent ?? 10}%',
              _ => rule.name,
            },
            cadence: cadence,
            ageThresholdDays: ageThresholdDays,
            storageWarningFreePercent: storageWarningFreePercent,
          )
        else
          rule,
    ];
    _persist();
    _sync(state);
  }

  void removeRule(String id) {
    final removed = state.where((rule) => rule.id == id).toList();
    state = state.where((rule) => rule.id != id).toList(growable: false);
    _persist();
    _sync(state);
    for (final rule in removed) {
      ref.read(automationWorkmanagerServiceProvider).cancelRule(rule);
    }
  }

  Future<void> _sync(List<AutomationRule> rules) {
    return ref
        .read(automationWorkmanagerServiceProvider)
        .syncRules(rules)
        .then((_) {
          final history = ref.read(automationExecutionHistoryProvider.notifier);
          for (final rule in rules.where((rule) => rule.enabled)) {
            history.recordScheduled(rule);
          }
        })
        .catchError((Object error) {
          final history = ref.read(automationExecutionHistoryProvider.notifier);
          for (final rule in rules.where((rule) => rule.enabled)) {
            history.recordFailure(rule, error);
          }
        });
  }

  Future<void> _load() async {
    final encoded = await ref
        .read(appPreferencesServiceProvider)
        .getString(_prefsKey);
    if (encoded == null || encoded.isEmpty || _hasLocalUpdate) {
      await _sync(state);
      return;
    }
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List<Object?>) return;
      final loaded = decoded
          .map(AutomationRule.fromJson)
          .nonNulls
          .toList(growable: false);
      if (loaded.isNotEmpty && !_hasLocalUpdate) state = loaded;
    } catch (_) {
      // Keep safe defaults if persisted data is malformed.
    }
    await _sync(state);
  }

  void _persist() {
    _hasLocalUpdate = true;
    unawaited(
      ref
          .read(appPreferencesServiceProvider)
          .setString(
            _prefsKey,
            jsonEncode(state.map((rule) => rule.toJson()).toList()),
          ),
    );
  }
}

final class AutomationExecutionEvent {
  const AutomationExecutionEvent({
    required this.ruleId,
    required this.ruleName,
    required this.startedAt,
    required this.status,
    this.message,
  });

  final String ruleId;
  final String ruleName;
  final DateTime startedAt;
  final AutomationExecutionStatus status;
  final String? message;

  Map<String, Object?> toJson() => {
    'ruleId': ruleId,
    'ruleName': ruleName,
    'startedAt': startedAt.millisecondsSinceEpoch,
    'status': status.name,
    'message': message,
  };

  static AutomationExecutionEvent? fromJson(Object? value) {
    if (value is! Map<String, Object?> ||
        value['ruleId'] is! String ||
        value['ruleName'] is! String ||
        value['startedAt'] is! num) {
      return null;
    }
    return AutomationExecutionEvent(
      ruleId: value['ruleId']! as String,
      ruleName: value['ruleName']! as String,
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        (value['startedAt']! as num).round(),
      ),
      status: AutomationExecutionStatus.values.firstWhere(
        (status) => status.name == value['status'],
        orElse: () => AutomationExecutionStatus.failed,
      ),
      message: value['message'] as String?,
    );
  }
}

enum AutomationExecutionStatus { scheduled, succeeded, failed }

final class AutomationExecutionHistoryController
    extends Notifier<List<AutomationExecutionEvent>> {
  static const _prefsKey = 'automation_execution_history_v1';
  bool _hasLocalUpdate = false;

  @override
  List<AutomationExecutionEvent> build() {
    unawaited(_load());
    return const [];
  }

  void recordScheduled(AutomationRule rule) {
    state = [
      AutomationExecutionEvent(
        ruleId: rule.id,
        ruleName: rule.name,
        startedAt: DateTime.now(),
        status: AutomationExecutionStatus.scheduled,
        message: 'Registered with the platform scheduler.',
      ),
      ...state,
    ].take(30).toList(growable: false);
    _persist();
  }

  void recordFailure(AutomationRule rule, Object error) {
    state = [
      AutomationExecutionEvent(
        ruleId: rule.id,
        ruleName: rule.name,
        startedAt: DateTime.now(),
        status: AutomationExecutionStatus.failed,
        message: error.toString(),
      ),
      ...state,
    ].take(30).toList(growable: false);
    _persist();
  }

  Future<void> _load() async {
    final encoded = await ref
        .read(appPreferencesServiceProvider)
        .getString(_prefsKey);
    if (encoded == null || encoded.isEmpty || _hasLocalUpdate) return;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List<Object?>) return;
      final loaded = decoded
          .map(AutomationExecutionEvent.fromJson)
          .nonNulls
          .take(30)
          .toList(growable: false);
      if (!_hasLocalUpdate) state = loaded;
    } catch (_) {
      return;
    }
  }

  void _persist() {
    _hasLocalUpdate = true;
    unawaited(
      ref
          .read(appPreferencesServiceProvider)
          .setString(
            _prefsKey,
            jsonEncode(state.map((event) => event.toJson()).toList()),
          ),
    );
  }
}

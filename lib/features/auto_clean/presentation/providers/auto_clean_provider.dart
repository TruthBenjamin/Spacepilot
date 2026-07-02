import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../duplicates/presentation/providers/duplicate_groups_provider.dart';
import '../../../storage/presentation/providers/storage_scan_provider.dart';
import '../../data/services/auto_clean_rule_engine.dart';
import '../../domain/models/auto_clean_rules.dart';

final autoCleanRuleEngineProvider = Provider<AutoCleanRuleEngine>(
  (ref) => const AutoCleanRuleEngine(),
);

final autoCleanRulesProvider =
    NotifierProvider<AutoCleanRulesController, AutoCleanRules>(
      AutoCleanRulesController.new,
    );

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
  @override
  AutoCleanRules build() => const AutoCleanRules.defaults();

  void setEnabled(bool value) => state = state.copyWith(enabled: value);

  void setDuplicateCopies(bool value) {
    state = state.copyWith(includeDuplicateCopies: value);
  }

  void setApkInstallers(bool value) {
    state = state.copyWith(includeApkInstallers: value);
  }

  void setOldScreenshots(bool value) {
    state = state.copyWith(includeOldScreenshots: value);
  }

  void setUnusedFiles(bool value) {
    state = state.copyWith(includeUnusedFiles: value);
  }

  void setEmptyFolders(bool value) {
    state = state.copyWith(includeEmptyFolders: value);
  }
}

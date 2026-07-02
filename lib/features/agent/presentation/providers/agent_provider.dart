import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../analytics/presentation/providers/analytics_provider.dart';
import '../../../auto_clean/presentation/providers/auto_clean_provider.dart';
import '../../../storage/presentation/providers/storage_scan_provider.dart';
import '../../data/services/agent_background_task_service.dart';
import '../../data/services/agent_engine.dart';
import '../../domain/models/agent_models.dart';

final agentEngineProvider = Provider<AgentEngine>((ref) => const AgentEngine());

final agentBackgroundTaskServiceProvider = Provider<AgentBackgroundTaskService>(
  (ref) => AgentBackgroundTaskService(),
);

final agentMonitoringProvider =
    AsyncNotifierProvider<AgentMonitoringController, bool>(
      AgentMonitoringController.new,
    );

final agentReportProvider = FutureProvider<AgentReport>((ref) async {
  final scan = await ref.watch(storageScanProvider.future);
  if (!scan.hasScanned) {
    throw StateError('A storage scan is required before agent reporting.');
  }

  final analytics = await ref.watch(storageAnalyticsProvider.future);
  final autoCleanPlan = await ref.watch(autoCleanPlanProvider.future);
  final snapshots = await ref
      .read(agentBackgroundTaskServiceProvider)
      .loadSnapshots();

  return ref
      .read(agentEngineProvider)
      .generateReport(
        snapshots: snapshots,
        analytics: analytics,
        autoCleanPlan: autoCleanPlan,
      );
});

final class AgentMonitoringController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    return ref.read(agentBackgroundTaskServiceProvider).scheduleMonitoring();
  }

  Future<void> setEnabled(bool enabled) async {
    state = const AsyncLoading();
    final service = ref.read(agentBackgroundTaskServiceProvider);
    final result = enabled
        ? await service.scheduleMonitoring()
        : await service.cancelMonitoring();
    state = AsyncData(result);
  }
}

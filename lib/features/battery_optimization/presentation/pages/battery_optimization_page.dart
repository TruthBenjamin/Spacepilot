import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../routes/app_navigation.dart';
import '../../../../shared/presentation/widgets/space_background.dart';
import '../../../power/presentation/providers/power_thermal_provider.dart';
import '../../../scheduled_scans/presentation/providers/scheduled_scan_provider.dart';
import '../providers/battery_optimization_provider.dart';

class BatteryOptimizationPage extends ConsumerWidget {
  const BatteryOptimizationPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(powerThermalSnapshotProvider);
    final recommendations = ref.watch(batteryRecommendationsProvider);
    final scheduled = ref.watch(scheduledScanProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Power advisor')),
      body: SpaceBackground(
        child: SafeArea(
          child: snapshot.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Text(
                error is UnsupportedError
                    ? 'Power Advisor is available on Android.'
                    : 'Battery information is unavailable.',
              ),
            ),
            data: (value) => SpacePageList(
              children: [
                SpaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value.batteryLevel == null
                            ? 'Battery level unavailable'
                            : '${value.batteryLevel}%',
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        value.charging
                            ? 'Charging via ${value.powerSource.name}'
                            : 'On battery power',
                      ),
                      Text(
                        value.powerSaveMode
                            ? 'Battery Saver on'
                            : 'Battery Saver off',
                      ),
                      Text(
                        value.batteryTemperatureCelsius == null
                            ? 'Temperature unavailable'
                            : '${value.batteryTemperatureCelsius!.toStringAsFixed(1)} °C',
                      ),
                      Text(
                        value.batteryHealth == null
                            ? 'Battery health unavailable'
                            : 'Android health status: ${value.batteryHealth}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SpaceCard(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Scheduled SpacePilot scans'),
                    subtitle: Text(
                      scheduled.enabled
                          ? 'Enabled — may run non-essential storage work'
                          : 'Disabled',
                    ),
                    value: scheduled.enabled,
                    onChanged: (enabled) => ref
                        .read(scheduledScanProvider.notifier)
                        .setEnabled(enabled),
                  ),
                ),
                const SizedBox(height: 16),
                SpaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Power recommendations',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      recommendations.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (_, _) =>
                            const Text('Recommendations unavailable.'),
                        data: (items) => items.isEmpty
                            ? const Text(
                                'No optimization opportunity is indicated by current signals.',
                              )
                            : Column(
                                children: [
                                  for (final item in items)
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(
                                        Icons.battery_saver_outlined,
                                      ),
                                      title: Text(item.title),
                                      subtitle: Text(
                                        '${item.reason}\n${item.expectedBenefit}',
                                      ),
                                      isThreeLine: true,
                                    ),
                                ],
                              ),
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: () {
                              ref.invalidate(powerThermalSnapshotProvider);
                              ref.invalidate(batteryRecommendationsProvider);
                            },
                            icon: const Icon(Icons.fact_check_outlined),
                            label: const Text('Review Power Optimization'),
                          ),
                          OutlinedButton(
                            onPressed: () => ref
                                .read(powerThermalServiceProvider)
                                .openBatterySaverSettings(),
                            child: const Text('Battery Saver'),
                          ),
                          OutlinedButton(
                            onPressed: () => ref
                                .read(powerThermalServiceProvider)
                                .openBatteryUsageSettings(),
                            child: const Text('Battery usage'),
                          ),
                          OutlinedButton(
                            onPressed: context.pushAutomation,
                            child: const Text('Automation'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const SpaceCard(
                  child: Text(
                    'SpacePilot reports Android-provided battery signals and its own background configuration. It cannot repair the battery, increase capacity, force-stop other apps, or promise a numeric battery-life improvement.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

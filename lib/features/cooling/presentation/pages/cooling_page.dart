import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/presentation/widgets/space_background.dart';
import '../../../power/presentation/providers/power_thermal_provider.dart';
import '../providers/cooling_provider.dart';

class CoolingPage extends ConsumerWidget {
  const CoolingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final advice = ref.watch(coolingAdviceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Thermal advisor')),
      body: SpaceBackground(
        child: SafeArea(
          child: advice.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _Message(
              title: 'Thermal data unavailable',
              message: error is UnsupportedError
                  ? 'Thermal signals are supported on Android devices.'
                  : 'Android did not provide power and thermal signals.',
              onRetry: () => ref.invalidate(coolingAdviceProvider),
            ),
            data: (value) => SpacePageList(
              children: [
                SpaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value.classification.name.toUpperCase(),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        value.snapshot.thermalStatus == null
                            ? 'Android thermal status unavailable'
                            : 'Android thermal status: ${value.snapshot.thermalStatus}',
                      ),
                      Text(
                        value.snapshot.batteryTemperatureCelsius == null
                            ? 'Battery temperature unavailable'
                            : 'Battery temperature: ${value.snapshot.batteryTemperatureCelsius!.toStringAsFixed(1)} °C',
                      ),
                      Text(
                        value.snapshot.charging
                            ? 'Charging via ${value.snapshot.powerSource.name}'
                            : 'Not charging',
                      ),
                      Text(
                        value.snapshot.powerSaveMode
                            ? 'Battery Saver on'
                            : 'Battery Saver off',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SpaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Measured factors',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      ...value.factors.map(
                        (text) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.analytics_outlined),
                          title: Text(text),
                        ),
                      ),
                      if (value.factors.isEmpty)
                        const Text('No measurable heat factors were detected.'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SpaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recommendations',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      ...value.recommendations.map(
                        (text) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.tips_and_updates_outlined),
                          title: Text(text),
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: () =>
                                ref.invalidate(coolingAdviceProvider),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Optimize Thermal Conditions'),
                          ),
                          OutlinedButton(
                            onPressed: () => ref
                                .read(powerThermalServiceProvider)
                                .openDisplaySettings(),
                            child: const Text('Display settings'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const SpaceCard(
                  child: Text(
                    'SpacePilot cannot physically cool your device or control Android thermal management. This advisor interprets Android thermal status and battery temperature when the device exposes them. Normal: status 0 or under 40 °C; Elevated: status 1–2 or 40–44.9 °C; High: status 3–4 or 45–49.9 °C; Critical: status 5–6 or at least 50 °C. Android thermal status takes precedence.',
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

class _Message extends StatelessWidget {
  const _Message({
    required this.title,
    required this.message,
    required this.onRetry,
  });
  final String title;
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

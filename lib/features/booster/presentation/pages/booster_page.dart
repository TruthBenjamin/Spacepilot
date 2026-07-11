import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../routes/app_navigation.dart';
import '../../../../shared/presentation/widgets/space_background.dart';
import '../../data/services/ram_booster_service.dart';
import '../providers/ram_booster_provider.dart';

class BoosterPage extends ConsumerWidget {
  const BoosterPage({super.key});

  Future<void> _applyBoost(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(ramBoostProvider.notifier).boost();
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(_boostMessage(result))));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final snapshot = ref.watch(ramSnapshotProvider);
    final boost = ref.watch(ramBoostProvider);
    final latestBoost = boost.value;

    return Scaffold(
      appBar: AppBar(title: const Text('RAM Booster')),
      body: SpaceBackground(
        child: SafeArea(
          child: SpacePageList(
            children: [
              SpaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.memory_rounded,
                          color: colorScheme.primary,
                          size: 30,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Optimize phone performance',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'SpacePilot checks live memory pressure, trims its own memory use, and asks Android to clear safe background app processes.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 18),
                    snapshot.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (error, _) => Text(error.toString()),
                      data: (value) => _RamMeter(snapshot: value),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: boost.isLoading
                          ? null
                          : () => _applyBoost(context, ref),
                      icon: boost.isLoading
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                              ),
                            )
                          : const Icon(Icons.flash_on_rounded),
                      label: Text(
                        boost.isLoading ? 'Boosting RAM' : 'Boost RAM now',
                      ),
                    ),
                    if (latestBoost != null) ...[
                      const SizedBox(height: 16),
                      _BoostSummary(result: latestBoost),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SpaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Performance actions',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _ActionTile(
                      icon: Icons.auto_fix_high_rounded,
                      title: 'One-step junk cleanup',
                      subtitle: 'Remove automatically detected temp files.',
                      onTap: () => context.pushJunkCleaner(),
                    ),
                    _ActionTile(
                      icon: Icons.memory_rounded,
                      title: 'Clear background RAM',
                      subtitle: 'Ask Android to reclaim idle app processes.',
                      onTap: boost.isLoading
                          ? null
                          : () => _applyBoost(context, ref),
                    ),
                    _ActionTile(
                      icon: Icons.apps_rounded,
                      title: 'Manage heavy apps',
                      subtitle: 'Review apps with high storage and cache use.',
                      onTap: () => context.pushAppAnalyzer(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RamMeter extends StatelessWidget {
  const _RamMeter({required this.snapshot});

  final RamSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (!snapshot.supported) {
      return const Text('RAM booster is available on Android devices.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: snapshot.usageFraction.clamp(0, 1),
            minHeight: 10,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _MetricTile(label: 'Used', value: _bytes(snapshot.usedBytes)),
            _MetricTile(
              label: 'Available',
              value: _bytes(snapshot.availableBytes),
            ),
            _MetricTile(label: 'Total', value: _bytes(snapshot.totalBytes)),
            _MetricTile(
              label: 'Pressure',
              value: snapshot.lowMemory ? 'High' : 'Normal',
              color: snapshot.lowMemory ? colorScheme.error : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _BoostSummary extends StatelessWidget {
  const _BoostSummary({required this.result});

  final RamBoostResult result;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Boost summary',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(_boostMessage(result)),
          if (result.limitations.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              result.limitations.first,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 132,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: onTap != null,
      onTap: onTap,
      leading: CircleAvatar(child: Icon(icon)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}

String _boostMessage(RamBoostResult result) {
  if (!result.supported) return 'RAM boosting is available on Android devices.';
  final reclaimed = result.reclaimedBytes;
  final apps = result.optimizedAppCount;
  if (reclaimed > 0) {
    return 'Reclaimed ${_bytes(reclaimed)} after optimizing $apps background ${apps == 1 ? 'app' : 'apps'}.';
  }
  return 'Optimized $apps background ${apps == 1 ? 'app' : 'apps'}; Android reported stable memory pressure.';
}

String _bytes(int bytes) {
  var value = bytes.toDouble();
  var unit = 0;
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}

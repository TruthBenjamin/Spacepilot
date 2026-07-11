import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../analytics/domain/models/storage_analytics.dart';
import '../../../analytics/presentation/providers/analytics_provider.dart';
import '../../../cleanup/domain/models/cleanup_candidate.dart';
import '../../../cleanup/presentation/providers/cleanup_center_provider.dart';
import '../../../storage/domain/models/storage_history_entry.dart';
import '../../../storage/domain/models/storage_stats.dart';
import '../../../storage/presentation/providers/device_storage_provider.dart';
import '../../../storage/presentation/providers/storage_history_provider.dart';
import '../../../../routes/app_navigation.dart';
import '../../../../shared/presentation/widgets/space_background.dart';
import '../../domain/models/device_health_report.dart';
import '../providers/device_health_provider.dart';

class DeviceHealthPage extends ConsumerWidget {
  const DeviceHealthPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(deviceHealthReportProvider);
    final stats = ref.watch(deviceStorageStatsProvider);
    final analytics = ref.watch(storageAnalyticsProvider);
    final cleanup = ref.watch(cleanupCenterReportProvider);
    final history = ref.watch(storageHistoryProvider);

    Future<void> refresh() async {
      ref
        ..invalidate(deviceStorageStatsProvider)
        ..invalidate(storageAnalyticsProvider)
        ..invalidate(cleanupCenterReportProvider)
        ..invalidate(storageHistoryProvider)
        ..invalidate(deviceHealthReportProvider);
      await ref.read(deviceHealthReportProvider.future);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Device Health')),
      body: SpaceBackground(
        child: report.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) =>
              _HealthError(error: error, onRetry: refresh),
          data: (health) {
            final storage = stats.value;
            final storageAnalytics = analytics.value;
            if (storage == null || storageAnalytics == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return RefreshIndicator(
              onRefresh: refresh,
              child: _HealthContent(
                health: health,
                stats: storage,
                analytics: storageAnalytics,
                cleanup: cleanup.value,
                history: history.value ?? const [],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HealthContent extends StatelessWidget {
  const _HealthContent({
    required this.health,
    required this.stats,
    required this.analytics,
    required this.cleanup,
    required this.history,
  });

  final DeviceHealthReport health;
  final StorageStats stats;
  final StorageAnalytics analytics;
  final CleanupCenterReport? cleanup;
  final List<StorageHistoryEntry> history;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final growth = _storageGrowth(history);
    final opportunity =
        cleanup?.recoverableBytes ??
        analytics.duplicateBytes + analytics.junkBytes + analytics.unusedBytes;

    return SpacePageList(
      children: [
        SpaceCard(
          child: Row(
            children: [
              SizedBox.square(
                dimension: 92,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: health.score / 100,
                      strokeWidth: 9,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                    ),
                    Text(
                      '${health.score}',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      health.category.label,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text('Measured storage health, scored out of 100.'),
                    const SizedBox(height: 8),
                    Text(
                      'Updated ${_formatDateTime(stats.lastUpdated)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Measured signals', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        _MetricGrid(
          children: [
            _MetricTile(
              icon: Icons.storage_outlined,
              label: 'Storage health',
              value: '${(stats.freePercent * 100).toStringAsFixed(1)}% free',
              detail: '${_formatBytes(stats.freeBytes)} available',
            ),
            _MetricTile(
              icon: Icons.copy_all_outlined,
              label: 'Duplicate impact',
              value: _formatBytes(analytics.duplicateBytes),
              detail: '${analytics.duplicateGroups} exact groups',
            ),
            _MetricTile(
              icon: Icons.cleaning_services_outlined,
              label: 'Cleanup opportunity',
              value: _formatBytes(opportunity),
              detail: cleanup?.hasScanned == true
                  ? '${cleanup!.candidateCount} review items'
                  : 'Run Smart Scan for categories',
            ),
            _MetricTile(
              icon: growth == null
                  ? Icons.timeline_outlined
                  : growth >= 0
                  ? Icons.trending_up
                  : Icons.trending_down,
              label: 'Storage growth',
              value: growth == null
                  ? 'No history yet'
                  : '${growth >= 0 ? '+' : '-'}${_formatBytes(growth.abs())}',
              detail: history.length < 2
                  ? 'Two scans are required'
                  : 'Since the previous recorded scan',
            ),
          ],
        ),
        const SizedBox(height: 20),
        _ScoreExplanation(health: health),
        const SizedBox(height: 20),
        Text(
          'Recommended actions',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        SpaceCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _ActionRow(
                icon: Icons.auto_awesome_outlined,
                title: 'Review cleanup opportunities',
                subtitle: health.suggestions.first,
                onTap: context.pushScanResults,
              ),
              const Divider(height: 1),
              _ActionRow(
                icon: Icons.copy_all_outlined,
                title: 'Inspect exact duplicates',
                subtitle: '${analytics.duplicateGroups} measured groups',
                onTap: context.pushDuplicates,
              ),
              const Divider(height: 1),
              _ActionRow(
                icon: Icons.folder_copy_outlined,
                title: 'Review large files',
                subtitle: 'Open the existing large-file explorer',
                onTap: context.pushLargeFiles,
              ),
              const Divider(height: 1),
              _ActionRow(
                icon: Icons.timeline_outlined,
                title: 'View storage history',
                subtitle: '${history.length} recorded snapshots',
                onTap: context.pushStorageTimeline,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Battery, temperature, memory, and performance are not included because this score only uses signals SpacePilot can measure reliably.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ScoreExplanation extends StatelessWidget {
  const _ScoreExplanation({required this.health});

  final DeviceHealthReport health;

  @override
  Widget build(BuildContext context) {
    final breakdown = health.breakdown;
    return SpaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How the score works',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(health.explanation),
          const SizedBox(height: 14),
          _PenaltyRow(
            label: 'Storage usage',
            points: breakdown.storageUsagePenalty,
          ),
          _PenaltyRow(
            label: 'Exact duplicates',
            points: breakdown.duplicateFilesPenalty,
          ),
          _PenaltyRow(
            label: 'Junk and stale files',
            points: breakdown.junkFilesPenalty,
          ),
          _PenaltyRow(
            label: 'Old downloads',
            points: breakdown.oldDownloadsPenalty,
          ),
          _PenaltyRow(
            label: 'Empty folders',
            points: breakdown.emptyFoldersPenalty,
          ),
          const Divider(),
          const Text('App usage is not measured and contributes 0 points.'),
        ],
      ),
    );
  }
}

class _PenaltyRow extends StatelessWidget {
  const _PenaltyRow({required this.label, required this.points});
  final String label;
  final int points;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(points == 0 ? 'No deduction' : '-$points points'),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 700
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
  });
  final IconData icon;
  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return SpaceCard(
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(value, style: Theme.of(context).textTheme.titleLarge),
                Text(detail, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _HealthError extends StatelessWidget {
  const _HealthError({required this.error, required this.onRetry});
  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final message = error is UnsupportedError
        ? 'Device health storage signals are not available on this platform.'
        : error.toString().toLowerCase().contains('permission')
        ? 'Storage permission is required to calculate device health.'
        : 'Device health could not be calculated from the available signals.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.health_and_safety_outlined, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

int? _storageGrowth(List<StorageHistoryEntry> history) {
  if (history.length < 2) return null;
  final ordered = [...history]
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return ordered.last.usedBytes - ordered[ordered.length - 2].usedBytes;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = -1;
  do {
    value /= 1024;
    unit++;
  } while (value >= 1024 && unit < units.length - 1);
  return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} ${units[unit]}';
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day}/${local.month}/${local.year} ${local.hour}:$minute';
}

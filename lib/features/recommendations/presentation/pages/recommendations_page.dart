import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../routes/app_routes.dart';
import '../../../../shared/presentation/widgets/space_background.dart';
import '../../domain/models/storage_recommendation.dart';
import '../providers/recommendations_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';

class RecommendationsPage extends ConsumerWidget {
  const RecommendationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(visibleRecommendationsProvider);
    final completed = ref.watch(completedRecommendationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Recommendations')),
      body: SpaceBackground(
        child: SafeArea(
          child: visible.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _StateCard(
              icon: Icons.error_outline_rounded,
              title: 'Recommendations unavailable',
              message: _errorMessage(error),
            ),
            data: (items) => SpacePageList(
              children: [
                _SummaryCard(recommendations: items),
                const SizedBox(height: 14),
                if (items.isEmpty)
                  const _StateCard(
                    icon: Icons.verified_rounded,
                    title: 'No active recommendations',
                    message:
                        'Run Smart Scan after your storage changes and SpacePilot will update this center from local scan data.',
                  )
                else
                  for (final recommendation in items) ...[
                    _RecommendationCard(recommendation: recommendation),
                    const SizedBox(height: 12),
                  ],
                completed.when(
                  data: (completedItems) =>
                      _CompletedCard(recommendations: completedItems),
                  error: (_, _) => const SizedBox.shrink(),
                  loading: () => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.recommendations});

  final List<StorageRecommendation> recommendations;

  @override
  Widget build(BuildContext context) {
    final impact = recommendations.fold<int>(
      0,
      (total, item) => total + item.storageSavingsBytes,
    );
    final critical = recommendations
        .where((item) => item.priority == RecommendationPriority.critical)
        .length;

    return SpaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Local intelligence center',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            'Generated on-device from scans, duplicates, cleanup opportunities, power, and scheduling state.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Metric(label: 'Active', value: '${recommendations.length}'),
              _Metric(label: 'Critical', value: '$critical'),
              _Metric(label: 'Estimated impact', value: _formatBytes(impact)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecommendationCard extends ConsumerWidget {
  const _RecommendationCard({required this.recommendation});

  final StorageRecommendation recommendation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final snoozeDays = ref.watch(recommendationSnoozeDaysProvider);

    return SpaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: _priorityColor(
                  recommendation,
                ).withValues(alpha: 0.16),
                foregroundColor: _priorityColor(recommendation),
                child: Icon(_iconForRecommendation(recommendation.type)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recommendation.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Chip(label: recommendation.priority.name),
                        _Chip(label: '${recommendation.riskLevel.name} risk'),
                        _Chip(
                          label: _formatBytes(
                            recommendation.storageSavingsBytes,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Detail(label: 'Evidence', value: recommendation.evidenceText),
          _Detail(
            label: 'Recommended action',
            value: recommendation.recommendedActionText,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => _openTarget(context, recommendation),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(recommendation.actionLabel),
              ),
              OutlinedButton.icon(
                onPressed: () => ref
                    .read(recommendationDispositionProvider.notifier)
                    .snooze(
                      recommendation.stableId,
                      Duration(days: snoozeDays),
                    ),
                icon: const Icon(Icons.snooze_rounded),
                label: const Text('Snooze'),
              ),
              OutlinedButton.icon(
                onPressed: () => ref
                    .read(recommendationDispositionProvider.notifier)
                    .complete(recommendation.stableId),
                icon: const Icon(Icons.done_rounded),
                label: const Text('Done'),
              ),
              TextButton.icon(
                onPressed: () => ref
                    .read(recommendationDispositionProvider.notifier)
                    .dismiss(recommendation.stableId),
                icon: Icon(Icons.close_rounded, color: colorScheme.error),
                label: const Text('Dismiss'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompletedCard extends ConsumerWidget {
  const _CompletedCard({required this.recommendations});

  final List<StorageRecommendation> recommendations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SpaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Completed recommendations',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          if (recommendations.isEmpty)
            Text(
              'Completed actions will appear here while the underlying scan signal still exists.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (final recommendation in recommendations)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.task_alt_rounded),
                title: Text(recommendation.title),
                trailing: TextButton(
                  onPressed: () => ref
                      .read(recommendationDispositionProvider.notifier)
                      .restore(recommendation.stableId),
                  child: const Text('Restore'),
                ),
              ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(value),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(visualDensity: VisualDensity.compact, label: Text(label));
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: SpaceCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 46,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _openTarget(BuildContext context, StorageRecommendation recommendation) {
  switch (recommendation.actionTarget) {
    case RecommendationActionTarget.scanResults:
      context.pushNamed(AppRouteNames.scanResults);
    case RecommendationActionTarget.duplicates:
      context.pushNamed(AppRouteNames.duplicates);
    case RecommendationActionTarget.cooling:
      context.pushNamed(AppRouteNames.cooling);
    case RecommendationActionTarget.battery:
      context.pushNamed(AppRouteNames.batteryOptimization);
    case RecommendationActionTarget.junkCleaner:
      context.pushNamed(AppRouteNames.junkCleaner);
  }
}

IconData _iconForRecommendation(StorageRecommendationType type) {
  return switch (type) {
    StorageRecommendationType.lowStorage => Icons.storage_rounded,
    StorageRecommendationType.largeDownloads => Icons.download_rounded,
    StorageRecommendationType.oldScreenshots => Icons.image_rounded,
    StorageRecommendationType.unusedFiles => Icons.history_rounded,
    StorageRecommendationType.duplicateMedia => Icons.copy_all_rounded,
    StorageRecommendationType.apkInstallers => Icons.android_rounded,
    StorageRecommendationType.emptyFolders => Icons.folder_delete_rounded,
    StorageRecommendationType.thermalPressure => Icons.thermostat_rounded,
    StorageRecommendationType.lowBatteryScan => Icons.battery_saver_rounded,
    StorageRecommendationType.cleanupOpportunity =>
      Icons.cleaning_services_rounded,
  };
}

Color _priorityColor(StorageRecommendation recommendation) {
  return switch (recommendation.priority) {
    RecommendationPriority.critical => Colors.red,
    RecommendationPriority.high => Colors.deepOrange,
    RecommendationPriority.medium => Colors.blue,
    RecommendationPriority.low => Colors.green,
  };
}

String _errorMessage(Object error) {
  if (error is UnsupportedError) return error.message ?? 'Unsupported device.';
  return 'Run Smart Scan to refresh local recommendation inputs.';
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return 'No direct savings';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final decimals = unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(decimals)} ${units[unit]}';
}

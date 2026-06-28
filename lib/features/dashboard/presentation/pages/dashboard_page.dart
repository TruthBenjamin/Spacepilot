import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../features/agent/domain/models/agent_models.dart';
import '../../../../features/agent/presentation/providers/agent_provider.dart';
import '../../../../features/auto_clean/domain/models/auto_clean_rules.dart';
import '../../../../features/auto_clean/presentation/providers/auto_clean_provider.dart';
import '../../../../features/storage/domain/models/storage_stats.dart';
import '../../../../features/recommendations/domain/models/storage_recommendation.dart';
import '../../../../features/recommendations/presentation/providers/recommendations_provider.dart';
import '../../../../features/scheduled_scans/presentation/providers/scheduled_scan_provider.dart';
import '../../../../features/storage/data/services/storage_scanner_service.dart';
import '../../../../features/storage/presentation/providers/device_storage_provider.dart';
import '../../../../features/storage/presentation/providers/storage_scan_provider.dart';
import '../../../../routes/app_navigation.dart';
import '../../../../shared/presentation/widgets/space_background.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final scanState = ref.watch(storageScanProvider);
    final storageStats = ref.watch(deviceStorageStatsWithHealthProvider);
    final recommendations = ref.watch(recommendationsProvider);
    final scheduledScan = ref.watch(scheduledScanProvider);
    final autoCleanPlan = ref.watch(autoCleanPlanProvider);
    final agentReport = ref.watch(agentReportProvider);
    ref.watch(agentMonitoringProvider);

    Future<void> runScan() async {
      try {
        await ref.read(storageScanProvider.notifier).scan();
        ref.invalidate(deviceStorageStatsProvider);
        ref.invalidate(deviceStorageStatsWithHealthProvider);
      } catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_scanErrorMessage(error))));
      }
    }

    return Scaffold(
      body: SpaceBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _DashboardHeader(),
                    const SizedBox(height: 28),
                    storageStats.when(
                      data: (stats) => _StorageOverview(stats: stats),
                      error: (error, _) => _StorageStatsUnavailable(
                        onRetry: () {
                          ref.invalidate(deviceStorageStatsProvider);
                          ref.invalidate(deviceStorageStatsWithHealthProvider);
                        },
                      ),
                      loading: () => const _StorageStatsLoading(),
                    ),
                    const SizedBox(height: 16),
                    storageStats.when(
                      data: (stats) => _StatsGrid(stats: stats),
                      error: (error, _) => const SizedBox.shrink(),
                      loading: () => const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 24),
                    _AgentAssistantCard(report: agentReport),
                    const SizedBox(height: 16),
                    _ScanButton(
                      isLoading: scanState.isLoading,
                      onPressed: runScan,
                    ),
                    const SizedBox(height: 16),
                    _ScanResultsSummary(scanState: scanState),
                    const SizedBox(height: 16),
                    _RecommendationsSection(recommendations: recommendations),
                    const SizedBox(height: 16),
                    _AutomationSummary(
                      nextScan: scheduledScan.nextRunAfter(DateTime.now()),
                      autoCleanPlan: autoCleanPlan,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Your files stay private and are analyzed on this device.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AgentAssistantCard extends StatelessWidget {
  const _AgentAssistantCard({required this.report});

  final AsyncValue<AgentReport> report;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: report.when(
          data: (data) {
            final topSuggestion = data.cleanupSuggestions.isEmpty
                ? null
                : data.cleanupSuggestions.first;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.smart_toy_rounded,
                      color: colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Local storage assistant',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                    const _LocalOnlyBadge(),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  _agentStatus(data),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                if (topSuggestion != null) ...[
                  const SizedBox(height: 12),
                  _AgentSuggestionRow(suggestion: topSuggestion),
                ],
              ],
            );
          },
          error: (error, _) => Text(
            'Run a storage scan to let the local assistant build a report.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          loading: () => Row(
            children: [
              SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.3,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Preparing local storage report...',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocalOnlyBadge extends StatelessWidget {
  const _LocalOnlyBadge();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          'Local only',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _AgentSuggestionRow extends StatelessWidget {
  const _AgentSuggestionRow({required this.suggestion});

  final AgentCleanupSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_fix_high_rounded, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  suggestion.title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${suggestion.reason} | ${_formatBytes(suggestion.estimatedSavingsBytes)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onPrimaryContainer.withValues(
                      alpha: 0.74,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AutomationSummary extends StatelessWidget {
  const _AutomationSummary({
    required this.nextScan,
    required this.autoCleanPlan,
  });

  final DateTime? nextScan;
  final AsyncValue<AutoCleanPlan> autoCleanPlan;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final scheduled = _AutomationCard(
          icon: Icons.event_repeat_rounded,
          title: 'Scheduled scans',
          value: nextScan == null ? 'Off' : _formatShortDateTime(nextScan!),
          actionLabel: 'Configure',
          onPressed: context.pushSettings,
        );
        final rules = autoCleanPlan.when(
          data: (plan) => _AutomationCard(
            icon: Icons.rule_rounded,
            title: 'Auto-clean rules',
            value:
                '${plan.ruleCount} active | ${_formatBytes(plan.estimatedSavingsBytes)}',
            actionLabel: 'Review',
            onPressed: context.pushSettings,
          ),
          error: (error, _) => _AutomationCard(
            icon: Icons.rule_rounded,
            title: 'Auto-clean rules',
            value: 'Needs scan',
            actionLabel: 'Review',
            onPressed: context.pushSettings,
          ),
          loading: () => _AutomationCard(
            icon: Icons.rule_rounded,
            title: 'Auto-clean rules',
            value: 'Checking...',
            actionLabel: 'Review',
            onPressed: context.pushSettings,
          ),
        );

        if (compact) {
          return Column(
            children: [scheduled, const SizedBox(height: 10), rules],
          );
        }

        return Row(
          children: [
            Expanded(child: scheduled),
            const SizedBox(width: 12),
            Expanded(child: rules),
          ],
        );
      },
    );
  }
}

class _AutomationCard extends StatelessWidget {
  const _AutomationCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String value;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: onPressed, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _RecommendationsSection extends StatelessWidget {
  const _RecommendationsSection({required this.recommendations});

  final AsyncValue<List<StorageRecommendation>> recommendations;

  @override
  Widget build(BuildContext context) {
    return recommendations.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Recommendations',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${items.length} found',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final item in items) ...[
              _RecommendationCard(recommendation: item),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
      error: (error, _) => const SizedBox.shrink(),
      loading: () => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              const SizedBox(width: 12),
              Text(
                'Finding recommendations...',
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

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.recommendation});

  final StorageRecommendation recommendation;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 430;
            final leading = Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                _recommendationIcon(recommendation.type),
                color: colorScheme.onPrimaryContainer,
              ),
            );
            final details = Expanded(
              child: _RecommendationDetails(recommendation: recommendation),
            );
            final action = FilledButton.tonal(
              onPressed: () => _openRecommendation(context, recommendation),
              child: Text(recommendation.actionLabel),
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [leading, const SizedBox(width: 14), details]),
                  const SizedBox(height: 12),
                  action,
                ],
              );
            }

            return Row(
              children: [
                leading,
                const SizedBox(width: 14),
                details,
                const SizedBox(width: 12),
                action,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RecommendationDetails extends StatelessWidget {
  const _RecommendationDetails({required this.recommendation});

  final StorageRecommendation recommendation;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          recommendation.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          '${_formatBytes(recommendation.storageSavingsBytes)} savings',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ScanResultsSummary extends StatelessWidget {
  const _ScanResultsSummary({required this.scanState});

  final AsyncValue<StorageScanState> scanState;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return scanState.when(
      data: (state) {
        if (!state.hasScanned) return const SizedBox.shrink();

        final largestFiles = [...state.files]
          ..sort((a, b) => b.size.compareTo(a.size));
        final previewFiles = largestFiles.take(3).toList(growable: false);

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: colorScheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.06),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.manage_search_rounded,
                      color: AppColors.info,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Scan complete',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${state.files.length} files analyzed | '
                          '${_formatBytes(state.totalBytes)} scanned',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.pushScanResults(),
                    child: const Text('View all'),
                  ),
                ],
              ),
              if (previewFiles.isEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'No files were found in Downloads, DCIM, Movies, or Pictures.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 18),
                for (final file in previewFiles) _ScannedFileRow(file: file),
              ],
            ],
          ),
        );
      },
      error: (error, _) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _scanErrorMessage(error),
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
      loading: () => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: 12),
            Text(
              'Scanning shared storage folders...',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScannedFileRow extends StatelessWidget {
  const _ScannedFileRow({required this.file});

  final ScannedFile file;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(
            Icons.insert_drive_file_outlined,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  file.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _formatBytes(file.size),
            style: textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.brand, Color(0xFF7C4DFF)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.brand.withValues(alpha: 0.28),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SpacePilot AI',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Your device is looking great',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Settings',
          onPressed: context.pushSettings,
          icon: const Icon(Icons.tune_rounded),
        ),
      ],
    );
  }
}

class _StorageOverview extends StatelessWidget {
  const _StorageOverview({required this.stats});

  final StorageStats stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF121735), Color(0xFF22104F), Color(0xFF7C3AED)],
          stops: [0, 0.58, 1],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.34),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 580;
          final details = _StorageDetails(stats: stats);
          final gauge = _StorageGauge(progress: stats.usedPercent);

          if (compact) {
            return Column(
              children: [gauge, const SizedBox(height: 24), details],
            );
          }

          return Row(
            children: [
              gauge,
              const SizedBox(width: 36),
              Expanded(child: details),
            ],
          );
        },
      ),
    );
  }
}

class _StorageStatsLoading extends StatelessWidget {
  const _StorageStatsLoading();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            SizedBox(width: 14),
            Expanded(child: Text('Reading device storage...')),
          ],
        ),
      ),
    );
  }
}

class _StorageStatsUnavailable extends StatelessWidget {
  const _StorageStatsUnavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.storage_rounded, color: colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Device storage stats are unavailable. Try refreshing.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _StorageGauge extends StatelessWidget {
  const _StorageGauge({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 174,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size.square(174),
            painter: _GaugePainter(progress: progress),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(progress * 100).round()}%',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'used',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.68),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StorageDetails extends StatelessWidget {
  const _StorageDetails({required this.stats});

  final StorageStats stats;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFF63E6BE),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Storage overview',
                style: textTheme.labelMedium?.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          '${stats.totalGigabytes.toStringAsFixed(0)} GB total storage',
          style: textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'SpacePilot found room to optimize without touching what matters.',
          style: textTheme.bodyMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.72),
            height: 1.45,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Updated ${_formatShortDateTime(stats.lastUpdated)}',
          style: textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.58),
          ),
        ),
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});

  final StorageStats stats;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 16.0;
        final columns = constraints.maxWidth >= 780
            ? 3
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        final itemWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;
        final cards = [
          _MetricCard(
            label: 'Storage Used',
            value: '${stats.usedGigabytes.toStringAsFixed(0)} GB',
            caption: '${(stats.usedPercent * 100).round()}% of capacity',
            icon: Icons.pie_chart_rounded,
            accent: AppColors.brand,
          ),
          _MetricCard(
            label: 'Storage Free',
            value: '${stats.freeGigabytes.toStringAsFixed(0)} GB',
            caption: 'Ready when you need it',
            icon: Icons.cloud_done_rounded,
            accent: AppColors.success,
          ),
          _HealthCard(score: stats.deviceHealthScore),
        ];

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards) SizedBox(width: itemWidth, child: card),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.07),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: accent, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final status = dashboardHealthStatusForScore(score);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: status.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$score',
              style: textTheme.titleLarge?.copyWith(
                color: status.color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Device Health Score',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  status.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: status.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              status.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(color: status.color),
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardHealthStatus {
  const DashboardHealthStatus({
    required this.label,
    required this.message,
    required this.color,
  });

  final String label;
  final String message;
  final Color color;
}

DashboardHealthStatus dashboardHealthStatusForScore(int score) {
  if (score >= 85) {
    return const DashboardHealthStatus(
      label: 'Excellent',
      message: 'Excellent condition. Your storage is running smoothly.',
      color: AppColors.success,
    );
  }

  if (score >= 70) {
    return const DashboardHealthStatus(
      label: 'Good',
      message: 'Good condition. A quick cleanup can keep things smooth.',
      color: AppColors.success,
    );
  }

  if (score >= 50) {
    return const DashboardHealthStatus(
      label: 'Fair',
      message: 'Storage is getting tight. Review recommendations soon.',
      color: AppColors.warning,
    );
  }

  return const DashboardHealthStatus(
    label: 'Poor',
    message: 'Storage is under pressure. Run cleanup recommendations.',
    color: AppColors.danger,
  );
}

class _ScanButton extends StatelessWidget {
  const _ScanButton({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(alpha: 0.32),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: FilledButton(
        onPressed: isLoading ? null : onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(60),
          backgroundColor: const Color(0xFF7C3AED),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            else
              const Icon(Icons.auto_awesome_rounded, size: 22),
            const SizedBox(width: 10),
            Text(
              isLoading ? 'Scanning storage...' : 'Run AI Scan',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _scanErrorMessage(Object error) {
  if (error is PlatformException && error.code == 'PERMISSION_DENIED') {
    return 'Storage and media access are required to scan your files.';
  }
  return 'The storage scan could not be completed. Please try again.';
}

void _openRecommendation(
  BuildContext context,
  StorageRecommendation recommendation,
) {
  switch (recommendation.actionTarget) {
    case RecommendationActionTarget.duplicates:
      context.pushDuplicates();
      return;
    case RecommendationActionTarget.scanResults:
      context.pushScanResults();
      return;
  }
}

IconData _recommendationIcon(StorageRecommendationType type) {
  return switch (type) {
    StorageRecommendationType.oldScreenshots => Icons.photo_library_rounded,
    StorageRecommendationType.unusedFiles => Icons.history_rounded,
    StorageRecommendationType.duplicateFiles => Icons.file_copy_rounded,
    StorageRecommendationType.apkInstallers => Icons.android_rounded,
  };
}

String _agentStatus(AgentReport report) {
  final trend = report.growthTrend;
  final prediction = report.shortagePrediction;

  if (prediction.willRunShort && prediction.daysUntilShortage != null) {
    return 'Storage may run low in ${prediction.daysUntilShortage} days at the current local growth rate.';
  }

  if (trend.isGrowing) {
    return 'Storage is growing by about ${_formatBytes(trend.bytesPerDay.round())} per day.';
  }

  if (trend.sampleCount < 2) {
    return 'Background monitoring is collecting local snapshots for trend detection.';
  }

  return 'Storage growth looks stable from local background monitoring.';
}

String _formatBytes(int bytes) {
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

String _formatShortDateTime(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final period = value.hour >= 12 ? 'PM' : 'AM';
  return '${value.month}/${value.day}, $hour:$minute $period';
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - 18) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const startAngle = -math.pi / 2;

    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12;
    final progressPaint = Paint()
      ..shader = const SweepGradient(
        colors: [Color(0xFF63E6BE), Colors.white],
        stops: [0, 1],
        transform: GradientRotation(startAngle),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 12;

    canvas.drawCircle(center, radius, trackPaint);
    canvas.drawArc(
      rect,
      startAngle,
      math.pi * 2 * progress.clamp(0, 1),
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

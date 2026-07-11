import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
// Kept for the dashboard recommendation components shared during migration.
// ignore: unused_import
import '../../../../features/analytics/presentation/providers/analytics_provider.dart';
import '../../../../features/auto_clean/domain/models/auto_clean_rules.dart';
import '../../../../features/auto_clean/domain/models/automation_rule.dart';
import '../../../../features/auto_clean/presentation/providers/auto_clean_provider.dart';
import '../../../../features/device_health/domain/models/device_health_report.dart';
import '../../../../features/device_health/presentation/providers/device_health_provider.dart';
import '../../../../features/cooling/domain/models/thermal_advice.dart';
import '../../../../features/cooling/presentation/providers/cooling_provider.dart';
import '../../../../features/cleanup/domain/models/cleanup_candidate.dart';
import '../../../../features/cleanup/presentation/providers/cleanup_center_provider.dart';
import '../../../../features/duplicates/domain/models/duplicate_group.dart';
import '../../../../features/duplicates/domain/models/similar_image_group.dart';
import '../../../../features/duplicates/presentation/providers/duplicate_groups_provider.dart';
import '../../../../features/large_files/presentation/providers/large_file_hunter_provider.dart';
import '../../../../features/recommendations/domain/models/storage_recommendation.dart';
import '../../../../features/power/domain/models/power_thermal_snapshot.dart';
import '../../../../features/power/presentation/providers/power_thermal_provider.dart';
// ignore: unused_import
import '../../../../features/recommendations/presentation/providers/recommendations_provider.dart';
import '../../../../features/storage/domain/models/scanned_file.dart';
import '../../../../features/storage/domain/models/storage_intelligence_report.dart';
import '../../../../features/storage/domain/models/storage_stats.dart';
import '../../../../features/storage/presentation/providers/device_storage_provider.dart';
import '../../../../features/storage/presentation/providers/storage_scan_provider.dart';
import '../../../../routes/app_navigation.dart';
import '../../../../routes/app_routes.dart';
import '../../../../shared/presentation/widgets/space_background.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scan = ref.watch(storageScanProvider);
    final storageStats = ref.watch(deviceStorageStatsWithHealthProvider);
    final healthReport = ref.watch(deviceHealthReportProvider);
    final largeFiles = ref.watch(largeFileHunterProvider);
    final duplicateGroups = ref.watch(duplicateGroupsProvider);
    final similarImageGroups = ref.watch(similarImageGroupsProvider);
    final autoCleanPlan = ref.watch(autoCleanPlanProvider);
    final automationRules = ref.watch(automationRulesProvider);
    final cooling = ref.watch(coolingAdviceProvider);
    final junk = ref.watch(cleanupCenterReportProvider);
    final power = ref.watch(powerThermalSnapshotProvider);

    Future<void> runSmartScan() async {
      HapticFeedback.mediumImpact();
      await context.pushScanResults();
    }

    final stats = storageStats.value;
    final scanState = scan.value;
    final report = scanState?.intelligenceReport;
    final quickActions = _buildQuickActions(
      context: context,
      scanState: scanState,
      report: report,
      largeFiles: largeFiles,
      duplicateGroups: duplicateGroups,
      similarImageGroups: similarImageGroups,
      autoCleanPlan: autoCleanPlan,
      automationRules: automationRules,
      cooling: cooling,
      junk: junk,
      power: power,
    );

    return Scaffold(
      drawer: const _HomeDrawer(),
      body: SpaceBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final horizontalPadding = width < 380 ? 16.0 : 24.0;

              return ListView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  14,
                  horizontalPadding,
                  112,
                ),
                children: [
                  const _DashboardHeader(),
                  const SizedBox(height: 18),
                  _StorageOverviewCard(
                    statsState: storageStats,
                    scanState: scan,
                    report: report,
                    onTap: context.pushStorageOverview,
                    onScan: runSmartScan,
                  ),
                  const SizedBox(height: 18),
                  _DeviceHealthCard(
                    healthReport: healthReport,
                    fallbackScore: stats?.deviceHealthScore,
                    onTap: context.pushDeviceHealth,
                  ),
                  const SizedBox(height: 24),
                  const _SectionHeader(title: 'Quick Actions'),
                  const SizedBox(height: 12),
                  _QuickActionsGrid(actions: quickActions),
                  const SizedBox(height: 16),
                  _SmartScanCard(
                    isScanning: scan.isLoading,
                    hasScanned: scanState?.hasScanned == true,
                    onScan: runSmartScan,
                  ),
                ],
              );
            },
          ),
        ),
      ),
      bottomNavigationBar: _DashboardNavigationBar(
        isScanning: scan.isLoading,
        onScan: runSmartScan,
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Builder(
          builder: (context) => IconButton(
            tooltip: 'Open navigation menu',
            onPressed: Scaffold.of(context).openDrawer,
            icon: const Icon(Icons.menu_rounded, size: 34),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Space'),
                    TextSpan(
                      text: 'Pilot AI',
                      style: TextStyle(color: colorScheme.primary),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              Text(
                'Smart Storage & Performance Optimizer',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Open recommendations',
          onPressed: () => context.pushNamed(AppRouteNames.recommendations),
          icon: Icon(
            Icons.psychology_alt_rounded,
            color: colorScheme.onSurface,
            size: 31,
          ),
        ),
      ],
    );
  }
}

class _StorageOverviewCard extends StatelessWidget {
  const _StorageOverviewCard({
    required this.statsState,
    required this.scanState,
    required this.report,
    required this.onTap,
    required this.onScan,
  });

  final AsyncValue<StorageStats> statsState;
  final AsyncValue<StorageScanState> scanState;
  final StorageIntelligenceReport? report;
  final VoidCallback onTap;
  final Future<void> Function() onScan;

  @override
  Widget build(BuildContext context) {
    return _DashboardCard(
      padding: const EdgeInsets.all(22),
      onTap: onTap,
      child: statsState.when(
        data: (stats) {
          final categories = _categoryRows(report);
          final hasCategoryData = categories.any((item) => item.bytes > 0);

          return Column(
            children: [
              if (scanState.isLoading) ...[
                const _StorageRefreshStatus(),
                const SizedBox(height: 18),
              ],
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 420;
                  final chart = _StorageDonut(
                    usedPercent: stats.usedPercent,
                    usedLabel: _formatBytes(stats.usedBytes, decimals: 0),
                    size: compact ? 172 : 200,
                  );
                  final details = _StorageOverviewDetails(
                    stats: stats,
                    categories: categories,
                    hasCategoryData: hasCategoryData,
                  );

                  if (compact) {
                    return Column(
                      children: [chart, const SizedBox(height: 18), details],
                    );
                  }

                  return Row(
                    children: [
                      chart,
                      const SizedBox(width: 24),
                      Expanded(child: details),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              Divider(color: Theme.of(context).colorScheme.outlineVariant),
              const SizedBox(height: 12),
              _StorageProgress(stats: stats),
            ],
          );
        },
        error: (error, _) => _DashboardStateMessage(
          icon: _permissionError(error)
              ? Icons.lock_outline_rounded
              : Icons.error_outline_rounded,
          title: _permissionError(error)
              ? 'Storage permission required'
              : 'Storage overview unavailable',
          message: _scanErrorMessage(error),
          actionLabel: 'Run scan',
          onAction: onScan,
        ),
        loading: () => _StorageOverviewLoading(isScanning: scanState.isLoading),
      ),
    );
  }
}

class _StorageOverviewLoading extends StatelessWidget {
  const _StorageOverviewLoading({required this.isScanning});

  final bool isScanning;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      liveRegion: true,
      label: isScanning
          ? 'Updating storage insights'
          : 'Preparing storage overview',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.donut_large_rounded,
                  color: colorScheme.primary,
                  size: 25,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Storage Overview',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isScanning
                          ? 'Updating your storage insights'
                          : 'Getting your overview ready',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              key: const ValueKey('storage-overview-loading-progress'),
              minHeight: 5,
              backgroundColor: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.55,
              ),
            ),
          ),
          const SizedBox(height: 13),
          Text(
            'This should only take a moment.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _StorageRefreshStatus extends StatelessWidget {
  const _StorageRefreshStatus();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      liveRegion: true,
      label: 'Updating storage insights',
      child: Row(
        children: [
          SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 9),
          Text(
            'Updating insights',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _StorageOverviewDetails extends StatelessWidget {
  const _StorageOverviewDetails({
    required this.stats,
    required this.categories,
    required this.hasCategoryData,
  });

  final StorageStats stats;
  final List<_StorageCategoryItem> categories;
  final bool hasCategoryData;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Storage Overview',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: colorScheme.onSurface),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Total ${_formatBytes(stats.totalBytes)}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        if (!hasCategoryData)
          Text(
            'Run Smart Scan for file category breakdown.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final category in categories) _CategoryRow(category: category),
      ],
    );
  }
}

class _StorageProgress extends StatelessWidget {
  const _StorageProgress({required this.stats});

  final StorageStats stats;

  @override
  Widget build(BuildContext context) {
    final usedPercent = (stats.usedPercent * 100).round().clamp(0, 100);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${_formatBytes(stats.freeBytes)} Free',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              '$usedPercent% Used',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 12,
            value: stats.usedPercent.clamp(0, 1),
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

class _StorageDonut extends StatelessWidget {
  const _StorageDonut({
    required this.usedPercent,
    required this.usedLabel,
    required this.size,
  });

  final double usedPercent;
  final String usedLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Storage used $usedLabel',
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _DonutPainter(
            percent: usedPercent.clamp(0, 1),
            trackColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    usedLabel,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
                Text(
                  'Used',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
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

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.percent, required this.trackColor});

  final double percent;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final strokeWidth = size.width * 0.13;
    final inset = strokeWidth / 2;
    final arcRect = rect.deflate(inset);
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..shader = const SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: [
          Color(0xFF5D5BFF),
          Color(0xFF21C6FF),
          Color(0xFF21D7C0),
          Color(0xFFFF8A1E),
          Color(0xFFB557FF),
          Color(0xFF5D5BFF),
        ],
      ).createShader(arcRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(arcRect, -math.pi / 2, math.pi * 2, false, track);
    canvas.drawArc(arcRect, -math.pi / 2, math.pi * 2 * percent, false, fill);
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.percent != percent ||
        oldDelegate.trackColor != trackColor;
  }
}

class _DeviceHealthCard extends StatelessWidget {
  const _DeviceHealthCard({
    required this.healthReport,
    required this.fallbackScore,
    required this.onTap,
  });

  final AsyncValue<DeviceHealthReport> healthReport;
  final int? fallbackScore;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final report = healthReport.value;
    final score = report?.score ?? fallbackScore ?? 0;
    final status = dashboardHealthStatusForScore(score);

    return _DashboardCard(
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 430;
          final badge = _HealthBadge(score: score, color: status.color);
          final scoreBlock = _HealthScoreBlock(
            score: score,
            label: report?.category.label ?? status.label,
          );
          final copy = Text(
            report?.suggestions.firstOrNull ?? status.message,
            maxLines: compact ? 3 : 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          );

          final title = Row(
            children: [
              Expanded(
                child: Text(
                  'Device Health',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 14),
                Row(
                  children: [
                    badge,
                    const SizedBox(width: 14),
                    Expanded(child: scoreBlock),
                  ],
                ),
                const SizedBox(height: 14),
                copy,
                if (healthReport.isLoading) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(minHeight: 3),
                ],
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: 10),
              Row(
                children: [
                  badge,
                  const SizedBox(width: 24),
                  scoreBlock,
                  const SizedBox(width: 24),
                  Expanded(child: copy),
                ],
              ),
              if (healthReport.isLoading) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(minHeight: 3),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _HealthBadge extends StatelessWidget {
  const _HealthBadge({required this.score, required this.color});

  final int score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 104,
      child: CustomPaint(
        painter: _ShieldPainter(color: color),
        child: Icon(Icons.monitor_heart_rounded, color: color, size: 42),
      ),
    );
  }
}

class _ShieldPainter extends CustomPainter {
  const _ShieldPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.5, size.height * 0.08)
      ..cubicTo(
        size.width * 0.68,
        size.height * 0.15,
        size.width * 0.78,
        size.height * 0.2,
        size.width * 0.9,
        size.height * 0.22,
      )
      ..cubicTo(
        size.width * 0.94,
        size.height * 0.58,
        size.width * 0.77,
        size.height * 0.84,
        size.width * 0.5,
        size.height * 0.95,
      )
      ..cubicTo(
        size.width * 0.23,
        size.height * 0.84,
        size.width * 0.06,
        size.height * 0.58,
        size.width * 0.1,
        size.height * 0.22,
      )
      ..cubicTo(
        size.width * 0.22,
        size.height * 0.2,
        size.width * 0.32,
        size.height * 0.15,
        size.width * 0.5,
        size.height * 0.08,
      )
      ..close();

    canvas.drawCircle(
      size.center(Offset.zero),
      size.width * 0.48,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: 0.35), Colors.transparent],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.9), color.withValues(alpha: 0.18)],
        ).createShader(Offset.zero & size)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ShieldPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _HealthScoreBlock extends StatelessWidget {
  const _HealthScoreBlock({required this.score, required this.label});

  final int score;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '$score'),
                TextSpan(
                  text: ' /100',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: dashboardHealthStatusForScore(score).color,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid({required this.actions});

  final List<_QuickActionData> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final columns = constraints.maxWidth >= 720
            ? 4
            : constraints.maxWidth >= 430
            ? 3
            : 2;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final action in actions)
              SizedBox(
                width: width,
                child: _QuickActionCard(data: action),
              ),
          ],
        );
      },
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({required this.data});

  final _QuickActionData data;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = data.onTap != null;

    return Semantics(
      button: enabled,
      enabled: enabled,
      label: '${data.title}, ${data.metric}',
      child: Opacity(
        opacity: enabled ? 1 : 0.62,
        child: _DashboardCard(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
          onTap: data.onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ActionIcon(icon: data.icon, color: data.color),
              const SizedBox(height: 12),
              Text(
                data.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                data.metric,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: enabled
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.35, -0.45),
          colors: [
            Color.lerp(color, Colors.white, 0.24)!,
            color,
            Color.lerp(color, Colors.black, 0.28)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.24),
            blurRadius: 18,
            spreadRadius: -3,
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 29),
    );
  }
}

// Retained temporarily so existing dashboard variants can migrate without a
// breaking widget removal; the production dashboard no longer renders it.
// ignore: unused_element
class _RecommendationsPanel extends StatelessWidget {
  const _RecommendationsPanel({
    required this.recommendations,
    required this.onReview,
  });

  final AsyncValue<List<StorageRecommendation>> recommendations;
  final ValueChanged<StorageRecommendation> onReview;

  @override
  Widget build(BuildContext context) {
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: Color(0xFFA060FF)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'AI Recommendations',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              TextButton.icon(
                onPressed: () => context.pushScanResults(),
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.chevron_right_rounded),
                label: const Text('View All'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          recommendations.when(
            data: (items) {
              if (items.isEmpty) {
                return const _InlineEmpty(
                  icon: Icons.radar_rounded,
                  title: 'Run Smart Scan for local recommendations.',
                );
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 680 ? 3 : 1;
                  final spacing = 12.0;
                  final width =
                      (constraints.maxWidth - spacing * (columns - 1)) /
                      columns;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (final item in items.take(3))
                        SizedBox(
                          width: width,
                          child: _RecommendationTile(
                            recommendation: item,
                            onReview: () => onReview(item),
                          ),
                        ),
                    ],
                  );
                },
              );
            },
            error: (error, _) => _InlineEmpty(
              icon: Icons.error_outline_rounded,
              title: _scanErrorMessage(error),
            ),
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: LinearProgressIndicator(),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendationTile extends StatelessWidget {
  const _RecommendationTile({
    required this.recommendation,
    required this.onReview,
  });

  final StorageRecommendation recommendation;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final color = _recommendationColor(recommendation);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ActionIcon(
                icon: _recommendationIcon(recommendation.type),
                color: color,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recommendation.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      recommendation.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Pill(text: _formatBytes(recommendation.storageSavingsBytes)),
              _Pill(text: recommendation.riskLevel.name),
              OutlinedButton(
                onPressed: onReview,
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color),
                  minimumSize: const Size(112, 38),
                ),
                child: Text(recommendation.actionLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SmartScanCard extends StatelessWidget {
  const _SmartScanCard({
    required this.isScanning,
    required this.hasScanned,
    required this.onScan,
  });

  final bool isScanning;
  final bool hasScanned;
  final Future<void> Function() onScan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFF6D38FF), Color(0xFF0B70FF)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4169FF).withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 460;
          final mark = const _ScanMark();
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Run Smart Scan',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                hasScanned
                    ? 'Refresh junk, duplicates, and large-file insights.'
                    : 'Scan for junk, duplicates, large files, and AI recommendations.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.72),
                  height: 1.35,
                ),
              ),
            ],
          );
          final button = FilledButton.icon(
            onPressed: isScanning ? null : onScan,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.72),
              foregroundColor: const Color(0xFF0637C9),
              minimumSize: const Size(176, 56),
            ),
            icon: isScanning
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Icon(Icons.manage_search_rounded),
            label: Text(
              isScanning ? 'Scanning storage' : 'Scan device storage',
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    mark,
                    const SizedBox(width: 16),
                    Expanded(child: copy),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: button),
              ],
            );
          }

          return Row(
            children: [
              mark,
              const SizedBox(width: 22),
              Expanded(child: copy),
              const SizedBox(width: 18),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _ScanMark extends StatelessWidget {
  const _ScanMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 82,
      child: Stack(
        alignment: Alignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
            ),
            child: const SizedBox.expand(),
          ),
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.96),
                  const Color(0xFF8FE7FF),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.manage_search_rounded,
              color: Color(0xFF0637C9),
              size: 34,
            ),
          ),
          Positioned(
            right: 8,
            bottom: 10,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF21D7C0),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Color(0xFF062B43),
                size: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardNavigationBar extends StatelessWidget {
  const _DashboardNavigationBar({
    required this.isScanning,
    required this.onScan,
  });

  final bool isScanning;
  final Future<void> Function() onScan;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: 0,
      onDestinationSelected: (index) {
        switch (index) {
          case 0:
            context.goToDashboard();
          case 1:
            context.pushLargeFiles();
          case 2:
            onScan();
          case 3:
            context.pushDuplicates();
          case 4:
            context.pushSettings();
        }
      },
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Dashboard',
        ),
        const NavigationDestination(
          icon: Icon(Icons.folder_outlined),
          selectedIcon: Icon(Icons.folder_rounded),
          label: 'Files',
        ),
        NavigationDestination(
          icon: isScanning
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              : const Icon(Icons.radar_rounded),
          label: 'Scan',
        ),
        const NavigationDestination(
          icon: Icon(Icons.business_center_outlined),
          selectedIcon: Icon(Icons.business_center_rounded),
          label: 'Tools',
        ),
        const NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings_rounded),
          label: 'Settings',
        ),
      ],
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.surface.withValues(alpha: 0.92),
            colorScheme.surfaceContainerHighest.withValues(alpha: 0.48),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );

    if (onTap == null) return card;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: card,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category});

  final _StorageCategoryItem category;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: category.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              category.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            _formatBytes(category.bytes),
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _DashboardStateMessage extends StatelessWidget {
  const _DashboardStateMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: colorScheme.primary, size: 42),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.radar_rounded),
            label: Text(actionLabel!),
          ),
        ],
      ],
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _HomeDrawer extends StatelessWidget {
  const _HomeDrawer();

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              title: Text(
                'SpacePilot AI',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              subtitle: const Text('Device care controls'),
            ),
            const SizedBox(height: 12),
            _DrawerLink(
              icon: Icons.dashboard_rounded,
              title: 'Dashboard',
              routeName: AppRouteNames.dashboard,
            ),
            _DrawerLink(
              icon: Icons.storage_rounded,
              title: 'Storage Overview',
              routeName: AppRouteNames.storageOverview,
            ),
            _DrawerLink(
              icon: Icons.psychology_alt_rounded,
              title: 'Recommendations',
              routeName: AppRouteNames.recommendations,
            ),
            _DrawerLink(
              icon: Icons.apps_rounded,
              title: 'Tools',
              routeName: AppRouteNames.tools,
            ),
            _DrawerLink(
              icon: Icons.radar_rounded,
              title: 'Smart Scan',
              routeName: AppRouteNames.scanResults,
            ),
            _DrawerLink(
              icon: Icons.inventory_2_rounded,
              title: 'Large Files',
              routeName: AppRouteNames.largeFiles,
            ),
            _DrawerLink(
              icon: Icons.copy_all_rounded,
              title: 'Duplicate Cleaner',
              routeName: AppRouteNames.duplicates,
            ),
            _DrawerLink(
              icon: Icons.android_rounded,
              title: 'App Analyzer',
              routeName: AppRouteNames.appAnalyzer,
            ),
            _DrawerLink(
              icon: Icons.memory_rounded,
              title: 'RAM Booster',
              routeName: AppRouteNames.booster,
            ),
            _DrawerLink(
              icon: Icons.image_search_rounded,
              title: 'Similar Images',
              routeName: AppRouteNames.similarImages,
            ),
            _DrawerLink(
              icon: Icons.settings_rounded,
              title: 'Settings',
              routeName: AppRouteNames.settings,
            ),
            _DrawerLink(
              icon: Icons.privacy_tip_rounded,
              title: 'Privacy Center',
              routeName: AppRouteNames.privacyCenter,
            ),
            _DrawerLink(
              icon: Icons.restore_from_trash_rounded,
              title: 'Recovery Bin',
              routeName: AppRouteNames.recoveryBin,
            ),
            _DrawerLink(
              icon: Icons.thermostat_rounded,
              title: 'Thermal Advisor',
              routeName: AppRouteNames.cooling,
            ),
            _DrawerLink(
              icon: Icons.cleaning_services_rounded,
              title: 'Junk Cleaner',
              routeName: AppRouteNames.junkCleaner,
            ),
            _DrawerLink(
              icon: Icons.battery_saver_rounded,
              title: 'Power Advisor',
              routeName: AppRouteNames.batteryOptimization,
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerLink extends StatelessWidget {
  const _DrawerLink({
    required this.icon,
    required this.title,
    required this.routeName,
  });

  final IconData icon;
  final String title;
  final String routeName;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      onTap: () {
        final router = GoRouter.of(context);
        Navigator.of(context).pop();
        router.goNamed(routeName);
      },
    );
  }
}

class _StorageCategoryItem {
  const _StorageCategoryItem({
    required this.label,
    required this.bytes,
    required this.color,
  });

  final String label;
  final int bytes;
  final Color color;
}

class _QuickActionData {
  const _QuickActionData({
    required this.title,
    required this.metric,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String metric;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
}

List<_QuickActionData> _buildQuickActions({
  required BuildContext context,
  required StorageScanState? scanState,
  required StorageIntelligenceReport? report,
  required AsyncValue<List<ScannedFile>> largeFiles,
  required AsyncValue<List<DuplicateGroup>> duplicateGroups,
  required AsyncValue<List<SimilarImageGroup>> similarImageGroups,
  required AsyncValue<AutoCleanPlan> autoCleanPlan,
  required List<AutomationRule> automationRules,
  required AsyncValue<ThermalAdvice> cooling,
  required AsyncValue<CleanupCenterReport> junk,
  required AsyncValue<PowerThermalSnapshot> power,
}) {
  final largeFileBytes =
      largeFiles.value?.fold<int>(0, (total, file) => total + file.size) ?? 0;
  final duplicateBytes =
      duplicateGroups.value?.fold<int>(
        0,
        (total, group) => total + group.recoverableBytes,
      ) ??
      0;
  final similarBytes =
      similarImageGroups.value?.fold<int>(
        0,
        (total, group) => total + group.recoverableBytes,
      ) ??
      0;
  final apkBytes = report?.summaryFor(StorageFileCategory.apk).totalBytes ?? 0;
  final activeRules = automationRules.where((rule) => rule.enabled).length;
  final hasScanned = scanState?.hasScanned == true;

  return [
    _QuickActionData(
      title: 'Cooling',
      metric: cooling.when(
        data: (value) => value.classification.name,
        loading: () => 'Checking',
        error: (_, _) => 'Unavailable',
      ),
      icon: Icons.thermostat_rounded,
      color: const Color(0xFF11BFD7),
      onTap: context.pushCooling,
    ),
    _QuickActionData(
      title: 'Junk Cleaner',
      metric: junk.when(
        data: (value) => !value.hasScanned
            ? 'Scan required'
            : value.recoverableBytes == 0
            ? 'No recommendations'
            : '${_formatBytes(value.recoverableBytes)} to review',
        loading: () => 'Loading',
        error: (_, _) => 'Unavailable',
      ),
      icon: Icons.cleaning_services_rounded,
      color: const Color(0xFFFF7E1D),
      onTap: context.pushJunkCleaner,
    ),
    _QuickActionData(
      title: 'Battery',
      metric: power.when(
        data: (value) => value.batteryLevel == null
            ? 'Unavailable'
            : value.charging
            ? '${value.batteryLevel}% - Charging'
            : '${value.batteryLevel}%',
        loading: () => 'Checking',
        error: (_, _) => 'Unavailable',
      ),
      icon: Icons.battery_saver_rounded,
      color: const Color(0xFF4D9A35),
      onTap: context.pushBatteryOptimization,
    ),
    _QuickActionData(
      title: 'RAM Booster',
      metric: 'Optimize',
      icon: Icons.memory_rounded,
      color: const Color(0xFF35C7BD),
      onTap: context.pushBooster,
    ),
    _QuickActionData(
      title: 'Large Files',
      metric: hasScanned ? _formatBytes(largeFileBytes) : 'Scan needed',
      icon: Icons.inventory_2_rounded,
      color: const Color(0xFF8E45FF),
      onTap: context.pushLargeFiles,
    ),
    _QuickActionData(
      title: 'Duplicate Cleaner',
      metric: hasScanned ? _formatBytes(duplicateBytes) : 'Scan needed',
      icon: Icons.file_copy_rounded,
      color: const Color(0xFF176BFF),
      onTap: context.pushDuplicates,
    ),
    _QuickActionData(
      title: 'App Analyzer',
      metric: hasScanned ? _formatBytes(apkBytes) : 'Scan needed',
      icon: Icons.android_rounded,
      color: const Color(0xFF4D9A35),
      onTap: context.pushAppAnalyzer,
    ),
    _QuickActionData(
      title: 'Smart Cleanup',
      metric: autoCleanPlan.value == null
          ? 'Review'
          : _formatBytes(autoCleanPlan.value!.estimatedSavingsBytes),
      icon: Icons.cleaning_services_rounded,
      color: const Color(0xFFFF7E1D),
      onTap: context.pushScanResults,
    ),
    _QuickActionData(
      title: 'Similar Images',
      metric: hasScanned ? _formatBytes(similarBytes) : 'Scan needed',
      icon: Icons.image_rounded,
      color: const Color(0xFF11BFD7),
      onTap: context.pushSimilarImages,
    ),
    _QuickActionData(
      title: 'Storage Timeline',
      metric: report == null ? 'No history' : 'Updated',
      icon: Icons.timeline_rounded,
      color: const Color(0xFFE2AA18),
      onTap: () => context.pushNamed(AppRouteNames.storageTimeline),
    ),
    _QuickActionData(
      title: 'Automation',
      metric: '$activeRules Active',
      icon: Icons.smart_toy_rounded,
      color: const Color(0xFFD849A9),
      onTap: () => context.pushNamed(AppRouteNames.automation),
    ),
    _QuickActionData(
      title: 'Recovery Bin',
      metric: 'App-managed',
      icon: Icons.delete_outline_rounded,
      color: const Color(0xFF7A3CFF),
      onTap: () => context.pushNamed(AppRouteNames.recoveryBin),
    ),
  ];
}

List<_StorageCategoryItem> _categoryRows(StorageIntelligenceReport? report) {
  int bytesFor(StorageFileCategory category) {
    return report?.summaryFor(category).totalBytes ?? 0;
  }

  final appBytes = bytesFor(StorageFileCategory.apk);
  final zipBytes = bytesFor(StorageFileCategory.zip);
  final downloadBytes = bytesFor(StorageFileCategory.download);
  final known =
      bytesFor(StorageFileCategory.image) +
      bytesFor(StorageFileCategory.video) +
      appBytes +
      bytesFor(StorageFileCategory.document) +
      bytesFor(StorageFileCategory.audio);
  final scannedTotal =
      report?.files.fold<int>(0, (total, file) => total + file.size) ?? 0;
  final otherBytes = math.max(
    bytesFor(StorageFileCategory.other),
    scannedTotal - known,
  );

  return [
    _StorageCategoryItem(
      label: 'Images',
      bytes: bytesFor(StorageFileCategory.image),
      color: const Color(0xFF9757FF),
    ),
    _StorageCategoryItem(
      label: 'Videos',
      bytes: bytesFor(StorageFileCategory.video),
      color: const Color(0xFF3E8CFF),
    ),
    _StorageCategoryItem(
      label: 'Apps',
      bytes: appBytes,
      color: const Color(0xFFFF8B2A),
    ),
    _StorageCategoryItem(
      label: 'Documents',
      bytes: bytesFor(StorageFileCategory.document),
      color: const Color(0xFFFFC83D),
    ),
    _StorageCategoryItem(
      label: 'Audio',
      bytes: bytesFor(StorageFileCategory.audio),
      color: const Color(0xFFE5489E),
    ),
    _StorageCategoryItem(
      label: 'Others',
      bytes: otherBytes + zipBytes + math.max(0, downloadBytes - zipBytes),
      color: const Color(0xFF35C7BD),
    ),
  ];
}

// ignore: unused_element
void _openRecommendation(
  BuildContext context,
  StorageRecommendation recommendation,
) {
  switch (recommendation.actionTarget) {
    case RecommendationActionTarget.duplicates:
      context.pushDuplicates();
    case RecommendationActionTarget.scanResults:
      context.pushScanResults();
    case RecommendationActionTarget.cooling:
      context.pushCooling();
    case RecommendationActionTarget.battery:
      context.pushBatteryOptimization();
    case RecommendationActionTarget.junkCleaner:
      context.pushJunkCleaner();
  }
}

IconData _recommendationIcon(StorageRecommendationType type) {
  return switch (type) {
    StorageRecommendationType.lowStorage => Icons.storage_rounded,
    StorageRecommendationType.largeDownloads => Icons.folder_rounded,
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

Color _recommendationColor(StorageRecommendation recommendation) {
  return switch (recommendation.priority) {
    RecommendationPriority.critical => AppColors.danger,
    RecommendationPriority.high => const Color(0xFFFF7E1D),
    RecommendationPriority.medium => const Color(0xFF4D8CFF),
    RecommendationPriority.low => AppColors.success,
  };
}

DashboardHealthStatus dashboardHealthStatusForScore(int score) {
  if (score >= 85) {
    return const DashboardHealthStatus(
      label: 'Excellent',
      message: 'Your device is in great condition. Keep it up.',
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

String _formatBytes(int bytes, {int decimals = 1}) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final resolvedDecimals = unit == 0 ? 0 : decimals;
  return '${value.toStringAsFixed(resolvedDecimals)} ${units[unit]}';
}

String _scanErrorMessage(Object error) {
  if (error is PlatformException && error.code == 'PERMISSION_DENIED') {
    return 'Storage and media access are required to scan your files.';
  }
  if (error is TimeoutException) {
    return 'The storage scan timed out. Please try again.';
  }
  if (error is UnsupportedError) {
    return 'SpacePilot storage scans are available on Android devices.';
  }
  return 'Storage data could not be loaded. Try running Smart Scan again.';
}

bool _permissionError(Object error) {
  return error is PlatformException && error.code == 'PERMISSION_DENIED';
}

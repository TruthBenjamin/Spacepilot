import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/presentation/widgets/space_background.dart';
import '../../domain/models/models.dart';
import '../providers/app_analyzer_provider.dart';

class AppAnalyzerPage extends ConsumerWidget {
  const AppAnalyzerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(installedAppsReportProvider);
    final apps = ref.watch(filteredInstalledAppsProvider);

    Future<void> refresh() async {
      ref.invalidate(installedAppsReportProvider);
      await ref.read(installedAppsReportProvider.future);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('App Analyzer'),
        actions: [
          IconButton(
            tooltip: 'Refresh app analysis',
            onPressed: report.isLoading ? null : () => refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SpaceBackground(
        child: SafeArea(
          child: report.when(
            loading: () => const _LoadingState(),
            error: (error, _) => _EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'App analysis unavailable',
              message: _errorMessage(error),
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(installedAppsReportProvider),
            ),
            data: (report) => SpacePageList(
              children: [
                _SummaryCard(report: report),
                const SizedBox(height: 12),
                if (!report.hasUsageAccess)
                  _UsageAccessCard(
                    onOpenSettings: () => ref
                        .read(appAnalyzerServiceProvider)
                        .openUsageAccessSettings(),
                  ),
                if (!report.hasUsageAccess) const SizedBox(height: 12),
                _ControlsCard(),
                const SizedBox(height: 12),
                apps.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => _InlineState(
                    icon: Icons.error_outline_rounded,
                    title: _errorMessage(error),
                  ),
                  data: (items) {
                    if (items.isEmpty) {
                      return const _InlineState(
                        icon: Icons.search_off_rounded,
                        title: 'No installed apps match these filters.',
                      );
                    }
                    return Column(
                      children: [
                        for (final app in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _AppCard(app: app),
                          ),
                      ],
                    );
                  },
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
  const _SummaryCard({required this.report});

  final InstalledAppsReport report;

  @override
  Widget build(BuildContext context) {
    final largest =
        report.apps.where((app) => app.hasSizeData).toList(growable: false)
          ..sort((a, b) => _sizeOf(b).compareTo(_sizeOf(a)));
    final rarelyUsed = report.apps.where((app) {
      final lastUsed = app.lastUsedTime;
      if (!report.hasUsageAccess || lastUsed == null) return false;
      return DateTime.now().difference(lastUsed).inDays >= 30;
    }).length;

    return SpaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${report.apps.length}',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'visible installed apps analyzed',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricChip(
                icon: Icons.sd_storage_rounded,
                label: _formatBytes(report.measurableSizeBytes),
                tooltip: 'Measurable app storage',
              ),
              _MetricChip(
                icon: Icons.trending_up_rounded,
                label: largest.isEmpty ? 'Size limited' : largest.first.appName,
                tooltip: 'Largest measurable app',
              ),
              _MetricChip(
                icon: Icons.history_toggle_off_rounded,
                label: report.hasUsageAccess
                    ? '$rarelyUsed rarely used'
                    : 'Usage access off',
                tooltip: 'Rarely used apps require Usage Access',
              ),
            ],
          ),
          if (report.limitations.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final limitation in report.limitations)
              Text(
                limitation,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _UsageAccessCard extends StatelessWidget {
  const _UsageAccessCard({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return SpaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lock_clock_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Usage access improves app analysis',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Android only exposes last-used and detailed app storage after you grant Usage Access in Settings.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.settings_rounded),
                  label: const Text('Open settings'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlsCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(appAnalyzerSortProvider);
    final filter = ref.watch(appAnalyzerFilterProvider);

    return SpaceCard(
      child: Column(
        children: [
          TextField(
            onChanged: (value) =>
                ref.read(appAnalyzerSearchProvider.notifier).state = value,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              labelText: 'Search apps',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<AppAnalyzerSort>(
                  initialValue: sort,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.sort_rounded),
                    labelText: 'Sort',
                  ),
                  items: [
                    for (final value in AppAnalyzerSort.values)
                      DropdownMenuItem(value: value, child: Text(value.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      ref.read(appAnalyzerSortProvider.notifier).state = value;
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<AppAnalyzerFilter>(
                  initialValue: filter,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.filter_alt_rounded),
                    labelText: 'Filter',
                  ),
                  items: [
                    for (final value in AppAnalyzerFilter.values)
                      DropdownMenuItem(value: value, child: Text(value.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      ref.read(appAnalyzerFilterProvider.notifier).state =
                          value;
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AppCard extends ConsumerWidget {
  const _AppCard({required this.app});

  final InstalledApp app;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(appAnalyzerServiceProvider);
    final colorScheme = Theme.of(context).colorScheme;

    Future<void> runAction(Future<void> Function() action) async {
      try {
        await action();
      } on PlatformException catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_actionError(error))));
      }
    }

    return SpaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: colorScheme.primaryContainer,
                child: Icon(
                  app.isSystemApp ? Icons.android_rounded : Icons.apps_rounded,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.appName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      app.packageName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _formatBytes(_sizeOf(app)),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FactChip(
                icon: Icons.category_rounded,
                label: app.isSystemApp ? 'System' : 'User app',
              ),
              _FactChip(
                icon: Icons.schedule_rounded,
                label: app.lastUsedTime == null
                    ? 'Last used unavailable'
                    : 'Used ${_relativeDate(app.lastUsedTime!)}',
              ),
              _FactChip(
                icon: Icons.update_rounded,
                label: app.lastUpdateTime == null
                    ? 'Update unknown'
                    : 'Updated ${_formatDate(app.lastUpdateTime!)}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: app.canLaunch
                    ? () => runAction(() => service.openApp(app.packageName))
                    : null,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    runAction(() => service.openAppInfo(app.packageName)),
                icon: const Icon(Icons.info_outline_rounded),
                label: const Text('App info'),
              ),
              FilledButton.tonalIcon(
                onPressed: app.isSystemApp
                    ? null
                    : () => runAction(
                        () => service.requestUninstall(app.packageName),
                      ),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Uninstall'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.icon,
    required this.label,
    required this.tooltip,
  });

  final IconData icon;
  final String label;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Chip(avatar: Icon(icon), label: Text(label)),
    );
  }
}

class _FactChip extends StatelessWidget {
  const _FactChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 14),
          Text('Reading installed apps'),
        ],
      ),
    );
  }
}

class _InlineState extends StatelessWidget {
  const _InlineState({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return SpaceCard(
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(title)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
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
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

int _sizeOf(InstalledApp app) => app.totalSizeBytes ?? app.appSizeBytes ?? 0;

String _formatBytes(int bytes) {
  if (bytes <= 0) return 'Unknown size';
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

String _formatDate(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

String _relativeDate(DateTime date) {
  final days = DateTime.now().difference(date).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  return '$days days ago';
}

String _errorMessage(Object error) {
  if (error is UnsupportedError) {
    return error.message ?? 'Unsupported platform.';
  }
  return 'SpacePilot could not read installed-app information.';
}

String _actionError(PlatformException error) {
  return switch (error.code) {
    'APP_NOT_FOUND' => 'That app is no longer installed.',
    'NO_HANDLER' => 'Android could not open this action.',
    _ => 'App action could not be completed.',
  };
}

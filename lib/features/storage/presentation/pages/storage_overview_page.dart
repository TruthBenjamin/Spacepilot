import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../routes/app_navigation.dart';
import '../../../../shared/presentation/widgets/space_background.dart';
import '../../domain/models/scanned_file.dart';
import '../../domain/models/storage_history_entry.dart';
import '../../domain/models/storage_intelligence_report.dart';
import '../../domain/models/storage_stats.dart';
import '../providers/device_storage_provider.dart';
import '../providers/storage_history_provider.dart';
import '../providers/storage_scan_provider.dart';

class StorageOverviewPage extends ConsumerStatefulWidget {
  const StorageOverviewPage({super.key});

  @override
  ConsumerState<StorageOverviewPage> createState() =>
      _StorageOverviewPageState();
}

class _StorageOverviewPageState extends ConsumerState<StorageOverviewPage> {
  _StorageOverviewCategory? _selectedCategory;

  Future<void> _refresh() async {
    if (ref.read(storageScanProvider).isLoading) return;

    HapticFeedback.mediumImpact();
    try {
      await ref.read(storageScanProvider.notifier).scanIntelligence();
      ref
        ..invalidate(deviceStorageStatsProvider)
        ..invalidate(deviceStorageStatsWithHealthProvider)
        ..invalidate(storageHistoryProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Storage intelligence refreshed.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_scanErrorMessage(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scan = ref.watch(storageScanProvider);
    final progress = ref.watch(storageScanProgressProvider);
    final statsState = ref.watch(deviceStorageStatsProvider);
    final history = ref.watch(storageHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage Intelligence'),
        actions: [
          IconButton(
            tooltip: 'Refresh storage intelligence',
            onPressed: scan.isLoading ? null : _refresh,
            icon: scan.isLoading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SpaceBackground(
        child: SafeArea(
          child: statsState.when(
            loading: () => _StorageIntelligenceLoading(
              progress: progress,
              isScanning: scan.isLoading || progress.isScanning,
            ),
            error: (error, _) => _StateMessage(
              icon: _permissionError(error)
                  ? Icons.lock_outline_rounded
                  : Icons.error_outline_rounded,
              title: _permissionError(error)
                  ? 'Storage permission required'
                  : 'Storage totals unavailable',
              message: _scanErrorMessage(error),
              actionLabel: 'Refresh',
              onAction: _refresh,
            ),
            data: (deviceStats) {
              return scan.when(
                loading: () => _Content(
                  stats:
                      _reportStats(scan.value?.intelligenceReport) ??
                      deviceStats,
                  report: scan.value?.intelligenceReport,
                  isScanning: true,
                  history: history.value ?? const [],
                  selectedCategory: _selectedCategory,
                  onSelectedCategoryChanged: _selectCategory,
                  onRefresh: _refresh,
                  onCategoryTap: _openCategory,
                ),
                error: (error, _) => _StateMessage(
                  icon: _permissionError(error)
                      ? Icons.lock_outline_rounded
                      : Icons.error_outline_rounded,
                  title: _permissionError(error)
                      ? 'Storage permission required'
                      : 'Scan failed',
                  message: _scanErrorMessage(error),
                  actionLabel: 'Refresh',
                  onAction: _refresh,
                ),
                data: (state) => _Content(
                  stats: state.intelligenceReport?.storageStats ?? deviceStats,
                  report: state.intelligenceReport,
                  isScanning: false,
                  history: history.value ?? const [],
                  selectedCategory: _selectedCategory,
                  onSelectedCategoryChanged: _selectCategory,
                  onRefresh: _refresh,
                  onCategoryTap: _openCategory,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _selectCategory(_StorageOverviewCategory category) {
    setState(() => _selectedCategory = category);
  }

  void _openCategory(_StorageOverviewCategory category) {
    context.pushStorageFiles(category: category.routeName);
  }
}

class _Content extends StatelessWidget {
  const _Content({
    required this.stats,
    required this.report,
    required this.isScanning,
    required this.history,
    required this.selectedCategory,
    required this.onSelectedCategoryChanged,
    required this.onRefresh,
    required this.onCategoryTap,
  });

  final StorageStats stats;
  final StorageIntelligenceReport? report;
  final bool isScanning;
  final List<StorageHistoryEntry> history;
  final _StorageOverviewCategory? selectedCategory;
  final ValueChanged<_StorageOverviewCategory> onSelectedCategoryChanged;
  final VoidCallback onRefresh;
  final ValueChanged<_StorageOverviewCategory> onCategoryTap;

  @override
  Widget build(BuildContext context) {
    final categories = _buildCategories(stats, report);
    final topCategories = [...categories]
      ..sort((a, b) => b.bytes.compareTo(a.bytes));
    final recentChanges = _recentChanges(history);

    return SpacePageList(
      children: [
        _HeroCard(stats: stats, report: report, isScanning: isScanning),
        const SizedBox(height: 14),
        _ScanStatusCard(
          report: report,
          isScanning: isScanning,
          onRefresh: onRefresh,
        ),
        const SizedBox(height: 14),
        _CategoryBreakdownCard(
          categories: categories,
          selectedCategory: selectedCategory ?? topCategories.first,
          onSelected: onSelectedCategoryChanged,
          onOpen: onCategoryTap,
        ),
        const SizedBox(height: 14),
        _TwoColumnSection(
          left: _LargestCategoriesCard(
            categories: topCategories.take(5).toList(growable: false),
            onOpen: onCategoryTap,
          ),
          right: _LargestFoldersCard(
            folders: report?.largestFolders ?? const [],
          ),
        ),
        const SizedBox(height: 14),
        _RecentChangesCard(changes: recentChanges),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.stats,
    required this.report,
    required this.isScanning,
  });

  final StorageStats stats;
  final StorageIntelligenceReport? report;
  final bool isScanning;

  @override
  Widget build(BuildContext context) {
    return SpaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storage_rounded, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Storage Overview',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _StatusPill(
                text: isScanning
                    ? 'Scanning'
                    : report == null
                    ? 'Cached scan needed'
                    : 'Cached',
              ),
            ],
          ),
          const SizedBox(height: 18),
          _UsageBar(stats: stats),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricTile(
                label: 'Total',
                value: _formatBytes(stats.totalBytes),
              ),
              _MetricTile(label: 'Used', value: _formatBytes(stats.usedBytes)),
              _MetricTile(label: 'Free', value: _formatBytes(stats.freeBytes)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScanStatusCard extends StatelessWidget {
  const _ScanStatusCard({
    required this.report,
    required this.isScanning,
    required this.onRefresh,
  });

  final StorageIntelligenceReport? report;
  final bool isScanning;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return SpaceCard(
      child: Row(
        children: [
          Icon(
            isScanning ? Icons.radar_rounded : Icons.history_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isScanning ? 'Scan in progress' : 'Scan status',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  report == null
                      ? 'No full storage intelligence scan is cached yet.'
                      : 'Last scan ${_formatDate(report!.completedAt)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: isScanning ? null : onRefresh,
            icon: isScanning
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(isScanning ? 'Scanning' : 'Refresh'),
          ),
        ],
      ),
    );
  }
}

class _CategoryBreakdownCard extends StatelessWidget {
  const _CategoryBreakdownCard({
    required this.categories,
    required this.selectedCategory,
    required this.onSelected,
    required this.onOpen,
  });

  final List<_StorageOverviewCategory> categories;
  final _StorageOverviewCategory selectedCategory;
  final ValueChanged<_StorageOverviewCategory> onSelected;
  final ValueChanged<_StorageOverviewCategory> onOpen;

  @override
  Widget build(BuildContext context) {
    return SpaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Category Breakdown',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          _InteractiveCategoryChart(
            categories: categories,
            selected: selectedCategory,
            onSelected: onSelected,
          ),
          const SizedBox(height: 14),
          Center(
            child: _CategoryDropdown(
              categories: categories,
              selectedCategory: selectedCategory,
              onSelected: onSelected,
            ),
          ),
          const SizedBox(height: 14),
          _CategoryDetailRow(category: selectedCategory, onOpen: onOpen),
        ],
      ),
    );
  }
}

class _CategoryDropdown extends StatelessWidget {
  const _CategoryDropdown({
    required this.categories,
    required this.selectedCategory,
    required this.onSelected,
  });

  final List<_StorageOverviewCategory> categories;
  final _StorageOverviewCategory selectedCategory;
  final ValueChanged<_StorageOverviewCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuButton<_StorageOverviewCategory>(
      tooltip: 'Choose category',
      initialValue: selectedCategory,
      onSelected: onSelected,
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 210, maxWidth: 260),
      itemBuilder: (context) => [
        for (final category in categories)
          PopupMenuItem<_StorageOverviewCategory>(
            value: category,
            child: Row(
              children: [
                IgnorePointer(
                  child: Checkbox(
                    value: category.routeName == selectedCategory.routeName,
                    onChanged: (_) {},
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(category.icon, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(category.label)),
              ],
            ),
          ),
      ],
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selectedCategory.icon, size: 18),
              const SizedBox(width: 8),
              Text(
                selectedCategory.label,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _InteractiveCategoryChart extends StatelessWidget {
  const _InteractiveCategoryChart({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<_StorageOverviewCategory> categories;
  final _StorageOverviewCategory selected;
  final ValueChanged<_StorageOverviewCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    final maxBytes = categories.fold<int>(
      1,
      (maxBytes, category) => math.max(maxBytes, category.bytes),
    );

    return Column(
      children: [
        for (final category in categories) ...[
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onSelected(category),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 98,
                    child: Text(
                      category.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 12,
                        value: category.bytes / maxBytes,
                        color: category.color,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 76,
                    child: Text(
                      _formatBytes(category.bytes),
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CategoryDetailRow extends StatelessWidget {
  const _CategoryDetailRow({required this.category, required this.onOpen});

  final _StorageOverviewCategory category;
  final ValueChanged<_StorageOverviewCategory> onOpen;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: category.color.withValues(alpha: 0.2),
        child: Icon(category.icon, color: category.color),
      ),
      title: Text(category.label),
      subtitle: Text(
        '${category.fileCount} files - ${_formatBytes(category.bytes)}',
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => onOpen(category),
    );
  }
}

class _LargestCategoriesCard extends StatelessWidget {
  const _LargestCategoriesCard({
    required this.categories,
    required this.onOpen,
  });

  final List<_StorageOverviewCategory> categories;
  final ValueChanged<_StorageOverviewCategory> onOpen;

  @override
  Widget build(BuildContext context) {
    return SpaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Largest Categories',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          for (final category in categories)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(category.icon, color: category.color),
              title: Text(category.label),
              subtitle: Text('${category.fileCount} files'),
              trailing: Text(_formatBytes(category.bytes)),
              onTap: () => onOpen(category),
            ),
        ],
      ),
    );
  }
}

class _LargestFoldersCard extends StatelessWidget {
  const _LargestFoldersCard({required this.folders});

  final List<StorageFolderSummary> folders;

  @override
  Widget build(BuildContext context) {
    return SpaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Largest Folders',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          if (folders.isEmpty)
            const _InlineMessage(
              icon: Icons.folder_off_rounded,
              message: 'Run refresh to cache folder sizes.',
            )
          else
            for (final folder in folders.take(5))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_rounded),
                title: Text(
                  _folderName(folder.path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('${folder.fileCount} files'),
                trailing: Text(_formatBytes(folder.sizeBytes)),
              ),
        ],
      ),
    );
  }
}

class _RecentChangesCard extends StatelessWidget {
  const _RecentChangesCard({required this.changes});

  final List<_RecentChange> changes;

  @override
  Widget build(BuildContext context) {
    return SpaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent Storage Changes',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          if (changes.isEmpty)
            const _InlineMessage(
              icon: Icons.timeline_rounded,
              message: 'Storage history appears here after two scans.',
            )
          else
            for (final change in changes)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  change.deltaBytes >= 0
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                ),
                title: Text(change.title),
                subtitle: Text(_formatDate(change.timestamp)),
                trailing: Text(change.formattedDelta),
              ),
        ],
      ),
    );
  }
}

class _TwoColumnSection extends StatelessWidget {
  const _TwoColumnSection({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(children: [left, const SizedBox(height: 14), right]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 14),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.stats});

  final StorageStats stats;

  @override
  Widget build(BuildContext context) {
    final usedPercent = (stats.usedPercent * 100).round().clamp(0, 100);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('$usedPercent% used')),
            Text('${_formatBytes(stats.freeBytes)} free'),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 14,
            value: stats.usedPercent.clamp(0, 1),
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
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
              const SizedBox(height: 4),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
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
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StorageIntelligenceLoading extends StatelessWidget {
  const _StorageIntelligenceLoading({
    required this.progress,
    required this.isScanning,
  });

  final StorageScanProgress progress;
  final bool isScanning;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SpaceCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colorScheme.primary.withValues(alpha: 0.26),
                          colorScheme.tertiary.withValues(alpha: 0.18),
                        ],
                      ),
                      border: Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.34),
                      ),
                    ),
                    child: Icon(
                      isScanning
                          ? Icons.manage_search_rounded
                          : Icons.storage_rounded,
                      color: colorScheme.primary,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isScanning
                              ? 'Scanning storage intelligence'
                              : 'Preparing storage intelligence',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isScanning
                              ? 'Reading accessible folders, classifying files, and measuring storage use.'
                              : 'Loading device totals before building the report.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress.stage == StorageScanStage.complete ? 1 : null,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _LoadingMetric(
                    label: 'Stage',
                    value: _stageLabel(progress.stage),
                  ),
                  _LoadingMetric(
                    label: 'Files',
                    value: progress.filesAnalyzed?.toString() ?? 'Counting',
                  ),
                  _LoadingMetric(
                    label: 'Storage',
                    value: progress.bytesAnalyzed == null
                        ? 'Measuring'
                        : _formatBytes(progress.bytesAnalyzed!),
                  ),
                  _LoadingMetric(
                    label: 'Roots',
                    value: progress.scannedRootCount?.toString() ?? 'Finding',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingMetric extends StatelessWidget {
  const _LoadingMetric({required this.label, required this.value});

  final String label;
  final String value;

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
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
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

class _StorageOverviewCategory {
  const _StorageOverviewCategory({
    required this.routeName,
    required this.label,
    required this.icon,
    required this.color,
    required this.bytes,
    required this.fileCount,
  });

  final String routeName;
  final String label;
  final IconData icon;
  final Color color;
  final int bytes;
  final int fileCount;
}

class _RecentChange {
  const _RecentChange({
    required this.title,
    required this.deltaBytes,
    required this.timestamp,
  });

  final String title;
  final int deltaBytes;
  final DateTime timestamp;

  String get formattedDelta {
    final sign = deltaBytes >= 0 ? '+' : '-';
    return '$sign${_formatBytes(deltaBytes.abs())}';
  }
}

List<_StorageOverviewCategory> _buildCategories(
  StorageStats stats,
  StorageIntelligenceReport? report,
) {
  int bytesFor(StorageFileCategory category) {
    return report?.summaryFor(category).totalBytes ?? 0;
  }

  int countFor(StorageFileCategory category) {
    return report?.summaryFor(category).fileCount ?? 0;
  }

  final scannedTotal = _uniqueScannedBytes(report?.files ?? const []);
  final appBytes = math.max(0, stats.usedBytes - scannedTotal);

  return [
    _StorageOverviewCategory(
      routeName: 'image',
      label: 'Images',
      icon: Icons.image_rounded,
      color: const Color(0xFF8E45FF),
      bytes: bytesFor(StorageFileCategory.image),
      fileCount: countFor(StorageFileCategory.image),
    ),
    _StorageOverviewCategory(
      routeName: 'video',
      label: 'Videos',
      icon: Icons.movie_rounded,
      color: const Color(0xFF176BFF),
      bytes: bytesFor(StorageFileCategory.video),
      fileCount: countFor(StorageFileCategory.video),
    ),
    _StorageOverviewCategory(
      routeName: 'audio',
      label: 'Audio',
      icon: Icons.audio_file_rounded,
      color: const Color(0xFFE5489E),
      bytes: bytesFor(StorageFileCategory.audio),
      fileCount: countFor(StorageFileCategory.audio),
    ),
    _StorageOverviewCategory(
      routeName: 'document',
      label: 'Documents',
      icon: Icons.description_rounded,
      color: const Color(0xFFE2AA18),
      bytes: bytesFor(StorageFileCategory.document),
      fileCount: countFor(StorageFileCategory.document),
    ),
    _StorageOverviewCategory(
      routeName: 'apps',
      label: 'Apps',
      icon: Icons.apps_rounded,
      color: const Color(0xFF4D9A35),
      bytes: appBytes,
      fileCount: 0,
    ),
    _StorageOverviewCategory(
      routeName: 'zip',
      label: 'Archives',
      icon: Icons.archive_rounded,
      color: const Color(0xFFFF7E1D),
      bytes: bytesFor(StorageFileCategory.zip),
      fileCount: countFor(StorageFileCategory.zip),
    ),
    _StorageOverviewCategory(
      routeName: 'apk',
      label: 'APKs',
      icon: Icons.android_rounded,
      color: const Color(0xFF11BFD7),
      bytes: bytesFor(StorageFileCategory.apk),
      fileCount: countFor(StorageFileCategory.apk),
    ),
    _StorageOverviewCategory(
      routeName: 'download',
      label: 'Downloads',
      icon: Icons.download_rounded,
      color: const Color(0xFFD849A9),
      bytes: bytesFor(StorageFileCategory.download),
      fileCount: countFor(StorageFileCategory.download),
    ),
    _StorageOverviewCategory(
      routeName: 'other',
      label: 'Other files',
      icon: Icons.category_rounded,
      color: const Color(0xFF35C7BD),
      bytes: bytesFor(StorageFileCategory.other),
      fileCount: countFor(StorageFileCategory.other),
    ),
  ];
}

List<_RecentChange> _recentChanges(List<StorageHistoryEntry> history) {
  if (history.length < 2) return const [];
  final sorted = [...history]
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  final changes = <_RecentChange>[];
  for (
    var index = 0;
    index < sorted.length - 1 && changes.length < 3;
    index++
  ) {
    final current = sorted[index];
    final previous = sorted[index + 1];
    changes.add(
      _RecentChange(
        title: current.usedBytes >= previous.usedBytes
            ? 'Storage used increased'
            : 'Storage used decreased',
        deltaBytes: current.usedBytes - previous.usedBytes,
        timestamp: current.timestamp,
      ),
    );
  }
  return changes;
}

StorageStats? _reportStats(StorageIntelligenceReport? report) {
  return report?.storageStats;
}

int _uniqueScannedBytes(List<ScannedFile> files) {
  final seen = <String>{};
  var total = 0;
  for (final file in files) {
    if (seen.add(file.path)) total += file.size;
  }
  return total;
}

String _folderName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) return path;
  return parts.last;
}

bool _permissionError(Object error) {
  return error is PlatformException && error.code == 'PERMISSION_DENIED';
}

String _stageLabel(StorageScanStage stage) {
  return switch (stage) {
    StorageScanStage.idle => 'Preparing',
    StorageScanStage.verifyingPermissions => 'Permissions',
    StorageScanStage.scanning => 'Scanning',
    StorageScanStage.savingHistory => 'Saving',
    StorageScanStage.complete => 'Complete',
    StorageScanStage.failed => 'Error',
  };
}

String _scanErrorMessage(Object error) {
  if (_permissionError(error)) {
    return 'Storage and media access are required to build storage intelligence.';
  }
  if (error is UnsupportedError) {
    return 'Storage intelligence is available on Android devices.';
  }
  if (error is PlatformException && error.message != null) {
    return error.message!;
  }
  return 'Storage intelligence could not be loaded. Please try again.';
}

String _formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${date.year}-$month-$day $hour:$minute';
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

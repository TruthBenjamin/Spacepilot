import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../analytics/domain/models/storage_analytics.dart';
import '../../../analytics/presentation/providers/analytics_provider.dart';
import '../../../../shared/presentation/widgets/space_background.dart';
import '../../../storage/data/services/storage_scanner_service.dart';
import '../../../storage/presentation/providers/storage_scan_provider.dart';

class ScanResultsPage extends ConsumerWidget {
  const ScanResultsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scan = ref.watch(storageScanProvider);
    final analytics = ref.watch(storageAnalyticsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Advanced Analytics')),
      body: SpaceBackground(
        child: SafeArea(
          child: scan.when(
            data: (state) {
              if (!state.hasScanned) {
                return const _EmptyState(
                  icon: Icons.analytics_outlined,
                  title: 'Run a scan to unlock analytics',
                  message:
                      'Advanced analytics will summarize file types, clutter, duplicates, and storage impact.',
                );
              }

              return analytics.when(
                data: (data) => _AnalyticsView(data: data),
                error: (error, _) => _EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Analytics unavailable',
                  message: 'Scan analytics could not be calculated.',
                ),
                loading: () => const _LoadingState(),
              );
            },
            error: (error, _) => _EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Scan unavailable',
              message: 'Run another scan to refresh analytics.',
            ),
            loading: () => const _LoadingState(),
          ),
        ),
      ),
    );
  }
}

class _AnalyticsView extends StatelessWidget {
  const _AnalyticsView({required this.data});

  final StorageAnalytics data;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        _MetricGrid(data: data),
        const SizedBox(height: 16),
        _CategoryBreakdownCard(categories: data.categories),
        const SizedBox(height: 16),
        _LargestFilesCard(files: data.largestFiles),
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.data});

  final StorageAnalytics data;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _MetricCard(
        icon: Icons.folder_copy_rounded,
        label: 'Files analyzed',
        value: '${data.totalFiles}',
        caption: _formatBytes(data.totalBytes),
      ),
      _MetricCard(
        icon: Icons.file_copy_rounded,
        label: 'Duplicate waste',
        value: _formatBytes(data.duplicateBytes),
        caption: '${data.duplicateGroups} groups',
      ),
      _MetricCard(
        icon: Icons.cleaning_services_rounded,
        label: 'Junk files',
        value: '${data.junkFileCount}',
        caption: _formatBytes(data.junkBytes),
      ),
      _MetricCard(
        icon: Icons.history_rounded,
        label: 'Unused files',
        value: '${data.unusedFileCount}',
        caption: _formatBytes(data.unusedBytes),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 680 ? 4 : 2;
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: columns == 4 ? 1.25 : 1.35,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: cards,
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
  });

  final IconData icon;
  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colorScheme.primary),
            const Spacer(),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryBreakdownCard extends StatelessWidget {
  const _CategoryBreakdownCard({required this.categories});

  final List<FileCategoryBreakdown> categories;

  @override
  Widget build(BuildContext context) {
    final totalBytes = categories.fold<int>(
      0,
      (total, category) => total + category.bytes,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'File type breakdown',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            if (categories.isEmpty)
              Text(
                'No files found in the latest scan.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              for (final category in categories)
                _CategoryRow(category: category, totalBytes: totalBytes),
          ],
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.totalBytes});

  final FileCategoryBreakdown category;
  final int totalBytes;

  @override
  Widget build(BuildContext context) {
    final ratio = totalBytes == 0 ? 0.0 : category.bytes / totalBytes;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  category.category.label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${category.fileCount} | ${_formatBytes(category.bytes)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: ratio.clamp(0, 1).toDouble()),
        ],
      ),
    );
  }
}

class _LargestFilesCard extends StatelessWidget {
  const _LargestFilesCard({required this.files});

  final List<ScannedFile> files;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Largest files',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            if (files.isEmpty)
              const Text('No files to display.')
            else
              for (final file in files) _FileRow(file: file),
          ],
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file});

  final ScannedFile file;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.insert_drive_file_outlined),
      title: Text(
        file.filename,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        file.path,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(_formatBytes(file.size)),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
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
    );
  }
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

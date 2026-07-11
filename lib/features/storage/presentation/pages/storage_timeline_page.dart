import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../../shared/presentation/widgets/space_background.dart';
import '../../data/services/storage_forecast_engine.dart';
import '../../domain/models/storage_forecast.dart';
import '../../domain/models/storage_history_entry.dart';
import '../../domain/models/storage_intelligence_report.dart';
import '../providers/device_storage_provider.dart';
import '../providers/storage_history_provider.dart';

final _timelineViewProvider = StateProvider<_TimelineView>(
  (ref) => _TimelineView.today,
);

enum _TimelineView {
  today('Today', Duration(days: 1)),
  yesterday('Yesterday', Duration(days: 2)),
  week('Week', Duration(days: 7)),
  month('Month', Duration(days: 30));

  const _TimelineView(this.label, this.window);

  final String label;
  final Duration window;
}

class StorageTimelinePage extends ConsumerWidget {
  const StorageTimelinePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(storageHistoryProvider);
    final stats = ref.watch(deviceStorageStatsProvider);
    final view = ref.watch(_timelineViewProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Storage Timeline')),
      body: SpaceBackground(
        child: SafeArea(
          child: history.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => const _EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Timeline unavailable',
              message: 'Run Smart Scan to rebuild local storage history.',
            ),
            data: (entries) {
              final forecast = stats.value == null
                  ? null
                  : const StorageForecastEngine().forecast(
                      history: entries,
                      currentStats: stats.value!,
                    );

              if (entries.isEmpty) {
                return const _EmptyState(
                  icon: Icons.timeline_rounded,
                  title: 'No timeline yet',
                  message:
                      'Smart Scan saves local storage snapshots after each successful scan.',
                );
              }

              final sorted = [...entries]
                ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
              final visible = _entriesForView(sorted, view, DateTime.now());
              final hasEnough = _hasEnoughHistory(visible);

              return SpacePageList(
                children: [
                  _ViewPicker(
                    selected: view,
                    onChanged: (next) =>
                        ref.read(_timelineViewProvider.notifier).state = next,
                  ),
                  const SizedBox(height: 16),
                  if (forecast != null) _ForecastCard(forecast: forecast),
                  if (forecast != null) const SizedBox(height: 16),
                  if (!hasEnough)
                    _EmptyState(
                      icon: Icons.insights_rounded,
                      title: 'Not enough ${view.label.toLowerCase()} history',
                      message:
                          'SpacePilot has ${visible.length} matching snapshot${visible.length == 1 ? '' : 's'}. More analytics appear after future scans are saved.',
                    )
                  else ...[
                    _TimelineSummaryCard(entries: visible, view: view),
                    const SizedBox(height: 16),
                    _UsageChart(entries: visible),
                    const SizedBox(height: 16),
                    _EventsCard(entries: visible),
                    const SizedBox(height: 16),
                    for (final entry in visible) ...[
                      _HistoryEntryCard(entry: entry),
                      const SizedBox(height: 12),
                    ],
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ViewPicker extends StatelessWidget {
  const _ViewPicker({required this.selected, required this.onChanged});

  final _TimelineView selected;
  final ValueChanged<_TimelineView> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<_TimelineView>(
        segments: [
          for (final view in _TimelineView.values)
            ButtonSegment(value: view, label: Text(view.label)),
        ],
        selected: {selected},
        onSelectionChanged: (values) {
          if (values.isNotEmpty) onChanged(values.first);
        },
      ),
    );
  }
}

class _TimelineSummaryCard extends StatelessWidget {
  const _TimelineSummaryCard({required this.entries, required this.view});

  final List<StorageHistoryEntry> entries;
  final _TimelineView view;

  @override
  Widget build(BuildContext context) {
    final newest = entries.first;
    final oldest = entries.last;
    final usedChange = newest.usedBytes - oldest.usedBytes;
    final downloadChange = newest.downloadBytes - oldest.downloadBytes;
    final emptyFolderChange = newest.emptyFolderCount - oldest.emptyFolderCount;
    final largestFolderChange = _largestFolderChange(entries);
    final categoryChanges = _categoryChanges(newest, oldest);

    return SpaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${view.label} analytics',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Metric(label: 'Total change', value: _signedBytes(usedChange)),
              _Metric(
                label: 'Download growth',
                value: _signedBytes(downloadChange),
              ),
              _Metric(
                label: 'Empty folders',
                value: _signedCount(emptyFolderChange),
              ),
              _Metric(label: 'Largest folder', value: largestFolderChange),
            ],
          ),
          if (categoryChanges.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Largest category changes',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final change in categoryChanges.take(3))
                  _Metric(
                    label: _categoryLabel(change.key.name),
                    value: _signedBytes(change.value),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _UsageChart extends StatelessWidget {
  const _UsageChart({required this.entries});

  final List<StorageHistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    final chronological = entries.reversed.toList(growable: false);

    return SpaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Storage trend',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final entry in chronological)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Tooltip(
                        message:
                            '${_formatDate(entry.timestamp)}: ${_formatBytes(entry.usedBytes)} used',
                        child: FractionallySizedBox(
                          heightFactor: entry.usedPercent.clamp(0.04, 1),
                          alignment: Alignment.bottomCenter,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
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

class _EventsCard extends StatelessWidget {
  const _EventsCard({required this.entries});

  final List<StorageHistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    final events = <String>[
      for (final entry in entries)
        if (entry.eventType == StorageHistoryEventType.cleanup)
          'Cleanup completed ${_formatDate(entry.timestamp)}${entry.affectedBytes > 0 ? ': ${_formatBytes(entry.affectedBytes)} moved or deleted' : ''}'
        else
          'Scan saved ${_formatDate(entry.timestamp)} with ${_formatBytes(entry.usedBytes)} used',
    ];

    return SpaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Scan and cleanup events',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          for (final event in events.take(8))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_note_rounded),
              title: Text(event),
            ),
        ],
      ),
    );
  }
}

List<MapEntry<StorageFileCategory, int>> _categoryChanges(
  StorageHistoryEntry newest,
  StorageHistoryEntry oldest,
) {
  final categories = {
    ...newest.categoryBytes.keys,
    ...oldest.categoryBytes.keys,
  };
  final changes = [
    for (final category in categories)
      MapEntry(
        category,
        (newest.categoryBytes[category] ?? 0) -
            (oldest.categoryBytes[category] ?? 0),
      ),
  ]..removeWhere((entry) => entry.value == 0);
  changes.sort((a, b) => b.value.abs().compareTo(a.value.abs()));
  return changes;
}

String _categoryLabel(String name) {
  if (name.isEmpty) return name;
  return '${name[0].toUpperCase()}${name.substring(1)}';
}

class _ForecastCard extends StatelessWidget {
  const _ForecastCard({required this.forecast});

  final StorageForecast forecast;

  @override
  Widget build(BuildContext context) {
    return SpaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Growth forecast',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Metric(
                label: 'Weekly growth',
                value: _formatBytes(forecast.weeklyGrowthBytes),
              ),
              _Metric(
                label: 'Days until full',
                value: forecast.daysUntilFull == null
                    ? 'Stable'
                    : forecast.daysUntilFull!.toStringAsFixed(1),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final recommendation in forecast.recommendations.take(2))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                recommendation,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryEntryCard extends StatelessWidget {
  const _HistoryEntryCard({required this.entry});

  final StorageHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final usedPercent = (entry.usedPercent * 100).round().clamp(0, 100);

    return SpaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _formatDate(entry.timestamp),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text('$usedPercent% used'),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: entry.usedPercent.clamp(0, 1)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Metric(label: 'Used', value: _formatBytes(entry.usedBytes)),
              _Metric(label: 'Free', value: _formatBytes(entry.freeBytes)),
              _Metric(
                label: 'Downloads',
                value: _formatBytes(entry.downloadBytes),
              ),
              _Metric(
                label: 'Empty folders',
                value: '${entry.emptyFolderCount}',
              ),
            ],
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
      width: 138,
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
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${date.year}-$month-$day $hour:$minute';
}

List<StorageHistoryEntry> _entriesForView(
  List<StorageHistoryEntry> sortedNewestFirst,
  _TimelineView view,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  if (view == _TimelineView.yesterday) {
    final start = today.subtract(const Duration(days: 1));
    return sortedNewestFirst
        .where(
          (entry) =>
              !entry.timestamp.isBefore(start) &&
              entry.timestamp.isBefore(today),
        )
        .toList(growable: false);
  }

  final start = now.subtract(view.window);
  return sortedNewestFirst
      .where((entry) => !entry.timestamp.isBefore(start))
      .toList(growable: false);
}

bool _hasEnoughHistory(List<StorageHistoryEntry> entries) {
  return entries.length >= 2;
}

String _signedBytes(int bytes) {
  if (bytes == 0) return 'No change';
  final prefix = bytes > 0 ? '+' : '-';
  return '$prefix${_formatBytes(bytes.abs())}';
}

String _signedCount(int count) {
  if (count == 0) return 'No change';
  return count > 0 ? '+$count' : '$count';
}

String _largestFolderChange(List<StorageHistoryEntry> entries) {
  final newest = entries.first.largestFolders.isEmpty
      ? null
      : entries.first.largestFolders.first;
  final oldest = entries.last.largestFolders.isEmpty
      ? null
      : entries.last.largestFolders.first;
  if (newest == null) return 'Unavailable';
  if (oldest == null || newest.path != oldest.path) {
    return _formatBytes(newest.sizeBytes);
  }
  return _signedBytes(newest.sizeBytes - oldest.sizeBytes);
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

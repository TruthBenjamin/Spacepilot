import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/presentation/widgets/space_background.dart';
import '../../../large_files/data/services/large_file_action_service.dart';
import '../../../large_files/presentation/providers/large_file_hunter_provider.dart';
import '../../../storage/presentation/providers/device_storage_provider.dart';
import '../../domain/models/recovery_bin_item.dart';
import '../providers/recovery_bin_provider.dart';

class RecoveryBinPage extends ConsumerStatefulWidget {
  const RecoveryBinPage({super.key});

  @override
  ConsumerState<RecoveryBinPage> createState() => _RecoveryBinPageState();
}

class _RecoveryBinPageState extends ConsumerState<RecoveryBinPage> {
  final _queryController = TextEditingController();
  final Set<String> _selected = <String>{};
  String _query = '';
  bool _expiredOnly = false;
  bool _purgeRunning = false;

  @override
  void initState() {
    super.initState();
    _queryController.addListener(() {
      setState(() => _query = _queryController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(recoveryBinProvider);
    final retentionDays = ref.watch(recoveryRetentionDaysProvider);
    final autoPurge = ref.watch(recoveryAutoPurgeProvider);
    final actions = ref.watch(largeFileActionServiceProvider);
    final now = DateTime.now();
    if (autoPurge &&
        !_purgeRunning &&
        items.any((item) => item.isExpired(now))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _purgeExpiredFiles(actions, items, now);
      });
    }
    final visible =
        items
            .where((item) {
              if (_expiredOnly && !item.isExpired(now)) return false;
              if (_query.isEmpty) return true;
              return item.filename.toLowerCase().contains(_query) ||
                  item.originalPath.toLowerCase().contains(_query);
            })
            .toList(growable: false)
          ..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));

    return Scaffold(
      appBar: AppBar(title: const Text('Recovery Bin')),
      body: SpaceBackground(
        child: SafeArea(
          child: SpacePageList(
            children: [
              SpaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'App-managed recovery',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Only files SpacePilot moves into recoverable app storage can appear here. Permanently deleted Android files cannot be recovered by this page.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _Metric(label: 'Items', value: '${items.length}'),
                        _Metric(
                          label: 'Recoverable size',
                          value: _formatBytes(
                            items.fold<int>(
                              0,
                              (total, item) => total + item.sizeBytes,
                            ),
                          ),
                        ),
                        _Metric(
                          label: 'Retention',
                          value: '$retentionDays days',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _ControlsCard(
                controller: _queryController,
                expiredOnly: _expiredOnly,
                autoPurge: autoPurge,
                retentionDays: retentionDays,
                selectedCount: _selected.length,
                onExpiredChanged: (value) =>
                    setState(() => _expiredOnly = value),
                onAutoPurgeChanged: (value) => ref
                    .read(recoverySettingsProvider.notifier)
                    .setAutoPurge(value),
                onRetentionChanged: (value) => ref
                    .read(recoverySettingsProvider.notifier)
                    .setRetentionDays(value),
                onClearSelected: _selected.isEmpty
                    ? null
                    : () => setState(_selected.clear),
                onDeleteSelected: _selected.isEmpty
                    ? null
                    : () => _confirmRemoveSelected(permanent: true),
              ),
              const SizedBox(height: 14),
              if (visible.isEmpty)
                _EmptyState(hasItems: items.isNotEmpty)
              else
                for (final item in visible) ...[
                  _RecoveryTile(
                    item: item,
                    selected: _selected.contains(item.id),
                    onSelected: (selected) => setState(() {
                      selected
                          ? _selected.add(item.id)
                          : _selected.remove(item.id);
                    }),
                    onRestore: () => _restoreItem(actions, item),
                    onDelete: () => _confirmRemoveSelected(
                      permanent: true,
                      itemIds: [item.id],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _purgeExpiredFiles(
    LargeFileActionService actions,
    List<RecoveryBinItem> items,
    DateTime now,
  ) async {
    if (_purgeRunning) return;
    _purgeRunning = true;
    final removed = <String>[];
    for (final item in items.where((item) => item.isExpired(now))) {
      try {
        await actions.deleteRecoveryItem(item.recoveryPath);
        removed.add(item.id);
      } catch (_) {
        // Keep metadata so the user can retry instead of hiding an orphaned file.
      }
    }
    if (mounted && removed.isNotEmpty) {
      ref.read(recoveryBinProvider.notifier).removeItems(removed);
    }
    _purgeRunning = false;
  }

  Future<void> _confirmRemoveSelected({
    required bool permanent,
    Iterable<String>? itemIds,
  }) async {
    final ids = (itemIds ?? _selected).toSet();
    if (ids.isEmpty) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.delete_forever_rounded,
          color: Theme.of(context).colorScheme.error,
        ),
        title: const Text('Permanently delete from bin?'),
        content: Text(
          'This removes ${ids.length} recoverable ${ids.length == 1 ? 'item' : 'items'} from SpacePilot recovery storage.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    final itemsById = {
      for (final item in ref.read(recoveryBinProvider)) item.id: item,
    };
    final deletedIds = <String>[];
    final failures = <String>[];
    final actions = ref.read(largeFileActionServiceProvider);

    for (final id in ids) {
      final item = itemsById[id];
      if (item == null) continue;
      try {
        await actions.deleteRecoveryItem(item.recoveryPath);
        deletedIds.add(id);
      } catch (error) {
        failures.add(item.filename);
      }
    }

    if (deletedIds.isNotEmpty) {
      ref.read(recoveryBinProvider.notifier).removeItems(deletedIds);
      setState(() => _selected.removeAll(deletedIds));
      ref
        ..invalidate(deviceStorageStatsProvider)
        ..invalidate(deviceStorageStatsWithHealthProvider);
    }

    if (!mounted) return;
    if (failures.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${deletedIds.length} deleted; ${failures.length} could not be deleted.',
          ),
        ),
      );
    }
  }

  Future<void> _restoreItem(
    LargeFileActionService actions,
    RecoveryBinItem item,
  ) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.restore_rounded),
        title: Text('Restore ${item.filename}?'),
        content: Text(
          'SpacePilot will move this file back to its original folder. If a file already exists there, Android will restore it with a unique name.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.restore_rounded),
            label: const Text('Restore'),
          ),
        ],
      ),
    );
    if (approved != true) return;

    try {
      final result = await actions.restoreRecoveryItem(
        recoveryPath: item.recoveryPath,
        originalPath: item.originalPath,
      );
      ref.read(recoveryBinProvider.notifier).removeItems([item.id]);
      setState(() => _selected.remove(item.id));
      ref
        ..invalidate(deviceStorageStatsProvider)
        ..invalidate(deviceStorageStatsWithHealthProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Restored ${result.filename}.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_fileActionError(error))));
    }
  }
}

class _ControlsCard extends StatelessWidget {
  const _ControlsCard({
    required this.controller,
    required this.expiredOnly,
    required this.autoPurge,
    required this.retentionDays,
    required this.selectedCount,
    required this.onExpiredChanged,
    required this.onAutoPurgeChanged,
    required this.onRetentionChanged,
    this.onClearSelected,
    this.onDeleteSelected,
  });

  final TextEditingController controller;
  final bool expiredOnly;
  final bool autoPurge;
  final int retentionDays;
  final int selectedCount;
  final ValueChanged<bool> onExpiredChanged;
  final ValueChanged<bool> onAutoPurgeChanged;
  final ValueChanged<int> onRetentionChanged;
  final VoidCallback? onClearSelected;
  final VoidCallback? onDeleteSelected;

  @override
  Widget build(BuildContext context) {
    return SpaceCard(
      child: Column(
        children: [
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              labelText: 'Search deleted items',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: expiredOnly,
            onChanged: onExpiredChanged,
            title: const Text('Show expired only'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: autoPurge,
            onChanged: onAutoPurgeChanged,
            title: const Text('Auto-purge expired items'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_repeat_rounded),
            title: const Text('Retention'),
            subtitle: Slider(
              value: retentionDays.toDouble(),
              min: 7,
              max: 90,
              divisions: 83,
              label: '$retentionDays days',
              onChanged: (value) => onRetentionChanged(value.round()),
            ),
          ),
          if (selectedCount > 0)
            Row(
              children: [
                Expanded(child: Text('$selectedCount selected')),
                TextButton(
                  onPressed: onClearSelected,
                  child: const Text('Clear'),
                ),
                FilledButton.icon(
                  onPressed: onDeleteSelected,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Delete'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _RecoveryTile extends StatelessWidget {
  const _RecoveryTile({
    required this.item,
    required this.selected,
    required this.onSelected,
    required this.onRestore,
    required this.onDelete,
  });

  final RecoveryBinItem item;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SpaceCard(
      child: Row(
        children: [
          Checkbox(
            value: selected,
            onChanged: (value) => onSelected(value ?? false),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.insert_drive_file_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  item.originalPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '${_formatBytes(item.sizeBytes)} | deleted ${_formatDate(item.deletedAt)} | expires ${_formatDate(item.expiresAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Restore',
            onPressed: onRestore,
            icon: const Icon(Icons.restore_rounded),
          ),
          IconButton(
            tooltip: 'Delete permanently',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_forever_rounded),
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
      width: 140,
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
  const _EmptyState({required this.hasItems});

  final bool hasItems;

  @override
  Widget build(BuildContext context) {
    return SpaceCard(
      child: Column(
        children: [
          Icon(
            Icons.restore_from_trash_rounded,
            size: 46,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            hasItems ? 'No items match the filters' : 'Recovery bin is empty',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            hasItems
                ? 'Adjust search or filters to see recoverable items.'
                : 'Items appear here only after SpacePilot moves them into app-managed recoverable storage.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime value) {
  return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
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

String _fileActionError(Object error) {
  if (error is UnsupportedError) {
    return error.message ?? 'Recovery action is unsupported.';
  }
  return 'Recovery action could not be completed.';
}

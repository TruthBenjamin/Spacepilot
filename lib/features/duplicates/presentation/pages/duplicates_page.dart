import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../cleanup/data/services/cleanup_service.dart';
import '../../../cleanup/presentation/providers/cleanup_service_provider.dart';
import '../../../../shared/presentation/widgets/space_background.dart';
import '../../../storage/presentation/providers/device_storage_provider.dart';
import '../../../storage/presentation/providers/storage_scan_provider.dart';
import '../../domain/models/duplicate_file.dart';
import '../../domain/models/duplicate_group.dart';
import '../providers/duplicate_groups_provider.dart';

class DuplicatesPage extends ConsumerStatefulWidget {
  const DuplicatesPage({super.key});

  @override
  ConsumerState<DuplicatesPage> createState() => _DuplicatesPageState();
}

class _DuplicatesPageState extends ConsumerState<DuplicatesPage> {
  final Set<String> _selectedPaths = {};
  final Set<String> _initializedGroups = {};
  bool _isDeleting = false;

  Future<void> _runScan() async {
    try {
      await ref.read(storageScanProvider.notifier).scan();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_scanErrorMessage(error))));
    }
  }

  void _initializeSelections(List<DuplicateGroup> groups) {
    for (final group in groups) {
      if (_initializedGroups.add(group.sha256Hash)) {
        _selectedPaths.addAll(group.files.skip(1).map((file) => file.path));
      }
    }
  }

  Future<void> _confirmAndDeleteDuplicates(
    List<DuplicateGroup> groups,
    int selectedBytes,
  ) async {
    if (_selectedPaths.isEmpty || _isDeleting) return;

    final approved = await _showDeleteConfirmation(
      context,
      title: 'Delete selected duplicates?',
      fileCount: _selectedPaths.length,
      bytes: selectedBytes,
    );
    if (approved != true || !mounted) return;

    setState(() => _isDeleting = true);
    final CleanupResult result;
    try {
      result = await ref
          .read(cleanupServiceProvider)
          .deleteDuplicates(
            groups,
            selectedPaths: Set<String>.of(_selectedPaths),
            userConfirmed: true,
          );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Duplicate files could not be deleted.')),
      );
      return;
    }
    if (!mounted) return;

    ref
        .read(storageScanProvider.notifier)
        .removeDeletedPaths(result.deletedPaths);
    ref.invalidate(deviceStorageStatsProvider);
    ref.invalidate(deviceStorageStatsWithHealthProvider);
    setState(() {
      _isDeleting = false;
      _selectedPaths.removeAll(result.deletedPaths);
      _initializedGroups.clear();
    });
    ref.invalidate(duplicateGroupsProvider);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_cleanupMessage(result))));
  }

  @override
  Widget build(BuildContext context) {
    final scan = ref.watch(storageScanProvider);
    final groups = ref.watch(duplicateGroupsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Duplicate Files')),
      body: SpaceBackground(
        child: SafeArea(
          child: groups.when(
            loading: () => const _LoadingState(),
            error: (error, _) => _ErrorState(
              message: 'Duplicate files could not be analyzed.',
              onRetry: () => ref.invalidate(duplicateGroupsProvider),
            ),
            data: (duplicateGroups) {
              _initializeSelections(duplicateGroups);

              if (scan.value?.hasScanned != true) {
                return _EmptyState(
                  icon: Icons.copy_all_rounded,
                  title: 'Scan to uncover duplicate files',
                  message:
                      'SpacePilot uses SHA256 hashes to compare images, videos, documents, and audio.',
                  actionLabel: 'Run storage scan',
                  onAction: _runScan,
                );
              }

              if (duplicateGroups.isEmpty) {
                return const _EmptyState(
                  icon: Icons.verified_rounded,
                  title: 'No duplicate files found',
                  message:
                      'Your scanned folders are already free of exact copies.',
                );
              }

              final fileCount = duplicateGroups.fold<int>(
                0,
                (total, group) => total + group.files.length,
              );
              final wastedBytes = duplicateGroups.fold<int>(
                0,
                (total, group) => total + group.recoverableBytes,
              );
              final selectedBytes = duplicateGroups
                  .expand((group) => group.files)
                  .where((file) => _selectedPaths.contains(file.path))
                  .fold<int>(0, (total, file) => total + file.sizeBytes);

              return LayoutBuilder(
                builder: (context, constraints) {
                  const maxWidth = 1040.0;
                  final extraWidth = (constraints.maxWidth - maxWidth)
                      .clamp(0, double.infinity)
                      .toDouble();
                  final sideInset = extraWidth / 2;

                  return CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          20 + sideInset,
                          12,
                          20 + sideInset,
                          28,
                        ),
                        sliver: SliverList.list(
                          children: [
                            _SummaryCard(
                              groupCount: duplicateGroups.length,
                              fileCount: fileCount,
                              wastedBytes: wastedBytes,
                            ),
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Duplicate groups',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ),
                                Text(
                                  '${_selectedPaths.length} selected',
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            for (
                              var index = 0;
                              index < duplicateGroups.length;
                              index++
                            ) ...[
                              _DuplicateGroupCard(
                                index: index,
                                group: duplicateGroups[index],
                                selectedPaths: _selectedPaths,
                                onFileChanged: (path, selected) {
                                  setState(() {
                                    selected
                                        ? _selectedPaths.add(path)
                                        : _selectedPaths.remove(path);
                                  });
                                },
                                onGroupChanged: (selected) {
                                  setState(() {
                                    final selectable = duplicateGroups[index]
                                        .files
                                        .skip(1)
                                        .map((file) => file.path);
                                    selected
                                        ? _selectedPaths.addAll(selectable)
                                        : _selectedPaths.removeAll(selectable);
                                  });
                                },
                              ),
                              const SizedBox(height: 12),
                            ],
                            _SelectionSummary(
                              count: _selectedPaths.length,
                              bytes: selectedBytes,
                              isDeleting: _isDeleting,
                              onDelete: () => _confirmAndDeleteDuplicates(
                                duplicateGroups,
                                selectedBytes,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.groupCount,
    required this.fileCount,
    required this.wastedBytes,
  });

  final int groupCount;
  final int fileCount;
  final int wastedBytes;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colorScheme.primary, colorScheme.primary.withBlue(210)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.24),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.layers_rounded, color: Colors.white, size: 32),
          const SizedBox(height: 16),
          Text(
            _formatBytes(wastedBytes),
            style: textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            'recoverable storage',
            style: textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.76),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  value: '$groupCount',
                  label: groupCount == 1 ? 'group' : 'groups',
                ),
              ),
              Container(
                width: 1,
                height: 38,
                color: Colors.white.withValues(alpha: 0.2),
              ),
              Expanded(
                child: _SummaryMetric(
                  value: '$fileCount',
                  label: fileCount == 1 ? 'file' : 'files',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.72),
          ),
        ),
      ],
    );
  }
}

class _DuplicateGroupCard extends StatelessWidget {
  const _DuplicateGroupCard({
    required this.index,
    required this.group,
    required this.selectedPaths,
    required this.onFileChanged,
    required this.onGroupChanged,
  });

  final int index;
  final DuplicateGroup group;
  final Set<String> selectedPaths;
  final void Function(String path, bool selected) onFileChanged;
  final ValueChanged<bool> onGroupChanged;

  @override
  Widget build(BuildContext context) {
    final selectableFiles = group.files.skip(1).toList(growable: false);
    final selectedCount = selectableFiles
        .where((file) => selectedPaths.contains(file.path))
        .length;
    final allSelected = selectedCount == selectableFiles.length;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: index == 0,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
          child: const Icon(Icons.file_copy_rounded),
        ),
        title: Text(
          'Group ${index + 1}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${group.files.length} files  |  ${_formatBytes(group.recoverableBytes)} wasted',
        ),
        trailing: Checkbox(
          value: selectedCount > 0 && !allSelected ? null : allSelected,
          tristate: selectedCount > 0 && !allSelected,
          onChanged: (value) => onGroupChanged(value ?? false),
        ),
        children: [
          for (var index = 0; index < group.files.length; index++)
            _DuplicateFileTile(
              file: group.files[index],
              isOriginal: index == 0,
              selected: selectedPaths.contains(group.files[index].path),
              onChanged: (selected) =>
                  onFileChanged(group.files[index].path, selected),
            ),
        ],
      ),
    );
  }
}

class _DuplicateFileTile extends StatelessWidget {
  const _DuplicateFileTile({
    required this.file,
    required this.isOriginal,
    required this.selected,
    required this.onChanged,
  });

  final DuplicateFile file;
  final bool isOriginal;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final directory = _parentDirectory(file.path);

    return Material(
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.38)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isOriginal ? null : () => onChanged(!selected),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: isOriginal
                    ? null
                    : (value) => onChanged(value ?? false),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (isOriginal)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'KEEP',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: colorScheme.onTertiaryContainer,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$directory  |  ${_formatBytes(file.sizeBytes)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
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

class _SelectionSummary extends StatelessWidget {
  const _SelectionSummary({
    required this.count,
    required this.bytes,
    required this.isDeleting,
    required this.onDelete,
  });

  final int count;
  final int bytes;
  final bool isDeleting;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = count == 0
        ? 'No duplicates selected'
        : '$count duplicate ${count == 1 ? 'file' : 'files'} selected';

    return Card(
      color: colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 360;
                final icon = Icon(
                  Icons.check_circle_rounded,
                  color: colorScheme.primary,
                );
                final label = Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                );
                final amount = Text(
                  _formatBytes(bytes),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                );

                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [icon, const SizedBox(width: 12), amount]),
                      const SizedBox(height: 8),
                      label,
                    ],
                  );
                }

                return Row(
                  children: [
                    icon,
                    const SizedBox(width: 12),
                    Expanded(child: label),
                    amount,
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Nothing is deleted unless you select files and confirm.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSecondaryContainer.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: count == 0 || isDeleting ? null : onDelete,
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.error,
                  foregroundColor: colorScheme.onError,
                ),
                icon: isDeleting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.delete_outline_rounded),
                label: Text(isDeleting ? 'Deleting...' : 'Delete selected'),
              ),
            ),
          ],
        ),
      ),
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
          SizedBox(height: 16),
          Text('Comparing file contents...'),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _EmptyState(
      icon: Icons.error_outline_rounded,
      title: 'Analysis interrupted',
      message: message,
      actionLabel: 'Try again',
      onAction: onRetry,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 18),
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
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.radar_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _parentDirectory(String path) {
  final normalized = path.replaceAll('\\', '/');
  final lastSeparator = normalized.lastIndexOf('/');
  if (lastSeparator <= 0) return path;
  return normalized.substring(0, lastSeparator);
}

String _scanErrorMessage(Object error) {
  if (error is PlatformException && error.code == 'PERMISSION_DENIED') {
    return 'Storage and media access are required to scan your files.';
  }
  if (error is UnsupportedError) {
    return 'Duplicate scans require Android storage access.';
  }
  return 'The storage scan could not be completed. Please try again.';
}

Future<bool?> _showDeleteConfirmation(
  BuildContext context, {
  required String title,
  required int fileCount,
  required int bytes,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(
        Icons.delete_forever_rounded,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text(title),
      content: Text(
        'This will permanently delete $fileCount '
        '${fileCount == 1 ? 'file' : 'files'} and free '
        '${_formatBytes(bytes)}. This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('Delete files'),
        ),
      ],
    ),
  );
}

String _cleanupMessage(CleanupResult result) {
  if (result.hasFailures) {
    return '${result.deletedCount} deleted; ${result.failures.length} could not be deleted.';
  }

  return '${result.deletedCount} ${result.deletedCount == 1 ? 'file' : 'files'} deleted.';
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

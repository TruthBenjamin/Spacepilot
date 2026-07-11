import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../routes/app_routes.dart';

import '../../../../shared/presentation/widgets/space_background.dart';
import '../../../cleanup/data/services/cleanup_service.dart';
import '../../../cleanup/presentation/providers/deletion_sync_provider.dart';
import '../../../cleanup/presentation/providers/cleanup_service_provider.dart';
import '../../../large_files/presentation/providers/large_file_hunter_provider.dart';
import '../../../storage/presentation/providers/storage_scan_provider.dart';
import '../../domain/models/duplicate_file.dart';
import '../../domain/models/duplicate_group.dart';
import '../providers/duplicate_groups_provider.dart';

enum _DuplicateSort {
  recoverable('Most wasted space'),
  largest('Largest files'),
  smallest('Smallest files'),
  files('Most copies'),
  newest('Newest first'),
  oldest('Oldest first'),
  name('Name A-Z');

  const _DuplicateSort(this.label);

  final String label;
}

enum _DuplicateKind {
  all('All', Icons.all_inbox_rounded),
  image('Images', Icons.image_rounded),
  video('Videos', Icons.movie_filter_rounded),
  audio('Audio', Icons.audio_file_rounded),
  document('Documents', Icons.description_rounded),
  download('Downloads', Icons.download_rounded),
  other('Other', Icons.insert_drive_file_outlined);

  const _DuplicateKind(this.label, this.icon);

  final String label;
  final IconData icon;
}

class DuplicatesPage extends ConsumerStatefulWidget {
  const DuplicatesPage({super.key});

  @override
  ConsumerState<DuplicatesPage> createState() => _DuplicatesPageState();
}

class _DuplicatesPageState extends ConsumerState<DuplicatesPage> {
  final Set<String> _selectedPaths = {};
  final Set<String> _initializedGroups = {};
  final TextEditingController _searchController = TextEditingController();
  _DuplicateSort _sort = _DuplicateSort.recoverable;
  _DuplicateKind _kind = _DuplicateKind.all;
  String _query = '';
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
        _selectedPaths.addAll(_smartSelectionFor(group));
      }
    }
  }

  Set<String> _smartSelectionFor(DuplicateGroup group) {
    final keeper = _keeperForGroup(group);
    return group.files
        .where((file) => file.path != keeper.path)
        .map((file) => file.path)
        .toSet();
  }

  void _selectSmart(List<DuplicateGroup> groups) {
    setState(() {
      _selectedPaths.clear();
      for (final group in groups) {
        _selectedPaths.addAll(_smartSelectionFor(group));
      }
    });
  }

  void _clearSelection() {
    if (_selectedPaths.isEmpty) return;
    setState(_selectedPaths.clear);
  }

  void _setFileSelected(DuplicateGroup group, DuplicateFile file, bool value) {
    setState(() {
      if (value) {
        final unselectedCount = group.files
            .where(
              (candidate) =>
                  candidate.path != file.path &&
                  !_selectedPaths.contains(candidate.path),
            )
            .length;
        if (unselectedCount == 0) {
          _showPreserveCopyMessage();
          return;
        }
        _selectedPaths.add(file.path);
      } else {
        _selectedPaths.remove(file.path);
      }
    });
  }

  void _setGroupSelected(DuplicateGroup group, bool value) {
    setState(() {
      final groupPaths = group.files.map((file) => file.path);
      if (value) {
        _selectedPaths
          ..removeAll(groupPaths)
          ..addAll(_smartSelectionFor(group));
      } else {
        _selectedPaths.removeAll(groupPaths);
      }
    });
  }

  Future<void> _previewFile(DuplicateFile file) async {
    try {
      await ref.read(largeFileActionServiceProvider).open(file.path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_fileActionError(error))));
    }
  }

  Future<void> _confirmAndDeleteDuplicates(
    List<DuplicateGroup> groups,
    int selectedBytes,
  ) async {
    if (_selectedPaths.isEmpty || _isDeleting) return;

    final selectedGroups = groups
        .where(
          (group) =>
              group.files.any((file) => _selectedPaths.contains(file.path)),
        )
        .toList(growable: false);
    if (selectedGroups.any(
      (group) =>
          group.files.every((file) => _selectedPaths.contains(file.path)),
    )) {
      _showPreserveCopyMessage();
      return;
    }
    final selectedFiles = [
      for (final group in selectedGroups)
        for (final file in group.files)
          if (_selectedPaths.contains(file.path)) file,
    ];

    final approved = await _showDeleteConfirmation(
      context,
      title: 'Delete selected duplicates?',
      fileCount: _selectedPaths.length,
      bytes: selectedBytes,
      files: selectedFiles,
      onPreview: _previewFile,
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

    ref.read(deletionSyncProvider).applyDeletedPaths(result.deletedPaths);
    setState(() {
      _isDeleting = false;
      _selectedPaths.removeAll(result.deletedPaths);
      _initializedGroups.clear();
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_cleanupMessage(result))));
  }

  void _showPreserveCopyMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('At least one copy must be preserved.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scan = ref.watch(storageScanProvider);
    final groups = ref.watch(duplicateGroupsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Duplicate Files'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  icon: Icon(Icons.copy_all_rounded),
                  label: Text('Exact copies'),
                ),
                ButtonSegment(
                  value: 1,
                  icon: Icon(Icons.image_search_rounded),
                  label: Text('Similar images'),
                ),
              ],
              selected: const {0},
              onSelectionChanged: (_) =>
                  context.pushNamed(AppRouteNames.similarImages),
            ),
          ),
        ),
      ),
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
                      'SpacePilot compares real scanned files by size and secure content hash.',
                  actionLabel: 'Run storage scan',
                  onAction: _runScan,
                );
              }

              final visibleGroups = _visibleGroups(duplicateGroups);
              final allFileCount = duplicateGroups.fold<int>(
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
                              fileCount: allFileCount,
                              wastedBytes: wastedBytes,
                              selectedBytes: selectedBytes,
                              onScanPressed: _runScan,
                            ),
                            const SizedBox(height: 16),
                            _FilterPanel(
                              searchController: _searchController,
                              selectedKind: _kind,
                              selectedSort: _sort,
                              onKindChanged: (kind) =>
                                  setState(() => _kind = kind),
                              onSortChanged: (sort) =>
                                  setState(() => _sort = sort),
                              onClear: () {
                                _searchController.clear();
                                setState(() {
                                  _kind = _DuplicateKind.all;
                                  _sort = _DuplicateSort.recoverable;
                                });
                              },
                            ),
                            const SizedBox(height: 18),
                            _Toolbar(
                              visibleCount: visibleGroups.length,
                              totalCount: duplicateGroups.length,
                              selectedCount: _selectedPaths.length,
                              onSmartSelect: () => _selectSmart(visibleGroups),
                              onClearSelection: _clearSelection,
                            ),
                            const SizedBox(height: 12),
                            if (duplicateGroups.isEmpty)
                              const _EmptyState(
                                icon: Icons.verified_rounded,
                                title: 'No duplicate files found',
                                message:
                                    'Your scanned folders are already free of exact copies.',
                              )
                            else if (visibleGroups.isEmpty)
                              _EmptyState(
                                icon: Icons.filter_alt_off_rounded,
                                title: 'No matches for these filters',
                                message:
                                    'Try another category, search term, or sort option.',
                                actionLabel: 'Clear filters',
                                onAction: () {
                                  _searchController.clear();
                                  setState(() {
                                    _kind = _DuplicateKind.all;
                                    _sort = _DuplicateSort.recoverable;
                                  });
                                },
                              )
                            else
                              for (
                                var index = 0;
                                index < visibleGroups.length;
                                index++
                              ) ...[
                                _DuplicateGroupCard(
                                  index: index,
                                  group: visibleGroups[index],
                                  selectedPaths: _selectedPaths,
                                  onFileChanged: (file, selected) =>
                                      _setFileSelected(
                                        visibleGroups[index],
                                        file,
                                        selected,
                                      ),
                                  onGroupChanged: (selected) =>
                                      _setGroupSelected(
                                        visibleGroups[index],
                                        selected,
                                      ),
                                  onFileDetails: (file) => _showFileDetails(
                                    context,
                                    file,
                                    group: visibleGroups[index],
                                    selected: _selectedPaths.contains(
                                      file.path,
                                    ),
                                    onToggleSelected: () => _setFileSelected(
                                      visibleGroups[index],
                                      file,
                                      !_selectedPaths.contains(file.path),
                                    ),
                                    onPreview: () => _previewFile(file),
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                            _SelectionSummary(
                              count: _selectedPaths.length,
                              bytes: selectedBytes,
                              isDeleting: _isDeleting,
                              onSmartSelect: () => _selectSmart(visibleGroups),
                              onClearSelection: _clearSelection,
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

  List<DuplicateGroup> _visibleGroups(List<DuplicateGroup> groups) {
    final visible = groups
        .where((group) {
          if (!_matchesKind(group, _kind)) return false;
          if (_query.isEmpty) return true;
          return group.sha256Hash.toLowerCase().contains(_query) ||
              group.files.any(
                (file) =>
                    file.name.toLowerCase().contains(_query) ||
                    file.path.toLowerCase().contains(_query),
              );
        })
        .toList(growable: false);

    visible.sort((a, b) {
      return switch (_sort) {
        _DuplicateSort.recoverable => b.recoverableBytes.compareTo(
          a.recoverableBytes,
        ),
        _DuplicateSort.largest => b.sizeBytes.compareTo(a.sizeBytes),
        _DuplicateSort.smallest => a.sizeBytes.compareTo(b.sizeBytes),
        _DuplicateSort.files => b.files.length.compareTo(a.files.length),
        _DuplicateSort.newest => _latestModified(
          b,
        ).compareTo(_latestModified(a)),
        _DuplicateSort.oldest => _oldestModified(
          a,
        ).compareTo(_oldestModified(b)),
        _DuplicateSort.name => _primaryName(a).compareTo(_primaryName(b)),
      };
    });

    return visible;
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.groupCount,
    required this.fileCount,
    required this.wastedBytes,
    required this.selectedBytes,
    required this.onScanPressed,
  });

  final int groupCount;
  final int fileCount;
  final int wastedBytes;
  final int selectedBytes;
  final Future<void> Function() onScanPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SpaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: colorScheme.primaryContainer,
                foregroundColor: colorScheme.onPrimaryContainer,
                child: const Icon(Icons.file_copy_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Duplicate Cleaner',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh duplicate scan',
                onPressed: onScanPressed,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            _formatBytes(wastedBytes),
            style: textTheme.headlineMedium?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            'total wasted space across exact duplicate groups',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricChip(value: '$groupCount', label: 'groups'),
              _MetricChip(value: '$fileCount', label: 'files'),
              _MetricChip(
                value: _formatBytes(selectedBytes),
                label: 'selected',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.searchController,
    required this.selectedKind,
    required this.selectedSort,
    required this.onKindChanged,
    required this.onSortChanged,
    required this.onClear,
  });

  final TextEditingController searchController;
  final _DuplicateKind selectedKind;
  final _DuplicateSort selectedSort;
  final ValueChanged<_DuplicateKind> onKindChanged;
  final ValueChanged<_DuplicateSort> onSortChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SpaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Search name, folder, or hash',
              suffixIcon: searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: searchController.clear,
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<_DuplicateKind>(
              segments: [
                for (final kind in _DuplicateKind.values)
                  ButtonSegment(
                    value: kind,
                    icon: Icon(kind.icon),
                    label: Text(kind.label),
                  ),
              ],
              selected: {selectedKind},
              onSelectionChanged: (values) {
                if (values.isNotEmpty) onKindChanged(values.first);
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<_DuplicateSort>(
                  initialValue: selectedSort,
                  decoration: const InputDecoration(
                    labelText: 'Sort',
                    prefixIcon: Icon(Icons.sort_rounded),
                  ),
                  items: [
                    for (final sort in _DuplicateSort.values)
                      DropdownMenuItem(value: sort, child: Text(sort.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) onSortChanged(value);
                  },
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                tooltip: 'Clear filters',
                onPressed: onClear,
                icon: const Icon(Icons.filter_alt_off_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.visibleCount,
    required this.totalCount,
    required this.selectedCount,
    required this.onSmartSelect,
    required this.onClearSelection,
  });

  final int visibleCount;
  final int totalCount;
  final int selectedCount;
  final VoidCallback onSmartSelect;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '$visibleCount of $totalCount groups | $selectedCount selected',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        TextButton.icon(
          onPressed: visibleCount == 0 ? null : onSmartSelect,
          icon: const Icon(Icons.auto_fix_high_rounded),
          label: const Text('Smart select'),
        ),
        TextButton(
          onPressed: selectedCount == 0 ? null : onClearSelection,
          child: const Text('Clear'),
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
    required this.onFileDetails,
  });

  final int index;
  final DuplicateGroup group;
  final Set<String> selectedPaths;
  final void Function(DuplicateFile file, bool selected) onFileChanged;
  final ValueChanged<bool> onGroupChanged;
  final ValueChanged<DuplicateFile> onFileDetails;

  @override
  Widget build(BuildContext context) {
    final selectedCount = group.files
        .where((file) => selectedPaths.contains(file.path))
        .length;
    final allCleanableSelected = selectedCount == group.files.length - 1;
    final partial = selectedCount > 0 && !allCleanableSelected;
    final selectedBytes = group.files
        .where((file) => selectedPaths.contains(file.path))
        .fold<int>(0, (total, file) => total + file.sizeBytes);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: index == 0,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
          child: Icon(_kindForGroup(group).icon),
        ),
        title: Text(
          'Group ${index + 1}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${group.files.length} files | ${_formatBytes(group.recoverableBytes)} wasted | ${_formatBytes(selectedBytes)} selected',
        ),
        trailing: Checkbox(
          value: partial ? null : allCleanableSelected,
          tristate: partial,
          onChanged: (value) => onGroupChanged(value ?? false),
        ),
        children: [
          for (final file in group.files)
            _DuplicateFileTile(
              file: file,
              preserved: !selectedPaths.contains(file.path),
              selected: selectedPaths.contains(file.path),
              onChanged: (selected) => onFileChanged(file, selected),
              onDetails: () => onFileDetails(file),
            ),
        ],
      ),
    );
  }
}

class _DuplicateFileTile extends StatelessWidget {
  const _DuplicateFileTile({
    required this.file,
    required this.preserved,
    required this.selected,
    required this.onChanged,
    required this.onDetails,
  });

  final DuplicateFile file;
  final bool preserved;
  final bool selected;
  final ValueChanged<bool> onChanged;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final directory = _parentDirectory(file.path);

    return Material(
      color: selected
          ? colorScheme.errorContainer.withValues(alpha: 0.36)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChanged(!selected),
        onLongPress: onDetails,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: (value) => onChanged(value ?? false),
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
                        if (preserved)
                          _StatusPill(
                            label: 'KEEP',
                            color: colorScheme.tertiaryContainer,
                            foreground: colorScheme.onTertiaryContainer,
                          )
                        else
                          _StatusPill(
                            label: 'DELETE',
                            color: colorScheme.errorContainer,
                            foreground: colorScheme.onErrorContainer,
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$directory | ${_formatBytes(file.sizeBytes)} | ${_formatDate(file.lastModified)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Preview and details',
                onPressed: onDetails,
                icon: const Icon(Icons.visibility_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    required this.foreground,
  });

  final String label;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w900,
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
    required this.onSmartSelect,
    required this.onClearSelection,
    required this.onDelete,
  });

  final int count;
  final int bytes;
  final bool isDeleting;
  final VoidCallback onSmartSelect;
  final VoidCallback onClearSelection;
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
            Row(
              children: [
                Icon(Icons.check_circle_rounded, color: colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  _formatBytes(bytes),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Smart selection keeps one copy in every group. Nothing is deleted until you confirm.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSecondaryContainer.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: isDeleting ? null : onSmartSelect,
                  icon: const Icon(Icons.auto_fix_high_rounded),
                  label: const Text('Smart select'),
                ),
                OutlinedButton.icon(
                  onPressed: count == 0 || isDeleting ? null : onClearSelection,
                  icon: const Icon(Icons.clear_rounded),
                  label: const Text('Clear'),
                ),
                FilledButton.icon(
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
                      : const Icon(Icons.rule_folder_rounded),
                  label: Text(isDeleting ? 'Deleting...' : 'Review & delete'),
                ),
              ],
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
    return Center(
      child: Card(
        margin: const EdgeInsets.all(24),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 18),
              Text(
                'Analyzing exact copies',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              const Text('1. Grouping files by size'),
              const Text('2. Verifying matches with SHA-256'),
              const Text('3. Calculating safely recoverable space'),
              const SizedBox(height: 10),
              const Text(
                'You can leave this screen; analysis continues in the background.',
              ),
            ],
          ),
        ),
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

void _showFileDetails(
  BuildContext context,
  DuplicateFile file, {
  required DuplicateGroup group,
  required bool selected,
  required VoidCallback onToggleSelected,
  required Future<void> Function() onPreview,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final colorScheme = Theme.of(context).colorScheme;
      final kind = _kindForFile(file);

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: colorScheme.secondaryContainer,
                    foregroundColor: colorScheme.onSecondaryContainer,
                    child: Icon(kind.icon),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      file.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _DetailRow(
                label: 'Status',
                value: selected ? 'Selected for deletion' : 'Preserved',
              ),
              _DetailRow(
                label: 'Group copies',
                value: '${group.files.length} exact matches',
              ),
              _DetailRow(label: 'Size', value: _formatBytes(file.sizeBytes)),
              _DetailRow(label: 'Type', value: kind.label),
              _DetailRow(
                label: 'Modified',
                value: _formatDate(file.lastModified),
              ),
              _DetailRow(label: 'Folder', value: _parentDirectory(file.path)),
              _DetailRow(label: 'Path', value: file.path),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: onPreview,
                    icon: const Icon(Icons.visibility_rounded),
                    label: const Text('Preview'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onToggleSelected();
                    },
                    icon: Icon(
                      selected
                          ? Icons.bookmark_remove_rounded
                          : Icons.delete_outline_rounded,
                    ),
                    label: Text(selected ? 'Preserve' : 'Select'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(value),
        ],
      ),
    );
  }
}

DuplicateFile _keeperForGroup(DuplicateGroup group) {
  final files = group.files.toList(growable: false)
    ..sort((a, b) {
      final modified = b.lastModified.compareTo(a.lastModified);
      if (modified != 0) return modified;
      return a.path.length.compareTo(b.path.length);
    });
  return files.first;
}

DateTime _latestModified(DuplicateGroup group) {
  return group.files
      .map((file) => file.lastModified)
      .reduce((a, b) => a.isAfter(b) ? a : b);
}

DateTime _oldestModified(DuplicateGroup group) {
  return group.files
      .map((file) => file.lastModified)
      .reduce((a, b) => a.isBefore(b) ? a : b);
}

String _primaryName(DuplicateGroup group) {
  return group.files.first.name.toLowerCase();
}

bool _matchesKind(DuplicateGroup group, _DuplicateKind kind) {
  if (kind == _DuplicateKind.all) return true;
  return group.files.any((file) => _kindForFile(file) == kind);
}

_DuplicateKind _kindForGroup(DuplicateGroup group) {
  for (final kind in _DuplicateKind.values) {
    if (kind != _DuplicateKind.all && _matchesKind(group, kind)) return kind;
  }
  return _DuplicateKind.other;
}

_DuplicateKind _kindForFile(DuplicateFile file) {
  final extension = _extension(file.name);
  final normalizedPath = file.path.replaceAll('\\', '/').toLowerCase();

  if (_imageExtensions.contains(extension)) return _DuplicateKind.image;
  if (_videoExtensions.contains(extension)) return _DuplicateKind.video;
  if (_audioExtensions.contains(extension)) return _DuplicateKind.audio;
  if (_documentExtensions.contains(extension)) return _DuplicateKind.document;
  if (normalizedPath.contains('/download/')) return _DuplicateKind.download;
  return _DuplicateKind.other;
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
  if (error is TimeoutException) {
    return 'The storage scan timed out. Please try again.';
  }
  if (error is UnsupportedError) {
    return 'Duplicate scans require Android storage access.';
  }
  return 'The storage scan could not be completed. Please try again.';
}

String _fileActionError(Object error) {
  if (error is UnsupportedError) {
    return error.message ?? 'File preview is unsupported.';
  }
  if (error is PlatformException) {
    return switch (error.code) {
      'FILE_NOT_FOUND' => 'That file no longer exists.',
      'NO_HANDLER' => 'No installed app can preview this file.',
      _ => error.message ?? 'The file preview could not be opened.',
    };
  }
  return 'The file preview could not be opened.';
}

Future<bool?> _showDeleteConfirmation(
  BuildContext context, {
  required String title,
  required int fileCount,
  required int bytes,
  required List<DuplicateFile> files,
  required Future<void> Function(DuplicateFile file) onPreview,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      final colorScheme = Theme.of(context).colorScheme;

      return AlertDialog(
        icon: Icon(Icons.fact_check_rounded, color: colorScheme.error),
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Review the selected copies before deleting. SpacePilot will free '
                '${_formatBytes(bytes)} and preserve at least one copy from every group.',
              ),
              const SizedBox(height: 14),
              _DeleteReviewHeader(
                icon: Icons.delete_sweep_rounded,
                title: '$fileCount ${fileCount == 1 ? 'file' : 'files'} queued',
                subtitle: 'Permanent delete after confirmation',
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: files.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final file = files[index];
                    return _DeleteReviewFileTile(
                      name: file.name,
                      path: file.path,
                      meta:
                          '${_formatBytes(file.sizeBytes)} | ${_formatDate(file.lastModified)}',
                      icon: _kindForFile(file).icon,
                      onPreview: () => onPreview(file),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'This cannot be undone.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(false),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Keep reviewing'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            icon: const Icon(Icons.delete_forever_rounded),
            label: const Text('Delete files'),
          ),
        ],
      );
    },
  );
}

class _DeleteReviewHeader extends StatelessWidget {
  const _DeleteReviewHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
            child: Icon(icon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
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

class _DeleteReviewFileTile extends StatelessWidget {
  const _DeleteReviewFileTile({
    required this.name,
    required this.path,
    required this.meta,
    required this.icon,
    required this.onPreview,
  });

  final String name;
  final String path;
  final String meta;
  final IconData icon;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: colorScheme.secondaryContainer,
        foregroundColor: colorScheme.onSecondaryContainer,
        child: Icon(icon, size: 20),
      ),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '$meta\n$path',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton.filledTonal(
        tooltip: 'Preview file',
        onPressed: onPreview,
        icon: const Icon(Icons.visibility_rounded),
      ),
    );
  }
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

String _formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String _extension(String filename) {
  final dotIndex = filename.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == filename.length - 1) return '';
  return filename.substring(dotIndex + 1).toLowerCase();
}

const Set<String> _imageExtensions = {
  'gif',
  'heic',
  'jpeg',
  'jpg',
  'png',
  'raw',
  'webp',
};

const Set<String> _videoExtensions = {
  '3gp',
  'avi',
  'm4v',
  'mkv',
  'mov',
  'mp4',
  'webm',
};

const Set<String> _audioExtensions = {
  'aac',
  'flac',
  'm4a',
  'mp3',
  'ogg',
  'opus',
  'wav',
  'wma',
};

const Set<String> _documentExtensions = {
  'csv',
  'doc',
  'docx',
  'epub',
  'odp',
  'ods',
  'odt',
  'pdf',
  'ppt',
  'pptx',
  'rtf',
  'txt',
  'xls',
  'xlsx',
};

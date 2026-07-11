import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../routes/app_routes.dart';

import '../../../../shared/presentation/widgets/space_background.dart';
import '../../../cleanup/data/services/cleanup_service.dart';
import '../../../cleanup/presentation/providers/deletion_sync_provider.dart';
import '../../../cleanup/presentation/providers/cleanup_service_provider.dart';
import '../../../large_files/presentation/providers/large_file_hunter_provider.dart';
import '../../../storage/presentation/providers/storage_scan_provider.dart';
import '../../domain/models/models.dart';
import '../providers/duplicate_groups_provider.dart';

enum _SimilarImageSort {
  recoverable('Most reviewable'),
  confidence('Highest confidence'),
  count('Most images'),
  newest('Newest');

  const _SimilarImageSort(this.label);

  final String label;
}

class SimilarImagesPage extends ConsumerStatefulWidget {
  const SimilarImagesPage({super.key});

  @override
  ConsumerState<SimilarImagesPage> createState() => _SimilarImagesPageState();
}

class _SimilarImagesPageState extends ConsumerState<SimilarImagesPage> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedPaths = <String>{};
  final Set<String> _initializedGroups = <String>{};
  _SimilarImageSort _sort = _SimilarImageSort.recoverable;
  double _minimumConfidence = 80;
  bool _onlySelected = false;
  bool _isDeleting = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _runScan() async {
    try {
      await ref.read(storageScanProvider.notifier).scanIntelligence();
      ref.read(deletionSyncProvider).refreshDerivedState();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Storage scan could not be completed.')),
      );
    }
  }

  void _initializeSelections(List<SimilarImageGroup> groups) {
    for (final group in groups) {
      final key = _groupKey(group);
      if (!_initializedGroups.add(key)) continue;

      final keepPath = _defaultKeepPath(group);
      for (final file in group.files) {
        if (file.path != keepPath) _selectedPaths.add(file.path);
      }
    }
  }

  void _smartSelect(List<SimilarImageGroup> groups) {
    setState(() {
      _selectedPaths.clear();
      _initializedGroups
        ..clear()
        ..addAll(groups.map(_groupKey));
      for (final group in groups) {
        final keepPath = _defaultKeepPath(group);
        for (final file in group.files) {
          if (file.path != keepPath) _selectedPaths.add(file.path);
        }
      }
    });
  }

  void _clearSelection() {
    setState(_selectedPaths.clear);
  }

  void _togglePath(String path, bool selected) {
    setState(() {
      if (selected) {
        _selectedPaths.add(path);
      } else {
        _selectedPaths.remove(path);
      }
    });
  }

  Future<void> _openFile(SimilarImageFile file) async {
    try {
      await ref.read(largeFileActionServiceProvider).open(file.path);
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_fileActionError(error))));
    } on UnsupportedError {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image preview is Android-only.')),
      );
    }
  }

  Future<void> _deleteSelected(List<SimilarImageGroup> groups) async {
    if (_selectedPaths.isEmpty || _isDeleting) return;

    final visibleGroups = _visibleGroups(groups);
    final visiblePaths = {
      for (final group in visibleGroups)
        for (final file in group.files)
          if (_selectedPaths.contains(file.path)) file.path,
    };
    if (visiblePaths.isEmpty) return;

    if (visibleGroups.any(
      (group) => group.files.every((file) => visiblePaths.contains(file.path)),
    )) {
      _showKeepOneMessage();
      return;
    }

    final selectedFiles = [
      for (final group in visibleGroups)
        for (final file in group.files)
          if (visiblePaths.contains(file.path)) file,
    ];
    final selectedBytes = selectedFiles.fold<int>(
      0,
      (total, file) => total + file.sizeBytes,
    );

    final approved = await _confirmDelete(
      files: selectedFiles,
      bytes: selectedBytes,
    );
    if (approved != true || !mounted) return;

    setState(() => _isDeleting = true);
    final CleanupResult result;
    try {
      result = await ref
          .read(cleanupServiceProvider)
          .deleteFiles(
            selectedFiles.map((file) => File(file.path)),
            userConfirmed: true,
          );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected images could not be deleted.')),
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

  Future<bool?> _confirmDelete({
    required List<SimilarImageFile> files,
    required int bytes,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        final fileCount = files.length;

        return AlertDialog(
          icon: Icon(Icons.photo_library_rounded, color: colorScheme.error),
          title: const Text('Delete selected similar images?'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Review each image before deleting. SpacePilot will free about '
                  '${_formatBytes(bytes)} and keep at least one image from every group.',
                ),
                const SizedBox(height: 14),
                _DeleteReviewHeader(
                  count: fileCount,
                  bytes: bytes,
                  color: colorScheme.error,
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: files.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final file = files[index];
                      return _ImageReviewTile(
                        file: file,
                        onOpen: () => _openFile(file),
                      );
                    },
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
              label: const Text('Delete images'),
            ),
          ],
        );
      },
    );
  }

  List<SimilarImageGroup> _visibleGroups(List<SimilarImageGroup> groups) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = groups
        .where((group) {
          if (group.strongestSimilarityScore < _minimumConfidence) return false;
          if (_onlySelected &&
              !group.files.any((file) => _selectedPaths.contains(file.path))) {
            return false;
          }
          if (query.isEmpty) return true;
          return group.files.any((file) {
            return file.name.toLowerCase().contains(query) ||
                file.path.toLowerCase().contains(query);
          });
        })
        .toList(growable: false);

    return filtered..sort(
      (a, b) => switch (_sort) {
        _SimilarImageSort.recoverable => b.recoverableBytes.compareTo(
          a.recoverableBytes,
        ),
        _SimilarImageSort.confidence => b.strongestSimilarityScore.compareTo(
          a.strongestSimilarityScore,
        ),
        _SimilarImageSort.count => b.imageCount.compareTo(a.imageCount),
        _SimilarImageSort.newest => _newestIn(b).compareTo(_newestIn(a)),
      },
    );
  }

  void _showKeepOneMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Keep at least one image from each group.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scan = ref.watch(storageScanProvider);
    final groups = ref.watch(similarImageGroupsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Similar Images'),
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
              selected: const {1},
              onSelectionChanged: (_) =>
                  context.pushReplacementNamed(AppRouteNames.duplicates),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh similar image scan',
            onPressed: scan.isLoading ? null : _runScan,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SpaceBackground(
        child: SafeArea(
          child: groups.when(
            loading: () => const _LoadingState(),
            error: (_, _) => _EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Similar image analysis unavailable',
              message: 'Run Smart Scan again to refresh image similarity data.',
              actionLabel: 'Run scan',
              onAction: _runScan,
            ),
            data: (items) {
              if (scan.value?.hasScanned != true) {
                return _EmptyState(
                  icon: Icons.image_search_rounded,
                  title: 'Scan to compare images',
                  message:
                      'SpacePilot compares images locally with perceptual hashing.',
                  actionLabel: 'Run scan',
                  onAction: _runScan,
                );
              }

              _initializeSelections(items);
              final visibleGroups = _visibleGroups(items);
              final selectedBytes = visibleGroups.fold<int>(
                0,
                (total, group) =>
                    total +
                    group.files
                        .where((file) => _selectedPaths.contains(file.path))
                        .fold<int>(0, (sum, file) => sum + file.sizeBytes),
              );
              final selectedCount = visibleGroups.fold<int>(
                0,
                (total, group) =>
                    total +
                    group.files
                        .where((file) => _selectedPaths.contains(file.path))
                        .length,
              );
              final recoverable = items.fold<int>(
                0,
                (total, group) => total + group.recoverableBytes,
              );

              return SpacePageList(
                children: [
                  _SummaryCard(
                    groupCount: items.length,
                    visibleCount: visibleGroups.length,
                    recoverableBytes: recoverable,
                    selectedCount: selectedCount,
                    selectedBytes: selectedBytes,
                    isDeleting: _isDeleting,
                    onSmartSelect: () => _smartSelect(visibleGroups),
                    onClear: _clearSelection,
                    onDelete: () => _deleteSelected(items),
                  ),
                  const SizedBox(height: 12),
                  _ControlsCard(
                    searchController: _searchController,
                    sort: _sort,
                    minimumConfidence: _minimumConfidence,
                    onlySelected: _onlySelected,
                    onChanged: () => setState(() {}),
                    onSortChanged: (sort) => setState(() => _sort = sort),
                    onConfidenceChanged: (value) =>
                        setState(() => _minimumConfidence = value),
                    onOnlySelectedChanged: (value) =>
                        setState(() => _onlySelected = value),
                  ),
                  const SizedBox(height: 12),
                  if (items.isEmpty)
                    const _EmptyPanel(
                      icon: Icons.verified_rounded,
                      title: 'No similar images found',
                      message:
                          'Your scanned image folders do not have close visual matches.',
                    )
                  else if (visibleGroups.isEmpty)
                    const _EmptyPanel(
                      icon: Icons.filter_alt_off_rounded,
                      title: 'No groups match these filters',
                      message:
                          'Try a lower confidence threshold or clear the search.',
                    )
                  else
                    for (var index = 0; index < visibleGroups.length; index++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _SimilarGroupCard(
                          index: index,
                          group: visibleGroups[index],
                          selectedPaths: _selectedPaths,
                          onToggle: _togglePath,
                          onOpen: _openFile,
                        ),
                      ),
                ],
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
    required this.visibleCount,
    required this.recoverableBytes,
    required this.selectedCount,
    required this.selectedBytes,
    required this.isDeleting,
    required this.onSmartSelect,
    required this.onClear,
    required this.onDelete,
  });

  final int groupCount;
  final int visibleCount;
  final int recoverableBytes;
  final int selectedCount;
  final int selectedBytes;
  final bool isDeleting;
  final VoidCallback onSmartSelect;
  final VoidCallback onClear;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SpaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatBytes(recoverableBytes),
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$visibleCount of $groupCount groups | '
                      '$selectedCount selected (${_formatBytes(selectedBytes)})',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isDeleting)
                const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onSmartSelect,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('Smart select'),
              ),
              TextButton.icon(
                onPressed: selectedCount == 0 ? null : onClear,
                icon: const Icon(Icons.clear_rounded),
                label: const Text('Clear'),
              ),
              FilledButton.icon(
                onPressed: selectedCount == 0 || isDeleting ? null : onDelete,
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                icon: const Icon(Icons.rule_folder_rounded),
                label: const Text('Review & delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeleteReviewHeader extends StatelessWidget {
  const _DeleteReviewHeader({
    required this.count,
    required this.bytes,
    required this.color,
  });

  final int count;
  final int bytes;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color,
            foregroundColor: colorScheme.onError,
            child: const Icon(Icons.delete_sweep_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$count ${count == 1 ? 'image' : 'images'} queued | ${_formatBytes(bytes)}',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageReviewTile extends StatelessWidget {
  const _ImageReviewTile({required this.file, required this.onOpen});

  final SimilarImageFile file;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: _ImagePreview(path: file.path),
      title: Text(
        file.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${_formatBytes(file.sizeBytes)} | ${_formatDate(file.lastModified)}\n'
        '${file.path}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton.filledTonal(
        tooltip: 'Preview image',
        onPressed: onOpen,
        icon: const Icon(Icons.visibility_rounded),
      ),
    );
  }
}

class _ControlsCard extends StatelessWidget {
  const _ControlsCard({
    required this.searchController,
    required this.sort,
    required this.minimumConfidence,
    required this.onlySelected,
    required this.onChanged,
    required this.onSortChanged,
    required this.onConfidenceChanged,
    required this.onOnlySelectedChanged,
  });

  final TextEditingController searchController;
  final _SimilarImageSort sort;
  final double minimumConfidence;
  final bool onlySelected;
  final VoidCallback onChanged;
  final ValueChanged<_SimilarImageSort> onSortChanged;
  final ValueChanged<double> onConfidenceChanged;
  final ValueChanged<bool> onOnlySelectedChanged;

  @override
  Widget build(BuildContext context) {
    return SpaceCard(
      child: Column(
        children: [
          TextField(
            controller: searchController,
            onChanged: (_) => onChanged(),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              labelText: 'Search images',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<_SimilarImageSort>(
                  initialValue: sort,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.sort_rounded),
                    labelText: 'Sort',
                  ),
                  items: [
                    for (final value in _SimilarImageSort.values)
                      DropdownMenuItem(value: value, child: Text(value.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) onSortChanged(value);
                  },
                ),
              ),
              const SizedBox(width: 12),
              FilterChip(
                selected: onlySelected,
                onSelected: onOnlySelectedChanged,
                label: const Text('Selected'),
                avatar: const Icon(Icons.checklist_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '${minimumConfidence.round()}%+ confidence',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              Expanded(
                child: Slider(
                  value: minimumConfidence,
                  min: 70,
                  max: 100,
                  divisions: 6,
                  label: '${minimumConfidence.round()}%',
                  onChanged: onConfidenceChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SimilarGroupCard extends StatelessWidget {
  const _SimilarGroupCard({
    required this.index,
    required this.group,
    required this.selectedPaths,
    required this.onToggle,
    required this.onOpen,
  });

  final int index;
  final SimilarImageGroup group;
  final Set<String> selectedPaths;
  final void Function(String path, bool selected) onToggle;
  final ValueChanged<SimilarImageFile> onOpen;

  @override
  Widget build(BuildContext context) {
    final selectedInGroup = group.files
        .where((file) => selectedPaths.contains(file.path))
        .length;

    return SpaceCard(
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        initiallyExpanded: index < 2,
        leading: const Icon(Icons.image_search_rounded),
        title: Text('Group ${index + 1}'),
        subtitle: Text(
          '${group.imageCount} images | '
          '${group.strongestSimilarityScore.toStringAsFixed(0)}% strongest | '
          '$selectedInGroup selected',
        ),
        children: [
          const SizedBox(height: 6),
          for (final file in group.files)
            _SimilarImageTile(
              file: file,
              selected: selectedPaths.contains(file.path),
              keep: !selectedPaths.contains(file.path),
              onChanged: (selected) => onToggle(file.path, selected),
              onOpen: () => onOpen(file),
            ),
        ],
      ),
    );
  }
}

class _SimilarImageTile extends StatelessWidget {
  const _SimilarImageTile({
    required this.file,
    required this.selected,
    required this.keep,
    required this.onChanged,
    required this.onOpen,
  });

  final SimilarImageFile file;
  final bool selected;
  final bool keep;
  final ValueChanged<bool> onChanged;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: selected,
            onChanged: (value) => onChanged(value ?? false),
          ),
          _ImagePreview(path: file.path),
        ],
      ),
      title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${_formatBytes(file.sizeBytes)} | ${_formatDate(file.lastModified)}\n'
        '${keep ? 'KEEP' : 'Review for cleanup'} | ${file.path}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: 'Open image',
        onPressed: onOpen,
        icon: Icon(Icons.open_in_new_rounded, color: colorScheme.primary),
      ),
      selected: selected,
      selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.22),
      onTap: () => onChanged(!selected),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox.square(
          dimension: 52,
          child: Image.file(
            File(path),
            fit: BoxFit.cover,
            cacheWidth: 128,
            errorBuilder: (_, _, _) => const _ImageFallback(),
          ),
        ),
      );
    }

    return const _ImageFallback();
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.image_rounded,
          color: colorScheme.onSecondaryContainer,
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
                'Analyzing similar images',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              const Text('1. Finding supported photos'),
              const Text('2. Comparing visual fingerprints locally'),
              const Text('3. Ranking groups by confidence and space'),
              const SizedBox(height: 10),
              const Text(
                'You can switch to Exact copies while this continues.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return SpaceCard(
      child: Column(
        children: [
          Icon(icon, size: 42, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            message,
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

String _groupKey(SimilarImageGroup group) {
  return group.files.map((file) => file.path).join('|');
}

String _defaultKeepPath(SimilarImageGroup group) {
  final files = group.files.toList(growable: false)
    ..sort((a, b) {
      final size = b.sizeBytes.compareTo(a.sizeBytes);
      if (size != 0) return size;
      return b.lastModified.compareTo(a.lastModified);
    });
  return files.first.path;
}

DateTime _newestIn(SimilarImageGroup group) {
  return group.files
      .map((file) => file.lastModified)
      .reduce((a, b) => a.isAfter(b) ? a : b);
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
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

String _cleanupMessage(CleanupResult result) {
  if (result.deletedCount == 0 && result.hasFailures) {
    return 'No images were deleted. ${result.failures.values.first}';
  }
  if (result.hasFailures) {
    return '${result.deletedCount} deleted. ${result.failures.length} could not be deleted.';
  }
  if (result.deletedCount == 0) return 'No selected images needed deletion.';
  return '${result.deletedCount} selected ${result.deletedCount == 1 ? 'image' : 'images'} deleted.';
}

String _fileActionError(PlatformException error) {
  return switch (error.code) {
    'FILE_NOT_FOUND' => 'Image was not found.',
    'NO_HANDLER' => 'No installed app can preview this image.',
    _ => 'Image could not be opened.',
  };
}

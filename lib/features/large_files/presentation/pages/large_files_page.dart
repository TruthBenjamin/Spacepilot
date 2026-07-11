import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../cleanup/data/services/cleanup_service.dart';
import '../../../cleanup/presentation/providers/deletion_sync_provider.dart';
import '../../../cleanup/presentation/providers/cleanup_service_provider.dart';
import '../../data/services/large_file_action_service.dart';
import '../../../../shared/presentation/widgets/space_background.dart';
import '../../../storage/domain/models/scanned_file.dart';
import '../../../storage/presentation/providers/storage_scan_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../../routes/app_navigation.dart';
import '../providers/large_file_hunter_provider.dart';

enum _LargeFileSort {
  largest('Largest first'),
  smallest('Smallest first'),
  newest('Newest first'),
  oldest('Oldest first'),
  name('Name A-Z');

  const _LargeFileSort(this.label);

  final String label;
}

enum _LargeFileKind {
  all('All', Icons.all_inbox_rounded),
  video('Videos', Icons.movie_filter_rounded),
  image('Images', Icons.image_rounded),
  audio('Audio', Icons.audio_file_rounded),
  document('Documents', Icons.description_rounded),
  apk('APKs', Icons.android_rounded),
  zip('ZIP files', Icons.archive_rounded),
  archive('Archives', Icons.folder_zip_rounded),
  download('Downloads', Icons.download_rounded),
  other('Other', Icons.insert_drive_file_outlined);

  const _LargeFileKind(this.label, this.icon);

  final String label;
  final IconData icon;
}

class LargeFilesPage extends ConsumerStatefulWidget {
  const LargeFilesPage({super.key});

  @override
  ConsumerState<LargeFilesPage> createState() => _LargeFilesPageState();
}

class _LargeFilesPageState extends ConsumerState<LargeFilesPage> {
  final ValueNotifier<Set<String>> _selectedPaths = ValueNotifier(<String>{});
  final TextEditingController _searchController = TextEditingController();
  final List<_CleanupHistoryEntry> _history = [];
  Timer? _searchDebounce;
  List<ScannedFile>? _cachedSourceFiles;
  List<ScannedFile>? _cachedVisibleFiles;
  _LargeFileSort? _cachedSort;
  _LargeFileKind? _cachedKind;
  String? _cachedQuery;
  _LargeFileSort _sort = _LargeFileSort.largest;
  _LargeFileKind _kind = _LargeFileKind.all;
  String _query = '';
  bool _isDeleting = false;
  int _visiblePages = 1;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        final query = _searchController.text.trim().toLowerCase();
        if (query == _query) return;
        setState(() {
          _query = query;
          _visiblePages = 1;
        });
      });
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _selectedPaths.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scanState = ref.watch(storageScanProvider);
    final threshold = ref.watch(largeFileThresholdProvider);
    final largeFiles = ref.watch(largeFileHunterProvider);
    final fileActions = ref.watch(largeFileActionServiceProvider);

    Future<void> runScan() async {
      try {
        await ref.read(storageScanProvider.notifier).scan();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Large file scan completed.')),
        );
      } catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_scanErrorMessage(error))));
      }
    }

    Future<void> deleteSelected(List<ScannedFile> files) async {
      final selectedPaths = _selectedPaths.value;
      if (selectedPaths.isEmpty || _isDeleting) return;

      final selectedFiles = files
          .where((file) => selectedPaths.contains(file.path))
          .toList(growable: false);
      if (selectedFiles.isEmpty) return;

      final selectedBytes = selectedFiles.fold<int>(
        0,
        (total, file) => total + file.size,
      );

      final approved = await _showDeleteConfirmation(
        context,
        title: 'Delete selected large files?',
        fileCount: selectedFiles.length,
        bytes: selectedBytes,
      );
      if (approved != true || !context.mounted) return;

      setState(() => _isDeleting = true);
      final CleanupResult result;
      try {
        result = await ref
            .read(cleanupServiceProvider)
            .deleteFiles(
              selectedFiles.map((file) => File(file.path)),
              userConfirmed: true,
            );
      } catch (error) {
        if (!context.mounted) return;
        setState(() => _isDeleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selected files could not be deleted.')),
        );
        return;
      }
      if (!context.mounted) return;

      ref.read(deletionSyncProvider).applyDeletedPaths(result.deletedPaths);
      setState(() {
        _isDeleting = false;
        _history.insert(
          0,
          _CleanupHistoryEntry(
            deletedCount: result.deletedCount,
            failedCount: result.failures.length,
            selectedBytes: selectedBytes,
            completedAt: DateTime.now(),
          ),
        );
      });
      _removeSelectedPaths(result.deletedPaths);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_cleanupMessage(result))));
    }

    Future<void> openFile(ScannedFile file) async {
      try {
        await fileActions.open(file.path);
      } catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_fileActionError(error))));
      }
    }

    Future<void> shareFile(ScannedFile file) async {
      try {
        await fileActions.share(file.path);
      } catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_fileActionError(error))));
      }
    }

    Future<void> moveFile(ScannedFile file) async {
      final destination = await _showMoveDestinationPicker(context);
      if (destination == null || !context.mounted) return;

      try {
        final result = await fileActions.move(
          path: file.path,
          destination: destination,
        );
        ref
            .read(storageScanProvider.notifier)
            .moveFilePath(
              fromPath: file.path,
              toPath: result.path,
              filename: result.filename,
            );
        _removeSelectedPaths([file.path]);
        if (!context.mounted) return;
        Navigator.of(context).maybePop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Moved ${result.filename} to ${destination.label}.'),
          ),
        );
      } catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_fileActionError(error))));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: const [
            Icon(Icons.rocket_launch_rounded, size: 20),
            SizedBox(width: 10),
            Text('Large File Hunter'),
          ],
        ),
        centerTitle: false,
      ),
      body: SpaceBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const pagePadding = EdgeInsets.fromLTRB(20, 12, 20, 28);
              const maxWidth = 1040.0;
              final extraWidth = (constraints.maxWidth - maxWidth)
                  .clamp(0, double.infinity)
                  .toDouble();
              final sideInset = extraWidth / 2;
              final resultPadding = EdgeInsets.fromLTRB(
                pagePadding.left + sideInset,
                0,
                pagePadding.right + sideInset,
                pagePadding.bottom,
              );

              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      pagePadding.left + sideInset,
                      pagePadding.top,
                      pagePadding.right + sideInset,
                      0,
                    ),
                    sliver: SliverList.list(
                      children: [
                        _HeaderCard(
                          isLoading: scanState.isLoading,
                          onScanPressed: runScan,
                          onOpenScanner: () => context.pushScanResults(),
                        ),
                        const SizedBox(height: 18),
                        _ThresholdPicker(selected: threshold),
                        const SizedBox(height: 18),
                      ],
                    ),
                  ),
                  scanState.when(
                    data: (state) {
                      if (!state.hasScanned) {
                        return SliverPadding(
                          padding: resultPadding,
                          sliver: const SliverToBoxAdapter(
                            child: _EmptyState(
                              icon: Icons.radar_rounded,
                              title: 'Run a scan to find large files',
                              message:
                                  'SpacePilot will inspect Downloads, DCIM, Movies, and Pictures.',
                            ),
                          ),
                        );
                      }

                      return largeFiles.when(
                        data: (files) {
                          final visibleFiles = _visibleFiles(files);
                          final visibleLimit =
                              (_visiblePages * largeFilePageSize)
                                  .clamp(0, visibleFiles.length)
                                  .toInt();
                          final pagedFiles = visibleFiles
                              .take(visibleLimit)
                              .toList(growable: false);
                          return _LargeFileSliverList(
                            files: pagedFiles,
                            totalFiles: files.length,
                            matchingFiles: visibleFiles.length,
                            threshold: threshold,
                            selectedPaths: _selectedPaths,
                            isDeleting: _isDeleting,
                            padding: resultPadding,
                            selectedSourceFiles: visibleFiles,
                            onFileChanged: _setFileSelected,
                            onSelectVisible: () =>
                                _selectVisibleFiles(pagedFiles),
                            onClearSelection: _clearSelection,
                            onFileDetails: (file) => _showFileDetails(
                              context,
                              file,
                              actionsSupported: fileActions.isSupported,
                              onOpen: () => openFile(file),
                              onShare: () => shareFile(file),
                              onMove: () => moveFile(file),
                            ),
                            onDeleteSelected: () =>
                                deleteSelected(visibleFiles),
                            history: _history,
                            stats: _LargeFileStats(files: files),
                            filters: _FilterPanel(
                              searchController: _searchController,
                              selectedKind: _kind,
                              selectedSort: _sort,
                              onKindChanged: (kind) => setState(() {
                                _kind = kind;
                                _visiblePages = 1;
                              }),
                              onSortChanged: (sort) => setState(() {
                                _sort = sort;
                                _visiblePages = 1;
                              }),
                              onClear: () {
                                _searchController.clear();
                                setState(() {
                                  _kind = _LargeFileKind.all;
                                  _sort = _LargeFileSort.largest;
                                  _visiblePages = 1;
                                });
                              },
                            ),
                            onClearFilters: () {
                              _searchController.clear();
                              setState(() {
                                _kind = _LargeFileKind.all;
                                _sort = _LargeFileSort.largest;
                                _visiblePages = 1;
                              });
                            },
                            hasMore: pagedFiles.length < visibleFiles.length,
                            onLoadMore: () =>
                                setState(() => _visiblePages += 1),
                          );
                        },
                        error: (error, _) => SliverPadding(
                          padding: resultPadding,
                          sliver: SliverToBoxAdapter(
                            child: _ErrorState(
                              message: _scanErrorMessage(error),
                            ),
                          ),
                        ),
                        loading: () => SliverPadding(
                          padding: resultPadding,
                          sliver: const SliverToBoxAdapter(
                            child: _LoadingState(),
                          ),
                        ),
                      );
                    },
                    error: (error, _) => SliverPadding(
                      padding: resultPadding,
                      sliver: SliverToBoxAdapter(
                        child: _ErrorState(message: _scanErrorMessage(error)),
                      ),
                    ),
                    loading: () => SliverPadding(
                      padding: resultPadding,
                      sliver: const SliverToBoxAdapter(child: _LoadingState()),
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

  void _setFileSelected(String path, bool selected) {
    final updated = Set<String>.of(_selectedPaths.value);
    selected ? updated.add(path) : updated.remove(path);
    _selectedPaths.value = updated;
  }

  void _selectVisibleFiles(List<ScannedFile> files) {
    if (files.isEmpty) return;
    final updated = Set<String>.of(_selectedPaths.value)
      ..addAll(files.map((file) => file.path));
    _selectedPaths.value = updated;
  }

  void _clearSelection() {
    if (_selectedPaths.value.isEmpty) return;
    _selectedPaths.value = <String>{};
  }

  void _removeSelectedPaths(Iterable<String> paths) {
    final updated = Set<String>.of(_selectedPaths.value)..removeAll(paths);
    _selectedPaths.value = updated;
  }

  List<ScannedFile> _visibleFiles(List<ScannedFile> files) {
    if (identical(files, _cachedSourceFiles) &&
        _sort == _cachedSort &&
        _kind == _cachedKind &&
        _query == _cachedQuery) {
      return _cachedVisibleFiles!;
    }

    final visible = files
        .where((file) {
          if (!_matchesKind(file, _kind)) return false;
          if (_query.isEmpty) return true;
          return file.filename.toLowerCase().contains(_query) ||
              file.path.toLowerCase().contains(_query);
        })
        .toList(growable: false);

    visible.sort((a, b) {
      return switch (_sort) {
        _LargeFileSort.largest => b.size.compareTo(a.size),
        _LargeFileSort.smallest => a.size.compareTo(b.size),
        _LargeFileSort.newest => b.lastModified.compareTo(a.lastModified),
        _LargeFileSort.oldest => a.lastModified.compareTo(b.lastModified),
        _LargeFileSort.name => a.filename.toLowerCase().compareTo(
          b.filename.toLowerCase(),
        ),
      };
    });

    _cachedSourceFiles = files;
    _cachedSort = _sort;
    _cachedKind = _kind;
    _cachedQuery = _query;
    _cachedVisibleFiles = visible;
    return visible;
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.isLoading,
    required this.onScanPressed,
    required this.onOpenScanner,
  });

  final bool isLoading;
  final Future<void> Function() onScanPressed;
  final VoidCallback onOpenScanner;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SpaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.rocket_launch_rounded,
            color: colorScheme.primary,
            size: 32,
          ),
          const SizedBox(height: 14),
          Text(
            'Launch a smart storage sweep',
            style: textTheme.headlineSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'SpacePilot scans your device orbit and surfaces the biggest storage hogs first.',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: isLoading ? null : onScanPressed,
                icon: isLoading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.3),
                      )
                    : const Icon(Icons.rocket_launch_rounded),
                label: Text(isLoading ? 'Scanning...' : 'Launch scan'),
              ),
              OutlinedButton.icon(
                onPressed: onOpenScanner,
                icon: const Icon(Icons.stacked_line_chart_rounded),
                label: const Text('Open cockpit'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThresholdPicker extends ConsumerWidget {
  const _ThresholdPicker({required this.selected});

  final LargeFileThreshold selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Detect files larger than',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<LargeFileThreshold>(
              segments: [
                for (final threshold in LargeFileThreshold.values)
                  ButtonSegment(value: threshold, label: Text(threshold.label)),
              ],
              selected: {selected},
              onSelectionChanged: (values) {
                if (values.isEmpty) return;
                ref.read(largeFileThresholdProvider.notifier).state =
                    values.first;
                ref
                    .read(appSettingsProvider.notifier)
                    .setLargeFileThresholdBytes(values.first.bytes);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _LargeFileStats extends StatelessWidget {
  const _LargeFileStats({required this.files});

  final List<ScannedFile> files;

  @override
  Widget build(BuildContext context) {
    final totalBytes = files.fold<int>(0, (total, file) => total + file.size);
    final largestBytes = files.isEmpty
        ? 0
        : files.map((file) => file.size).reduce((a, b) => a > b ? a : b);
    final videoCount = files
        .where((file) => _matchesKind(file, _LargeFileKind.video))
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 700 ? 4 : 2;
        final spacing = 10.0;
        final cardWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;
        final cardHeight = constraints.maxWidth >= 700 ? 106.0 : 116.0;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              width: cardWidth,
              height: cardHeight,
              child: _StatCard(
                icon: Icons.storage_rounded,
                label: 'Reviewable',
                value: _formatBytes(totalBytes),
              ),
            ),
            SizedBox(
              width: cardWidth,
              height: cardHeight,
              child: _StatCard(
                icon: Icons.vertical_align_top_rounded,
                label: 'Largest',
                value: _formatBytes(largestBytes),
              ),
            ),
            SizedBox(
              width: cardWidth,
              height: cardHeight,
              child: _StatCard(
                icon: Icons.folder_special_rounded,
                label: 'Files',
                value: '${files.length}',
              ),
            ),
            SizedBox(
              width: cardWidth,
              height: cardHeight,
              child: _StatCard(
                icon: Icons.movie_filter_rounded,
                label: 'Videos',
                value: '$videoCount',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: colorScheme.primary),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
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
  final _LargeFileKind selectedKind;
  final _LargeFileSort selectedSort;
  final ValueChanged<_LargeFileKind> onKindChanged;
  final ValueChanged<_LargeFileSort> onSortChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Search filename or path',
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kind in _LargeFileKind.values)
                  FilterChip(
                    avatar: Icon(kind.icon, size: 18),
                    label: Text(kind.label),
                    selected: selectedKind == kind,
                    onSelected: (_) => onKindChanged(kind),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<_LargeFileSort>(
                    initialValue: selectedSort,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.sort_rounded),
                      labelText: 'Sort',
                    ),
                    items: [
                      for (final sort in _LargeFileSort.values)
                        DropdownMenuItem(value: sort, child: Text(sort.label)),
                    ],
                    onChanged: (sort) {
                      if (sort != null) onSortChanged(sort);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: 'Reset filters',
                  onPressed: onClear,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LargeFileSliverList extends StatelessWidget {
  const _LargeFileSliverList({
    required this.files,
    required this.totalFiles,
    required this.matchingFiles,
    required this.threshold,
    required this.selectedPaths,
    required this.isDeleting,
    required this.padding,
    required this.selectedSourceFiles,
    required this.onFileChanged,
    required this.onSelectVisible,
    required this.onClearSelection,
    required this.onFileDetails,
    required this.onDeleteSelected,
    required this.history,
    required this.stats,
    required this.filters,
    required this.onClearFilters,
    required this.hasMore,
    required this.onLoadMore,
  });

  final List<ScannedFile> files;
  final int totalFiles;
  final int matchingFiles;
  final LargeFileThreshold threshold;
  final ValueListenable<Set<String>> selectedPaths;
  final bool isDeleting;
  final EdgeInsets padding;
  final List<ScannedFile> selectedSourceFiles;
  final void Function(String path, bool selected) onFileChanged;
  final VoidCallback onSelectVisible;
  final VoidCallback onClearSelection;
  final ValueChanged<ScannedFile> onFileDetails;
  final VoidCallback onDeleteSelected;
  final List<_CleanupHistoryEntry> history;
  final Widget stats;
  final Widget filters;
  final VoidCallback onClearFilters;
  final bool hasMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (totalFiles == 0) {
      return SliverPadding(
        padding: padding,
        sliver: SliverToBoxAdapter(
          child: _EmptyState(
            icon: Icons.check_circle_outline_rounded,
            title: 'No files over ${threshold.label}',
            message:
                'Try a smaller threshold or scan again after new files are added.',
          ),
        ),
      );
    }

    if (matchingFiles == 0) {
      return SliverPadding(
        padding: padding,
        sliver: SliverToBoxAdapter(
          child: _EmptyState(
            icon: Icons.filter_alt_off_rounded,
            title: 'No matching large files',
            message: 'Adjust search, filters, sorting, or the size threshold.',
            actionLabel: 'Clear filters',
            onAction: onClearFilters,
          ),
        ),
      );
    }

    return ValueListenableBuilder<Set<String>>(
      valueListenable: selectedPaths,
      builder: (context, selectedPaths, _) {
        var selectedBytes = 0;
        var selectedCount = 0;
        for (final file in selectedSourceFiles) {
          if (!selectedPaths.contains(file.path)) continue;
          selectedBytes += file.size;
          selectedCount++;
        }

        return SliverPadding(
          padding: padding,
          sliver: SliverList.builder(
            itemCount: files.length + (hasMore ? 9 : 8),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        totalFiles == matchingFiles
                            ? '$matchingFiles files found'
                            : '$matchingFiles of $totalFiles files found',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      '$selectedCount selected',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                );
              }

              if (index == 1) return const SizedBox(height: 10);

              final fileIndex = index - 2;
              if (hasMore && fileIndex == files.length) {
                return _LoadMoreLargeFilesCard(
                  visibleCount: files.length,
                  totalCount: matchingFiles,
                  onLoadMore: onLoadMore,
                );
              }

              final footerIndex = fileIndex - (hasMore ? 1 : 0);
              if (footerIndex == files.length) {
                return _SelectionToolbar(
                  visibleCount: files.length,
                  matchingCount: matchingFiles,
                  selectedCount: selectedCount,
                  selectedBytes: selectedBytes,
                  onSelectVisible: onSelectVisible,
                  onClearSelection: onClearSelection,
                );
              }
              if (footerIndex == files.length + 1) {
                return Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 10),
                  child: _LargeFileBriefingCard(files: files),
                );
              }
              if (footerIndex == files.length + 2) {
                return _DeleteSelectionCard(
                  selectedCount: selectedCount,
                  selectedBytes: selectedBytes,
                  isDeleting: isDeleting,
                  onDelete: onDeleteSelected,
                );
              }
              if (footerIndex == files.length + 3) {
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _CleanupHistoryCard(history: history),
                );
              }
              if (footerIndex == files.length + 4) {
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: filters,
                );
              }
              if (footerIndex == files.length + 5) {
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: stats,
                );
              }
              if (footerIndex >= files.length) {
                return const SizedBox.shrink();
              }

              final file = files[fileIndex];
              return _LargeFileCard(
                key: ValueKey(file.path),
                file: file,
                selected: selectedPaths.contains(file.path),
                onChanged: (selected) => onFileChanged(file.path, selected),
                onDetails: () => onFileDetails(file),
              );
            },
          ),
        );
      },
    );
  }
}

class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({
    required this.visibleCount,
    required this.matchingCount,
    required this.selectedCount,
    required this.selectedBytes,
    required this.onSelectVisible,
    required this.onClearSelection,
  });

  final int visibleCount;
  final int matchingCount;
  final int selectedCount;
  final int selectedBytes;
  final VoidCallback onSelectVisible;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final allVisibleSelected = selectedCount >= visibleCount;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.64),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Chip(
              avatar: const Icon(Icons.fact_check_rounded, size: 18),
              label: Text(
                selectedCount == 0
                    ? '$visibleCount ready to review'
                    : '${_formatBytes(selectedBytes)} selected',
              ),
            ),
            OutlinedButton.icon(
              onPressed: allVisibleSelected ? null : onSelectVisible,
              icon: const Icon(Icons.select_all_rounded),
              label: Text(
                visibleCount == matchingCount
                    ? 'Select all'
                    : 'Select visible $visibleCount',
              ),
            ),
            TextButton.icon(
              onPressed: selectedCount == 0 ? null : onClearSelection,
              icon: const Icon(Icons.remove_done_rounded),
              label: const Text('Clear'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LargeFileBriefingCard extends StatelessWidget {
  const _LargeFileBriefingCard({required this.files});

  final List<ScannedFile> files;

  @override
  Widget build(BuildContext context) {
    final totalBytes = files.fold<int>(0, (total, file) => total + file.size);
    final largestFile = files.reduce((a, b) => a.size >= b.size ? a : b);
    final newestFile = files.reduce(
      (a, b) => a.lastModified.isAfter(b.lastModified) ? a : b,
    );
    final videos = files.where((file) {
      return _matchesKind(file, _LargeFileKind.video);
    }).length;
    final downloads = files.where((file) {
      return _matchesKind(file, _LargeFileKind.download);
    }).length;
    final colorScheme = Theme.of(context).colorScheme;
    final pressure = _reviewPressureForBytes(totalBytes);

    return Card(
      elevation: 0,
      color: colorScheme.primaryContainer.withValues(alpha: 0.28),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.psychology_alt_rounded, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Review briefing',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _PressureBadge(label: pressure),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'This view holds ${_formatBytes(totalBytes)} across ${files.length} visible files. '
              'Start with ${largestFile.filename}; it alone can free ${_formatBytes(largestFile.size)}.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.32,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _BriefingPill(
                  icon: Icons.movie_filter_rounded,
                  label: '$videos video-heavy',
                ),
                _BriefingPill(
                  icon: Icons.download_rounded,
                  label: '$downloads downloads',
                ),
                _BriefingPill(
                  icon: Icons.schedule_rounded,
                  label: 'Newest ${_formatDate(newestFile.lastModified)}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PressureBadge extends StatelessWidget {
  const _PressureBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colorScheme.onPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _BriefingPill extends StatelessWidget {
  const _BriefingPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Chip(
      avatar: Icon(icon, size: 18, color: colorScheme.primary),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _LargeFileCard extends StatelessWidget {
  const _LargeFileCard({
    super.key,
    required this.file,
    required this.selected,
    required this.onChanged,
    required this.onDetails,
  });

  final ScannedFile file;
  final bool selected;
  final ValueChanged<bool> onChanged;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () => onChanged(!selected),
        title: Text(
          file.filename,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${file.path}\nModified ${_formatDate(file.lastModified)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 116),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _formatBytes(file.size),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelLarge?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'File details',
                onPressed: onDetails,
                icon: const Icon(Icons.info_outline_rounded),
              ),
            ],
          ),
        ),
        selected: selected,
        selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.24),
        contentPadding: const EdgeInsets.only(left: 4, right: 16),
        horizontalTitleGap: 4,
        minLeadingWidth: 0,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: selected,
              onChanged: (value) => onChanged(value ?? false),
            ),
            _FilePreview(file: file, colorScheme: colorScheme),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _FilePreview extends StatelessWidget {
  const _FilePreview({required this.file, required this.colorScheme});

  final ScannedFile file;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final previewPath = file.previewPath;
    final previewType = file.previewType;

    if (!kIsWeb && previewPath != null && previewType == 'image') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox.square(
          dimension: 42,
          child: Image.file(
            File(previewPath),
            fit: BoxFit.cover,
            cacheWidth: 96,
            errorBuilder: (_, _, _) => _PreviewIcon(
              icon: _iconForFile(file),
              colorScheme: colorScheme,
            ),
          ),
        ),
      );
    }

    return _PreviewIcon(icon: _iconForFile(file), colorScheme: colorScheme);
  }
}

class _PreviewIcon extends StatelessWidget {
  const _PreviewIcon({required this.icon, required this.colorScheme});

  final IconData icon;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 42,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: colorScheme.onSecondaryContainer),
      ),
    );
  }
}

class _LoadMoreLargeFilesCard extends StatelessWidget {
  const _LoadMoreLargeFilesCard({
    required this.visibleCount,
    required this.totalCount,
    required this.onLoadMore,
  });

  final int visibleCount;
  final int totalCount;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 10),
      child: OutlinedButton.icon(
        onPressed: onLoadMore,
        icon: const Icon(Icons.expand_more_rounded),
        label: Text('Load more ($visibleCount of $totalCount)'),
      ),
    );
  }
}

class _DeleteSelectionCard extends StatelessWidget {
  const _DeleteSelectionCard({
    required this.selectedCount,
    required this.selectedBytes,
    required this.isDeleting,
    required this.onDelete,
  });

  final int selectedCount;
  final int selectedBytes;
  final bool isDeleting;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = selectedCount == 0
        ? 'No large files selected'
        : '$selectedCount selected for deletion';

    return Card(
      elevation: 0,
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
                final details = Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                );
                final bytes = Text(
                  _formatBytes(selectedBytes),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                );

                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [icon, const SizedBox(width: 12), bytes]),
                      const SizedBox(height: 8),
                      details,
                    ],
                  );
                }

                return Row(
                  children: [
                    icon,
                    const SizedBox(width: 12),
                    Expanded(child: details),
                    bytes,
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: selectedCount == 0 || isDeleting ? null : onDelete,
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

class _CleanupHistoryCard extends StatelessWidget {
  const _CleanupHistoryCard({required this.history});

  final List<_CleanupHistoryEntry> history;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history_rounded, color: colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  'Cleanup history',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (history.isEmpty)
              Text(
                'No large-file cleanup actions in this session.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final entry in history.take(5))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: colorScheme.primaryContainer,
                    foregroundColor: colorScheme.onPrimaryContainer,
                    child: Icon(
                      entry.failedCount == 0
                          ? Icons.done_rounded
                          : Icons.warning_amber_rounded,
                    ),
                  ),
                  title: Text(
                    '${entry.deletedCount} ${entry.deletedCount == 1 ? 'file' : 'files'} deleted',
                  ),
                  subtitle: Text(
                    '${_formatBytes(entry.selectedBytes)} selected | ${_formatTime(entry.completedAt)}',
                  ),
                  trailing: entry.failedCount == 0
                      ? null
                      : Text('${entry.failedCount} failed'),
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
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.errorContainer,
      child: ListTile(
        leading: Icon(
          Icons.error_outline_rounded,
          color: colorScheme.onErrorContainer,
        ),
        title: Text(
          message,
          style: TextStyle(color: colorScheme.onErrorContainer),
        ),
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
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 42, color: colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.filter_alt_off_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class _CleanupHistoryEntry {
  const _CleanupHistoryEntry({
    required this.deletedCount,
    required this.failedCount,
    required this.selectedBytes,
    required this.completedAt,
  });

  final int deletedCount;
  final int failedCount;
  final int selectedBytes;
  final DateTime completedAt;
}

void _showFileDetails(
  BuildContext context,
  ScannedFile file, {
  required bool actionsSupported,
  required Future<void> Function() onOpen,
  required Future<void> Function() onShare,
  required Future<void> Function() onMove,
}) {
  final kind = _kindForFile(file);

  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final colorScheme = Theme.of(context).colorScheme;

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
                      file.filename,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _DetailRow(label: 'Size', value: _formatBytes(file.size)),
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
                    onPressed: actionsSupported ? onOpen : null,
                    icon: const Icon(Icons.visibility_rounded),
                    label: const Text('Preview'),
                  ),
                  OutlinedButton.icon(
                    onPressed: actionsSupported ? onShare : null,
                    icon: const Icon(Icons.ios_share_rounded),
                    label: const Text('Share'),
                  ),
                  OutlinedButton.icon(
                    onPressed: actionsSupported ? onMove : null,
                    icon: const Icon(Icons.drive_file_move_rounded),
                    label: const Text('Move'),
                  ),
                ],
              ),
              if (!actionsSupported) ...[
                const SizedBox(height: 10),
                Text(
                  'File actions are available on Android devices.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

Future<LargeFileMoveDestination?> _showMoveDestinationPicker(
  BuildContext context,
) {
  return showModalBottomSheet<LargeFileMoveDestination>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Move to',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              for (final destination in LargeFileMoveDestination.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_rounded),
                  title: Text(destination.label),
                  onTap: () => Navigator.of(context).pop(destination),
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

String _scanErrorMessage(Object error) {
  if (error is PlatformException && error.code == 'PERMISSION_DENIED') {
    return 'Storage and media access are required to scan your files.';
  }
  if (error is TimeoutException) {
    return 'The storage scan timed out. Please try again.';
  }
  if (error is UnsupportedError) {
    return 'Large File Hunter scans Android storage only.';
  }
  return 'The storage scan could not be completed. Please try again.';
}

String _fileActionError(Object error) {
  if (error is UnsupportedError) {
    return error.message ?? 'File action is unsupported.';
  }
  if (error is PlatformException) {
    return switch (error.code) {
      'FILE_NOT_FOUND' => 'That file no longer exists.',
      'NO_HANDLER' => 'No installed app can handle this file.',
      'MOVE_FAILED' => 'The file could not be moved.',
      _ => error.message ?? 'The file action could not be completed.',
    };
  }
  return 'The file action could not be completed.';
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

String _reviewPressureForBytes(int bytes) {
  const gigabyte = 1024 * 1024 * 1024;
  if (bytes >= 8 * gigabyte) return 'High impact';
  if (bytes >= 2 * gigabyte) return 'Medium impact';
  return 'Low impact';
}

String _formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String _formatTime(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _parentDirectory(String path) {
  final normalized = path.replaceAll('\\', '/');
  final lastSeparator = normalized.lastIndexOf('/');
  if (lastSeparator <= 0) return path;
  return normalized.substring(0, lastSeparator);
}

bool _matchesKind(ScannedFile file, _LargeFileKind kind) {
  if (kind == _LargeFileKind.all) return true;

  final extension = _extension(file.filename);
  final normalizedPath = file.path.replaceAll('\\', '/').toLowerCase();

  return switch (kind) {
    _LargeFileKind.all => true,
    _LargeFileKind.video => _videoExtensions.contains(extension),
    _LargeFileKind.image => _imageExtensions.contains(extension),
    _LargeFileKind.audio => _audioExtensions.contains(extension),
    _LargeFileKind.document => _documentExtensions.contains(extension),
    _LargeFileKind.apk => extension == 'apk',
    _LargeFileKind.zip => extension == 'zip',
    _LargeFileKind.archive => _archiveExtensions.contains(extension),
    _LargeFileKind.download => normalizedPath.contains('/download/'),
    _LargeFileKind.other =>
      !_videoExtensions.contains(extension) &&
          !_imageExtensions.contains(extension) &&
          !_audioExtensions.contains(extension) &&
          !_documentExtensions.contains(extension) &&
          extension != 'apk' &&
          !_archiveExtensions.contains(extension) &&
          !normalizedPath.contains('/download/'),
  };
}

_LargeFileKind _kindForFile(ScannedFile file) {
  if (_matchesKind(file, _LargeFileKind.video)) return _LargeFileKind.video;
  if (_matchesKind(file, _LargeFileKind.image)) return _LargeFileKind.image;
  if (_matchesKind(file, _LargeFileKind.audio)) return _LargeFileKind.audio;
  if (_matchesKind(file, _LargeFileKind.document)) {
    return _LargeFileKind.document;
  }
  if (_matchesKind(file, _LargeFileKind.apk)) return _LargeFileKind.apk;
  if (_matchesKind(file, _LargeFileKind.zip)) return _LargeFileKind.zip;
  if (_matchesKind(file, _LargeFileKind.archive)) return _LargeFileKind.archive;
  if (_matchesKind(file, _LargeFileKind.download)) {
    return _LargeFileKind.download;
  }
  return _LargeFileKind.other;
}

IconData _iconForFile(ScannedFile file) {
  return _kindForFile(file).icon;
}

String _extension(String filename) {
  final dotIndex = filename.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == filename.length - 1) return '';
  return filename.substring(dotIndex + 1).toLowerCase();
}

const Set<String> _videoExtensions = {
  '3gp',
  'avi',
  'm4v',
  'mkv',
  'mov',
  'mp4',
  'webm',
};

const Set<String> _imageExtensions = {
  'gif',
  'heic',
  'jpeg',
  'jpg',
  'png',
  'raw',
  'webp',
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

const Set<String> _archiveExtensions = {'7z', 'gz', 'rar', 'tar', 'zip'};

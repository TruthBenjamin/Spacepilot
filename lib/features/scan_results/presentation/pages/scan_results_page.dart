import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/presentation/widgets/space_background.dart';
import '../../../analytics/domain/models/storage_analytics.dart';
import '../../../analytics/presentation/providers/analytics_provider.dart';
import '../../../cleanup/data/services/cleanup_service.dart';
import '../../../cleanup/presentation/providers/cleanup_service_provider.dart';
import '../../../storage/domain/models/scanned_file.dart';
import '../../../storage/presentation/providers/device_storage_provider.dart';
import '../../../storage/presentation/providers/storage_scan_provider.dart';

class ScanResultsPage extends ConsumerStatefulWidget {
  const ScanResultsPage({super.key});

  @override
  ConsumerState<ScanResultsPage> createState() => _ScanResultsPageState();
}

class _ScanResultsPageState extends ConsumerState<ScanResultsPage> {
  static const targetOptions = [
    250 * 1024 * 1024,
    1024 * 1024 * 1024,
    2 * 1024 * 1024 * 1024,
    5 * 1024 * 1024 * 1024,
  ];

  final Set<String> _selectedPaths = {};
  var _targetBytes = targetOptions[1];
  var _isCleaning = false;
  var _scanStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runScan());
  }

  Future<void> _runScan() async {
    if (_scanStarted && ref.read(storageScanProvider).isLoading) return;

    setState(() {
      _scanStarted = true;
      _selectedPaths.clear();
    });

    try {
      await ref.read(storageScanProvider.notifier).scan();
      ref.invalidate(deviceStorageStatsProvider);
      ref.invalidate(deviceStorageStatsWithHealthProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_scanErrorMessage(error))));
    }
  }

  Future<void> _cleanSelected(List<ScannedFile> files) async {
    if (_isCleaning || _selectedPaths.isEmpty) return;

    final selectedFiles = files
        .where((file) => _selectedPaths.contains(file.path))
        .toList(growable: false);
    if (selectedFiles.isEmpty) return;

    final approved = await _showDeleteConfirmation(
      context,
      fileCount: selectedFiles.length,
      bytes: _sumBytes(selectedFiles),
    );
    if (approved != true || !mounted) return;

    setState(() => _isCleaning = true);
    final CleanupResult result;
    try {
      result = await ref
          .read(cleanupServiceProvider)
          .deleteFiles(
            selectedFiles.map((file) => File(file.path)),
            userConfirmed: true,
          );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isCleaning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected files could not be cleaned.')),
      );
      return;
    }

    if (!mounted) return;
    ref.read(storageScanProvider.notifier).removeDeletedPaths(result.deletedPaths);
    ref.invalidate(deviceStorageStatsProvider);
    ref.invalidate(deviceStorageStatsWithHealthProvider);
    setState(() {
      _isCleaning = false;
      _selectedPaths.removeAll(result.deletedPaths);
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_cleanupMessage(result))));
  }

  @override
  Widget build(BuildContext context) {
    final scan = ref.watch(storageScanProvider);
    final analytics = ref.watch(storageAnalyticsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Cleanup Scan'),
        actions: [
          IconButton(
            tooltip: 'Run scan again',
            onPressed: scan.isLoading || _isCleaning ? null : _runScan,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SpaceBackground(
        child: SafeArea(
          child: _isCleaning
              ? const _SpaceJanitorState(
                  mode: _JanitorMode.cleaning,
                  title: 'Space janitor is cleaning',
                  message: 'Deleting the selected files and refreshing storage.',
                )
              : scan.when(
                  data: (state) {
                    if (!state.hasScanned) {
                      return _EmptyState(
                        icon: Icons.auto_awesome_rounded,
                        title: 'Ready for an AI cleanup scan',
                        message:
                            'Run a scan to review files by cleanup category before deleting anything.',
                        onAction: _runScan,
                      );
                    }

                    final buckets = _buildCleanupBuckets(state.files);
                    final selectedBytes = _sumBytes(
                      state.files.where(
                        (file) => _selectedPaths.contains(file.path),
                      ),
                    );

                    return analytics.when(
                      data: (data) => _CleanupReview(
                        analytics: data,
                        files: state.files,
                        buckets: buckets,
                        selectedPaths: _selectedPaths,
                        selectedBytes: selectedBytes,
                        targetBytes: _targetBytes,
                        onTargetChanged: (value) =>
                            setState(() => _targetBytes = value),
                        onFileChanged: _setFileSelected,
                        onCategoryChanged: _setCategorySelected,
                        onSelectSuggested: () =>
                            _selectSuggested(state.files, _targetBytes),
                        onClearSelection: () => setState(_selectedPaths.clear),
                        onCleanSelected: () => _cleanSelected(state.files),
                      ),
                      error: (error, _) => _CleanupReview(
                        analytics: _fallbackAnalytics(state.files),
                        files: state.files,
                        buckets: buckets,
                        selectedPaths: _selectedPaths,
                        selectedBytes: selectedBytes,
                        targetBytes: _targetBytes,
                        onTargetChanged: (value) =>
                            setState(() => _targetBytes = value),
                        onFileChanged: _setFileSelected,
                        onCategoryChanged: _setCategorySelected,
                        onSelectSuggested: () =>
                            _selectSuggested(state.files, _targetBytes),
                        onClearSelection: () => setState(_selectedPaths.clear),
                        onCleanSelected: () => _cleanSelected(state.files),
                      ),
                      loading: () => const _SpaceJanitorState(
                        mode: _JanitorMode.searching,
                        title: 'Sorting cleanup categories',
                        message: 'Preparing analytics for the latest scan.',
                      ),
                    );
                  },
                  error: (error, _) => _EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Scan unavailable',
                    message: _scanErrorMessage(error),
                    onAction: _runScan,
                  ),
                  loading: () => const _SpaceJanitorState(
                    mode: _JanitorMode.searching,
                    title: 'Space janitor is searching',
                    message:
                        'Scanning Downloads, DCIM, Movies, and Pictures for cleanup candidates.',
                  ),
                ),
        ),
      ),
    );
  }

  void _setFileSelected(String path, bool selected) {
    setState(() {
      selected ? _selectedPaths.add(path) : _selectedPaths.remove(path);
    });
  }

  void _setCategorySelected(_CleanupBucket bucket, bool selected) {
    setState(() {
      final paths = bucket.files.map((file) => file.path);
      selected ? _selectedPaths.addAll(paths) : _selectedPaths.removeAll(paths);
    });
  }

  void _selectSuggested(List<ScannedFile> files, int targetBytes) {
    final suggested = _suggestFilesForTarget(files, targetBytes);
    setState(() {
      _selectedPaths
        ..clear()
        ..addAll(suggested.map((file) => file.path));
    });
  }
}

class _CleanupReview extends StatelessWidget {
  const _CleanupReview({
    required this.analytics,
    required this.files,
    required this.buckets,
    required this.selectedPaths,
    required this.selectedBytes,
    required this.targetBytes,
    required this.onTargetChanged,
    required this.onFileChanged,
    required this.onCategoryChanged,
    required this.onSelectSuggested,
    required this.onClearSelection,
    required this.onCleanSelected,
  });

  final StorageAnalytics analytics;
  final List<ScannedFile> files;
  final List<_CleanupBucket> buckets;
  final Set<String> selectedPaths;
  final int selectedBytes;
  final int targetBytes;
  final ValueChanged<int> onTargetChanged;
  final void Function(String path, bool selected) onFileChanged;
  final void Function(_CleanupBucket bucket, bool selected) onCategoryChanged;
  final VoidCallback onSelectSuggested;
  final VoidCallback onClearSelection;
  final VoidCallback onCleanSelected;

  @override
  Widget build(BuildContext context) {
    final suggested = _suggestFilesForTarget(files, targetBytes);

    return SpacePageList(
      children: [
        _CleanupHero(
          fileCount: files.length,
          totalBytes: _sumBytes(files),
          selectedCount: selectedPaths.length,
          selectedBytes: selectedBytes,
        ),
        const SizedBox(height: 16),
        _MetricGrid(data: analytics),
        const SizedBox(height: 16),
        _TargetSuggestionCard(
          targetBytes: targetBytes,
          suggestedCount: suggested.length,
          suggestedBytes: _sumBytes(suggested),
          onTargetChanged: onTargetChanged,
          onSelectSuggested: onSelectSuggested,
        ),
        const SizedBox(height: 16),
        _SelectionBar(
          selectedCount: selectedPaths.length,
          selectedBytes: selectedBytes,
          onClearSelection: onClearSelection,
          onCleanSelected: onCleanSelected,
        ),
        const SizedBox(height: 16),
        if (buckets.isEmpty)
          const _NoFilesCard()
        else
          for (final bucket in buckets) ...[
            _CleanupCategoryCard(
              bucket: bucket,
              selectedPaths: selectedPaths,
              onFileChanged: onFileChanged,
              onCategoryChanged: onCategoryChanged,
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _CleanupHero extends StatelessWidget {
  const _CleanupHero({
    required this.fileCount,
    required this.totalBytes,
    required this.selectedCount,
    required this.selectedBytes,
  });

  final int fileCount;
  final int totalBytes;
  final int selectedCount;
  final int selectedBytes;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 460;
            final icon = Icon(
              Icons.smart_toy_rounded,
              size: 42,
              color: colorScheme.onPrimaryContainer,
            );
            final copy = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cleanup review ready',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$fileCount files sorted by cleanup category. '
                  '$selectedCount selected to free ${_formatBytes(selectedBytes)}.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onPrimaryContainer.withValues(
                      alpha: 0.76,
                    ),
                  ),
                ),
              ],
            );
            final total = Text(
              _formatBytes(totalBytes),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w900,
              ),
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [icon, const SizedBox(width: 12), total]),
                  const SizedBox(height: 14),
                  copy,
                ],
              );
            }

            return Row(
              children: [
                icon,
                const SizedBox(width: 16),
                Expanded(child: copy),
                const SizedBox(width: 12),
                total,
              ],
            );
          },
        ),
      ),
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
        label: 'Old files',
        value: '${data.unusedFileCount}',
        caption: _formatBytes(data.unusedBytes),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 680
            ? 4
            : constraints.maxWidth >= 360
            ? 2
            : 1;
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: columns == 4
              ? 1.25
              : columns == 2
              ? 1.35
              : 2.6,
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
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
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

class _TargetSuggestionCard extends StatelessWidget {
  const _TargetSuggestionCard({
    required this.targetBytes,
    required this.suggestedCount,
    required this.suggestedBytes,
    required this.onTargetChanged,
    required this.onSelectSuggested,
  });

  final int targetBytes;
  final int suggestedCount;
  final int suggestedBytes;
  final ValueChanged<int> onTargetChanged;
  final VoidCallback onSelectSuggested;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_rounded, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Suggestions by space goal',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<int>(
                segments: [
                  for (final option in _ScanResultsPageState.targetOptions)
                    ButtonSegment(
                      value: option,
                      label: Text(_formatBytes(option)),
                    ),
                ],
                selected: {targetBytes},
                onSelectionChanged: (values) {
                  if (values.isEmpty) return;
                  onTargetChanged(values.first);
                },
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Select $suggestedCount suggested files to free about '
              '${_formatBytes(suggestedBytes)}.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: suggestedCount == 0 ? null : onSelectSuggested,
              icon: const Icon(Icons.auto_fix_high_rounded),
              label: const Text('Select suggested cleanup'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.selectedCount,
    required this.selectedBytes,
    required this.onClearSelection,
    required this.onCleanSelected,
  });

  final int selectedCount;
  final int selectedBytes;
  final VoidCallback onClearSelection;
  final VoidCallback onCleanSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = selectedCount == 0
        ? 'Choose files to clean'
        : '$selectedCount selected | ${_formatBytes(selectedBytes)}';

    return Card(
      elevation: 0,
      color: colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            final clear = TextButton(
              onPressed: selectedCount == 0 ? null : onClearSelection,
              child: const Text('Clear'),
            );
            final clean = FilledButton.icon(
              onPressed: selectedCount == 0 ? null : onCleanSelected,
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              icon: const Icon(Icons.cleaning_services_rounded),
              label: const Text('Clean all selected'),
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerLeft, child: clear),
                  const SizedBox(height: 8),
                  clean,
                ],
              );
            }

            return Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                clear,
                clean,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CleanupCategoryCard extends StatelessWidget {
  const _CleanupCategoryCard({
    required this.bucket,
    required this.selectedPaths,
    required this.onFileChanged,
    required this.onCategoryChanged,
  });

  final _CleanupBucket bucket;
  final Set<String> selectedPaths;
  final void Function(String path, bool selected) onFileChanged;
  final void Function(_CleanupBucket bucket, bool selected) onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedCount = bucket.files
        .where((file) => selectedPaths.contains(file.path))
        .length;
    final allSelected =
        bucket.files.isNotEmpty && selectedCount == bucket.files.length;

    return Card(
      elevation: 0,
      child: ExpansionTile(
        initiallyExpanded: bucket.priority <= 3,
        leading: Icon(bucket.icon, color: colorScheme.primary),
        title: Text(
          bucket.title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        subtitle: Text(
          '${bucket.files.length} files | ${_formatBytes(bucket.bytes)} | '
          '$selectedCount selected',
        ),
        trailing: Checkbox(
          value: allSelected,
          onChanged: bucket.files.isEmpty
              ? null
              : (value) => onCategoryChanged(bucket, value ?? false),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Text(
              bucket.description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final file in bucket.files)
            CheckboxListTile(
              value: selectedPaths.contains(file.path),
              onChanged: (value) => onFileChanged(file.path, value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                file.filename,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: Text(
                file.path,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              secondary: Text(
                _formatBytes(file.size),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NoFilesCard extends StatelessWidget {
  const _NoFilesCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('No files were found in the scanned folders.'),
      ),
    );
  }
}

enum _JanitorMode { searching, cleaning }

class _SpaceJanitorState extends StatefulWidget {
  const _SpaceJanitorState({
    required this.mode,
    required this.title,
    required this.message,
  });

  final _JanitorMode mode;
  final String title;
  final String message;

  @override
  State<_SpaceJanitorState> createState() => _SpaceJanitorStateState();
}

class _SpaceJanitorStateState extends State<_SpaceJanitorState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            reduceMotion
                ? _SpaceJanitorMark(mode: widget.mode)
                : AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      final bob = math.sin(_controller.value * math.pi) * 12;
                      final sweep =
                          math.sin(_controller.value * math.pi * 2) * 0.22;
                      return Transform.translate(
                        offset: Offset(0, -bob),
                        child: Transform.rotate(
                          angle: widget.mode == _JanitorMode.searching
                              ? sweep
                              : -0.45 + sweep,
                          child: _SpaceJanitorMark(mode: widget.mode),
                        ),
                      );
                    },
                  ),
            const SizedBox(height: 22),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 22),
            const SizedBox(width: 180, child: LinearProgressIndicator()),
          ],
        ),
      ),
    );
  }
}

class _SpaceJanitorMark extends StatelessWidget {
  const _SpaceJanitorMark({required this.mode});

  final _JanitorMode mode;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 150,
          height: 150,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.primaryContainer,
          ),
        ),
        Icon(
          mode == _JanitorMode.searching
              ? Icons.manage_search_rounded
              : Icons.cleaning_services_rounded,
          size: 72,
          color: colorScheme.primary,
        ),
        Positioned(
          top: 18,
          child: Icon(
            Icons.smart_toy_rounded,
            size: 44,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onAction;

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
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text('Run AI Scan'),
            ),
          ],
        ),
      ),
    );
  }
}

final class _CleanupBucket {
  const _CleanupBucket({
    required this.title,
    required this.description,
    required this.icon,
    required this.priority,
    required this.files,
  });

  final String title;
  final String description;
  final IconData icon;
  final int priority;
  final List<ScannedFile> files;

  int get bytes => _sumBytes(files);
}

enum _CleanupCategory {
  junk,
  installers,
  archives,
  largeFiles,
  oldFiles,
  videos,
  images,
  documents,
  audio,
  other;

  String get title => switch (this) {
    junk => 'Junk, temp, and cache files',
    installers => 'App installers',
    archives => 'Archives and downloads',
    largeFiles => 'Large files',
    oldFiles => 'Older files',
    videos => 'Videos',
    images => 'Images',
    documents => 'Documents',
    audio => 'Audio',
    other => 'Other scanned files',
  };

  String get description => switch (this) {
    junk => 'Usually safe candidates such as temporary files, logs, and cache.',
    installers => 'APK installers are often no longer needed after installation.',
    archives => 'Compressed downloads can take up space after extraction.',
    largeFiles => 'Big files worth reviewing before removal.',
    oldFiles => 'Files not modified in more than 180 days.',
    videos => 'Video files are often the biggest storage consumers.',
    images => 'Photos, screenshots, and image exports.',
    documents => 'Documents and text files from scanned folders.',
    audio => 'Music, voice notes, and other audio files.',
    other => 'Everything else found by the storage scan.',
  };

  IconData get icon => switch (this) {
    junk => Icons.cleaning_services_rounded,
    installers => Icons.android_rounded,
    archives => Icons.inventory_2_rounded,
    largeFiles => Icons.sd_storage_rounded,
    oldFiles => Icons.history_rounded,
    videos => Icons.movie_rounded,
    images => Icons.image_rounded,
    documents => Icons.description_rounded,
    audio => Icons.audiotrack_rounded,
    other => Icons.folder_rounded,
  };

  int get priority => switch (this) {
    junk => 0,
    installers => 1,
    archives => 2,
    largeFiles => 3,
    oldFiles => 4,
    videos => 5,
    images => 6,
    documents => 7,
    audio => 8,
    other => 9,
  };
}

List<_CleanupBucket> _buildCleanupBuckets(List<ScannedFile> files) {
  final oldBefore = DateTime.now().subtract(const Duration(days: 180));
  final grouped = <_CleanupCategory, List<ScannedFile>>{
    for (final category in _CleanupCategory.values) category: [],
  };

  for (final file in files) {
    grouped[_cleanupCategoryFor(file, oldBefore: oldBefore)]!.add(file);
  }

  return [
    for (final category in _CleanupCategory.values)
      if (grouped[category]!.isNotEmpty)
        _CleanupBucket(
          title: category.title,
          description: category.description,
          icon: category.icon,
          priority: category.priority,
          files: grouped[category]!..sort((a, b) => b.size.compareTo(a.size)),
        ),
  ]..sort((a, b) {
      final priority = a.priority.compareTo(b.priority);
      if (priority != 0) return priority;
      return b.bytes.compareTo(a.bytes);
    });
}

List<ScannedFile> _suggestFilesForTarget(
  List<ScannedFile> files,
  int targetBytes,
) {
  final oldBefore = DateTime.now().subtract(const Duration(days: 180));
  final priorities = <String, int>{};
  final candidates = [...files]
    ..sort((a, b) {
      final aPriority = priorities.putIfAbsent(
        a.path,
        () => _cleanupCategoryFor(a, oldBefore: oldBefore).priority,
      );
      final bPriority = priorities.putIfAbsent(
        b.path,
        () => _cleanupCategoryFor(b, oldBefore: oldBefore).priority,
      );
      final priority = aPriority.compareTo(bPriority);
      if (priority != 0) return priority;
      return b.size.compareTo(a.size);
    });

  var total = 0;
  final selected = <ScannedFile>[];
  for (final file in candidates) {
    selected.add(file);
    total += file.size;
    if (total >= targetBytes) break;
  }
  return selected;
}

_CleanupCategory _cleanupCategoryFor(
  ScannedFile file, {
  required DateTime oldBefore,
}) {
  final extension = _extension(file);
  final name = file.filename.toLowerCase();
  final path = file.path.toLowerCase().replaceAll('\\', '/');

  if (name.endsWith('.tmp') ||
      name.endsWith('.log') ||
      name.endsWith('.bak') ||
      path.contains('/cache/') ||
      path.contains('/temp/')) {
    return _CleanupCategory.junk;
  }
  if (extension == 'apk') return _CleanupCategory.installers;
  if (_archiveExtensions.contains(extension)) {
    return _CleanupCategory.archives;
  }
  if (file.size >= 100 * 1024 * 1024) return _CleanupCategory.largeFiles;
  if (file.lastModified.isBefore(oldBefore)) return _CleanupCategory.oldFiles;
  if (_videoExtensions.contains(extension)) {
    return _CleanupCategory.videos;
  }
  if (_imageExtensions.contains(extension)) {
    return _CleanupCategory.images;
  }
  if (_documentExtensions.contains(extension)) {
    return _CleanupCategory.documents;
  }
  if (_audioExtensions.contains(extension)) {
    return _CleanupCategory.audio;
  }
  return _CleanupCategory.other;
}

const _archiveExtensions = {'zip', 'rar', '7z', 'tar', 'gz'};
const _videoExtensions = {'mp4', 'mov', 'mkv', 'avi', 'webm'};
const _imageExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'};
const _documentExtensions = {
  'pdf',
  'doc',
  'docx',
  'xls',
  'xlsx',
  'ppt',
  'pptx',
  'txt',
};
const _audioExtensions = {'mp3', 'wav', 'm4a', 'aac', 'ogg'};

String _extension(ScannedFile file) {
  final name = file.filename.toLowerCase();
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return '';
  return name.substring(dot + 1);
}

int _sumBytes(Iterable<ScannedFile> files) {
  return files.fold<int>(0, (total, file) => total + file.size);
}

StorageAnalytics _fallbackAnalytics(List<ScannedFile> files) {
  return StorageAnalytics(
    totalFiles: files.length,
    totalBytes: _sumBytes(files),
    duplicateGroups: 0,
    duplicateBytes: 0,
    junkFileCount: 0,
    junkBytes: 0,
    unusedFileCount: 0,
    unusedBytes: 0,
    categories: const [],
    largestFiles: const [],
  );
}

String _scanErrorMessage(Object error) {
  if (error is PlatformException && error.code == 'PERMISSION_DENIED') {
    return 'Storage and media access are required to scan your files.';
  }
  if (error is UnsupportedError) {
    return 'AI cleanup scans Android storage only.';
  }
  return 'The storage scan could not be completed. Please try again.';
}

Future<bool?> _showDeleteConfirmation(
  BuildContext context, {
  required int fileCount,
  required int bytes,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(
        Icons.cleaning_services_rounded,
        color: Theme.of(context).colorScheme.error,
      ),
      title: const Text('Clean selected files?'),
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
          icon: const Icon(Icons.cleaning_services_rounded),
          label: const Text('Clean files'),
        ),
      ],
    ),
  );
}

String _cleanupMessage(CleanupResult result) {
  if (result.hasFailures) {
    return '${result.deletedCount} cleaned; ${result.failures.length} could not be cleaned.';
  }
  return '${result.deletedCount} ${result.deletedCount == 1 ? 'file' : 'files'} cleaned.';
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

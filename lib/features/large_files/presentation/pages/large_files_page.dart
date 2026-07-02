import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../cleanup/data/services/cleanup_service.dart';
import '../../../cleanup/presentation/providers/cleanup_service_provider.dart';
import '../../../../shared/presentation/widgets/space_background.dart';
import '../../../storage/domain/models/scanned_file.dart';
import '../../../storage/presentation/providers/device_storage_provider.dart';
import '../../../storage/presentation/providers/storage_scan_provider.dart';
import '../../../../routes/app_navigation.dart';
import '../providers/large_file_hunter_provider.dart';

class LargeFilesPage extends ConsumerStatefulWidget {
  const LargeFilesPage({super.key});

  @override
  ConsumerState<LargeFilesPage> createState() => _LargeFilesPageState();
}

class _LargeFilesPageState extends ConsumerState<LargeFilesPage> {
  final ValueNotifier<Set<String>> _selectedPaths = ValueNotifier(<String>{});
  bool _isDeleting = false;

  @override
  void dispose() {
    _selectedPaths.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scanState = ref.watch(storageScanProvider);
    final threshold = ref.watch(largeFileThresholdProvider);
    final largeFiles = ref.watch(largeFileHunterProvider);

    Future<void> runScan() async {
      await context.pushScanResults();
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

      ref
          .read(storageScanProvider.notifier)
          .removeDeletedPaths(result.deletedPaths);
      ref.invalidate(deviceStorageStatsProvider);
      ref.invalidate(deviceStorageStatsWithHealthProvider);
      setState(() {
        _isDeleting = false;
      });
      _removeSelectedPaths(result.deletedPaths);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_cleanupMessage(result))));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Large File Hunter'),
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
                        data: (files) => _LargeFileSliverList(
                          files: files,
                          threshold: threshold,
                          selectedPaths: _selectedPaths,
                          isDeleting: _isDeleting,
                          padding: resultPadding,
                          onFileChanged: _setFileSelected,
                          onDeleteSelected: () => deleteSelected(files),
                        ),
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

  void _removeSelectedPaths(Iterable<String> paths) {
    final updated = Set<String>.of(_selectedPaths.value)..removeAll(paths);
    _selectedPaths.value = updated;
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.isLoading, required this.onScanPressed});

  final bool isLoading;
  final Future<void> Function() onScanPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.folder_special_rounded,
              color: colorScheme.onPrimaryContainer,
              size: 32,
            ),
            const SizedBox(height: 14),
            Text(
              'Find the files taking the most space',
              style: textTheme.headlineSmall?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a size threshold, scan storage, and review results sorted from largest to smallest.',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onPrimaryContainer.withValues(alpha: 0.74),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: isLoading ? null : onScanPressed,
              icon: isLoading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.3),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(isLoading ? 'Scanning...' : 'Run AI Scan'),
            ),
          ],
        ),
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
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _LargeFileSliverList extends StatelessWidget {
  const _LargeFileSliverList({
    required this.files,
    required this.threshold,
    required this.selectedPaths,
    required this.isDeleting,
    required this.padding,
    required this.onFileChanged,
    required this.onDeleteSelected,
  });

  final List<ScannedFile> files;
  final LargeFileThreshold threshold;
  final ValueListenable<Set<String>> selectedPaths;
  final bool isDeleting;
  final EdgeInsets padding;
  final void Function(String path, bool selected) onFileChanged;
  final VoidCallback onDeleteSelected;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
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

    return ValueListenableBuilder<Set<String>>(
      valueListenable: selectedPaths,
      builder: (context, selectedPaths, _) {
        var selectedBytes = 0;
        var selectedCount = 0;
        for (final file in files) {
          if (!selectedPaths.contains(file.path)) continue;
          selectedBytes += file.size;
          selectedCount++;
        }

        return SliverPadding(
          padding: padding,
          sliver: SliverList.builder(
            itemCount: files.length + 3,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${files.length} files found',
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
              if (fileIndex == files.length) {
                return _DeleteSelectionCard(
                  selectedCount: selectedCount,
                  selectedBytes: selectedBytes,
                  isDeleting: isDeleting,
                  onDelete: onDeleteSelected,
                );
              }

              final file = files[fileIndex];
              return _LargeFileCard(
                key: ValueKey(file.path),
                file: file,
                selected: selectedPaths.contains(file.path),
                onChanged: (selected) => onFileChanged(file.path, selected),
              );
            },
          ),
        );
      },
    );
  }
}

class _LargeFileCard extends StatelessWidget {
  const _LargeFileCard({
    super.key,
    required this.file,
    required this.selected,
    required this.onChanged,
  });

  final ScannedFile file;
  final bool selected;
  final ValueChanged<bool> onChanged;

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
          child: Text(file.path, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        trailing: Text(
          _formatBytes(file.size),
          style: textTheme.labelLarge?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w800,
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
            CircleAvatar(
              backgroundColor: colorScheme.secondaryContainer,
              foregroundColor: colorScheme.onSecondaryContainer,
              child: const Icon(Icons.insert_drive_file_outlined),
            ),
          ],
        ),
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
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
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
  });

  final IconData icon;
  final String title;
  final String message;

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
          ],
        ),
      ),
    );
  }
}

String _scanErrorMessage(Object error) {
  if (error is PlatformException && error.code == 'PERMISSION_DENIED') {
    return 'Storage and media access are required to scan your files.';
  }
  if (error is UnsupportedError) {
    return 'Large File Hunter scans Android storage only.';
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

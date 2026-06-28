import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../cleanup/data/services/cleanup_service.dart';
import '../../../cleanup/presentation/providers/cleanup_service_provider.dart';
import '../../../../shared/presentation/widgets/space_background.dart';
import '../../../storage/data/services/storage_scanner_service.dart';
import '../../../storage/presentation/providers/device_storage_provider.dart';
import '../../../storage/presentation/providers/storage_scan_provider.dart';
import '../providers/large_file_hunter_provider.dart';

class LargeFilesPage extends ConsumerStatefulWidget {
  const LargeFilesPage({super.key});

  @override
  ConsumerState<LargeFilesPage> createState() => _LargeFilesPageState();
}

class _LargeFilesPageState extends ConsumerState<LargeFilesPage> {
  final Set<String> _selectedPaths = {};
  bool _isDeleting = false;

  @override
  Widget build(BuildContext context) {
    final scanState = ref.watch(storageScanProvider);
    final threshold = ref.watch(largeFileThresholdProvider);
    final largeFiles = ref.watch(largeFileHunterProvider);

    Future<void> runScan() async {
      try {
        await ref.read(storageScanProvider.notifier).scan();
      } catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_scanErrorMessage(error))),
        );
      }
    }

    Future<void> deleteSelected(List<ScannedFile> files) async {
      if (_selectedPaths.isEmpty || _isDeleting) return;

      final selectedFiles = files
          .where((file) => _selectedPaths.contains(file.path))
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
      if (approved != true || !mounted) return;

      setState(() => _isDeleting = true);
      final result = await ref
          .read(cleanupServiceProvider)
          .deleteFiles(selectedFiles.map((file) => File(file.path)));
      if (!mounted) return;

      ref
          .read(storageScanProvider.notifier)
          .removeDeletedPaths(result.deletedPaths);
      ref.invalidate(deviceStorageStatsProvider);
      ref.invalidate(deviceStorageStatsWithHealthProvider);
      setState(() {
        _isDeleting = false;
        _selectedPaths.removeAll(result.deletedPaths);
      });

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
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
            _HeaderCard(
              isLoading: scanState.isLoading,
              onScanPressed: runScan,
            ),
            const SizedBox(height: 18),
            _ThresholdPicker(selected: threshold),
            const SizedBox(height: 18),
            scanState.when(
              data: (state) {
                if (!state.hasScanned) {
                  return const _EmptyState(
                    icon: Icons.radar_rounded,
                    title: 'Run a scan to find large files',
                    message:
                        'SpacePilot will inspect Downloads, DCIM, Movies, and Pictures.',
                  );
                }

                return largeFiles.when(
                  data: (files) => _LargeFileList(
                    files: files,
                    threshold: threshold,
                    selectedPaths: _selectedPaths,
                    isDeleting: _isDeleting,
                    onFileChanged: (path, selected) {
                      setState(() {
                        selected
                            ? _selectedPaths.add(path)
                            : _selectedPaths.remove(path);
                      });
                    },
                    onDeleteSelected: () => deleteSelected(files),
                  ),
                  error: (error, _) =>
                      _ErrorState(message: _scanErrorMessage(error)),
                  loading: () => const _LoadingState(),
                );
              },
              error: (error, _) =>
                  _ErrorState(message: _scanErrorMessage(error)),
              loading: () => const _LoadingState(),
            ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.isLoading,
    required this.onScanPressed,
  });

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
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<LargeFileThreshold>(
            segments: [
              for (final threshold in LargeFileThreshold.values)
                ButtonSegment(
                  value: threshold,
                  label: Text(threshold.label),
                ),
            ],
            selected: {selected},
            onSelectionChanged: (values) {
              ref.read(largeFileThresholdProvider.notifier).state = values.first;
            },
          ),
        ),
      ],
    );
  }
}

class _LargeFileList extends StatelessWidget {
  const _LargeFileList({
    required this.files,
    required this.threshold,
    required this.selectedPaths,
    required this.isDeleting,
    required this.onFileChanged,
    required this.onDeleteSelected,
  });

  final List<ScannedFile> files;
  final LargeFileThreshold threshold;
  final Set<String> selectedPaths;
  final bool isDeleting;
  final void Function(String path, bool selected) onFileChanged;
  final VoidCallback onDeleteSelected;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return _EmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'No files over ${threshold.label}',
        message:
            'Try a smaller threshold or scan again after new files are added.',
      );
    }

    final selectedBytes = files
        .where((file) => selectedPaths.contains(file.path))
        .fold<int>(0, (total, file) => total + file.size);
    final selectedCount = files
        .where((file) => selectedPaths.contains(file.path))
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${files.length} files found',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
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
        ),
        const SizedBox(height: 10),
        for (final file in files)
          _LargeFileCard(
            file: file,
            selected: selectedPaths.contains(file.path),
            onChanged: (selected) => onFileChanged(file.path, selected),
          ),
        _DeleteSelectionCard(
          selectedCount: selectedCount,
          selectedBytes: selectedBytes,
          isDeleting: isDeleting,
          onDelete: onDeleteSelected,
        ),
      ],
    );
  }
}

class _LargeFileCard extends StatelessWidget {
  const _LargeFileCard({
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
          child: Text(
            file.path,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
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

    return Card(
      elevation: 0,
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
                    selectedCount == 0
                        ? 'No large files selected'
                        : '$selectedCount selected for deletion',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  _formatBytes(selectedBytes),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../storage/data/services/storage_scanner_service.dart';
import '../../../storage/presentation/providers/storage_scan_provider.dart';
import '../providers/large_file_hunter_provider.dart';

class LargeFilesPage extends ConsumerWidget {
  const LargeFilesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Large File Hunter'),
        centerTitle: false,
      ),
      body: SafeArea(
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
                  ),
                  error: (error, _) => _ErrorState(message: _scanErrorMessage(error)),
                  loading: () => const _LoadingState(),
                );
              },
              error: (error, _) => _ErrorState(message: _scanErrorMessage(error)),
              loading: () => const _LoadingState(),
            ),
          ],
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
  });

  final List<ScannedFile> files;
  final LargeFileThreshold threshold;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return _EmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'No files over ${threshold.label}',
        message: 'Try a smaller threshold or scan again after new files are added.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${files.length} files found',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 10),
        for (final file in files) _LargeFileCard(file: file),
      ],
    );
  }
}

class _LargeFileCard extends StatelessWidget {
  const _LargeFileCard({required this.file});

  final ScannedFile file;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.secondaryContainer,
          foregroundColor: colorScheme.onSecondaryContainer,
          child: const Icon(Icons.insert_drive_file_outlined),
        ),
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
    return 'Storage access is required to scan your files.';
  }
  if (error is UnsupportedError) {
    return 'Large File Hunter scans Android storage only.';
  }
  return 'The storage scan could not be completed. Please try again.';
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

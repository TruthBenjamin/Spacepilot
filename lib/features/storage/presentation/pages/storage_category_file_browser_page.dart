import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../cleanup/presentation/providers/deletion_sync_provider.dart';
import '../../../large_files/data/services/large_file_action_service.dart';
import '../../../large_files/presentation/providers/large_file_hunter_provider.dart';
import '../../../recovery/domain/models/recovery_bin_item.dart';
import '../../../recovery/presentation/providers/recovery_bin_provider.dart';
import '../../../../shared/presentation/widgets/space_background.dart';
import '../../domain/models/scanned_file.dart';
import '../../domain/models/storage_intelligence_report.dart';
import '../providers/device_storage_provider.dart';
import '../providers/storage_scan_provider.dart';

enum _FileBrowserSort {
  largest('Largest'),
  newest('Newest'),
  oldest('Oldest'),
  name('Name');

  const _FileBrowserSort(this.label);

  final String label;
}

class StorageCategoryFileBrowserPage extends ConsumerStatefulWidget {
  const StorageCategoryFileBrowserPage({this.categoryName, super.key});

  final String? categoryName;

  @override
  ConsumerState<StorageCategoryFileBrowserPage> createState() =>
      _StorageCategoryFileBrowserPageState();
}

class _StorageCategoryFileBrowserPageState
    extends ConsumerState<StorageCategoryFileBrowserPage> {
  final _searchController = TextEditingController();
  _FileBrowserSort _sort = _FileBrowserSort.largest;
  String _query = '';
  final Set<String> _selectedPaths = <String>{};
  String? _folderPath;

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

  @override
  Widget build(BuildContext context) {
    final category = _categoryFromRoute(widget.categoryName);
    final scan = ref.watch(storageScanProvider);
    final fileActions = ref.watch(largeFileActionServiceProvider);
    final title = category?.label ?? 'Storage Files';

    Future<void> refresh() async {
      HapticFeedback.mediumImpact();
      try {
        await ref.read(storageScanProvider.notifier).scanIntelligence();
        ref
          ..invalidate(deviceStorageStatsProvider)
          ..invalidate(deviceStorageStatsWithHealthProvider);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Storage scan refreshed.')),
        );
      } catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_scanErrorMessage(error))));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Refresh storage scan',
            onPressed: scan.isLoading ? null : refresh,
            icon: scan.isLoading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SpaceBackground(
        child: SafeArea(
          child: scan.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _StateMessage(
              icon: _permissionError(error)
                  ? Icons.lock_outline_rounded
                  : Icons.error_outline_rounded,
              title: _permissionError(error)
                  ? 'Storage permission required'
                  : 'Files unavailable',
              message: _scanErrorMessage(error),
              actionLabel: 'Refresh',
              onAction: refresh,
            ),
            data: (state) {
              if (!state.hasScanned || state.intelligenceReport == null) {
                return _StateMessage(
                  icon: Icons.manage_search_rounded,
                  title: 'No cached scan yet',
                  message:
                      'Run a manual refresh to load file details for this category.',
                  actionLabel: 'Refresh',
                  onAction: refresh,
                );
              }

              final report = state.intelligenceReport!;
              final categoryFiles = _filteredFiles(report, category);
              final folderPaths =
                  categoryFiles
                      .map((file) => _parentDirectory(file.path))
                      .toSet()
                      .toList(growable: false)
                    ..sort();
              final folderFiltered = _folderPath == null
                  ? categoryFiles
                  : categoryFiles
                        .where(
                          (file) => _parentDirectory(file.path) == _folderPath,
                        )
                        .toList(growable: false);
              final files = _visibleFiles(folderFiltered);
              if (files.isEmpty) {
                return _StateMessage(
                  icon: category?.icon ?? Icons.insert_drive_file_outlined,
                  title: 'No ${title.toLowerCase()} found',
                  message:
                      'The latest cached scan did not find files in this category.',
                  actionLabel: 'Refresh',
                  onAction: refresh,
                );
              }

              return SpacePageList(
                children: [
                  _SummaryCard(category: category, files: files),
                  const SizedBox(height: 14),
                  _FileBrowserControls(
                    controller: _searchController,
                    sort: _sort,
                    folderPaths: folderPaths,
                    selectedFolder: folderPaths.contains(_folderPath)
                        ? _folderPath
                        : null,
                    onFolderChanged: (folder) => setState(() {
                      _folderPath = folder;
                      _selectedPaths.clear();
                    }),
                    onSortChanged: (sort) => setState(() => _sort = sort),
                  ),
                  if (_selectedPaths.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SpaceCard(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('${_selectedPaths.length} selected'),
                          OutlinedButton(
                            onPressed: () => setState(_selectedPaths.clear),
                            child: const Text('Clear'),
                          ),
                          FilledButton.icon(
                            onPressed: fileActions.isSupported
                                ? () => _recoverSelected(fileActions, files)
                                : null,
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: const Text('Move to Recovery Bin'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  for (final file in files) ...[
                    _FileTile(
                      file: file,
                      selected: _selectedPaths.contains(file.path),
                      selectionActive: _selectedPaths.isNotEmpty,
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _selectedPaths.add(file.path);
                        } else {
                          _selectedPaths.remove(file.path);
                        }
                      }),
                      onLongPress: () => setState(() {
                        _selectedPaths.add(file.path);
                      }),
                      onTap: () => _showFileDetails(
                        context,
                        file,
                        actionsSupported: fileActions.isSupported,
                        onOpen: () => _runFileAction(
                          context,
                          () => fileActions.open(file.path),
                        ),
                        onShare: () => _runFileAction(
                          context,
                          () => fileActions.share(file.path),
                        ),
                        onMove: () => _runFileAction(context, () async {
                          final destination = await _showMoveDestinationPicker(
                            context,
                          );
                          if (destination == null) return;
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
                        }),
                        onRename: () => _runFileAction(context, () async {
                          final filename = await _showRenameDialog(
                            context,
                            file.filename,
                          );
                          if (filename == null) return;
                          final result = await fileActions.rename(
                            path: file.path,
                            filename: filename,
                          );
                          ref
                              .read(storageScanProvider.notifier)
                              .moveFilePath(
                                fromPath: file.path,
                                toPath: result.path,
                                filename: result.filename,
                              );
                        }),
                        onRecoverableDelete: () => _runFileAction(
                          context,
                          () async {
                            final approved = await _showRecoverableDeleteDialog(
                              context,
                              file,
                            );
                            if (approved != true) return;
                            final result = await fileActions.moveToRecovery(
                              path: file.path,
                              retentionDays: ref.read(
                                recoveryRetentionDaysProvider,
                              ),
                            );
                            ref
                                .read(recoveryBinProvider.notifier)
                                .registerMovedItem(
                                  RecoveryBinItem(
                                    id: result.id,
                                    filename: result.filename,
                                    originalPath: result.originalPath,
                                    recoveryPath: result.recoveryPath,
                                    sizeBytes: result.sizeBytes,
                                    deletedAt: result.deletedAt,
                                    expiresAt: result.expiresAt,
                                  ),
                                );
                            ref.read(deletionSyncProvider).applyDeletedPaths([
                              file.path,
                            ]);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _recoverSelected(
    LargeFileActionService actions,
    List<ScannedFile> visibleFiles,
  ) async {
    final selected = visibleFiles
        .where((file) => _selectedPaths.contains(file.path))
        .toList(growable: false);
    if (selected.isEmpty) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.restore_from_trash_rounded),
        title: const Text('Move selected files to Recovery Bin?'),
        content: Text(
          '${selected.length} files will be moved into SpacePilot-managed recoverable storage. No permanent deletion is performed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Move files'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;

    final movedPaths = <String>[];
    var failures = 0;
    for (final file in selected) {
      try {
        final result = await actions.moveToRecovery(
          path: file.path,
          retentionDays: ref.read(recoveryRetentionDaysProvider),
        );
        ref
            .read(recoveryBinProvider.notifier)
            .registerMovedItem(
              RecoveryBinItem(
                id: result.id,
                filename: result.filename,
                originalPath: result.originalPath,
                recoveryPath: result.recoveryPath,
                sizeBytes: result.sizeBytes,
                deletedAt: result.deletedAt,
                expiresAt: result.expiresAt,
              ),
            );
        movedPaths.add(file.path);
      } catch (_) {
        failures++;
      }
    }
    if (!mounted) return;
    ref.read(deletionSyncProvider).applyDeletedPaths(movedPaths);
    setState(() => _selectedPaths.removeAll(movedPaths));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failures == 0
              ? '${movedPaths.length} files moved to Recovery Bin.'
              : '${movedPaths.length} moved; $failures could not be moved.',
        ),
      ),
    );
  }

  List<ScannedFile> _visibleFiles(List<ScannedFile> files) {
    final visible = files
        .where((file) {
          if (_query.isEmpty) return true;
          return file.filename.toLowerCase().contains(_query) ||
              file.path.toLowerCase().contains(_query);
        })
        .toList(growable: false);

    visible.sort((a, b) {
      return switch (_sort) {
        _FileBrowserSort.largest => b.size.compareTo(a.size),
        _FileBrowserSort.newest => b.lastModified.compareTo(a.lastModified),
        _FileBrowserSort.oldest => a.lastModified.compareTo(b.lastModified),
        _FileBrowserSort.name => a.filename.toLowerCase().compareTo(
          b.filename.toLowerCase(),
        ),
      };
    });

    return visible;
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.category, required this.files});

  final _RouteCategory? category;
  final List<ScannedFile> files;

  @override
  Widget build(BuildContext context) {
    final totalBytes = files.fold<int>(0, (total, file) => total + file.size);

    return SpaceCard(
      child: Row(
        children: [
          Icon(
            category?.icon ?? Icons.insert_drive_file_outlined,
            color: Theme.of(context).colorScheme.primary,
            size: 34,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category?.label ?? 'All files',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '${files.length} files - ${_formatBytes(totalBytes)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
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

class _FileBrowserControls extends StatelessWidget {
  const _FileBrowserControls({
    required this.controller,
    required this.sort,
    required this.onSortChanged,
    required this.folderPaths,
    required this.selectedFolder,
    required this.onFolderChanged,
  });

  final TextEditingController controller;
  final _FileBrowserSort sort;
  final ValueChanged<_FileBrowserSort> onSortChanged;
  final List<String> folderPaths;
  final String? selectedFolder;
  final ValueChanged<String?> onFolderChanged;

  @override
  Widget build(BuildContext context) {
    return SpaceCard(
      child: Column(
        children: [
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              labelText: 'Search files',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: selectedFolder,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.folder_open_rounded),
              labelText: 'Folder',
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All permitted folders'),
              ),
              for (final folder in folderPaths)
                DropdownMenuItem<String?>(
                  value: folder,
                  child: Text(
                    folder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: onFolderChanged,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<_FileBrowserSort>(
                segments: [
                  for (final sort in _FileBrowserSort.values)
                    ButtonSegment(value: sort, label: Text(sort.label)),
                ],
                selected: {sort},
                onSelectionChanged: (values) {
                  if (values.isNotEmpty) onSortChanged(values.first);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _parentDirectory(String filePath) {
  final normalized = filePath.replaceAll('\\', '/');
  final separator = normalized.lastIndexOf('/');
  return separator <= 0 ? normalized : normalized.substring(0, separator);
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.file,
    required this.onTap,
    required this.onLongPress,
    required this.selected,
    required this.selectionActive,
    required this.onSelected,
  });

  final ScannedFile file;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selected;
  final bool selectionActive;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return SpaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: InkWell(
        onTap: selectionActive ? () => onSelected(!selected) : onTap,
        onLongPress: onLongPress,
        child: Row(
          children: [
            if (selectionActive)
              Checkbox(
                value: selected,
                onChanged: (value) => onSelected(value ?? false),
              )
            else
              const Icon(Icons.insert_drive_file_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    file.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _formatBytes(file.size),
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

void _showFileDetails(
  BuildContext context,
  ScannedFile file, {
  required bool actionsSupported,
  required Future<void> Function() onOpen,
  required Future<void> Function() onShare,
  required Future<void> Function() onMove,
  required Future<void> Function() onRename,
  required Future<void> Function() onRecoverableDelete,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              file.filename,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            _DetailRow(label: 'Size', value: _formatBytes(file.size)),
            _DetailRow(
              label: 'Modified',
              value: _formatDate(file.lastModified),
            ),
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
                OutlinedButton.icon(
                  onPressed: actionsSupported ? onRename : null,
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Rename'),
                ),
                OutlinedButton.icon(
                  onPressed: actionsSupported ? onRecoverableDelete : null,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Delete'),
                ),
              ],
            ),
            if (!actionsSupported) ...[
              const SizedBox(height: 10),
              Text(
                'File actions are available on Android devices.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(value),
        ],
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
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
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

List<ScannedFile> _filteredFiles(
  StorageIntelligenceReport report,
  _RouteCategory? category,
) {
  final files =
      report.fileInsights
          .where((insight) {
            final fileCategory = category?.fileCategory;
            if (fileCategory == null) return true;
            return insight.hasCategory(fileCategory);
          })
          .map((insight) => insight.file)
          .toList(growable: false)
        ..sort((a, b) => b.size.compareTo(a.size));
  return files;
}

_RouteCategory? _categoryFromRoute(String? value) {
  if (value == null || value.isEmpty) return null;
  for (final category in _RouteCategory.values) {
    if (category.routeName == value) return category;
  }
  return null;
}

enum _RouteCategory {
  images('image', 'Images', Icons.image_rounded, StorageFileCategory.image),
  videos('video', 'Videos', Icons.movie_rounded, StorageFileCategory.video),
  audio('audio', 'Audio', Icons.audio_file_rounded, StorageFileCategory.audio),
  documents(
    'document',
    'Documents',
    Icons.description_rounded,
    StorageFileCategory.document,
  ),
  apps('apps', 'Apps', Icons.apps_rounded, null),
  archives('zip', 'Archives', Icons.archive_rounded, StorageFileCategory.zip),
  apks('apk', 'APKs', Icons.android_rounded, StorageFileCategory.apk),
  downloads(
    'download',
    'Downloads',
    Icons.download_rounded,
    StorageFileCategory.download,
  ),
  other(
    'other',
    'Other files',
    Icons.category_rounded,
    StorageFileCategory.other,
  );

  const _RouteCategory(
    this.routeName,
    this.label,
    this.icon,
    this.fileCategory,
  );

  final String routeName;
  final String label;
  final IconData icon;
  final StorageFileCategory? fileCategory;
}

bool _permissionError(Object error) {
  return error is PlatformException && error.code == 'PERMISSION_DENIED';
}

Future<void> _runFileAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
    if (!context.mounted) return;
    Navigator.of(context).maybePop();
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_fileActionError(error))));
  }
}

Future<LargeFileMoveDestination?> _showMoveDestinationPicker(
  BuildContext context,
) {
  return showModalBottomSheet<LargeFileMoveDestination>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
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
    ),
  );
}

Future<String?> _showRenameDialog(
  BuildContext context,
  String currentFilename,
) async {
  final controller = TextEditingController(text: currentFilename);
  try {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.edit_rounded),
        title: const Text('Rename file'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'File name'),
          textInputAction: TextInputAction.done,
          onSubmitted: (value) {
            final trimmed = value.trim();
            Navigator.of(context).pop(trimmed.isEmpty ? null : trimmed);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              Navigator.of(context).pop(trimmed.isEmpty ? null : trimmed);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}

Future<bool?> _showRecoverableDeleteDialog(
  BuildContext context,
  ScannedFile file,
) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(
        Icons.delete_outline_rounded,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text('Move ${file.filename} to Recovery Bin?'),
      content: Text(
        'SpacePilot will move this file into app-managed recoverable storage. You can restore it from Recovery Bin until retention expires.',
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
          label: const Text('Move to bin'),
        ),
      ],
    ),
  );
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
      'RENAME_FAILED' => 'The file could not be renamed.',
      'RECOVERY_FAILED' => 'The file could not be moved to Recovery Bin.',
      'DELETE_FAILED' => 'The recovery item could not be deleted.',
      'INVALID_NAME' => 'Use a valid filename without folder separators.',
      _ => error.message ?? 'The file action could not be completed.',
    };
  }
  return 'The file action could not be completed.';
}

String _scanErrorMessage(Object error) {
  if (_permissionError(error)) {
    return 'Storage and media access are required to browse files.';
  }
  if (error is UnsupportedError) {
    return 'Storage browsing is available on Android devices.';
  }
  if (error is PlatformException && error.message != null) {
    return error.message!;
  }
  return 'Storage files could not be loaded. Please try again.';
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

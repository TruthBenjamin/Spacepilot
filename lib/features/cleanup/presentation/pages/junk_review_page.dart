import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/presentation/widgets/space_background.dart';
import '../../domain/models/cleanup_candidate.dart';
import '../providers/cleanup_center_provider.dart';
import '../providers/junk_cleaner_provider.dart';

class JunkReviewPage extends ConsumerWidget {
  const JunkReviewPage({required this.categoryId, super.key});

  final String? categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportState = ref.watch(cleanupCenterReportProvider);
    final selected = ref.watch(junkSelectionProvider);
    final cleanup = ref.watch(junkCleanupProvider);
    final report = reportState.value;
    final categories =
        report?.categories
            .where((item) => categoryId == null || item.id == categoryId)
            .toList() ??
        const <CleanupCategory>[];
    final summary = report == null
        ? null
        : summarizeCleanupSelection(report: report, selectedIds: selected);

    return Scaffold(
      appBar: AppBar(title: const Text('Review cleanup')),
      body: SpaceBackground(
        child: SafeArea(
          child: reportState.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _ReviewStateCard(
              icon: Icons.warning_amber_rounded,
              title: 'Cleanup review unavailable',
              message: error.toString(),
              actionLabel: 'Try again',
              action: () => ref.invalidate(cleanupCenterReportProvider),
            ),
            data: (_) {
              if (report == null || !report.hasScanned) {
                return _ReviewStateCard(
                  icon: Icons.manage_search_rounded,
                  title: 'Run a junk scan first',
                  message:
                      'SpacePilot needs a completed storage scan before it can review cleanup candidates.',
                  actionLabel: 'Refresh',
                  action: () => ref.invalidate(cleanupCenterReportProvider),
                );
              }

              if (categories.isEmpty) {
                return _ReviewStateCard(
                  icon: Icons.check_circle_outline_rounded,
                  title: 'No items to review',
                  message:
                      'This cleanup category has no current candidates from the latest scan.',
                  actionLabel: 'Refresh',
                  action: () => ref.invalidate(cleanupCenterReportProvider),
                );
              }

              return SpacePageList(
                children: [
                  for (final category in categories) ...[
                    SpaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(category.title),
                            subtitle: Text(category.description),
                            value: category.candidates.every(
                              (item) => selected.contains(item.id),
                            ),
                            onChanged: cleanup.isLoading
                                ? null
                                : (value) => ref
                                      .read(junkSelectionProvider.notifier)
                                      .setCategory(category, value ?? false),
                          ),
                          for (final item in category.candidates)
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: selected.contains(item.id),
                              onChanged: cleanup.isLoading
                                  ? null
                                  : (_) => ref
                                        .read(junkSelectionProvider.notifier)
                                        .toggle(item.id),
                              title: Text(item.title),
                              subtitle: Text(
                                '${item.path}\n${_bytes(item.bytes)} - ${item.riskLevel.label}\n${item.reason}',
                              ),
                              isThreeLine: true,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  FilledButton.icon(
                    onPressed:
                        cleanup.isLoading || summary == null || summary.isEmpty
                        ? null
                        : () => _confirm(context, ref, summary),
                    icon: cleanup.isLoading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : const Icon(Icons.delete_outline),
                    label: Text(
                      cleanup.isLoading
                          ? 'Cleaning selected'
                          : summary == null
                          ? 'Select items'
                          : 'Review deletion (${summary.fileCount + summary.emptyFolderCount})',
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

  Future<void> _confirm(
    BuildContext context,
    WidgetRef ref,
    CleanupSelectionSummary summary,
  ) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm cleanup'),
            content: Text(
              '${summary.fileCount} files and ${summary.emptyFolderCount} empty folders will be affected. Estimated recovery: ${_bytes(summary.selectedBytes)}. Files are deleted directly; a recovery bin is not available. Changed, missing, or inaccessible files may be skipped.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete selected'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    final result = await ref
        .read(junkCleanupProvider.notifier)
        .clean(summary, userConfirmed: true);
    ref.invalidate(cleanupCenterReportProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${result.deletedCount} deleted, ${result.skippedPaths.length} skipped, ${result.failures.length} failed.',
        ),
      ),
    );
  }
}

class _ReviewStateCard extends StatelessWidget {
  const _ReviewStateCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SpaceCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 54,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 18),
              FilledButton(onPressed: action, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}

String _bytes(int bytes) {
  var value = bytes.toDouble();
  var unit = 0;
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}

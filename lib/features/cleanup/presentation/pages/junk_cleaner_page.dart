import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../routes/app_routes.dart';
import '../../../../shared/presentation/widgets/space_background.dart';
import '../../data/services/cleanup_service.dart';
import '../../domain/models/cleanup_candidate.dart';
import '../../../storage/presentation/providers/storage_scan_provider.dart';
import '../providers/cleanup_center_provider.dart';
import '../providers/junk_cleaner_provider.dart';

class JunkCleanerPage extends ConsumerStatefulWidget {
  const JunkCleanerPage({super.key});

  @override
  ConsumerState<JunkCleanerPage> createState() => _JunkCleanerPageState();
}

class _JunkCleanerPageState extends ConsumerState<JunkCleanerPage> {
  var _entryScanStarted = false;
  var _stoppingScan = false;
  CleanupCenterReport? _latestReport;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startEntryScan());
  }

  void _startEntryScan() {
    if (!mounted || _entryScanStarted) return;
    final scan = ref.read(storageScanProvider);
    final progress = ref.read(storageScanProgressProvider);
    if (scan.value?.hasScanned == true || progress.isScanning) return;

    _entryScanStarted = true;
    unawaited(() async {
      try {
        await ref.read(storageScanProvider.notifier).scan();
      } catch (_) {}
    }());
  }

  Future<void> _stopScanAndClean() async {
    if (_stoppingScan) return;

    setState(() => _stoppingScan = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(storageScanProvider.notifier).cancelScan();
      ref.invalidate(cleanupCenterReportProvider);
      final report = await ref.read(cleanupCenterReportProvider.future);
      final automaticSelection = summarizeAutomaticJunkSelection(
        report: report,
      );

      if (automaticSelection.isEmpty) {
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('No safe junk was discovered yet.')),
        );
        return;
      }

      final result = await ref
          .read(junkCleanupProvider.notifier)
          .clean(automaticSelection, userConfirmed: true);
      ref.invalidate(cleanupCenterReportProvider);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(_cleanupMessage(result))));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Scan could not be stopped for cleanup.')),
      );
    } finally {
      if (mounted) setState(() => _stoppingScan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(cleanupCenterReportProvider);
    final scan = ref.watch(storageScanProvider);
    final progress = ref.watch(storageScanProgressProvider);
    final cleanup = ref.watch(junkCleanupProvider);
    final availableReport = report.value ?? _latestReport;

    final currentReport = report.value;
    if (currentReport != null && currentReport.hasScanned) {
      _latestReport = currentReport;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Junk Clean')),
      body: SpaceBackground(
        child: SafeArea(
          bottom: false,
          child: report.when(
            loading: () => _CleanupActivityState(
              progress: progress,
              lastScan: scan.value,
              report: availableReport,
              isStopping: _stoppingScan || cleanup.isLoading,
              onStopAndClean: _stopScanAndClean,
            ),
            error: (error, _) => _StateCard(
              icon: Icons.warning_amber_rounded,
              title: 'Cleanup scan unavailable',
              message: error.toString(),
              action: () => ref.invalidate(cleanupCenterReportProvider),
              actionIcon: Icons.refresh_rounded,
            ),
            data: (value) {
              final automaticSelection = summarizeAutomaticJunkSelection(
                report: value,
              );
              if (!value.hasScanned) {
                return _CleanupActivityState(
                  progress: progress,
                  lastScan: scan.value,
                  report: availableReport,
                  isStopping: _stoppingScan || cleanup.isLoading,
                  onStopAndClean: _stopScanAndClean,
                );
              }

              return SpacePageList(
                children: [
                  SpaceCard(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Theme.of(context).colorScheme.primaryContainer,
                        Theme.of(
                          context,
                        ).colorScheme.tertiaryContainer.withValues(alpha: 0.78),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _CleanupIconBadge(
                              icon: Icons.cleaning_services_rounded,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _bytes(value.recoverableBytes),
                                    style: Theme.of(context)
                                        .textTheme
                                        .displaySmall
                                        ?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                  Text(
                                    automaticSelection.fileCount > 0
                                        ? 'safe junk ready for one-step clean'
                                        : 'accessible files to review',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          automaticSelection.fileCount > 0
                              ? '${automaticSelection.fileCount} temporary files found automatically - ${value.candidateCount} total cleanup candidates'
                              : '${value.candidateCount} items - scanned ${value.completedAt?.toLocal() ?? 'recently'}',
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilledButton.icon(
                              onPressed:
                                  cleanup.isLoading ||
                                      automaticSelection.fileCount == 0
                                  ? null
                                  : () async {
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      final result = await ref
                                          .read(junkCleanupProvider.notifier)
                                          .clean(
                                            automaticSelection,
                                            userConfirmed: true,
                                          );
                                      ref.invalidate(
                                        cleanupCenterReportProvider,
                                      );
                                      if (!context.mounted) return;
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            _cleanupMessage(result),
                                          ),
                                        ),
                                      );
                                    },
                              icon: cleanup.isLoading
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                      ),
                                    )
                                  : const Icon(Icons.auto_fix_high_rounded),
                              label: Text(
                                cleanup.isLoading ? 'Cleaning junk' : 'Clean',
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: scan.isLoading
                                  ? null
                                  : () {
                                      ref
                                          .read(storageScanProvider.notifier)
                                          .scan();
                                    },
                              icon: scan.isLoading
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                      ),
                                    )
                                  : const Icon(Icons.manage_search_rounded),
                              label: Text(
                                scan.isLoading
                                    ? 'Scanning storage'
                                    : 'Refresh finder',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (value.categories.isEmpty)
                    const SpaceCard(
                      child: Text(
                        'No cleanup recommendations were found in accessible storage.',
                      ),
                    ),
                  for (final category in value.categories) ...[
                    SpaceCard(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _CleanupIconBadge(
                          icon: _categoryIcon(category.id),
                          color: _categoryColor(context, category.id),
                          size: 46,
                        ),
                        title: Text(category.title),
                        subtitle: Text(
                          '${category.actionableCount} items - ${_bytes(category.recoverableBytes)}\n${category.riskLevel.label}',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.pushNamed(
                          AppRouteNames.junkReview,
                          queryParameters: {'category': category.id},
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
    required this.actionIcon,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback action;
  final IconData actionIcon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SpaceCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CleanupIconBadge(
                icon: icon,
                color: Theme.of(context).colorScheme.primary,
                size: 76,
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
              FilledButton.icon(
                onPressed: action,
                icon: Icon(actionIcon),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CleanupActivityState extends StatelessWidget {
  const _CleanupActivityState({
    required this.progress,
    required this.lastScan,
    required this.report,
    required this.isStopping,
    required this.onStopAndClean,
  });

  final StorageScanProgress progress;
  final StorageScanState? lastScan;
  final CleanupCenterReport? report;
  final bool isStopping;
  final Future<void> Function() onStopAndClean;

  @override
  Widget build(BuildContext context) {
    final isScanning = progress.isScanning;
    final bytes = progress.bytesAnalyzed ?? lastScan?.totalBytes;
    final discoveredSelection = report == null
        ? null
        : summarizeAutomaticJunkSelection(report: report!);
    final discoveredBytes = discoveredSelection?.selectedBytes ?? 0;
    final shownBytes = discoveredBytes > 0 ? discoveredBytes : (bytes ?? 0);
    final progressValue = _scanProgress(progress);

    return LayoutBuilder(
      builder: (context, constraints) {
        final colorScheme = Theme.of(context).colorScheme;
        final bottomInset = MediaQuery.paddingOf(context).bottom;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
            child: Column(
              children: [
                SizedBox(height: constraints.maxHeight > 720 ? 78 : 42),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: _compactBytes(shownBytes).$1),
                      TextSpan(
                        text: ' ${_compactBytes(shownBytes).$2}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  discoveredBytes > 0 ? 'Junk discovered' : 'Junk',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  isStopping
                      ? 'Cleaning'
                      : isScanning
                      ? 'Scanning'
                      : 'Preparing scan',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 34),
                SpaceCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  child: Column(
                    children: [
                      _ScanCategoryRow(
                        title: 'Cache junk',
                        state: _categoryState(report, 'junk', isScanning),
                      ),
                      _ScanCategoryRow(
                        title: 'Residual junk',
                        state: _categoryState(report, 'oldFiles', isScanning),
                      ),
                      _ScanCategoryRow(
                        title: 'Clean Up Packages',
                        state: _categoryState(report, 'oldApks', isScanning),
                      ),
                      _ScanCategoryRow(
                        title: 'System junk',
                        state: _categoryState(
                          report,
                          'emptyFolders',
                          isScanning,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 324,
                  child: FilledButton(
                    onPressed:
                        isStopping ||
                            (!isScanning &&
                                progress.stage != StorageScanStage.complete)
                        ? null
                        : onStopAndClean,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        isStopping
                            ? 'Cleaning discovered junk'
                            : isScanning
                            ? 'Stop scanning (${(progressValue * 100).round()}%)'
                            : 'Clean',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ScanCategoryRow extends StatelessWidget {
  const _ScanCategoryRow({required this.title, required this.state});

  final String title;
  final _ScanCategoryState state;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 72,
      child: Row(
        children: [
          const Icon(Icons.keyboard_arrow_down_rounded),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: switch (state) {
              _ScanCategoryState.found => Icon(
                Icons.check_rounded,
                key: const ValueKey('found'),
                color: colorScheme.primary,
                size: 30,
              ),
              _ScanCategoryState.scanning => SizedBox.square(
                key: const ValueKey('scanning'),
                dimension: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              _ScanCategoryState.pending => Icon(
                Icons.more_horiz_rounded,
                key: const ValueKey('pending'),
                color: colorScheme.onSurfaceVariant,
              ),
            },
          ),
        ],
      ),
    );
  }
}

enum _ScanCategoryState { pending, scanning, found }

_ScanCategoryState _categoryState(
  CleanupCenterReport? report,
  String categoryId,
  bool isScanning,
) {
  final category = report?.categories.where((item) => item.id == categoryId);
  if (category != null && category.isNotEmpty) return _ScanCategoryState.found;
  return isScanning ? _ScanCategoryState.scanning : _ScanCategoryState.pending;
}

double _scanProgress(StorageScanProgress progress) {
  final reported = progress.fraction;
  if (reported != null) return reported.clamp(0, 1);
  return switch (progress.stage) {
    StorageScanStage.idle => 0,
    StorageScanStage.verifyingPermissions => 0.02,
    StorageScanStage.scanning => 0.05,
    StorageScanStage.savingHistory => 0.96,
    StorageScanStage.complete => 1,
    StorageScanStage.failed => 0,
  };
}

(String, String) _compactBytes(int bytes) {
  var value = bytes.toDouble();
  var unit = 0;
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }

  final decimals = unit == 0 ? 0 : 2;
  return (value.toStringAsFixed(decimals), units[unit]);
}

class _CleanupIconBadge extends StatelessWidget {
  const _CleanupIconBadge({
    required this.icon,
    required this.color,
    this.size = 56,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.28),
            Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.18),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.38)),
      ),
      child: Icon(icon, color: color, size: size * 0.48),
    );
  }
}

IconData _categoryIcon(String id) {
  return switch (id) {
    'duplicates' => Icons.copy_all_rounded,
    'junk' => Icons.cleaning_services_rounded,
    'oldApks' => Icons.android_rounded,
    'downloads' => Icons.download_rounded,
    'oldScreenshots' => Icons.screenshot_monitor_rounded,
    'largeFiles' => Icons.sd_storage_rounded,
    'oldFiles' => Icons.history_rounded,
    'emptyFolders' => Icons.folder_off_rounded,
    _ => Icons.folder_rounded,
  };
}

Color _categoryColor(BuildContext context, String id) {
  return switch (id) {
    'duplicates' => const Color(0xFF176BFF),
    'junk' => const Color(0xFFFF7E1D),
    'oldApks' => const Color(0xFF4D9A35),
    'downloads' => const Color(0xFFD849A9),
    'oldScreenshots' => const Color(0xFF11BFD7),
    'largeFiles' => const Color(0xFF8E45FF),
    'oldFiles' => const Color(0xFFE2AA18),
    'emptyFolders' => const Color(0xFF35C7BD),
    _ => Theme.of(context).colorScheme.primary,
  };
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

String _cleanupMessage(CleanupResult result) {
  if (result.hasFailures) {
    return '${result.deletedCount} cleaned; ${result.failures.length} could not be cleaned.';
  }
  if (result.deletedCount == 0) return 'No temporary junk needed cleaning.';
  return '${result.deletedCount} ${result.deletedCount == 1 ? 'file' : 'files'} cleaned.';
}

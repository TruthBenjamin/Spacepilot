import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../routes/app_routes.dart';
import '../../../../shared/presentation/widgets/space_background.dart';
import '../../../analytics/domain/models/storage_analytics.dart';
import '../../../analytics/presentation/providers/analytics_provider.dart';
import '../../../cleanup/data/services/cleanup_service.dart';
import '../../../cleanup/domain/models/cleanup_candidate.dart';
import '../../../cleanup/presentation/providers/cleanup_center_provider.dart';
import '../../../cleanup/presentation/providers/deletion_sync_provider.dart';
import '../../../cleanup/presentation/providers/cleanup_service_provider.dart';
import '../../../permissions/presentation/providers/permission_service_provider.dart';
import '../../../recommendations/presentation/providers/recommendations_provider.dart';
import '../../../recommendations/domain/models/storage_recommendation.dart';
import '../../../storage/domain/models/scanned_file.dart';
import '../../../storage/presentation/providers/device_storage_provider.dart';
import '../../../storage/presentation/providers/storage_scan_provider.dart';

class ScanResultsPage extends ConsumerStatefulWidget {
  const ScanResultsPage({super.key, this.showResults = false});

  final bool showResults;

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
  late bool _showResults = widget.showResults;

  @override
  void initState() {
    super.initState();
    final hasScan = ref.read(storageScanProvider).value?.hasScanned == true;
    if (widget.showResults && !hasScan) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runScan());
    }
  }

  @override
  void didUpdateWidget(covariant ScanResultsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showResults == widget.showResults) return;

    setState(() {
      _showResults = widget.showResults;
      if (!widget.showResults) {
        _scanStarted = false;
      }
    });

    final hasScan = ref.read(storageScanProvider).value?.hasScanned == true;
    if (widget.showResults && !hasScan) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runScan());
    }
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

  Future<void> _cleanSelected(CleanupCenterReport report) async {
    if (_isCleaning || _selectedPaths.isEmpty) return;

    final selection = summarizeCleanupSelection(
      report: report,
      selectedIds: _selectedPaths,
    );
    if (selection.isEmpty) return;

    final approved = await _showCleanupSimulationConfirmation(
      context,
      selection: selection,
    );
    if (approved != true || !mounted) return;

    setState(() => _isCleaning = true);
    final CleanupResult result;
    try {
      final cleanupService = ref.read(cleanupServiceProvider);
      final duplicatePaths = selection.duplicateGroups
          .expand((group) => group.files)
          .map((file) => file.path)
          .toSet();
      final regularFiles = selection.files
          .where((file) => !duplicatePaths.contains(file.path))
          .toList(growable: false);
      final results = <CleanupResult>[];

      if (regularFiles.isNotEmpty) {
        results.add(
          await cleanupService.deleteFiles(
            regularFiles.map((file) => File(file.path)),
            userConfirmed: true,
          ),
        );
      }
      if (selection.duplicateGroups.isNotEmpty) {
        results.add(
          await cleanupService.deleteDuplicates(
            selection.duplicateGroups,
            selectedPaths: selection.files.map((file) => file.path).toSet(),
            userConfirmed: true,
          ),
        );
      }
      if (selection.emptyFolders.isNotEmpty) {
        results.add(
          await cleanupService.deleteEmptyFolders(
            selection.emptyFolders.map((folder) => Directory(folder.path)),
            userConfirmed: true,
          ),
        );
      }

      result = _combineCleanupResults(results);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isCleaning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected files could not be cleaned.')),
      );
      return;
    }

    if (!mounted) return;
    ref.read(deletionSyncProvider).applyDeletedPaths(result.deletedPaths);
    setState(() {
      _isCleaning = false;
      _selectedPaths.clear();
    });

    await _showCleanupCompletionSummary(context, result);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_cleanupMessage(result))));
  }

  @override
  Widget build(BuildContext context) {
    if (!_showResults) {
      return _SmartScanExperience(
        onViewResults: () {
          context.goNamed(
            AppRouteNames.scanResults,
            queryParameters: const {'view': 'results'},
          );
          setState(() {
            _showResults = true;
            _scanStarted = false;
          });
        },
      );
    }

    final scan = ref.watch(storageScanProvider);
    final analytics = ref.watch(storageAnalyticsProvider);
    final cleanupReport = ref.watch(cleanupCenterReportProvider);

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
                  message:
                      'Deleting the selected files and refreshing storage.',
                )
              : scan.when(
                  data: (state) {
                    if (!state.hasScanned) {
                      return _CleanupReview(
                        analytics: _fallbackAnalytics(const []),
                        report: const CleanupCenterReport.empty(),
                        selectedPaths: _selectedPaths,
                        selectedBytes: 0,
                        targetBytes: _targetBytes,
                        onTargetChanged: (value) =>
                            setState(() => _targetBytes = value),
                        onFileChanged: _setFileSelected,
                        onCategoryChanged: _setCategorySelected,
                        onSelectSuggested: () => _selectSuggested(
                          const CleanupCenterReport.empty(),
                          _targetBytes,
                        ),
                        onClearSelection: () => setState(_selectedPaths.clear),
                        onCleanSelected: () =>
                            _cleanSelected(const CleanupCenterReport.empty()),
                        emptyMessage:
                            'Storage access is required for cleanup suggestions. Run the scan again after granting access.',
                      );
                    }

                    return cleanupReport.when(
                      data: (report) {
                        final selectedBytes = summarizeCleanupSelection(
                          report: report,
                          selectedIds: _selectedPaths,
                        ).selectedBytes;

                        return analytics.when(
                          data: (data) => _CleanupReview(
                            analytics: data,
                            report: report,
                            selectedPaths: _selectedPaths,
                            selectedBytes: selectedBytes,
                            targetBytes: _targetBytes,
                            onTargetChanged: (value) =>
                                setState(() => _targetBytes = value),
                            onFileChanged: _setFileSelected,
                            onCategoryChanged: _setCategorySelected,
                            onSelectSuggested: () =>
                                _selectSuggested(report, _targetBytes),
                            onClearSelection: () =>
                                setState(_selectedPaths.clear),
                            onCleanSelected: () => _cleanSelected(report),
                          ),
                          error: (error, _) => _CleanupReview(
                            analytics: _fallbackAnalytics(state.files),
                            report: report,
                            selectedPaths: _selectedPaths,
                            selectedBytes: selectedBytes,
                            targetBytes: _targetBytes,
                            onTargetChanged: (value) =>
                                setState(() => _targetBytes = value),
                            onFileChanged: _setFileSelected,
                            onCategoryChanged: _setCategorySelected,
                            onSelectSuggested: () =>
                                _selectSuggested(report, _targetBytes),
                            onClearSelection: () =>
                                setState(_selectedPaths.clear),
                            onCleanSelected: () => _cleanSelected(report),
                          ),
                          loading: () => _CleanupReview(
                            analytics: _fallbackAnalytics(state.files),
                            report: report,
                            selectedPaths: _selectedPaths,
                            selectedBytes: selectedBytes,
                            targetBytes: _targetBytes,
                            onTargetChanged: (value) =>
                                setState(() => _targetBytes = value),
                            onFileChanged: _setFileSelected,
                            onCategoryChanged: _setCategorySelected,
                            onSelectSuggested: () =>
                                _selectSuggested(report, _targetBytes),
                            onClearSelection: () =>
                                setState(_selectedPaths.clear),
                            onCleanSelected: () => _cleanSelected(report),
                          ),
                        );
                      },
                      error: (error, _) => _EmptyState(
                        icon: Icons.error_outline_rounded,
                        title: 'Cleanup center unavailable',
                        message:
                            'Actionable cleanup results could not be prepared.',
                        onAction: () =>
                            ref.invalidate(cleanupCenterReportProvider),
                      ),
                      loading: () => const _SpaceJanitorState(
                        mode: _JanitorMode.searching,
                        title: 'Preparing cleanup center',
                        message:
                            'Grouping large files, duplicates, downloads, screenshots, and folders.',
                      ),
                    );
                  },
                  error: (error, _) => _EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Scan unavailable',
                    message: _scanErrorMessage(error),
                    onAction: _runScan,
                  ),
                  loading: () => _CleanupReview(
                    analytics: _fallbackAnalytics(const []),
                    report: const CleanupCenterReport.empty(),
                    selectedPaths: _selectedPaths,
                    selectedBytes: 0,
                    targetBytes: _targetBytes,
                    onTargetChanged: (value) =>
                        setState(() => _targetBytes = value),
                    onFileChanged: _setFileSelected,
                    onCategoryChanged: _setCategorySelected,
                    onSelectSuggested: () => _selectSuggested(
                      const CleanupCenterReport.empty(),
                      _targetBytes,
                    ),
                    onClearSelection: () => setState(_selectedPaths.clear),
                    onCleanSelected: () =>
                        _cleanSelected(const CleanupCenterReport.empty()),
                    emptyMessage:
                        'Storage access is required for cleanup suggestions. Run the scan again after granting access.',
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

  void _setCategorySelected(CleanupCategory bucket, bool selected) {
    setState(() {
      final ids = bucket.candidates.map((candidate) => candidate.id);
      selected ? _selectedPaths.addAll(ids) : _selectedPaths.removeAll(ids);
    });
  }

  void _selectSuggested(CleanupCenterReport report, int targetBytes) {
    final suggested = _suggestCandidatesForTarget(report, targetBytes);
    setState(() {
      _selectedPaths
        ..clear()
        ..addAll(suggested.map((candidate) => candidate.id));
    });
  }
}

enum _SmartScanPermissionState { checking, granted, denied, unsupported }

class _SmartScanExperience extends ConsumerStatefulWidget {
  const _SmartScanExperience({required this.onViewResults});

  final VoidCallback onViewResults;

  @override
  ConsumerState<_SmartScanExperience> createState() =>
      _SmartScanExperienceState();
}

class _SmartScanExperienceState extends ConsumerState<_SmartScanExperience> {
  _SmartScanPermissionState _permissionState =
      _SmartScanPermissionState.checking;
  Timer? _elapsedTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _verifyPermissions();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    super.dispose();
  }

  Future<void> _verifyPermissions() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      if (mounted) {
        setState(
          () => _permissionState = _SmartScanPermissionState.unsupported,
        );
      }
      return;
    }

    setState(() => _permissionState = _SmartScanPermissionState.checking);
    final permissionService = ref.read(permissionServiceProvider);
    final hasAccess =
        await permissionService.hasStorageAccess() &&
        await permissionService.hasMediaAccess();
    if (!mounted) return;
    setState(() {
      _permissionState = hasAccess
          ? _SmartScanPermissionState.granted
          : _SmartScanPermissionState.denied;
    });
  }

  Future<void> _requestPermissions() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      setState(() => _permissionState = _SmartScanPermissionState.unsupported);
      return;
    }

    setState(() => _permissionState = _SmartScanPermissionState.checking);
    final granted = await ref
        .read(permissionServiceProvider)
        .requestRequiredAccess();
    if (!mounted) return;
    setState(() {
      _permissionState = granted
          ? _SmartScanPermissionState.granted
          : _SmartScanPermissionState.denied;
    });
  }

  Future<void> _startScan() async {
    if (ref.read(storageScanProvider).isLoading) return;

    try {
      final report = await ref
          .read(storageScanProvider.notifier)
          .scanIntelligence();
      if (!mounted) return;
      _refreshDependentState();
      setState(() => _permissionState = _SmartScanPermissionState.granted);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Smart Scan complete: ${report.files.length} files analyzed.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      await _verifyPermissions();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_scanErrorMessage(error))));
    }
  }

  void _refreshDependentState() {
    ref.read(deletionSyncProvider).refreshDerivedState();
  }

  @override
  Widget build(BuildContext context) {
    final scan = ref.watch(storageScanProvider);
    final stats = ref.watch(deviceStorageStatsWithHealthProvider);
    final state = scan.value ?? const StorageScanState.initial();
    final progress = ref.watch(storageScanProgressProvider);
    final recommendations = ref.watch(recommendationsProvider);
    final isScanning = scan.isLoading || progress.isScanning;
    final hasCompletedScan =
        state.hasScanned && progress.stage == StorageScanStage.complete;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Scan'),
        actions: [
          IconButton(
            tooltip: 'Refresh permissions',
            onPressed: isScanning ? null : _verifyPermissions,
            icon: const Icon(Icons.verified_user_rounded),
          ),
        ],
      ),
      body: SpaceBackground(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: isScanning ? () async {} : _verifyPermissions,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                _SmartScanHeader(
                  permissionState: _permissionState,
                  isScanning: isScanning,
                  hasCompletedScan: hasCompletedScan,
                  onStart: _startScan,
                  onRequestPermissions: _requestPermissions,
                  onRetry: _startScan,
                  onViewResults: widget.onViewResults,
                ),
                const SizedBox(height: 16),
                stats.when(
                  data: (storageStats) => _PreScanSummary(
                    totalBytes: storageStats.totalBytes,
                    usedBytes: storageStats.usedBytes,
                    freeBytes: storageStats.freeBytes,
                    healthScore: storageStats.deviceHealthScore,
                    lastScanFileCount: state.hasScanned
                        ? state.files.length
                        : null,
                    lastScanBytes: state.hasScanned ? state.totalBytes : null,
                  ),
                  error: (_, _) => _ScanInfoPanel(
                    icon: Icons.error_outline_rounded,
                    title: 'Storage summary unavailable',
                    message:
                        'Smart Scan can still run, but storage totals could not be loaded right now.',
                  ),
                  loading: () => const _ScanInfoPanel(
                    icon: Icons.storage_rounded,
                    title: 'Loading storage summary',
                    message: 'Checking device storage before scanning.',
                    isLoading: true,
                  ),
                ),
                const SizedBox(height: 16),
                _PermissionPanel(
                  state: _permissionState,
                  isScanning: isScanning,
                  onRequestPermissions: _requestPermissions,
                  onVerify: _verifyPermissions,
                ),
                const SizedBox(height: 16),
                _LiveScanPanel(
                  progress: progress,
                  isScanning: isScanning,
                  hasScanned: state.hasScanned,
                  elapsed: progress.elapsed(_now),
                  fileCount: state.files.length,
                  totalBytes: state.totalBytes,
                  errorMessage: scan.hasError
                      ? _scanErrorMessage(scan.error!)
                      : progress.errorMessage,
                  onRetry: _startScan,
                  onViewResults: widget.onViewResults,
                ),
                const SizedBox(height: 16),
                _ScanRecommendations(
                  recommendations: recommendations,
                  hasScanned: state.hasScanned,
                  onRunScan: _startScan,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScanRecommendations extends StatelessWidget {
  const _ScanRecommendations({
    required this.recommendations,
    required this.hasScanned,
    required this.onRunScan,
  });

  final AsyncValue<List<StorageRecommendation>> recommendations;
  final bool hasScanned;
  final VoidCallback onRunScan;

  @override
  Widget build(BuildContext context) {
    return _ScanSection(
      title: 'AI recommendations',
      icon: Icons.auto_awesome_rounded,
      child: recommendations.when(
        loading: () => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(),
            SizedBox(height: 12),
            Text('Building recommendations from the scan results…'),
          ],
        ),
        error: (_, _) => const Text(
          'Recommendations could not be prepared. Retry the Smart Scan.',
        ),
        data: (items) {
          if (!hasScanned || items.isEmpty) {
            return Row(
              children: [
                const Expanded(
                  child: Text(
                    'Run Smart Scan to generate local AI cleanup recommendations.',
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: onRunScan,
                  child: const Text('Run scan'),
                ),
              ],
            );
          }
          return Column(
            children: [
              for (final item in items) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    child: Icon(Icons.auto_awesome_rounded),
                  ),
                  title: Text(item.title),
                  subtitle: Text(item.description),
                  trailing: Text(_formatBytes(item.storageSavingsBytes)),
                  onTap: () => context.pushNamed(
                    item.actionTarget == RecommendationActionTarget.duplicates
                        ? AppRouteNames.duplicates
                        : AppRouteNames.scanResults,
                    queryParameters:
                        item.actionTarget ==
                            RecommendationActionTarget.scanResults
                        ? const {'view': 'results'}
                        : const {},
                  ),
                ),
                if (item != items.last) const Divider(height: 1),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SmartScanHeader extends StatelessWidget {
  const _SmartScanHeader({
    required this.permissionState,
    required this.isScanning,
    required this.hasCompletedScan,
    required this.onStart,
    required this.onRequestPermissions,
    required this.onRetry,
    required this.onViewResults,
  });

  final _SmartScanPermissionState permissionState;
  final bool isScanning;
  final bool hasCompletedScan;
  final VoidCallback onStart;
  final VoidCallback onRequestPermissions;
  final VoidCallback onRetry;
  final VoidCallback onViewResults;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final needsPermission = permissionState == _SmartScanPermissionState.denied;
    final unsupported =
        permissionState == _SmartScanPermissionState.unsupported;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.radar_rounded, color: colorScheme.primary, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'On-device storage intelligence',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            unsupported
                ? 'Smart Scan is available on Android devices with storage access.'
                : 'Scan real user-accessible folders, then refresh cleanup recommendations, health, large files, duplicates, and storage history.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: isScanning || unsupported
                    ? null
                    : needsPermission
                    ? onRequestPermissions
                    : onStart,
                icon: Icon(
                  needsPermission
                      ? Icons.lock_open_rounded
                      : Icons.play_arrow_rounded,
                ),
                label: Text(needsPermission ? 'Grant access' : 'Start scan'),
              ),
              OutlinedButton.icon(
                onPressed: isScanning ? null : onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
              OutlinedButton.icon(
                onPressed: hasCompletedScan && !isScanning
                    ? onViewResults
                    : null,
                icon: const Icon(Icons.fact_check_rounded),
                label: const Text('View results'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreScanSummary extends StatelessWidget {
  const _PreScanSummary({
    required this.totalBytes,
    required this.usedBytes,
    required this.freeBytes,
    required this.healthScore,
    this.lastScanFileCount,
    this.lastScanBytes,
  });

  final int totalBytes;
  final int usedBytes;
  final int freeBytes;
  final int healthScore;
  final int? lastScanFileCount;
  final int? lastScanBytes;

  @override
  Widget build(BuildContext context) {
    return _ScanSection(
      title: 'Pre-scan summary',
      icon: Icons.analytics_rounded,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _MetricTile(label: 'Used storage', value: _formatBytes(usedBytes)),
          _MetricTile(label: 'Free storage', value: _formatBytes(freeBytes)),
          _MetricTile(label: 'Total storage', value: _formatBytes(totalBytes)),
          _MetricTile(label: 'Health score', value: '$healthScore/100'),
          _MetricTile(
            label: 'Cached files',
            value: lastScanFileCount == null
                ? 'No scan yet'
                : '$lastScanFileCount',
          ),
          _MetricTile(
            label: 'Cached scan size',
            value: lastScanBytes == null
                ? 'No scan yet'
                : _formatBytes(lastScanBytes!),
          ),
        ],
      ),
    );
  }
}

class _PermissionPanel extends StatelessWidget {
  const _PermissionPanel({
    required this.state,
    required this.isScanning,
    required this.onRequestPermissions,
    required this.onVerify,
  });

  final _SmartScanPermissionState state;
  final bool isScanning;
  final VoidCallback onRequestPermissions;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final (icon, title, message) = switch (state) {
      _SmartScanPermissionState.checking => (
        Icons.hourglass_top_rounded,
        'Checking permissions',
        'Verifying storage and media access before scanning.',
      ),
      _SmartScanPermissionState.granted => (
        Icons.verified_rounded,
        'Permissions ready',
        'Storage and media access are available for the real scanner.',
      ),
      _SmartScanPermissionState.denied => (
        Icons.lock_rounded,
        'Permission required',
        'Grant storage and media access to scan real files on this device.',
      ),
      _SmartScanPermissionState.unsupported => (
        Icons.android_rounded,
        'Android required',
        'The native storage scanner is available on Android only.',
      ),
    };

    return _ScanSection(
      title: 'Permission verification',
      icon: icon,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(message),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: isScanning ? null : onVerify,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Verify'),
              ),
              FilledButton.icon(
                onPressed:
                    state == _SmartScanPermissionState.denied && !isScanning
                    ? onRequestPermissions
                    : null,
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('Grant access'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LiveScanPanel extends StatelessWidget {
  const _LiveScanPanel({
    required this.progress,
    required this.isScanning,
    required this.hasScanned,
    required this.elapsed,
    required this.fileCount,
    required this.totalBytes,
    required this.errorMessage,
    required this.onRetry,
    required this.onViewResults,
  });

  final StorageScanProgress progress;
  final bool isScanning;
  final bool hasScanned;
  final Duration elapsed;
  final int fileCount;
  final int totalBytes;
  final String? errorMessage;
  final VoidCallback onRetry;
  final VoidCallback onViewResults;

  @override
  Widget build(BuildContext context) {
    final supportsGranularProgress = progress.supportsGranularProgress;
    final isError = progress.stage == StorageScanStage.failed;
    final isComplete =
        progress.stage == StorageScanStage.complete && hasScanned;

    return _ScanSection(
      title: 'Live scan',
      icon: Icons.manage_search_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isScanning) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 14),
          ] else if (isComplete) ...[
            LinearProgressIndicator(value: 1),
            const SizedBox(height: 14),
          ],
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricTile(label: 'Stage', value: _stageLabel(progress.stage)),
              _MetricTile(label: 'Elapsed', value: _formatDuration(elapsed)),
              _MetricTile(
                label: 'Files analyzed',
                value:
                    progress.filesAnalyzed?.toString() ??
                    (isScanning ? 'Final report pending' : '$fileCount'),
              ),
              _MetricTile(
                label: 'Storage analyzed',
                value: progress.bytesAnalyzed == null
                    ? (isScanning
                          ? 'Final report pending'
                          : _formatBytes(totalBytes))
                    : _formatBytes(progress.bytesAnalyzed!),
              ),
              _MetricTile(
                label: 'Scan roots',
                value:
                    progress.scannedRootCount?.toString() ??
                    (isScanning ? 'Discovering' : 'Not available'),
              ),
              _MetricTile(
                label: 'Progress detail',
                value: supportsGranularProgress ? 'Granular' : 'Indeterminate',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            supportsGranularProgress
                ? 'The scanner is reporting granular progress.'
                : 'The native scanner reports a final payload, so progress is shown as indeterminate until completion.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (isError && errorMessage != null) ...[
            const SizedBox(height: 14),
            Text(
              errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: isScanning ? null : onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
              OutlinedButton.icon(
                onPressed: progress.supportsCancellation && isScanning
                    ? () {}
                    : null,
                icon: const Icon(Icons.cancel_rounded),
                label: const Text('Cancel scan'),
              ),
              FilledButton.icon(
                onPressed: isComplete && !isScanning ? onViewResults : null,
                icon: const Icon(Icons.fact_check_rounded),
                label: const Text('Open results'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScanInfoPanel extends StatelessWidget {
  const _ScanInfoPanel({
    required this.icon,
    required this.title,
    required this.message,
    this.isLoading = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return _ScanSection(
      title: title,
      icon: icon,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isLoading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
          ],
          Text(message),
        ],
      ),
    );
  }
}

class _ScanSection extends StatelessWidget {
  const _ScanSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 220),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CleanupReview extends StatelessWidget {
  const _CleanupReview({
    required this.analytics,
    required this.report,
    required this.selectedPaths,
    required this.selectedBytes,
    required this.targetBytes,
    required this.onTargetChanged,
    required this.onFileChanged,
    required this.onCategoryChanged,
    required this.onSelectSuggested,
    required this.onClearSelection,
    required this.onCleanSelected,
    this.emptyMessage,
  });

  final StorageAnalytics analytics;
  final CleanupCenterReport report;
  final Set<String> selectedPaths;
  final int selectedBytes;
  final int targetBytes;
  final ValueChanged<int> onTargetChanged;
  final void Function(String id, bool selected) onFileChanged;
  final void Function(CleanupCategory bucket, bool selected) onCategoryChanged;
  final VoidCallback onSelectSuggested;
  final VoidCallback onClearSelection;
  final VoidCallback onCleanSelected;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    final suggested = _suggestCandidatesForTarget(report, targetBytes);

    return SpacePageList(
      children: [
        _CleanupHero(
          fileCount: report.candidateCount,
          totalBytes: report.recoverableBytes,
          selectedCount: selectedPaths.length,
          selectedBytes: selectedBytes,
        ),
        const SizedBox(height: 16),
        _MetricGrid(data: analytics),
        const SizedBox(height: 16),
        _TargetSuggestionCard(
          targetBytes: targetBytes,
          suggestedCount: suggested.length,
          suggestedBytes: _sumCandidateBytes(suggested),
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
        if (report.categories.isEmpty)
          _NoFilesCard(message: emptyMessage)
        else
          for (final bucket in report.categories) ...[
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
                  '$fileCount items sorted by cleanup category. '
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
        ? 'Choose items to clean'
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

  final CleanupCategory bucket;
  final Set<String> selectedPaths;
  final void Function(String id, bool selected) onFileChanged;
  final void Function(CleanupCategory bucket, bool selected) onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedCount = bucket.candidates
        .where((candidate) => selectedPaths.contains(candidate.id))
        .length;
    final allSelected =
        bucket.candidates.isNotEmpty &&
        selectedCount == bucket.candidates.length;

    return Card(
      elevation: 0,
      child: ExpansionTile(
        initiallyExpanded: bucket.priority <= 3,
        leading: Icon(
          _iconForCleanupCategory(bucket.id),
          color: colorScheme.primary,
        ),
        title: Text(
          bucket.title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          '${bucket.candidates.length} items | '
          '${_formatBytes(bucket.recoverableBytes)} | '
          '$selectedCount selected',
        ),
        trailing: Checkbox(
          value: allSelected,
          onChanged: bucket.candidates.isEmpty
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _RiskChip(level: bucket.riskLevel),
            ),
          ),
          for (final candidate in bucket.candidates)
            CheckboxListTile(
              value: selectedPaths.contains(candidate.id),
              onChanged: (value) => onFileChanged(candidate.id, value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                candidate.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                '${candidate.reason}\n${candidate.path}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              secondary: Text(
                candidate.type == CleanupCandidateType.emptyFolder
                    ? 'Folder'
                    : _formatBytes(candidate.bytes),
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
  const _NoFilesCard({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message ?? 'No files were found in the scanned folders.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
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
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
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

int _sumBytes(Iterable<ScannedFile> files) {
  return files.fold<int>(0, (total, file) => total + file.size);
}

List<CleanupCandidate> _suggestCandidatesForTarget(
  CleanupCenterReport report,
  int targetBytes,
) {
  final candidates =
      [for (final category in report.categories) ...category.candidates]
        ..sort((a, b) {
          final aPriority = report.categories
              .firstWhere((category) => category.candidates.contains(a))
              .priority;
          final bPriority = report.categories
              .firstWhere((category) => category.candidates.contains(b))
              .priority;
          final priority = aPriority.compareTo(bPriority);
          if (priority != 0) return priority;
          return b.bytes.compareTo(a.bytes);
        });

  final selected = <CleanupCandidate>[];
  final selectedPaths = <String>{};
  var total = 0;
  for (final candidate in candidates) {
    selected.add(candidate);
    if (candidate.type != CleanupCandidateType.emptyFolder &&
        selectedPaths.add(candidate.path)) {
      total += candidate.bytes;
    }
    if (total >= targetBytes) break;
  }
  return selected;
}

int _sumCandidateBytes(Iterable<CleanupCandidate> candidates) {
  final paths = <String>{};
  var total = 0;
  for (final candidate in candidates) {
    if (candidate.type == CleanupCandidateType.emptyFolder) continue;
    if (paths.add(candidate.path)) total += candidate.bytes;
  }
  return total;
}

IconData _iconForCleanupCategory(String id) {
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

class _RiskChip extends StatelessWidget {
  const _RiskChip({required this.level});

  final CleanupRiskLevel level;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = switch (level) {
      CleanupRiskLevel.usuallyRemovable => colorScheme.primary,
      CleanupRiskLevel.keepOneCopy => colorScheme.tertiary,
      CleanupRiskLevel.reviewRecommended => colorScheme.secondary,
    };

    return Chip(
      avatar: Icon(Icons.info_outline_rounded, size: 16, color: color),
      label: Text(level.label),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: color.withValues(alpha: 0.45)),
      backgroundColor: color.withValues(alpha: 0.10),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w800),
    );
  }
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
  if (error is TimeoutException) {
    return 'The storage scan timed out. Please try again.';
  }
  if (error is UnsupportedError) {
    return 'AI cleanup scans Android storage only.';
  }
  return 'The storage scan could not be completed. Please try again.';
}

Future<bool?> _showCleanupSimulationConfirmation(
  BuildContext context, {
  required CleanupSelectionSummary selection,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(
        Icons.cleaning_services_rounded,
        color: Theme.of(context).colorScheme.error,
      ),
      title: const Text('Cleanup preview'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SpacePilot will attempt to delete ${selection.fileCount} '
              '${selection.fileCount == 1 ? 'file' : 'files'} and '
              '${selection.emptyFolderCount} empty '
              '${selection.emptyFolderCount == 1 ? 'folder' : 'folders'}, '
              'freeing about ${_formatBytes(selection.selectedBytes)}.',
            ),
            const SizedBox(height: 12),
            if (selection.duplicateGroups.isNotEmpty)
              Text(
                'Duplicate cleanup preserves at least one copy from each exact-match group.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            Text(
              'Nothing has been deleted yet. Confirm only after reviewing the selected items.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
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
          label: const Text('Confirm cleanup'),
        ),
      ],
    ),
  );
}

Future<void> _showCleanupCompletionSummary(
  BuildContext context,
  CleanupResult result,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(
        result.hasFailures
            ? Icons.warning_amber_rounded
            : Icons.task_alt_rounded,
        color: result.hasFailures
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary,
      ),
      title: Text(
        result.hasFailures ? 'Cleanup partially completed' : 'Cleanup complete',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${result.deletedCount} deleted'),
            if (result.skippedPaths.isNotEmpty)
              Text('${result.skippedPaths.length} skipped'),
            if (result.failures.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('${result.failures.length} could not be cleaned:'),
              const SizedBox(height: 6),
              for (final entry in result.failures.entries.take(4))
                Text(
                  '${entry.key}: ${entry.value}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

CleanupResult _combineCleanupResults(List<CleanupResult> results) {
  if (results.isEmpty) {
    return CleanupResult(
      deletedPaths: const [],
      skippedPaths: const [],
      failures: const {},
    );
  }

  return CleanupResult(
    deletedPaths: [for (final result in results) ...result.deletedPaths],
    skippedPaths: [for (final result in results) ...result.skippedPaths],
    failures: {for (final result in results) ...result.failures},
  );
}

String _cleanupMessage(CleanupResult result) {
  if (result.hasFailures) {
    return '${result.deletedCount} cleaned; ${result.failures.length} could not be cleaned.';
  }
  return '${result.deletedCount} ${result.deletedCount == 1 ? 'file' : 'files'} cleaned.';
}

String _stageLabel(StorageScanStage stage) {
  return switch (stage) {
    StorageScanStage.idle => 'Ready',
    StorageScanStage.verifyingPermissions => 'Verifying permissions',
    StorageScanStage.scanning => 'Scanning storage',
    StorageScanStage.savingHistory => 'Saving scan history',
    StorageScanStage.complete => 'Complete',
    StorageScanStage.failed => 'Error',
  };
}

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds.clamp(0, 24 * 60 * 60);
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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

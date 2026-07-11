import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../routes/app_routes.dart';
import '../../../../shared/presentation/widgets/space_background.dart';
import '../../../auto_clean/presentation/providers/auto_clean_provider.dart';
import '../../../cleanup/presentation/providers/cleanup_center_provider.dart';
import '../../../duplicates/presentation/providers/duplicate_groups_provider.dart';
import '../../../large_files/presentation/providers/large_file_hunter_provider.dart';
import '../../../recovery/presentation/providers/recovery_bin_provider.dart';
import '../../../recommendations/presentation/providers/recommendations_provider.dart';
import '../../../storage/presentation/providers/storage_history_provider.dart';
import '../../../storage/presentation/providers/storage_scan_provider.dart';

class ToolsPage extends ConsumerWidget {
  const ToolsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scan = ref.watch(storageScanProvider);
    final largeFiles = ref.watch(largeFileHunterProvider);
    final duplicates = ref.watch(duplicateGroupsProvider);
    final similar = ref.watch(similarImageGroupsProvider);
    final cleanup = ref.watch(cleanupCenterReportProvider);
    final recommendations = ref.watch(visibleRecommendationsProvider);
    final automation = ref.watch(automationPlanProvider);
    final history = ref.watch(storageHistoryProvider);
    final bin = ref.watch(recoveryBinProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Tools')),
      body: SpaceBackground(
        child: SafeArea(
          child: SpacePageList(
            children: [
              _HeaderCard(hasScanned: scan.value?.hasScanned == true),
              const SizedBox(height: 14),
              _ToolTile(
                icon: Icons.psychology_alt_rounded,
                title: 'Recommendations',
                summary: recommendations.when(
                  data: (items) => '${items.length} active',
                  loading: () => 'Updating',
                  error: (_, _) => 'Run scan',
                ),
                routeName: AppRouteNames.recommendations,
              ),
              _ToolTile(
                icon: Icons.inventory_2_rounded,
                title: 'Large Files',
                summary: largeFiles.when(
                  data: (files) => _bytesSummary(
                    files.fold<int>(0, (total, file) => total + file.size),
                  ),
                  loading: () => 'Checking',
                  error: (_, _) => 'Scan required',
                ),
                routeName: AppRouteNames.largeFiles,
              ),
              _ToolTile(
                icon: Icons.copy_all_rounded,
                title: 'Duplicate Cleaner',
                summary: duplicates.when(
                  data: (groups) => _bytesSummary(
                    groups.fold<int>(
                      0,
                      (total, group) => total + group.recoverableBytes,
                    ),
                  ),
                  loading: () => 'Checking',
                  error: (_, _) => 'Scan required',
                ),
                routeName: AppRouteNames.duplicates,
              ),
              _ToolTile(
                icon: Icons.image_search_rounded,
                title: 'Similar Images',
                summary: similar.when(
                  data: (groups) => '${groups.length} groups',
                  loading: () => 'Checking',
                  error: (_, _) => 'Scan required',
                ),
                routeName: AppRouteNames.similarImages,
              ),
              _ToolTile(
                icon: Icons.android_rounded,
                title: 'App Analyzer',
                summary: 'Installed apps and APK installers',
                routeName: AppRouteNames.appAnalyzer,
              ),
              _ToolTile(
                icon: Icons.memory_rounded,
                title: 'RAM Booster',
                summary: 'Free safe background memory',
                routeName: AppRouteNames.booster,
              ),
              _ToolTile(
                icon: Icons.cleaning_services_rounded,
                title: 'Smart Cleanup',
                summary: cleanup.when(
                  data: (report) => report.hasScanned
                      ? _bytesSummary(report.recoverableBytes)
                      : 'Scan required',
                  loading: () => 'Checking',
                  error: (_, _) => 'Review unavailable',
                ),
                routeName: AppRouteNames.junkCleaner,
              ),
              _ToolTile(
                icon: Icons.timeline_rounded,
                title: 'Storage Timeline',
                summary: history.when(
                  data: (entries) => '${entries.length} snapshots',
                  loading: () => 'Loading history',
                  error: (_, _) => 'History unavailable',
                ),
                routeName: AppRouteNames.storageTimeline,
              ),
              _ToolTile(
                icon: Icons.auto_mode_rounded,
                title: 'Automation',
                summary: automation.when(
                  data: (plan) => '${plan.scheduledTaskCount} scheduled',
                  loading: () => 'Syncing',
                  error: (_, _) => 'Needs scan',
                ),
                routeName: AppRouteNames.automation,
              ),
              _ToolTile(
                icon: Icons.restore_from_trash_rounded,
                title: 'Recovery Bin',
                summary: '${bin.length} recoverable items',
                routeName: AppRouteNames.recoveryBin,
              ),
              _ToolTile(
                icon: Icons.privacy_tip_rounded,
                title: 'Privacy Center',
                summary: 'Permissions and local processing',
                routeName: AppRouteNames.privacyCenter,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.hasScanned});

  final bool hasScanned;

  @override
  Widget build(BuildContext context) {
    return SpaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Utility hub',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            hasScanned
                ? 'Summaries below come from the latest local scan and feature providers.'
                : 'Run Smart Scan to populate tool status summaries.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.icon,
    required this.title,
    required this.summary,
    required this.routeName,
  });

  final IconData icon;
  final String title;
  final String summary;
  final String routeName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SpaceCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: CircleAvatar(child: Icon(icon)),
          title: Text(title),
          subtitle: Text(summary),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => context.pushNamed(routeName),
        ),
      ),
    );
  }
}

String _bytesSummary(int bytes) {
  if (bytes <= 0) return 'No current findings';
  return '${_formatBytes(bytes)} found';
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

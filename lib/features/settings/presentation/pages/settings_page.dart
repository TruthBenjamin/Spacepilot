import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auto_clean/presentation/providers/auto_clean_provider.dart';
import '../../../../shared/presentation/widgets/space_background.dart';
import '../../../scheduled_scans/domain/models/scheduled_scan_config.dart';
import '../../../scheduled_scans/presentation/providers/scheduled_scan_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduledScan = ref.watch(scheduledScanProvider);
    final autoCleanRules = ref.watch(autoCleanRulesProvider);
    final autoCleanPlan = ref.watch(autoCleanPlanProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SpaceBackground(
        child: SafeArea(
          child: SpacePageList(
            children: [
              _ScheduledScanCard(config: scheduledScan),
              const SizedBox(height: 16),
              _AutoCleanCard(
                enabled: autoCleanRules.enabled,
                includeDuplicateCopies: autoCleanRules.includeDuplicateCopies,
                includeApkInstallers: autoCleanRules.includeApkInstallers,
                includeOldScreenshots: autoCleanRules.includeOldScreenshots,
                includeUnusedFiles: autoCleanRules.includeUnusedFiles,
                includeEmptyFolders: autoCleanRules.includeEmptyFolders,
              ),
              const SizedBox(height: 16),
              autoCleanPlan.when(
                data: (plan) => _AutoCleanPlanCard(
                  ruleCount: plan.ruleCount,
                  fileCount: plan.fileCount,
                  savingsBytes: plan.estimatedSavingsBytes,
                ),
                error: (error, _) => const SizedBox.shrink(),
                loading: () =>
                    const _LoadingCard(label: 'Calculating rule impact...'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduledScanCard extends ConsumerWidget {
  const _ScheduledScanCard({required this.config});

  final ScheduledScanConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(scheduledScanProvider.notifier);
    final nextRun = config.nextRunAfter(DateTime.now());

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: config.enabled,
              onChanged: controller.setEnabled,
              title: const Text('Scheduled scans'),
              subtitle: Text(
                nextRun == null
                    ? 'Run scans manually'
                    : 'Next scan: ${_formatDateTime(nextRun)}',
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<ScheduledScanFrequency>(
                segments: [
                  for (final frequency in ScheduledScanFrequency.values)
                    ButtonSegment(
                      value: frequency,
                      label: Text(frequency.label),
                    ),
                ],
                selected: {config.frequency},
                onSelectionChanged: config.enabled
                    ? (values) {
                        if (values.isEmpty) return;
                        controller.setFrequency(values.first);
                      }
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_rounded),
              title: const Text('Preferred scan time'),
              subtitle: Text(_formatMinutes(config.minutesAfterMidnight)),
              trailing: const Icon(Icons.chevron_right_rounded),
              enabled: config.enabled,
              onTap: config.enabled
                  ? () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(
                          hour: config.minutesAfterMidnight ~/ 60,
                          minute: config.minutesAfterMidnight % 60,
                        ),
                      );
                      if (picked == null || !context.mounted) return;
                      controller.setMinutesAfterMidnight(
                        picked.hour * 60 + picked.minute,
                      );
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _AutoCleanCard extends ConsumerWidget {
  const _AutoCleanCard({
    required this.enabled,
    required this.includeDuplicateCopies,
    required this.includeApkInstallers,
    required this.includeOldScreenshots,
    required this.includeUnusedFiles,
    required this.includeEmptyFolders,
  });

  final bool enabled;
  final bool includeDuplicateCopies;
  final bool includeApkInstallers;
  final bool includeOldScreenshots;
  final bool includeUnusedFiles;
  final bool includeEmptyFolders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(autoCleanRulesProvider.notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: enabled,
              onChanged: controller.setEnabled,
              title: const Text('Auto-clean rules'),
              subtitle: const Text('Prepare cleanup suggestions for review'),
            ),
            const Divider(),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: includeDuplicateCopies,
              onChanged: enabled
                  ? (value) => controller.setDuplicateCopies(value ?? false)
                  : null,
              title: const Text('Duplicate copies'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: includeApkInstallers,
              onChanged: enabled
                  ? (value) => controller.setApkInstallers(value ?? false)
                  : null,
              title: const Text('APK installers'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: includeOldScreenshots,
              onChanged: enabled
                  ? (value) => controller.setOldScreenshots(value ?? false)
                  : null,
              title: const Text('Screenshots older than 90 days'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: includeUnusedFiles,
              onChanged: enabled
                  ? (value) => controller.setUnusedFiles(value ?? false)
                  : null,
              title: const Text('Unused files older than 180 days'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: includeEmptyFolders,
              onChanged: enabled
                  ? (value) => controller.setEmptyFolders(value ?? false)
                  : null,
              title: const Text('Empty folders'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AutoCleanPlanCard extends StatelessWidget {
  const _AutoCleanPlanCard({
    required this.ruleCount,
    required this.fileCount,
    required this.savingsBytes,
  });

  final int ruleCount;
  final int fileCount;
  final int savingsBytes;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 360;
            final icon = Icon(
              Icons.rule_rounded,
              color: Theme.of(context).colorScheme.primary,
            );
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$ruleCount active ${ruleCount == 1 ? 'rule' : 'rules'}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  '$fileCount files matched | ${_formatBytes(savingsBytes)} potential savings',
                  maxLines: compact ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [icon, const SizedBox(height: 12), details],
              );
            }

            return Row(
              children: [
                icon,
                const SizedBox(width: 14),
                Expanded(child: details),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2.3),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    );
  }
}

String _formatMinutes(int minutesAfterMidnight) {
  final hour = minutesAfterMidnight ~/ 60;
  final minute = minutesAfterMidnight % 60;
  final period = hour >= 12 ? 'PM' : 'AM';
  final displayHour = hour % 12 == 0 ? 12 : hour % 12;
  return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
}

String _formatDateTime(DateTime value) {
  return '${value.month}/${value.day} at ${_formatMinutes(value.hour * 60 + value.minute)}';
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

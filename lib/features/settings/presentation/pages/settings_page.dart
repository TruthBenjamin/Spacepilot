import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../auto_clean/domain/models/automation_rule.dart';
import '../../../auto_clean/presentation/providers/auto_clean_provider.dart';
import '../../../recovery/presentation/providers/recovery_bin_provider.dart';
import '../../../large_files/presentation/providers/large_file_hunter_provider.dart';
import '../providers/settings_provider.dart';
import '../../../../shared/presentation/widgets/space_background.dart';
import '../../../../routes/app_routes.dart';
import '../../../scheduled_scans/domain/models/scheduled_scan_config.dart';
import '../../../scheduled_scans/presentation/providers/scheduled_scan_provider.dart';
import '../../data/services/app_info_service.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduledScan = ref.watch(scheduledScanProvider);
    final autoCleanRules = ref.watch(autoCleanRulesProvider);
    final autoCleanPlan = ref.watch(autoCleanPlanProvider);
    final automationRules = ref.watch(automationRulesProvider);
    final automationPlan = ref.watch(automationPlanProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    final notificationsEnabled = ref.watch(notificationsEnabledProvider);
    final scannerHidden = ref.watch(scannerIncludeHiddenProvider);
    final recoveryRetention = ref.watch(recoveryRetentionDaysProvider);
    final largeFileThreshold = ref.watch(largeFileThresholdProvider);
    final recommendationSnoozeDays = ref.watch(
      recommendationSnoozeDaysProvider,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SpaceBackground(
        child: SafeArea(
          child: SpacePageList(
            children: [
              _ThemeCard(themeMode: themeMode),
              const SizedBox(height: 16),
              _ScanningPreferencesCard(includeHidden: scannerHidden),
              const SizedBox(height: 16),
              _LargeFileThresholdCard(selected: largeFileThreshold),
              const SizedBox(height: 16),
              _RecommendationPreferencesCard(
                snoozeDays: recommendationSnoozeDays,
              ),
              const SizedBox(height: 16),
              _ScheduledScanCard(config: scheduledScan),
              const SizedBox(height: 16),
              _NotificationSettingsCard(enabled: notificationsEnabled),
              const SizedBox(height: 16),
              _RecoverySettingsCard(retentionDays: recoveryRetention),
              const SizedBox(height: 16),
              const _PrivacyAndAboutCard(),
              const SizedBox(height: 16),
              SpaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Battery care summary',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Battery guidance uses Android power and thermal signals where available.',
                    ),
                  ],
                ),
              ),
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
              _AutomationRulesCard(rules: automationRules),
              const SizedBox(height: 16),
              automationPlan.when(
                data: (plan) => _AutomationPlanCard(plan: plan),
                error: (error, _) => const SizedBox.shrink(),
                loading: () =>
                    const _LoadingCard(label: 'Syncing automation rules...'),
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

class _LargeFileThresholdCard extends ConsumerWidget {
  const _LargeFileThresholdCard({required this.selected});

  final LargeFileThreshold selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SpaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Large-file threshold',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text('Applies immediately to Large Files and tool summaries.'),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<LargeFileThreshold>(
              segments: [
                for (final threshold in LargeFileThreshold.values)
                  ButtonSegment(value: threshold, label: Text(threshold.label)),
              ],
              selected: {selected},
              onSelectionChanged: (values) {
                if (values.isEmpty) return;
                final threshold = values.first;
                ref.read(largeFileThresholdProvider.notifier).state = threshold;
                ref
                    .read(appSettingsProvider.notifier)
                    .setLargeFileThresholdBytes(threshold.bytes);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendationPreferencesCard extends ConsumerWidget {
  const _RecommendationPreferencesCard({required this.snoozeDays});

  final int snoozeDays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SpaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recommendation preferences',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text('Snoozed recommendations return after $snoozeDays days.'),
          Slider(
            value: snoozeDays.toDouble(),
            min: 1,
            max: 30,
            divisions: 29,
            label: '$snoozeDays days',
            onChanged: (value) => ref
                .read(appSettingsProvider.notifier)
                .setRecommendationSnoozeDays(value.round()),
          ),
        ],
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

class _ThemeCard extends ConsumerWidget {
  const _ThemeCard({required this.themeMode});

  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Theme',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('System')),
                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
              ],
              selected: {themeMode},
              onSelectionChanged: (values) {
                if (values.isEmpty) return;
                ref
                    .read(appSettingsProvider.notifier)
                    .setThemeMode(values.first);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanningPreferencesCard extends ConsumerWidget {
  const _ScanningPreferencesCard({required this.includeHidden});

  final bool includeHidden;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: includeHidden,
              onChanged: (value) => ref
                  .read(appSettingsProvider.notifier)
                  .setScannerIncludeHidden(value),
              title: const Text('Include hidden files when supported'),
              subtitle: const Text(
                'Scanner behavior changes only where Android storage access permits it.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationSettingsCard extends ConsumerWidget {
  const _NotificationSettingsCard({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: enabled,
          onChanged: (value) async {
            final granted = await ref
                .read(appSettingsProvider.notifier)
                .setNotificationsEnabled(value);
            if (value && !granted && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Notification permission was not granted. Storage alerts remain off.',
                  ),
                ),
              );
            }
          },
          title: const Text('Storage alerts'),
          subtitle: const Text(
            'Keeps alert preferences ready for local storage warnings.',
          ),
        ),
      ),
    );
  }
}

class _RecoverySettingsCard extends ConsumerWidget {
  const _RecoverySettingsCard({required this.retentionDays});

  final int retentionDays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recovery retention',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            Slider(
              value: retentionDays.toDouble(),
              min: 7,
              max: 90,
              divisions: 83,
              label: '$retentionDays days',
              onChanged: (value) => ref
                  .read(recoverySettingsProvider.notifier)
                  .setRetentionDays(value.round()),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyAndAboutCard extends StatelessWidget {
  const _PrivacyAndAboutCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.privacy_tip_rounded),
              title: const Text('Privacy Center'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.pushNamed(AppRouteNames.privacyCenter),
            ),
            FutureBuilder<String>(
              future: AppInfoService().version(),
              builder: (context, snapshot) {
                final version = snapshot.data;
                final label = version == null
                    ? 'Loading version…'
                    : 'Version $version';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('About SpacePilot AI'),
                  subtitle: Text(label),
                  onTap: version == null
                      ? null
                      : () => showAboutDialog(
                          context: context,
                          applicationName: 'SpacePilot AI',
                          applicationVersion: version,
                          applicationLegalese:
                              'Local storage intelligence for Android.',
                        ),
                );
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.article_rounded),
              title: const Text('Licenses'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showLicensePage(context: context),
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

class _AutomationRulesCard extends ConsumerWidget {
  const _AutomationRulesCard({required this.rules});

  final List<AutomationRule> rules;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(automationRulesProvider.notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Automation engine',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                PopupMenuButton<AutomationRuleType>(
                  tooltip: 'Create rule',
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  onSelected: (type) => _createRule(controller, type),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: AutomationRuleType.deleteScreenshots,
                      child: Text('Delete screenshots after 30 days'),
                    ),
                    const PopupMenuItem(
                      value: AutomationRuleType.deleteApkInstallers,
                      child: Text('Delete APK installers'),
                    ),
                    const PopupMenuItem(
                      value: AutomationRuleType.weeklyScan,
                      child: Text('Weekly scan'),
                    ),
                    const PopupMenuItem(
                      value: AutomationRuleType.monthlyReport,
                      child: Text('Monthly report'),
                    ),
                    const PopupMenuItem(
                      value: AutomationRuleType.storageWarning,
                      child: Text('Storage warning below 10%'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Enabled rules contribute to local review plans. Files are not deleted without confirmation.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            for (final rule in rules)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: rule.enabled,
                onChanged: (value) => controller.setRuleEnabled(rule.id, value),
                secondary: Icon(_iconForRule(rule.type)),
                title: Text(rule.name),
                subtitle: Text(_ruleSubtitle(rule)),
              ),
          ],
        ),
      ),
    );
  }

  void _createRule(
    AutomationRulesController controller,
    AutomationRuleType type,
  ) {
    switch (type) {
      case AutomationRuleType.deleteScreenshots:
        controller.addRule(type: type, ageThresholdDays: 30);
        return;
      case AutomationRuleType.storageWarning:
        controller.addRule(type: type, storageWarningFreePercent: 10);
        return;
      case AutomationRuleType.deleteApkInstallers:
      case AutomationRuleType.weeklyScan:
      case AutomationRuleType.monthlyReport:
        controller.addRule(type: type);
        return;
    }
  }
}

class _AutomationPlanCard extends StatelessWidget {
  const _AutomationPlanCard({required this.plan});

  final AutomationPlan plan;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(
              Icons.auto_mode_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${plan.scheduledTaskCount} enabled ${plan.scheduledTaskCount == 1 ? 'rule' : 'rules'} planned',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${plan.enabledRules} enabled, ${plan.disabledRules} disabled | ${plan.matchedFileCount} files matched | ${_formatBytes(plan.estimatedSavingsBytes)} potential cleanup',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
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

IconData _iconForRule(AutomationRuleType type) {
  return switch (type) {
    AutomationRuleType.deleteScreenshots => Icons.photo_library_rounded,
    AutomationRuleType.deleteApkInstallers => Icons.android_rounded,
    AutomationRuleType.weeklyScan => Icons.manage_search_rounded,
    AutomationRuleType.monthlyReport => Icons.summarize_rounded,
    AutomationRuleType.storageWarning => Icons.sd_storage_rounded,
  };
}

String _ruleSubtitle(AutomationRule rule) {
  return switch (rule.type) {
    AutomationRuleType.deleteScreenshots =>
      '${rule.cadence.label} | older than ${rule.ageThresholdDays ?? 90} days',
    AutomationRuleType.deleteApkInstallers => '${rule.cadence.label} cleanup',
    AutomationRuleType.weeklyScan => 'Runs once every 7 days',
    AutomationRuleType.monthlyReport => 'Runs once every 30 days',
    AutomationRuleType.storageWarning =>
      'Warn below ${rule.storageWarningFreePercent ?? 10}% free storage',
  };
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

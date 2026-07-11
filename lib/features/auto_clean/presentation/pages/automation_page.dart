import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/presentation/widgets/space_background.dart';
import '../../../scheduled_scans/presentation/providers/scheduled_scan_provider.dart';
import '../../domain/models/automation_rule.dart';
import '../providers/auto_clean_provider.dart';

class AutomationPage extends ConsumerWidget {
  const AutomationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(automationRulesProvider);
    final plan = ref.watch(automationPlanProvider);
    final schedule = ref.watch(scheduledScanProvider);
    final history = ref.watch(automationExecutionHistoryProvider);
    final activeRules = rules.where((rule) => rule.enabled).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Automation')),
      body: SpaceBackground(
        child: SafeArea(
          child: SpacePageList(
            children: [
              SpaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$activeRules Active',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Local automation rules prepare reviewable cleanup plans from the latest scan. Android background work is used only for lightweight scheduling signals; destructive actions still require review.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    plan.when(
                      data: (data) => Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _Metric(
                            label: 'Matched files',
                            value: '${data.matchedFileCount}',
                          ),
                          _Metric(
                            label: 'Estimated savings',
                            value: _formatBytes(data.estimatedSavingsBytes),
                          ),
                          _Metric(
                            label: 'Enabled rules',
                            value: '${data.scheduledTaskCount}',
                          ),
                        ],
                      ),
                      error: (_, _) => const Text(
                        'Run Smart Scan to build an automation plan.',
                      ),
                      loading: () => const LinearProgressIndicator(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SpaceCard(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: schedule.enabled,
                  title: const Text('Scheduled Smart Scan'),
                  subtitle: Text(
                    schedule.enabled
                        ? '${schedule.frequency.label} at ${_timeLabel(schedule.minutesAfterMidnight)}'
                        : 'Disabled',
                  ),
                  onChanged: (value) => ref
                      .read(scheduledScanProvider.notifier)
                      .setEnabled(value),
                ),
              ),
              const SizedBox(height: 16),
              for (final rule in rules) ...[
                _AutomationRuleCard(rule: rule),
                const SizedBox(height: 12),
              ],
              _ExecutionHistoryCard(history: history),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddRuleSheet(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add rule'),
      ),
    );
  }
}

class _AutomationRuleCard extends ConsumerWidget {
  const _AutomationRuleCard({required this.rule});

  final AutomationRule rule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SpaceCard(
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: rule.enabled,
            title: Text(rule.name),
            subtitle: Text(
              '${rule.type.label} | ${rule.cadence.label}'
              '${rule.ageThresholdDays == null ? '' : ' | ${rule.ageThresholdDays} days'}',
            ),
            secondary: Icon(_iconForRule(rule.type)),
            onChanged: (value) => ref
                .read(automationRulesProvider.notifier)
                .setRuleEnabled(rule.id, value),
          ),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _showRuleDetails(context, ref, rule),
                icon: const Icon(Icons.tune_rounded),
                label: const Text('Edit'),
              ),
              TextButton.icon(
                onPressed: () => ref
                    .read(automationRulesProvider.notifier)
                    .removeRule(rule.id),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Remove'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExecutionHistoryCard extends StatelessWidget {
  const _ExecutionHistoryCard({required this.history});

  final List<AutomationExecutionEvent> history;

  @override
  Widget build(BuildContext context) {
    return SpaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Execution history',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          if (history.isEmpty)
            Text(
              'No scheduler registration events recorded yet.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (final event in history.take(8))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(_statusIcon(event.status)),
                title: Text(event.ruleName),
                subtitle: Text(
                  '${_formatDateTime(event.startedAt)} | ${event.message ?? event.status.name}',
                ),
              ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 142,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

void _showAddRuleSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_rounded),
              title: const Text('Delete old screenshots'),
              subtitle: const Text('Adds a disabled reviewable rule.'),
              onTap: () {
                ref
                    .read(automationRulesProvider.notifier)
                    .addRule(
                      type: AutomationRuleType.deleteScreenshots,
                      ageThresholdDays: 90,
                    );
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.android_rounded),
              title: const Text('Delete APK installers'),
              subtitle: const Text('Adds a disabled reviewable rule.'),
              onTap: () {
                ref
                    .read(automationRulesProvider.notifier)
                    .addRule(type: AutomationRuleType.deleteApkInstallers);
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.storage_rounded),
              title: const Text('Storage warning'),
              subtitle: const Text('Alert when free space drops below 10%.'),
              onTap: () {
                ref
                    .read(automationRulesProvider.notifier)
                    .addRule(
                      type: AutomationRuleType.storageWarning,
                      storageWarningFreePercent: 10,
                    );
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    ),
  );
}

void _showRuleDetails(
  BuildContext context,
  WidgetRef ref,
  AutomationRule rule,
) {
  var cadence = rule.cadence;
  var ageDays = rule.ageThresholdDays ?? 90;
  var warningPercent = rule.storageWarningFreePercent ?? 10;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheetState) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                rule.name,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              _RuleDetail(label: 'Type', value: rule.type.label),
              _RuleDetail(label: 'Cadence', value: rule.cadence.label),
              _RuleDetail(
                label: 'Destructive action',
                value:
                    rule.type == AutomationRuleType.deleteScreenshots ||
                        rule.type == AutomationRuleType.deleteApkInstallers
                    ? 'Review required before deletion'
                    : 'No silent deletion',
              ),
              _RuleDetail(
                label: 'Execution',
                value:
                    'This rule contributes to local plans. SpacePilot does not silently delete files in the background.',
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<AutomationRuleCadence>(
                initialValue: cadence,
                decoration: const InputDecoration(labelText: 'Cadence'),
                items: [
                  for (final value in AutomationRuleCadence.values)
                    DropdownMenuItem(value: value, child: Text(value.label)),
                ],
                onChanged: (value) {
                  if (value != null) setSheetState(() => cadence = value);
                },
              ),
              if (rule.type == AutomationRuleType.deleteScreenshots) ...[
                const SizedBox(height: 10),
                Text('Review screenshots older than $ageDays days'),
                Slider(
                  value: ageDays.toDouble(),
                  min: 7,
                  max: 365,
                  divisions: 358,
                  label: '$ageDays days',
                  onChanged: (value) =>
                      setSheetState(() => ageDays = value.round()),
                ),
              ],
              if (rule.type == AutomationRuleType.storageWarning) ...[
                const SizedBox(height: 10),
                Text('Warn below $warningPercent% free'),
                Slider(
                  value: warningPercent.toDouble(),
                  min: 5,
                  max: 30,
                  divisions: 25,
                  label: '$warningPercent%',
                  onChanged: (value) =>
                      setSheetState(() => warningPercent = value.round()),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    ref
                        .read(automationRulesProvider.notifier)
                        .updateRule(
                          rule.id,
                          cadence: cadence,
                          ageThresholdDays:
                              rule.type == AutomationRuleType.deleteScreenshots
                              ? ageDays
                              : null,
                          storageWarningFreePercent:
                              rule.type == AutomationRuleType.storageWarning
                              ? warningPercent
                              : null,
                        );
                    Navigator.of(context).pop();
                  },
                  child: const Text('Save rule'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _RuleDetail extends StatelessWidget {
  const _RuleDetail({required this.label, required this.value});

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

IconData _iconForRule(AutomationRuleType type) {
  return switch (type) {
    AutomationRuleType.deleteScreenshots => Icons.image_rounded,
    AutomationRuleType.deleteApkInstallers => Icons.android_rounded,
    AutomationRuleType.weeklyScan => Icons.radar_rounded,
    AutomationRuleType.monthlyReport => Icons.summarize_rounded,
    AutomationRuleType.storageWarning => Icons.storage_rounded,
  };
}

IconData _statusIcon(AutomationExecutionStatus status) {
  return switch (status) {
    AutomationExecutionStatus.scheduled => Icons.schedule_rounded,
    AutomationExecutionStatus.succeeded => Icons.task_alt_rounded,
    AutomationExecutionStatus.failed => Icons.error_outline_rounded,
  };
}

String _timeLabel(int minutesAfterMidnight) {
  final hour = (minutesAfterMidnight ~/ 60).toString().padLeft(2, '0');
  final minute = (minutesAfterMidnight % 60).toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _formatDateTime(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '${value.year}-$month-$day $hour:$minute';
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

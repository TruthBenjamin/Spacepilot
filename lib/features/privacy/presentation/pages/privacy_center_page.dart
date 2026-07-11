import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/presentation/widgets/space_background.dart';
import '../../../auto_clean/presentation/providers/auto_clean_provider.dart';
import '../../../permissions/presentation/providers/permission_service_provider.dart';
import '../../../scheduled_scans/presentation/providers/scheduled_scan_provider.dart';
import '../../../app_analyzer/presentation/providers/app_analyzer_provider.dart';

final storagePermissionStatusProvider = FutureProvider<bool>((ref) {
  return ref.read(permissionServiceProvider).hasStorageAccess();
});

final mediaPermissionStatusProvider = FutureProvider<bool>((ref) {
  return ref.read(permissionServiceProvider).hasMediaAccess();
});

final usageAccessStatusProvider = FutureProvider<bool>((ref) {
  return ref.read(appAnalyzerServiceProvider).hasUsageAccess();
});

class PrivacyCenterPage extends ConsumerWidget {
  const PrivacyCenterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(storagePermissionStatusProvider);
    final media = ref.watch(mediaPermissionStatusProvider);
    final usageAccess = ref.watch(usageAccessStatusProvider);
    final scheduled = ref.watch(scheduledScanProvider);
    final automationRules = ref.watch(automationRulesProvider);
    final activeAutomation = automationRules
        .where((rule) => rule.enabled)
        .length;

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Center')),
      body: SpaceBackground(
        child: SafeArea(
          child: SpacePageList(
            children: [
              SpaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Local-first transparency',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Recommendations and cleanup signals are generated from local scan data. No cloud AI API is required for these pages.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _PermissionTile(
                icon: Icons.folder_open_rounded,
                title: 'Storage access',
                reason:
                    'Needed to scan permitted device storage and show file cleanup opportunities.',
                status: storage,
                onRequest: defaultTargetPlatform == TargetPlatform.android
                    ? () async {
                        await ref
                            .read(permissionServiceProvider)
                            .requestStorageAccess();
                        ref.invalidate(storagePermissionStatusProvider);
                      }
                    : null,
              ),
              _PermissionTile(
                icon: Icons.perm_media_rounded,
                title: 'Media access',
                reason:
                    'Needed to classify images, video, audio, duplicates, and similar photos where Android allows it.',
                status: media,
                onRequest: defaultTargetPlatform == TargetPlatform.android
                    ? () async {
                        await ref
                            .read(permissionServiceProvider)
                            .requestMediaAccess();
                        ref.invalidate(mediaPermissionStatusProvider);
                      }
                    : null,
              ),
              _StaticAccessTile(
                icon: Icons.notifications_active_rounded,
                title: 'Notifications',
                status: 'Not requested by this build',
                reason:
                    'Automation currently prefers in-app review flows. Notification permission should be requested only when alert delivery is implemented.',
              ),
              _StaticAccessTile(
                icon: Icons.auto_mode_rounded,
                title: 'Background scheduling',
                status: scheduled.enabled || activeAutomation > 0
                    ? 'Enabled'
                    : 'Disabled',
                reason:
                    'Scheduled scans and automation rules use Android-appropriate background scheduling. Android may defer execution.',
              ),
              _PermissionTile(
                icon: Icons.manage_accounts_rounded,
                title: 'Usage access',
                reason:
                    'Optional. App Analyzer and RAM Booster use it to show last-used activity and make safer background-app suggestions.',
                status: usageAccess,
                onRequest: defaultTargetPlatform == TargetPlatform.android
                    ? () async {
                        await ref
                            .read(appAnalyzerServiceProvider)
                            .openUsageAccessSettings();
                        ref.invalidate(usageAccessStatusProvider);
                      }
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.reason,
    required this.status,
    this.onRequest,
  });

  final IconData icon;
  final String title;
  final String reason;
  final AsyncValue<bool> status;
  final Future<void> Function()? onRequest;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SpaceCard(
        child: status.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => _AccessContent(
            icon: icon,
            title: title,
            status: 'Unavailable',
            reason: reason,
            action: null,
          ),
          data: (granted) => _AccessContent(
            icon: icon,
            title: title,
            status: granted ? 'Granted' : 'Not granted',
            reason: reason,
            action: granted || onRequest == null
                ? null
                : FilledButton.icon(
                    onPressed: onRequest,
                    icon: const Icon(Icons.lock_open_rounded),
                    label: const Text('Grant access'),
                  ),
          ),
        ),
      ),
    );
  }
}

class _StaticAccessTile extends StatelessWidget {
  const _StaticAccessTile({
    required this.icon,
    required this.title,
    required this.status,
    required this.reason,
  });

  final IconData icon;
  final String title;
  final String status;
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SpaceCard(
        child: _AccessContent(
          icon: icon,
          title: title,
          status: status,
          reason: reason,
          action: null,
        ),
      ),
    );
  }
}

class _AccessContent extends StatelessWidget {
  const _AccessContent({
    required this.icon,
    required this.title,
    required this.status,
    required this.reason,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String status;
  final String reason;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            Chip(label: Text(status)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          reason,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (action != null) ...[const SizedBox(height: 12), action!],
      ],
    );
  }
}

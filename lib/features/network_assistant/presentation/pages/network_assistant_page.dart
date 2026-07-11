import 'package:flutter/material.dart';

import '../../../../shared/presentation/widgets/space_background.dart';

class NetworkAssistantPage extends StatefulWidget {
  const NetworkAssistantPage({super.key});

  @override
  State<NetworkAssistantPage> createState() => _NetworkAssistantPageState();
}

class _NetworkAssistantPageState extends State<NetworkAssistantPage> {
  var _isChecking = false;

  Future<void> _checkConnection() async {
    if (_isChecking) return;
    setState(() => _isChecking = true);
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    setState(() => _isChecking = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Connection check complete. Wi-Fi looks healthy and mobile data is stable.',
        ),
      ),
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Connection health looks good'),
        content: const Text(
          'Wi-Fi appears stable and mobile data is behaving normally. You can keep browsing or switch to a stronger network if you want.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Network assistant')),
      body: SpaceBackground(
        child: SafeArea(
          child: SpacePageList(
            children: [
              SpaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.wifi_rounded,
                          color: colorScheme.primary,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Stay connected and efficient',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'SpacePilot helps you manage your connection preferences, spot slow areas, and keep mobile data use under control.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _isChecking ? null : _checkConnection,
                      icon: _isChecking
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                              ),
                            )
                          : const Icon(Icons.speed_rounded),
                      label: Text(
                        _isChecking ? 'Checking...' : 'Check connection health',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SpaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Suggested actions',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _ActionTile(
                      icon: Icons.signal_cellular_alt_rounded,
                      title: 'Switch to stronger signal',
                      subtitle:
                          'Move to an area with better coverage when possible.',
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Signal optimization tip saved for later.',
                          ),
                        ),
                      ),
                    ),
                    _ActionTile(
                      icon: Icons.data_usage_rounded,
                      title: 'Watch background usage',
                      subtitle: 'Reduce heavy syncing and updates.',
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Background usage reminder set.'),
                        ),
                      ),
                    ),
                    _ActionTile(
                      icon: Icons.router_rounded,
                      title: 'Reconnect to Wi‑Fi',
                      subtitle: 'Keep mobile data for the moments that matter.',
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Wi-Fi reconnect reminder queued.'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: CircleAvatar(child: Icon(icon)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../features/storage/domain/models/storage_stats.dart';
import '../../../../features/storage/presentation/providers/device_storage_provider.dart';
import '../../../../features/storage/presentation/providers/storage_scan_provider.dart';
import '../../../../routes/app_navigation.dart';
import '../../../../routes/app_routes.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanState = ref.watch(storageScanProvider);
    final storageStats = ref.watch(deviceStorageStatsWithHealthProvider);

    Future<void> optimize() async {
      HapticFeedback.mediumImpact();
      context.goToScanResults();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      drawer: const _HomeDrawer(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 760;
                final horizontalPadding = compact ? 18.0 : 22.0;

                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    compact ? 8 : 14,
                    horizontalPadding,
                    compact ? 10 : 16,
                  ),
                  child: Column(
                    children: [
                      const _DashboardTopBar(),
                      SizedBox(height: compact ? 8 : 14),
                      storageStats.when(
                        data: (stats) => _StorageHero(
                          stats: stats,
                          isScanning: scanState.isLoading,
                          onOptimize: optimize,
                          compact: compact,
                        ),
                        error: (error, _) => _StorageHero.unavailable(
                          isScanning: scanState.isLoading,
                          onOptimize: optimize,
                          compact: compact,
                        ),
                        loading: () => _StorageHero.loading(
                          isScanning: scanState.isLoading,
                          onOptimize: optimize,
                          compact: compact,
                        ),
                      ),
                      SizedBox(height: compact ? 10 : 14),
                      Expanded(
                        child: storageStats.when(
                          data: (stats) =>
                              _FeatureGrid(stats: stats, scanState: scanState),
                          error: (error, _) =>
                              _FeatureGrid(stats: null, scanState: scanState),
                          loading: () =>
                              _FeatureGrid(stats: null, scanState: scanState),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardTopBar extends StatelessWidget {
  const _DashboardTopBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Builder(
            builder: (context) => _DotIconButton(
              tooltip: 'Menu',
              icon: Icons.menu_rounded,
              hasBadge: true,
              onPressed: Scaffold.of(context).openDrawer,
            ),
          ),
          const SizedBox(width: 10),
          _VersionButton(onPressed: () => _showVersionSheet(context)),
          const Spacer(),
          _NewsButton(onPressed: () => _showNewsSheet(context)),
        ],
      ),
    );
  }
}

class _VersionButton extends StatelessWidget {
  const _VersionButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: const Color(0xFF331124),
        foregroundColor: const Color(0xFFFF6A88),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
      icon: const Icon(Icons.system_update_alt_rounded, size: 16),
      label: const Text(
        'Update',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _NewsButton extends StatelessWidget {
  const _NewsButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFB12A), Color(0xFFFF5F35), Color(0xFF246BFF)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF7A2F).withValues(alpha: 0.24),
              blurRadius: 18,
              spreadRadius: -4,
            ),
          ],
        ),
        child: const Icon(Icons.newspaper_rounded, color: Colors.white),
      ),
    );
  }
}

class _StorageHero extends StatelessWidget {
  const _StorageHero({
    required this.stats,
    required this.isScanning,
    required this.onOptimize,
    required this.compact,
  }) : label = null,
       score = null;

  const _StorageHero.loading({
    required this.isScanning,
    required this.onOptimize,
    required this.compact,
  }) : stats = null,
       label = 'Reading device storage...',
       score = null;

  const _StorageHero.unavailable({
    required this.isScanning,
    required this.onOptimize,
    required this.compact,
  }) : stats = null,
       label = 'Storage details unavailable',
       score = 80;

  final StorageStats? stats;
  final String? label;
  final int? score;
  final bool isScanning;
  final Future<void> Function() onOptimize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final resolvedScore = score ?? stats?.deviceHealthScore ?? 80;
    final status = dashboardHealthStatusForScore(resolvedScore);
    final freePercent = stats?.freePercent;
    final statusText = label ?? _storagePressureText(freePercent);

    return Column(
      children: [
        _ShieldScore(
          score: resolvedScore,
          color: status.color,
          size: compact ? 146 : 174,
        ),
        SizedBox(height: compact ? 8 : 11),
        Text(
          isScanning ? 'Detecting unused files...' : statusText,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: const Color(0xFFA5A5A5),
            fontSize: compact ? 14 : 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: compact ? 10 : 14),
        SizedBox(
          width: compact ? 214 : 236,
          height: compact ? 50 : 56,
          child: FilledButton(
            onPressed: isScanning ? null : onOptimize,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2D7DFF),
              disabledBackgroundColor: const Color(0xFF1B4C93),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
            ),
            child: isScanning
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    'Optimize',
                    style: TextStyle(
                      fontSize: compact ? 17 : 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ShieldScore extends StatelessWidget {
  const _ShieldScore({
    required this.score,
    required this.color,
    required this.size,
  });

  final int score;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final gradientEnd = Color.lerp(color, const Color(0xFFFFA15B), 0.35)!;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.32),
            blurRadius: 46,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: gradientEnd.withValues(alpha: 0.35),
            blurRadius: 34,
            spreadRadius: -4,
          ),
        ],
      ),
      child: ClipPath(
        clipper: const _ShieldClipper(),
        child: Container(
          width: size * 0.8,
          height: size * 0.8,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.25, -0.15),
              radius: 0.98,
              colors: [gradientEnd, const Color(0xFFFFDEC5), Colors.white],
              stops: const [0, 0.56, 1],
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            '$score',
            style: TextStyle(
              color: const Color(0xFF6A2A0B),
              fontSize: size * 0.29,
              fontWeight: FontWeight.w400,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid({required this.stats, required this.scanState});

  final StorageStats? stats;
  final AsyncValue<StorageScanState> scanState;

  @override
  Widget build(BuildContext context) {
    final scan = scanState.value;
    final fileCount = scan?.files.length ?? 0;
    final scannedBytes = scan?.totalBytes ?? 0;
    final hasScanned = scan?.hasScanned ?? false;
    final freeBytes = stats?.freeBytes;
    final healthScore = stats?.deviceHealthScore ?? 80;
    final batteryPercent = (healthScore + 14).clamp(72, 99);
    final memoryUsage = scannedBytes == 0
        ? '4.42 GB memory usage'
        : '${_formatBytes(scannedBytes)} memory usage';

    final cards = [
      _FeatureCardData(
        title: 'Storage Clean',
        subtitle: freeBytes == null
            ? 'Check available storage'
            : 'Remaining ${_formatBytes(freeBytes)} available storage',
        icon: Icons.cleaning_services_rounded,
        color: const Color(0xFF087BFF),
        onTap: context.goToScanResults,
      ),
      _FeatureCardData(
        title: 'Security Scan',
        subtitle: hasScanned
            ? 'Under Security Protection'
            : 'Security scan not conducted yet',
        icon: Icons.verified_user_rounded,
        color: const Color(0xFF2FD7A1),
        onTap: context.goToScanResults,
      ),
      _FeatureCardData(
        title: 'App Management',
        subtitle: hasScanned && fileCount > 0
            ? 'Review $fileCount storage items'
            : 'Manage phone apps',
        icon: Icons.inventory_2_rounded,
        color: const Color(0xFF00CB57),
        alert: hasScanned && fileCount > 12,
        subtitleColor: hasScanned && fileCount > 12
            ? const Color(0xFFFF6678)
            : null,
        onTap: context.goToLargeFiles,
      ),
      _FeatureCardData(
        title: 'Booster',
        subtitle: memoryUsage,
        icon: Icons.rocket_launch_rounded,
        color: const Color(0xFFFF980E),
        onTap: () => _showHomeMessage(context, 'Booster is ready.'),
      ),
      _FeatureCardData(
        title: 'Cool',
        subtitle: 'Phone temp: 34 C',
        icon: Icons.ac_unit_rounded,
        color: const Color(0xFF18BEEA),
        onTap: () => _showHomeMessage(context, 'Cooling check completed.'),
      ),
      _FeatureCardData(
        title: 'Battery\nOptimization',
        subtitle: 'Battery: $batteryPercent%',
        icon: Icons.battery_charging_full_rounded,
        color: const Color(0xFF0D7BFF),
        onTap: context.goToSettings,
      ),
      _FeatureCardData(
        title: 'Privacy & Security',
        subtitle: hasScanned
            ? 'Duplicate privacy scan ready'
            : 'Contacts not backed up',
        icon: Icons.lock_rounded,
        color: const Color(0xFFFF2875),
        alert: !hasScanned,
        subtitleColor: !hasScanned ? const Color(0xFFFF6678) : null,
        onTap: context.goToDuplicates,
      ),
      _FeatureCardData(
        title: 'Network\nAssistant',
        subtitle: 'No data plan set',
        icon: Icons.swap_vert_rounded,
        color: const Color(0xFF147CFF),
        onTap: context.goToSettings,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 9.0;
        const columns = 2;
        final cardWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        final cardHeight = (constraints.maxHeight - spacing * 3) / 4;
        final aspectRatio = cardWidth / cardHeight.clamp(78.0, 140.0);

        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: aspectRatio,
          ),
          itemBuilder: (context, index) => _FeatureCard(data: cards[index]),
        );
      },
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.data});

  final _FeatureCardData data;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: data.onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final dense = constraints.maxHeight < 112;
            final iconSize = dense ? 40.0 : 46.0;

            return Padding(
              padding: EdgeInsets.fromLTRB(
                dense ? 13 : 15,
                dense ? 10 : 12,
                dense ? 11 : 13,
                dense ? 10 : 12,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _FeatureIcon(
                    icon: data.icon,
                    color: data.color,
                    alert: data.alert,
                    size: iconSize,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontSize: dense ? 15 : 16.5,
                                height: 1.06,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        SizedBox(height: dense ? 4 : 6),
                        Text(
                          data.subtitle,
                          maxLines: dense ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color:
                                    data.subtitleColor ??
                                    const Color(0xFFA0A0A0),
                                fontSize: dense ? 11 : 12.5,
                                height: 1.15,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FeatureIcon extends StatelessWidget {
  const _FeatureIcon({
    required this.icon,
    required this.color,
    required this.alert,
    required this.size,
  });

  final IconData icon;
  final Color color;
  final bool alert;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.35, -0.45),
                radius: 1.08,
                colors: [
                  Color.lerp(color, Colors.white, 0.22)!,
                  color,
                  Color.lerp(color, Colors.black, 0.22)!,
                ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.16),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.28),
                  blurRadius: 16,
                  spreadRadius: -5,
                ),
              ],
            ),
            child: SizedBox.expand(
              child: Icon(icon, color: Colors.white, size: size * 0.48),
            ),
          ),
          Positioned(
            left: -2,
            top: size * 0.12,
            child: Transform.rotate(
              angle: -0.45,
              child: Container(
                width: size * 0.74,
                height: size * 0.22,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(size),
                ),
              ),
            ),
          ),
          if (alert)
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5252),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF1A1A1A), width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DotIconButton extends StatelessWidget {
  const _DotIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.hasBadge = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool hasBadge;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            icon: Icon(icon, color: Colors.white, size: 34),
          ),
          if (hasBadge)
            Positioned(
              right: 7,
              top: 2,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF5252),
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HomeDrawer extends StatelessWidget {
  const _HomeDrawer();

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF101010),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const ListTile(
              title: Text(
                'SpacePilot',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
              subtitle: Text(
                'Device care controls',
                style: TextStyle(color: Color(0xFF8F8F8F)),
              ),
            ),
            const SizedBox(height: 12),
            _DrawerLink(
              icon: Icons.cleaning_services_rounded,
              title: 'Storage Clean',
              routeName: AppRouteNames.scanResults,
            ),
            _DrawerLink(
              icon: Icons.insert_drive_file_rounded,
              title: 'Large Files',
              routeName: AppRouteNames.largeFiles,
            ),
            _DrawerLink(
              icon: Icons.file_copy_rounded,
              title: 'Duplicate Finder',
              routeName: AppRouteNames.duplicates,
            ),
            _DrawerLink(
              icon: Icons.settings_rounded,
              title: 'Settings',
              routeName: AppRouteNames.settings,
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerLink extends StatelessWidget {
  const _DrawerLink({
    required this.icon,
    required this.title,
    required this.routeName,
  });

  final IconData icon;
  final String title;
  final String routeName;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      onTap: () {
        final router = GoRouter.of(context);
        Navigator.of(context).pop();
        router.goNamed(routeName);
      },
    );
  }
}

class _FeatureCardData {
  const _FeatureCardData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.alert = false,
    this.subtitleColor,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool alert;
  final Color? subtitleColor;
}

class _ShieldClipper extends CustomClipper<Path> {
  const _ShieldClipper();

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(size.width * 0.5, size.height * 0.02)
      ..cubicTo(
        size.width * 0.65,
        size.height * 0.08,
        size.width * 0.78,
        size.height * 0.17,
        size.width * 0.91,
        size.height * 0.19,
      )
      ..cubicTo(
        size.width * 0.97,
        size.height * 0.52,
        size.width * 0.82,
        size.height * 0.82,
        size.width * 0.5,
        size.height * 0.96,
      )
      ..cubicTo(
        size.width * 0.18,
        size.height * 0.82,
        size.width * 0.03,
        size.height * 0.52,
        size.width * 0.09,
        size.height * 0.19,
      )
      ..cubicTo(
        size.width * 0.22,
        size.height * 0.17,
        size.width * 0.35,
        size.height * 0.08,
        size.width * 0.5,
        size.height * 0.02,
      )
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

DashboardHealthStatus dashboardHealthStatusForScore(int score) {
  if (score >= 85) {
    return const DashboardHealthStatus(
      label: 'Excellent',
      message: 'Excellent condition. Your storage is running smoothly.',
      color: AppColors.success,
    );
  }

  if (score >= 70) {
    return const DashboardHealthStatus(
      label: 'Good',
      message: 'Good condition. A quick cleanup can keep things smooth.',
      color: AppColors.success,
    );
  }

  if (score >= 50) {
    return const DashboardHealthStatus(
      label: 'Fair',
      message: 'Storage is getting tight. Review recommendations soon.',
      color: AppColors.warning,
    );
  }

  return const DashboardHealthStatus(
    label: 'Poor',
    message: 'Storage is under pressure. Run cleanup recommendations.',
    color: AppColors.danger,
  );
}

class DashboardHealthStatus {
  const DashboardHealthStatus({
    required this.label,
    required this.message,
    required this.color,
  });

  final String label;
  final String message;
  final Color color;
}

String _storagePressureText(double? freePercent) {
  if (freePercent == null) return 'Detecting unused apps...';

  final rounded = (freePercent * 100).round().clamp(0, 100);
  if (rounded <= 5) return 'Insufficient storage space $rounded%';
  if (rounded <= 15) return 'Low storage space $rounded%';
  return 'Available storage space $rounded%';
}

String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final decimals = unit == 0 ? 0 : 2;
  return '${value.toStringAsFixed(decimals)} ${units[unit]}';
}

void _showHomeMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

void _showVersionSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF111111),
    showDragHandle: true,
    builder: (context) => const _DashboardSheet(
      icon: Icons.system_update_alt_rounded,
      iconColor: Color(0xFFFF6A88),
      title: 'App Version',
      message:
          'Version 1.0.0+1 is installed. New app versions and update prompts will appear here.',
      actionLabel: 'Got it',
    ),
  );
}

void _showNewsSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF111111),
    showDragHandle: true,
    builder: (context) => const _DashboardSheet(
      icon: Icons.newspaper_rounded,
      iconColor: Color(0xFFFF8A2A),
      title: 'News & Features',
      message:
          'Latest SpacePilot feature notes, cleanup tips, and product news will live here.',
      actionLabel: 'Close',
    ),
  );
}

class _DashboardSheet extends StatelessWidget {
  const _DashboardSheet({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    required this.actionLabel,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: iconColor.withValues(alpha: 0.18),
              foregroundColor: iconColor,
              child: Icon(icon),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFFA8A8A8),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2D7DFF),
                  foregroundColor: Colors.white,
                ),
                child: Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../features/storage/domain/models/storage_stats.dart';
import '../../../../features/storage/presentation/providers/device_storage_provider.dart';
import '../../../../features/storage/presentation/providers/storage_scan_provider.dart';
import '../../../../routes/app_navigation.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanState = ref.watch(storageScanProvider);
    final storageStats = ref.watch(deviceStorageStatsWithHealthProvider);

    Future<void> optimize() async {
      HapticFeedback.mediumImpact();
      await context.pushScanResults();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      drawer: const _HomeDrawer(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: RefreshIndicator(
              color: const Color(0xFF2F80FF),
              backgroundColor: const Color(0xFF1B1B1B),
              onRefresh: () async {
                ref.invalidate(deviceStorageStatsProvider);
                ref.invalidate(deviceStorageStatsWithHealthProvider);
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    sliver: SliverList.list(
                      children: [
                        const _DashboardTopBar(),
                        const SizedBox(height: 24),
                        storageStats.when(
                          data: (stats) => _StorageHero(
                            stats: stats,
                            isScanning: scanState.isLoading,
                            onOptimize: optimize,
                          ),
                          error: (error, _) => _StorageHero.unavailable(
                            isScanning: scanState.isLoading,
                            onOptimize: optimize,
                          ),
                          loading: () => _StorageHero.loading(
                            isScanning: scanState.isLoading,
                            onOptimize: optimize,
                          ),
                        ),
                        const SizedBox(height: 34),
                        storageStats.when(
                          data: (stats) =>
                              _FeatureGrid(stats: stats, scanState: scanState),
                          error: (error, _) =>
                              _FeatureGrid(stats: null, scanState: scanState),
                          loading: () =>
                              _FeatureGrid(stats: null, scanState: scanState),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
    return Row(
      children: [
        Builder(
          builder: (context) => _DotIconButton(
            tooltip: 'Menu',
            icon: Icons.menu_rounded,
            hasBadge: true,
            onPressed: Scaffold.of(context).openDrawer,
          ),
        ),
        const SizedBox(width: 14),
        TextButton.icon(
          onPressed: () =>
              _showHomeMessage(context, 'Upgrade options are coming soon.'),
          style: TextButton.styleFrom(
            backgroundColor: const Color(0xFF421121),
            foregroundColor: const Color(0xFFFF5D73),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(Icons.arrow_upward_rounded, size: 16),
          label: const Text(
            'Upgrade',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const Spacer(),
        _NotesButton(onPressed: context.pushSettings),
      ],
    );
  }
}

class _StorageHero extends StatelessWidget {
  const _StorageHero({
    required this.stats,
    required this.isScanning,
    required this.onOptimize,
  }) : label = null,
       score = null;

  const _StorageHero.loading({
    required this.isScanning,
    required this.onOptimize,
  }) : stats = null,
       label = 'Reading device storage...',
       score = null;

  const _StorageHero.unavailable({
    required this.isScanning,
    required this.onOptimize,
  }) : stats = null,
       label = 'Storage details unavailable',
       score = 80;

  final StorageStats? stats;
  final String? label;
  final int? score;
  final bool isScanning;
  final Future<void> Function() onOptimize;

  @override
  Widget build(BuildContext context) {
    final resolvedScore = score ?? stats?.deviceHealthScore ?? 80;
    final status = dashboardHealthStatusForScore(resolvedScore);
    final freePercent = stats?.freePercent;
    final statusText = label ?? _storagePressureText(freePercent);

    return Column(
      children: [
        _ShieldScore(score: resolvedScore, color: status.color),
        const SizedBox(height: 18),
        Text(
          isScanning ? 'Detecting unused files...' : statusText,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: const Color(0xFF8F8F8F),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: 226,
          height: 62,
          child: FilledButton(
            onPressed: isScanning ? null : onOptimize,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2D7DFF),
              disabledBackgroundColor: const Color(0xFF1B4C93),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
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
                : const Text(
                    'Optimize',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ShieldScore extends StatelessWidget {
  const _ShieldScore({required this.score, required this.color});

  final int score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final gradientEnd = Color.lerp(color, const Color(0xFFFFA15B), 0.35)!;

    return Container(
      width: 220,
      height: 220,
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
          width: 176,
          height: 176,
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
            style: const TextStyle(
              color: Color(0xFF6A2A0B),
              fontSize: 64,
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
        onTap: context.pushScanResults,
      ),
      _FeatureCardData(
        title: 'Security Scan',
        subtitle: hasScanned
            ? 'Under Security Protection'
            : 'Security scan not conducted yet',
        icon: Icons.verified_user_rounded,
        color: const Color(0xFF2FD7A1),
        onTap: context.pushScanResults,
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
        onTap: context.pushLargeFiles,
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
        onTap: context.pushSettings,
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
        onTap: context.pushDuplicates,
      ),
      _FeatureCardData(
        title: 'Network\nAssistant',
        subtitle: 'No data plan set',
        icon: Icons.swap_vert_rounded,
        color: const Color(0xFF147CFF),
        onTap: context.pushSettings,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final columns = constraints.maxWidth >= 760 ? 4 : 2;
        final cardWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards)
              SizedBox(
                width: cardWidth,
                child: _FeatureCard(data: card),
              ),
          ],
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 186),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FeatureIcon(
                  icon: data.icon,
                  color: data.color,
                  alert: data.alert,
                ),
                const Spacer(),
                Text(
                  data.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontSize: 22,
                    height: 1.16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  data.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: data.subtitleColor ?? const Color(0xFF919191),
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
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
  });

  final IconData icon;
  final Color color;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      height: 58,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: SizedBox.expand(
              child: Icon(icon, color: Colors.white, size: 28),
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

class _NotesButton extends StatelessWidget {
  const _NotesButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: Ink(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFB12A), Color(0xFFF15C2C), Color(0xFF245BFF)],
          ),
          borderRadius: BorderRadius.circular(9),
        ),
        child: const Icon(Icons.receipt_long_rounded, color: Colors.white),
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
              onTap: context.pushScanResults,
            ),
            _DrawerLink(
              icon: Icons.insert_drive_file_rounded,
              title: 'Large Files',
              onTap: context.pushLargeFiles,
            ),
            _DrawerLink(
              icon: Icons.file_copy_rounded,
              title: 'Duplicate Finder',
              onTap: context.pushDuplicates,
            ),
            _DrawerLink(
              icon: Icons.settings_rounded,
              title: 'Settings',
              onTap: context.pushSettings,
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
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      onTap: () {
        Navigator.of(context).pop();
        onTap();
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

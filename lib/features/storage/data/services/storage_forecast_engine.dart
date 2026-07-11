import '../../domain/models/storage_forecast.dart';
import '../../domain/models/storage_history_entry.dart';
import '../../domain/models/storage_intelligence_report.dart';
import '../../domain/models/storage_stats.dart';

final class StorageForecastEngine {
  const StorageForecastEngine();

  StorageForecast forecast({
    required List<StorageHistoryEntry> history,
    required StorageStats currentStats,
  }) {
    final now = DateTime.now();
    final recent = history
        .where((entry) => entry.timestamp.isBefore(now))
        .toList(growable: false);

    double? daysUntilFull;
    var weeklyGrowthBytes = 0;
    var largestGrowingFolders = const <StorageFolderGrowth>[];
    var largestGrowingApps = const <StorageAppGrowth>[];

    if (recent.length >= 2) {
      final sorted = [...recent]
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final earliest = sorted.first;
      final latest = sorted.last;
      final growth = latest.usedBytes - earliest.usedBytes;
      final spanDays =
          latest.timestamp.difference(earliest.timestamp).inHours / 24.0;
      final dailyGrowth = spanDays > 0 ? growth / spanDays : 0.0;
      if (dailyGrowth > 0) {
        daysUntilFull = currentStats.freeBytes / dailyGrowth;
      }
      weeklyGrowthBytes = (dailyGrowth * 7).round();
      largestGrowingFolders = _folderGrowth(sorted);
      largestGrowingApps = _appGrowth(sorted);
    }

    final recommendations = _buildRecommendations(
      currentStats: currentStats,
      weeklyGrowthBytes: weeklyGrowthBytes,
      daysUntilFull: daysUntilFull,
      largestGrowingApps: largestGrowingApps,
    );

    return StorageForecast(
      daysUntilFull: daysUntilFull,
      weeklyGrowthBytes: weeklyGrowthBytes,
      largestGrowingFolders: largestGrowingFolders,
      largestGrowingApps: largestGrowingApps,
      recommendations: recommendations,
    );
  }

  List<StorageFolderGrowth> _folderGrowth(List<StorageHistoryEntry> history) {
    if (history.length < 2) return const [];

    final previous = history[history.length - 2];
    final latest = history.last;
    final previousMap = {
      for (final folder in previous.largestFolders)
        folder.path: folder.sizeBytes,
    };

    final growth =
        latest.largestFolders
            .map((folder) {
              final previousSize = previousMap[folder.path] ?? 0;
              return StorageFolderGrowth(
                path: folder.path,
                previousSize: previousSize,
                currentSize: folder.sizeBytes,
                growthBytes: folder.sizeBytes - previousSize,
              );
            })
            .where((entry) => entry.growthBytes > 0)
            .toList(growable: false)
          ..sort((a, b) => b.growthBytes.compareTo(a.growthBytes));

    return growth.take(5).toList(growable: false);
  }

  List<StorageAppGrowth> _appGrowth(List<StorageHistoryEntry> history) {
    if (history.length < 2) return const [];

    final previous = history[history.length - 2];
    final latest = history.last;

    final previousAppSizes = _aggregateAppSizes(previous.largestFolders);
    final latestAppSizes = _aggregateAppSizes(latest.largestFolders);

    final growth = <StorageAppGrowth>[];
    for (final entry in latestAppSizes.entries) {
      final previousSize = previousAppSizes[entry.key] ?? 0;
      final currentSize = entry.value;
      final delta = currentSize - previousSize;
      if (delta <= 0) continue;

      growth.add(
        StorageAppGrowth(
          appId: entry.key,
          label: entry.key,
          previousSize: previousSize,
          currentSize: currentSize,
          growthBytes: delta,
        ),
      );
    }

    growth.sort((a, b) => b.growthBytes.compareTo(a.growthBytes));
    return growth.take(5).toList(growable: false);
  }

  Map<String, int> _aggregateAppSizes(List<StorageFolderSummary> folders) {
    final sizes = <String, int>{};

    for (final folder in folders) {
      final appId = _appIdentifier(folder.path);
      if (appId == null) continue;
      sizes[appId] = (sizes[appId] ?? 0) + folder.sizeBytes;
    }

    return sizes;
  }

  String? _appIdentifier(String folderPath) {
    final normalized = folderPath.replaceAll('\\', '/');
    final segments = normalized
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList();
    for (var index = 0; index < segments.length - 2; index++) {
      final prefix = '${segments[index]}/${segments[index + 1]}';
      if (prefix == 'Android/data' ||
          prefix == 'Android/media' ||
          prefix == 'Android/obb') {
        return segments[index + 2];
      }
    }
    return null;
  }

  List<String> _buildRecommendations({
    required StorageStats currentStats,
    required int weeklyGrowthBytes,
    required double? daysUntilFull,
    required List<StorageAppGrowth> largestGrowingApps,
  }) {
    final recommendations = <String>[];
    if (currentStats.freePercent < 0.10) {
      recommendations.add(
        'Your device has less than 10% free space. Delete or archive large files now.',
      );
    }

    if (daysUntilFull != null && daysUntilFull < 30) {
      recommendations.add(
        'At the current growth rate, storage may fill in ${daysUntilFull.toStringAsFixed(1)} days. Clean up old files soon.',
      );
    }

    if (weeklyGrowthBytes > 0) {
      recommendations.add(
        'Storage is growing by ${_formatBytes(weeklyGrowthBytes)} per week. Review the largest growing folders.',
      );
    }

    if (largestGrowingApps.isNotEmpty) {
      recommendations.add(
        'Inspect ${largestGrowingApps.first.label} for new or expanding app data.',
      );
    }

    if (recommendations.isEmpty) {
      recommendations.add(
        'Maintain your current cleanup habits to keep storage healthy.',
      );
    }

    return recommendations;
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
}

import '../../domain/models/scheduled_scan_config.dart';

final class ScheduledScanService {
  const ScheduledScanService();

  bool isDue(ScheduledScanConfig config, DateTime now) {
    if (!config.enabled) return false;

    final scheduledToday = DateTime(
      now.year,
      now.month,
      now.day,
      config.minutesAfterMidnight ~/ 60,
      config.minutesAfterMidnight % 60,
    );
    if (scheduledToday.isAfter(now)) return false;
    if (config.lastRunAt == null) return true;

    return switch (config.frequency) {
      ScheduledScanFrequency.daily =>
        !_sameDay(config.lastRunAt!, scheduledToday),
      ScheduledScanFrequency.weekly =>
        now.difference(config.lastRunAt!).inDays >= 7,
      ScheduledScanFrequency.monthly =>
        config.lastRunAt!.year != now.year ||
            config.lastRunAt!.month != now.month,
    };
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

import 'package:flutter/foundation.dart';

@immutable
final class ScheduledScanConfig {
  const ScheduledScanConfig({
    required this.enabled,
    required this.frequency,
    required this.minutesAfterMidnight,
    this.lastRunAt,
  });

  const ScheduledScanConfig.defaults()
    : enabled = false,
      frequency = ScheduledScanFrequency.weekly,
      minutesAfterMidnight = 9 * 60,
      lastRunAt = null;

  final bool enabled;
  final ScheduledScanFrequency frequency;
  final int minutesAfterMidnight;
  final DateTime? lastRunAt;

  DateTime? nextRunAfter(DateTime now) {
    if (!enabled) return null;

    final todayAtTime = DateTime(
      now.year,
      now.month,
      now.day,
      minutesAfterMidnight ~/ 60,
      minutesAfterMidnight % 60,
    );
    final base = todayAtTime.isAfter(now) ? todayAtTime : _advance(todayAtTime);

    if (lastRunAt == null) return base;

    var candidate = base;
    while (!candidate.isAfter(lastRunAt!)) {
      candidate = _advance(candidate);
    }
    return candidate;
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'frequency': frequency.name,
    'minutesAfterMidnight': minutesAfterMidnight,
    'lastRunAt': lastRunAt?.millisecondsSinceEpoch,
  };

  static ScheduledScanConfig fromJson(Object? value) {
    if (value is! Map<String, Object?>) {
      return const ScheduledScanConfig.defaults();
    }
    final minutes = value['minutesAfterMidnight'];
    final lastRun = value['lastRunAt'];
    return ScheduledScanConfig(
      enabled: value['enabled'] == true,
      frequency: ScheduledScanFrequency.values.firstWhere(
        (frequency) => frequency.name == value['frequency'],
        orElse: () => ScheduledScanFrequency.weekly,
      ),
      minutesAfterMidnight: minutes is num
          ? minutes.round().clamp(0, 1439)
          : 9 * 60,
      lastRunAt: lastRun is num
          ? DateTime.fromMillisecondsSinceEpoch(lastRun.round())
          : null,
    );
  }

  ScheduledScanConfig copyWith({
    bool? enabled,
    ScheduledScanFrequency? frequency,
    int? minutesAfterMidnight,
    DateTime? lastRunAt,
    bool clearLastRunAt = false,
  }) {
    return ScheduledScanConfig(
      enabled: enabled ?? this.enabled,
      frequency: frequency ?? this.frequency,
      minutesAfterMidnight: minutesAfterMidnight ?? this.minutesAfterMidnight,
      lastRunAt: clearLastRunAt ? null : lastRunAt ?? this.lastRunAt,
    );
  }

  DateTime _advance(DateTime value) {
    return switch (frequency) {
      ScheduledScanFrequency.daily => value.add(const Duration(days: 1)),
      ScheduledScanFrequency.weekly => value.add(const Duration(days: 7)),
      ScheduledScanFrequency.monthly => DateTime(
        value.year,
        value.month + 1,
        value.day,
        value.hour,
        value.minute,
      ),
    };
  }
}

enum ScheduledScanFrequency {
  daily('Daily'),
  weekly('Weekly'),
  monthly('Monthly');

  const ScheduledScanFrequency(this.label);

  final String label;
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/scheduled_scan_config.dart';

final scheduledScanProvider =
    NotifierProvider<ScheduledScanController, ScheduledScanConfig>(
      ScheduledScanController.new,
    );

final class ScheduledScanController extends Notifier<ScheduledScanConfig> {
  @override
  ScheduledScanConfig build() => const ScheduledScanConfig.defaults();

  void setEnabled(bool enabled) {
    state = state.copyWith(enabled: enabled);
  }

  void setFrequency(ScheduledScanFrequency frequency) {
    state = state.copyWith(frequency: frequency);
  }

  void setMinutesAfterMidnight(int minutesAfterMidnight) {
    state = state.copyWith(
      minutesAfterMidnight: minutesAfterMidnight.clamp(0, 1439).toInt(),
    );
  }

  void markRun(DateTime runAt) {
    state = state.copyWith(lastRunAt: runAt);
  }
}

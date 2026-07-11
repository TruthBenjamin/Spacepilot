import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auto_clean/presentation/providers/auto_clean_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/models/scheduled_scan_config.dart';

final scheduledScanProvider =
    NotifierProvider<ScheduledScanController, ScheduledScanConfig>(
      ScheduledScanController.new,
    );

final class ScheduledScanController extends Notifier<ScheduledScanConfig> {
  static const _prefsKey = 'scheduled_scan_config_v1';
  bool _hasLocalUpdate = false;

  @override
  ScheduledScanConfig build() {
    unawaited(_load());
    return const ScheduledScanConfig.defaults();
  }

  void setEnabled(bool enabled) {
    _update(state.copyWith(enabled: enabled));
  }

  void setFrequency(ScheduledScanFrequency frequency) {
    _update(state.copyWith(frequency: frequency));
  }

  void setMinutesAfterMidnight(int minutesAfterMidnight) {
    _update(
      state.copyWith(
        minutesAfterMidnight: minutesAfterMidnight.clamp(0, 1439).toInt(),
      ),
    );
  }

  void markRun(DateTime runAt) {
    _update(state.copyWith(lastRunAt: runAt));
  }

  Future<void> _load() async {
    final encoded = await ref
        .read(appPreferencesServiceProvider)
        .getString(_prefsKey);
    if (encoded == null || encoded.isEmpty || _hasLocalUpdate) return;
    try {
      state = ScheduledScanConfig.fromJson(jsonDecode(encoded));
      unawaited(
        ref.read(automationWorkmanagerServiceProvider).syncScheduledScan(state),
      );
    } catch (_) {
      return;
    }
  }

  void _update(ScheduledScanConfig next) {
    _hasLocalUpdate = true;
    state = next;
    unawaited(
      ref
          .read(appPreferencesServiceProvider)
          .setString(_prefsKey, jsonEncode(next.toJson())),
    );
    unawaited(
      ref.read(automationWorkmanagerServiceProvider).syncScheduledScan(next),
    );
  }
}

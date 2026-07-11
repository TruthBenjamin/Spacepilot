import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../duplicates/presentation/providers/duplicate_groups_provider.dart';
import '../../../cleanup/presentation/providers/cleanup_center_provider.dart';
import '../../../power/presentation/providers/power_thermal_provider.dart';
import '../../../scheduled_scans/presentation/providers/scheduled_scan_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../storage/presentation/providers/device_storage_provider.dart';
import '../../../storage/presentation/providers/storage_scan_provider.dart';
import '../../data/services/recommendation_engine.dart';
import '../../domain/models/storage_recommendation.dart';

final recommendationEngineProvider = Provider<RecommendationEngine>(
  (ref) => const RecommendationEngine(),
);

final recommendationsProvider = FutureProvider<List<StorageRecommendation>>((
  ref,
) async {
  final scan = await ref.watch(storageScanProvider.future);
  if (!scan.hasScanned || scan.files.isEmpty) return const [];

  final engine = ref.read(recommendationEngineProvider);
  final duplicateGroups = await ref.watch(duplicateGroupsProvider.future);
  final similarImageGroups = await ref.watch(similarImageGroupsProvider.future);
  final storageStats = await ref.watch(deviceStorageStatsProvider.future);
  final cleanupReport = await ref.watch(cleanupCenterReportProvider.future);
  final scheduledScan = ref.watch(scheduledScanProvider);
  final powerSnapshot = ref.watch(powerThermalSnapshotProvider).value;

  final storageRecommendations = engine.buildRecommendations(
    files: scan.files,
    duplicateGroups: duplicateGroups,
    similarImageGroups: similarImageGroups,
    emptyFolderPaths:
        scan.intelligenceReport?.emptyFolders.map((folder) => folder.path) ??
        const [],
    storageStats: storageStats,
  );
  final deviceCareRecommendations = engine.buildDeviceCareRecommendations(
    thermalStatus: powerSnapshot?.thermalStatus,
    scanActive: scan.progress.isScanning,
    batteryLevel: powerSnapshot?.batteryLevel,
    scheduledScanning: scheduledScan.enabled,
    cleanupBytes: cleanupReport.recoverableBytes,
  );

  return [...storageRecommendations, ...deviceCareRecommendations];
});

final recommendationDispositionProvider =
    NotifierProvider<
      RecommendationDispositionController,
      Map<String, RecommendationDisposition>
    >(RecommendationDispositionController.new);

final visibleRecommendationsProvider =
    FutureProvider<List<StorageRecommendation>>((ref) async {
      final recommendations = await ref.watch(recommendationsProvider.future);
      final dispositions = ref.watch(recommendationDispositionProvider);
      final now = DateTime.now();

      return recommendations
          .where((recommendation) {
            final disposition = dispositions[recommendation.stableId];
            if (disposition == null) return true;
            if (disposition.completedAt != null ||
                disposition.dismissedAt != null) {
              return false;
            }
            final snoozedUntil = disposition.snoozedUntil;
            return snoozedUntil == null || !snoozedUntil.isAfter(now);
          })
          .toList(growable: false);
    });

final completedRecommendationsProvider =
    FutureProvider<List<StorageRecommendation>>((ref) async {
      final recommendations = await ref.watch(recommendationsProvider.future);
      final dispositions = ref.watch(recommendationDispositionProvider);

      return recommendations
          .where((recommendation) {
            return dispositions[recommendation.stableId]?.completedAt != null;
          })
          .toList(growable: false);
    });

final class RecommendationDisposition {
  const RecommendationDisposition({
    this.dismissedAt,
    this.snoozedUntil,
    this.completedAt,
  });

  final DateTime? dismissedAt;
  final DateTime? snoozedUntil;
  final DateTime? completedAt;

  RecommendationDisposition copyWith({
    DateTime? dismissedAt,
    DateTime? snoozedUntil,
    DateTime? completedAt,
    bool clearSnooze = false,
  }) {
    return RecommendationDisposition(
      dismissedAt: dismissedAt ?? this.dismissedAt,
      snoozedUntil: clearSnooze ? null : snoozedUntil ?? this.snoozedUntil,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'dismissedAt': dismissedAt?.millisecondsSinceEpoch,
      'snoozedUntil': snoozedUntil?.millisecondsSinceEpoch,
      'completedAt': completedAt?.millisecondsSinceEpoch,
    };
  }

  static RecommendationDisposition fromJson(Object? value) {
    if (value is! Map<String, Object?>) {
      return const RecommendationDisposition();
    }

    return RecommendationDisposition(
      dismissedAt: _dateFromEpoch(value['dismissedAt']),
      snoozedUntil: _dateFromEpoch(value['snoozedUntil']),
      completedAt: _dateFromEpoch(value['completedAt']),
    );
  }

  static DateTime? _dateFromEpoch(Object? value) {
    if (value is! num) return null;
    return DateTime.fromMillisecondsSinceEpoch(value.round());
  }
}

final class RecommendationDispositionController
    extends Notifier<Map<String, RecommendationDisposition>> {
  static const String _prefsKey = 'recommendation_dispositions_v1';
  bool _hasLocalUpdate = false;

  @override
  Map<String, RecommendationDisposition> build() {
    unawaited(_load());
    return const {};
  }

  void dismiss(String id) {
    state = {
      ...state,
      id: (state[id] ?? const RecommendationDisposition()).copyWith(
        dismissedAt: DateTime.now(),
        clearSnooze: true,
      ),
    };
    _persist();
  }

  void snooze(String id, Duration duration) {
    state = {
      ...state,
      id: (state[id] ?? const RecommendationDisposition()).copyWith(
        snoozedUntil: DateTime.now().add(duration),
      ),
    };
    _persist();
  }

  void complete(String id) {
    state = {
      ...state,
      id: (state[id] ?? const RecommendationDisposition()).copyWith(
        completedAt: DateTime.now(),
        clearSnooze: true,
      ),
    };
    _persist();
  }

  void restore(String id) {
    final next = Map<String, RecommendationDisposition>.of(state)..remove(id);
    state = next;
    _persist();
  }

  Future<void> _load() async {
    final encoded = await ref
        .read(appPreferencesServiceProvider)
        .getString(_prefsKey);
    if (encoded == null || encoded.isEmpty) return;

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, Object?>) return;
      if (_hasLocalUpdate) return;
      state = decoded.map(
        (id, value) => MapEntry(id, RecommendationDisposition.fromJson(value)),
      );
    } catch (_) {
      return;
    }
  }

  void _persist() {
    _hasLocalUpdate = true;
    unawaited(
      ref
          .read(appPreferencesServiceProvider)
          .setString(
            _prefsKey,
            jsonEncode(
              state.map((id, disposition) {
                return MapEntry(id, disposition.toJson());
              }),
            ),
          ),
    );
  }
}

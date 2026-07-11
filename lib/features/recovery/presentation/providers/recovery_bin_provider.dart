import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../auto_clean/data/services/automation_workmanager_service.dart';
import '../../domain/models/recovery_bin_item.dart';

final recoverySettingsProvider =
    NotifierProvider<RecoverySettingsController, RecoverySettings>(
      RecoverySettingsController.new,
    );

final recoveryRetentionDaysProvider = Provider<int>((ref) {
  return ref.watch(recoverySettingsProvider).retentionDays;
});

final recoveryAutoPurgeProvider = Provider<bool>((ref) {
  return ref.watch(recoverySettingsProvider).autoPurge;
});

final recoveryBinProvider =
    NotifierProvider<RecoveryBinController, List<RecoveryBinItem>>(
      RecoveryBinController.new,
    );

@immutable
final class RecoverySettings {
  const RecoverySettings({this.retentionDays = 30, this.autoPurge = true});

  final int retentionDays;
  final bool autoPurge;

  RecoverySettings copyWith({int? retentionDays, bool? autoPurge}) {
    return RecoverySettings(
      retentionDays: retentionDays ?? this.retentionDays,
      autoPurge: autoPurge ?? this.autoPurge,
    );
  }

  Map<String, Object> toJson() {
    return {'retentionDays': retentionDays, 'autoPurge': autoPurge};
  }

  static RecoverySettings fromJson(Object? value) {
    if (value is! Map<String, Object?>) return const RecoverySettings();
    final retentionDays = value['retentionDays'];
    return RecoverySettings(
      retentionDays: retentionDays is num
          ? retentionDays.round().clamp(7, 90)
          : 30,
      autoPurge: value['autoPurge'] != false,
    );
  }
}

final class RecoverySettingsController extends Notifier<RecoverySettings> {
  static const String _prefsKey = 'recovery_settings_v1';
  bool _hasLocalUpdate = false;

  @override
  RecoverySettings build() {
    unawaited(_load());
    return const RecoverySettings();
  }

  void setRetentionDays(int value) {
    _update(state.copyWith(retentionDays: value.clamp(7, 90).toInt()));
  }

  void setAutoPurge(bool value) {
    _update(state.copyWith(autoPurge: value));
    unawaited(AutomationWorkmanagerService().syncRecoveryPurge(enabled: value));
  }

  Future<void> _load() async {
    final encoded = await ref
        .read(appPreferencesServiceProvider)
        .getString(_prefsKey);
    if (encoded == null || encoded.isEmpty) return;
    try {
      if (_hasLocalUpdate) return;
      state = RecoverySettings.fromJson(jsonDecode(encoded));
      unawaited(
        AutomationWorkmanagerService().syncRecoveryPurge(
          enabled: state.autoPurge,
        ),
      );
    } catch (_) {
      return;
    }
  }

  void _update(RecoverySettings next) {
    _hasLocalUpdate = true;
    state = next;
    unawaited(
      ref
          .read(appPreferencesServiceProvider)
          .setString(_prefsKey, jsonEncode(next.toJson())),
    );
  }
}

final class RecoveryBinController extends Notifier<List<RecoveryBinItem>> {
  static const String _prefsKey = 'recovery_bin_items_v1';
  bool _hasLocalUpdate = false;

  @override
  List<RecoveryBinItem> build() {
    unawaited(_load());
    return const [];
  }

  void registerMovedItem(RecoveryBinItem item) {
    state = [item, ...state.where((existing) => existing.id != item.id)];
    _persist();
  }

  void removeItems(Iterable<String> ids) {
    final selected = ids.toSet();
    state = state.where((item) => !selected.contains(item.id)).toList();
    _persist();
  }

  void purgeExpired(DateTime now) {
    state = state.where((item) => !item.isExpired(now)).toList();
    _persist();
  }

  Future<void> _load() async {
    final encoded = await ref
        .read(appPreferencesServiceProvider)
        .getString(_prefsKey);
    if (encoded == null || encoded.isEmpty) return;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List<Object?>) return;
      final items = decoded
          .map(RecoveryBinItem.fromJson)
          .nonNulls
          .toList(growable: false);
      if (_hasLocalUpdate) return;
      state = items;
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
            jsonEncode(state.map((item) => item.toJson()).toList()),
          ),
    );
  }
}

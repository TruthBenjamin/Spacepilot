import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/app_preferences_service.dart';
import '../../data/services/notification_service.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

final appPreferencesServiceProvider = Provider<AppPreferencesService>((ref) {
  return AppPreferencesService();
});

final appSettingsProvider =
    NotifierProvider<AppSettingsController, AppSettings>(
      AppSettingsController.new,
    );

final appThemeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(appSettingsProvider).themeMode;
});

final recommendationSnoozeDaysProvider = Provider<int>((ref) {
  return ref.watch(appSettingsProvider).recommendationSnoozeDays;
});

final notificationsEnabledProvider = Provider<bool>((ref) {
  return ref.watch(appSettingsProvider).notificationsEnabled;
});

final scannerIncludeHiddenProvider = Provider<bool>((ref) {
  return ref.watch(appSettingsProvider).scannerIncludeHidden;
});

final largeFileThresholdBytesSettingProvider = Provider<int>((ref) {
  return ref.watch(appSettingsProvider).largeFileThresholdBytes;
});

@immutable
final class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.recommendationSnoozeDays = 7,
    this.notificationsEnabled = false,
    this.scannerIncludeHidden = false,
    this.largeFileThresholdBytes = 100 * 1024 * 1024,
  });

  final ThemeMode themeMode;
  final int recommendationSnoozeDays;
  final bool notificationsEnabled;
  final bool scannerIncludeHidden;
  final int largeFileThresholdBytes;

  AppSettings copyWith({
    ThemeMode? themeMode,
    int? recommendationSnoozeDays,
    bool? notificationsEnabled,
    bool? scannerIncludeHidden,
    int? largeFileThresholdBytes,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      recommendationSnoozeDays:
          recommendationSnoozeDays ?? this.recommendationSnoozeDays,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      scannerIncludeHidden: scannerIncludeHidden ?? this.scannerIncludeHidden,
      largeFileThresholdBytes:
          largeFileThresholdBytes ?? this.largeFileThresholdBytes,
    );
  }

  Map<String, Object> toJson() {
    return {
      'themeMode': themeMode.name,
      'recommendationSnoozeDays': recommendationSnoozeDays,
      'notificationsEnabled': notificationsEnabled,
      'scannerIncludeHidden': scannerIncludeHidden,
      'largeFileThresholdBytes': largeFileThresholdBytes,
    };
  }

  static AppSettings fromJson(Object? value) {
    if (value is! Map<String, Object?>) return const AppSettings();

    return AppSettings(
      themeMode: ThemeMode.values.firstWhere(
        (mode) => mode.name == value['themeMode'],
        orElse: () => ThemeMode.system,
      ),
      recommendationSnoozeDays: _intInRange(
        value['recommendationSnoozeDays'],
        min: 1,
        max: 90,
        fallback: 7,
      ),
      notificationsEnabled: value['notificationsEnabled'] == true,
      scannerIncludeHidden: value['scannerIncludeHidden'] == true,
      largeFileThresholdBytes: _intInRange(
        value['largeFileThresholdBytes'],
        min: 50 * 1024 * 1024,
        max: 2 * 1024 * 1024 * 1024,
        fallback: 100 * 1024 * 1024,
      ),
    );
  }

  static int _intInRange(
    Object? value, {
    required int min,
    required int max,
    required int fallback,
  }) {
    if (value is! num) return fallback;
    return value.round().clamp(min, max);
  }
}

final class AppSettingsController extends Notifier<AppSettings> {
  static const String _prefsKey = 'app_settings_v1';
  bool _hasLocalUpdate = false;

  @override
  AppSettings build() {
    unawaited(_load());
    return const AppSettings();
  }

  void setThemeMode(ThemeMode value) =>
      _update(state.copyWith(themeMode: value));

  void setRecommendationSnoozeDays(int value) {
    _update(
      state.copyWith(recommendationSnoozeDays: value.clamp(1, 90).toInt()),
    );
  }

  Future<bool> setNotificationsEnabled(bool value) async {
    if (!value) {
      _update(state.copyWith(notificationsEnabled: false));
      return true;
    }
    final granted = await ref
        .read(notificationServiceProvider)
        .requestPermission();
    _update(state.copyWith(notificationsEnabled: granted));
    return granted;
  }

  void setScannerIncludeHidden(bool value) {
    _update(state.copyWith(scannerIncludeHidden: value));
  }

  void setLargeFileThresholdBytes(int value) {
    _update(state.copyWith(largeFileThresholdBytes: value));
  }

  Future<void> _load() async {
    final encoded = await ref
        .read(appPreferencesServiceProvider)
        .getString(_prefsKey);
    if (encoded == null || encoded.isEmpty) return;

    try {
      if (_hasLocalUpdate) return;
      state = AppSettings.fromJson(jsonDecode(encoded));
    } catch (_) {
      return;
    }
  }

  void _update(AppSettings next) {
    _hasLocalUpdate = true;
    state = next;
    unawaited(
      ref
          .read(appPreferencesServiceProvider)
          .setString(_prefsKey, jsonEncode(next.toJson())),
    );
  }
}

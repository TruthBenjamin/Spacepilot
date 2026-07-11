import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

final class RamBoosterService {
  RamBoosterService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'ai.spacepilot.app/ram_booster';
  final MethodChannel _channel;

  bool get isSupported => defaultTargetPlatform == TargetPlatform.android;

  Future<RamSnapshot> getMemorySnapshot() async {
    if (!isSupported) return const RamSnapshot.unsupported();
    final result = await _channel.invokeMethod<Object?>('getMemorySnapshot');
    if (result is! Map<Object?, Object?>) {
      throw StateError('RAM booster returned an invalid memory payload.');
    }
    return RamSnapshot.fromMap(result);
  }

  Future<RamBoostResult> boost() async {
    if (!isSupported) {
      return const RamBoostResult.unsupported();
    }
    final result = await _channel.invokeMethod<Object?>('boostRam');
    if (result is! Map<Object?, Object?>) {
      throw StateError('RAM booster returned an invalid boost payload.');
    }
    return RamBoostResult.fromMap(result);
  }
}

@immutable
final class RamSnapshot {
  const RamSnapshot({
    required this.totalBytes,
    required this.availableBytes,
    required this.lowMemory,
    required this.thresholdBytes,
    required this.capturedAt,
    this.supported = true,
  });

  const RamSnapshot.unsupported()
    : totalBytes = 0,
      availableBytes = 0,
      lowMemory = false,
      thresholdBytes = 0,
      capturedAt = null,
      supported = false;

  factory RamSnapshot.fromMap(Map<Object?, Object?> map) {
    return RamSnapshot(
      totalBytes: _intOrZero(map['totalBytes']),
      availableBytes: _intOrZero(map['availableBytes']),
      lowMemory: map['lowMemory'] == true,
      thresholdBytes: _intOrZero(map['thresholdBytes']),
      capturedAt: _dateFromMillis(map['capturedAt']),
    );
  }

  final int totalBytes;
  final int availableBytes;
  final bool lowMemory;
  final int thresholdBytes;
  final DateTime? capturedAt;
  final bool supported;

  int get usedBytes => (totalBytes - availableBytes).clamp(0, totalBytes);
  double get usageFraction => totalBytes <= 0 ? 0 : usedBytes / totalBytes;
}

@immutable
final class RamBoostResult {
  const RamBoostResult({
    required this.before,
    required this.after,
    required this.optimizedAppCount,
    required this.optimizedPackages,
    required this.skippedPackages,
    required this.limitations,
    this.supported = true,
  });

  const RamBoostResult.unsupported()
    : before = const RamSnapshot.unsupported(),
      after = const RamSnapshot.unsupported(),
      optimizedAppCount = 0,
      optimizedPackages = const [],
      skippedPackages = const [],
      limitations = const ['RAM boosting is Android-only.'],
      supported = false;

  factory RamBoostResult.fromMap(Map<Object?, Object?> map) {
    return RamBoostResult(
      before: map['before'] is Map<Object?, Object?>
          ? RamSnapshot.fromMap(map['before'] as Map<Object?, Object?>)
          : const RamSnapshot.unsupported(),
      after: map['after'] is Map<Object?, Object?>
          ? RamSnapshot.fromMap(map['after'] as Map<Object?, Object?>)
          : const RamSnapshot.unsupported(),
      optimizedAppCount: _intOrZero(map['optimizedAppCount']),
      optimizedPackages: _stringList(map['optimizedPackages']),
      skippedPackages: _stringList(map['skippedPackages']),
      limitations: _stringList(map['limitations']),
    );
  }

  final RamSnapshot before;
  final RamSnapshot after;
  final int optimizedAppCount;
  final List<String> optimizedPackages;
  final List<String> skippedPackages;
  final List<String> limitations;
  final bool supported;

  int get reclaimedBytes =>
      (after.availableBytes - before.availableBytes).clamp(0, after.totalBytes);
}

int _intOrZero(Object? value) => value is num ? value.toInt() : 0;

DateTime? _dateFromMillis(Object? value) {
  final millis = _intOrZero(value);
  if (millis <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(millis);
}

List<String> _stringList(Object? value) {
  if (value is! List<Object?>) return const [];
  return value.whereType<String>().toList(growable: false);
}

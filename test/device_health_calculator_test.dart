import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/features/device_health/data/services/services.dart';

void main() {
  const calculator = DeviceHealthCalculator();

  test('returns perfect score for healthy storage with no clutter', () {
    final score = calculator.calculateScore(
      totalBytes: 100,
      freeBytes: 30,
      duplicateCount: 0,
      junkFileCount: 0,
      unusedFileCount: 0,
    );

    expect(score, 100);
  });

  test('reduces score for low storage and clutter factors', () {
    final score = calculator.calculateScore(
      totalBytes: 100,
      freeBytes: 5,
      duplicateCount: 4,
      junkFileCount: 6,
      unusedFileCount: 3,
    );

    expect(score, 38);
  });

  test('clamps score between zero and one hundred', () {
    final score = calculator.calculateScore(
      totalBytes: 100,
      freeBytes: 0,
      duplicateCount: 100,
      junkFileCount: 100,
      unusedFileCount: 100,
    );

    expect(score, 0);
  });
}

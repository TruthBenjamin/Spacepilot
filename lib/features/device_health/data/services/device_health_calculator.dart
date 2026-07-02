final class DeviceHealthCalculator {
  const DeviceHealthCalculator();

  int calculateScore({
    required int totalBytes,
    required int freeBytes,
    required int duplicateCount,
    required int junkFileCount,
    required int unusedFileCount,
  }) {
    final normalizedTotalBytes = totalBytes < 0 ? 0 : totalBytes;
    final normalizedFreeBytes = freeBytes
        .clamp(0, normalizedTotalBytes)
        .toInt();
    final freeRatio = normalizedTotalBytes == 0
        ? 0.0
        : normalizedFreeBytes / normalizedTotalBytes;

    final score =
        100 -
        _freeStoragePenalty(freeRatio) -
        _duplicatePenalty(duplicateCount) -
        _junkPenalty(junkFileCount) -
        _unusedPenalty(unusedFileCount);

    return score.clamp(0, 100).round();
  }

  double _freeStoragePenalty(double freeRatio) {
    const healthyFreeRatio = 0.25;
    const criticalFreeRatio = 0.05;
    const maxPenalty = 45.0;

    if (freeRatio >= healthyFreeRatio) return 0;
    if (freeRatio <= criticalFreeRatio) return maxPenalty;

    final pressure =
        (healthyFreeRatio - freeRatio) / (healthyFreeRatio - criticalFreeRatio);
    return pressure * maxPenalty;
  }

  int _duplicatePenalty(int duplicateCount) {
    return (duplicateCount < 0 ? 0 : duplicateCount * 2).clamp(0, 20).toInt();
  }

  int _junkPenalty(int junkFileCount) {
    return (junkFileCount < 0 ? 0 : junkFileCount).clamp(0, 20).toInt();
  }

  int _unusedPenalty(int unusedFileCount) {
    return (unusedFileCount < 0 ? 0 : unusedFileCount).clamp(0, 15).toInt();
  }
}

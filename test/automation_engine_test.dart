import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/features/auto_clean/data/services/services.dart';
import 'package:spacepilot/features/auto_clean/domain/models/models.dart';
import 'package:spacepilot/features/storage/domain/models/scanned_file.dart';

void main() {
  const engine = AutomationEngine();

  test('creates default disabled rules for supported automation examples', () {
    final rules = engine.defaultRules(now: DateTime(2026));

    expect(rules, hasLength(5));
    expect(rules.every((rule) => !rule.enabled), isTrue);
    expect(
      rules.map((rule) => rule.type),
      containsAll(AutomationRuleType.values),
    );
  });

  test('plans enabled file cleanup rules without double-counting files', () {
    final now = DateTime(2026, 7, 5);
    final rules = [
      AutomationRule.deleteScreenshotsAfter(
        id: 'screenshots',
        days: 30,
        createdAt: now,
      ),
      AutomationRule.deleteApkInstallers(id: 'apk', createdAt: now),
      AutomationRule.weeklyScan(id: 'weekly', createdAt: now),
      AutomationRule.monthlyReport(
        id: 'monthly',
        enabled: false,
        createdAt: now,
      ),
    ];
    final files = [
      ScannedFile(
        filename: 'Screenshot_1.png',
        path: '/storage/Pictures/Screenshots/Screenshot_1.png',
        size: 10,
        lastModified: now.subtract(const Duration(days: 45)),
      ),
      ScannedFile(
        filename: 'app.apk',
        path: '/storage/Download/app.apk',
        size: 20,
        lastModified: now,
      ),
      ScannedFile(
        filename: 'fresh_screenshot.png',
        path: '/storage/Pictures/Screenshots/fresh_screenshot.png',
        size: 30,
        lastModified: now.subtract(const Duration(days: 2)),
      ),
    ];

    final plan = engine.buildPlan(rules: rules, files: files, now: now);

    expect(plan.enabledRules, 3);
    expect(plan.disabledRules, 1);
    expect(plan.scheduledTaskCount, 3);
    expect(plan.matchedFileCount, 2);
    expect(plan.estimatedSavingsBytes, 30);
  });
}

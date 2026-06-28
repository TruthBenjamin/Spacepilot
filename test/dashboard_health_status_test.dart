import 'package:flutter_test/flutter_test.dart';
import 'package:spacepilot/core/theme/app_colors.dart';
import 'package:spacepilot/features/dashboard/presentation/pages/dashboard_page.dart';

void main() {
  test('shows low device health scores as poor', () {
    final status = dashboardHealthStatusForScore(28);

    expect(status.label, 'Poor');
    expect(
      status.message,
      'Storage is under pressure. Run cleanup recommendations.',
    );
    expect(status.color, AppColors.danger);
  });

  test('shows excellent only for high device health scores', () {
    final lowStatus = dashboardHealthStatusForScore(28);
    final excellentStatus = dashboardHealthStatusForScore(85);

    expect(lowStatus.label, isNot('Excellent'));
    expect(excellentStatus.label, 'Excellent');
  });
}

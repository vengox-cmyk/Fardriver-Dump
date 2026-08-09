import 'package:arcdash/models/dashboard_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'R-inspired landscape default layout contains all mandatory metrics and valid structure',
      () {
    final layout = DashboardLayout.defaults();
    final landscape = layout.landscape;

    expect(landscape.columns, 12);
    expect(landscape.rows, 6);
    expect(landscape.validate, returnsNormally);

    final metricsInLandscape = landscape.tiles.map((t) => t.metric).toSet();
    final requiredMetrics = {
      DashboardMetric.speed,
      DashboardMetric.power,
      DashboardMetric.soc,
      DashboardMetric.range,
      DashboardMetric.motorTemperature,
      DashboardMetric.controllerTemperature,
      DashboardMetric.trip,
      DashboardMetric.profile,
    };

    expect(metricsInLandscape.containsAll(requiredMetrics), true);

    final powerTile =
        landscape.tiles.firstWhere((t) => t.metric == DashboardMetric.power);
    expect(powerTile.row, 0);
    expect(powerTile.width, 12);
    expect(powerTile.kind, DashboardTileKind.arc);

    final speedTile =
        landscape.tiles.firstWhere((t) => t.metric == DashboardMetric.speed);
    expect(speedTile.column >= 3 && speedTile.column <= 4, true);
    expect(speedTile.row, 2);
  });

  test('portrait default layout remains valid and independent', () {
    final layout = DashboardLayout.defaults();
    final portrait = layout.portrait;

    expect(portrait.validate, returnsNormally);
    expect(portrait.columns, 4);
    expect(portrait.rows, 8);
  });
}

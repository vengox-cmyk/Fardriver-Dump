import 'package:arcdash/models/range_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('does not invent a range without capacity and consumption data', () {
    final estimate = RangeEstimate.estimate(
      socPercent: 90,
      usableCapacityWh: null,
      consumptionWhPerKm: null,
    );
    expect(estimate.available, isFalse);
    expect(estimate.status, 'Noch keine Reichweitendaten');
  });

  test('calculates a bounded provisional range', () {
    final estimate = RangeEstimate.estimate(
      socPercent: 50,
      usableCapacityWh: 10000,
      consumptionWhPerKm: 200,
      confidence: 0.4,
    );
    expect(estimate.kilometers, 25);
    expect(estimate.uncertainty, greaterThan(0));
  });

  test('separates consumed and recovered energy and flags gaps', () {
    final integration = EnergyIntegration();
    integration.add(const EnergySample(
      elapsed: Duration(hours: 1),
      voltageV: 72,
      currentA: 10,
    ));
    integration.add(const EnergySample(
      elapsed: Duration(seconds: 1),
      voltageV: 72,
      currentA: -2,
    ));
    expect(integration.consumedWh, 720);
    expect(integration.recoveredWh, 0.04);
    expect(integration.hasGap, isTrue);
  });
}

import 'package:arcdash/models/range_prediction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('missing chemistry keeps SOC confidence low', () {
    final soc = SocFilter().update(voltageV: 84.5);
    expect(soc.percent, 0);
    expect(soc.confidence, lessThan(0.5));
  });

  test('consumption window is bounded and ignores tiny distance', () {
    final window = ConsumptionWindow(maxSamples: 2);
    window
      ..add(distanceKm: 0.001, netWh: 100)
      ..add(distanceKm: 1, netWh: 200)
      ..add(distanceKm: 2, netWh: 300)
      ..add(distanceKm: 3, netWh: 600);
    expect(window.samples, hasLength(2));
    expect(window.averageWhPerKm, 175);
  });

  test('capacity learner ignores unqualified and outlier cycles', () {
    final learner = CapacityLearner(maxWh: 1000);
    learner.observeCycle(dischargedWh: 500, qualified: false);
    expect(learner.capacityWh, isNull);
    learner.observeCycle(dischargedWh: 500, qualified: true);
    learner.observeCycle(dischargedWh: 5000, qualified: true);
    expect(learner.capacityWh, 500);
  });
}

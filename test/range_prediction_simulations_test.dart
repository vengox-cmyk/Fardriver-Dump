import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/models/range_model.dart';
import 'package:arcdash/models/range_prediction.dart';

void main() {
  group('T069 - Fahrfixture Simulationen', () {
    late CapacityLearner capacityLearner;
    late ConsumptionWindow consumptionWindow;
    late SocFilter socFilter;

    const ocvCurve72V = [
      OcvPoint(60.0, 0.0),
      OcvPoint(72.0, 50.0),
      OcvPoint(84.0, 100.0),
    ];

    setUp(() {
      capacityLearner = CapacityLearner(minWh: 100, maxWh: 5000);
      capacityLearner.capacityWh = 2000.0; // Init 2 kWh
      consumptionWindow = ConsumptionWindow(maxSamples: 50);
      socFilter = SocFilter(curve: ocvCurve72V);
    });

    test('Simulation 1: Laden (Charging Profile)', () {
      final integration = EnergyIntegration();
      // Simulate charging: negative current (recovery/charging)
      for (int i = 1; i <= 10; i++) {
        integration.add(EnergySample(
          elapsed: const Duration(seconds: 60),
          voltageV: 72.0 + (i * 1.0), // Voltage rises from 73V to 82V
          currentA: -15.0, // 15A charging current
        ));
      }

      expect(integration.recoveredWh, greaterThan(0));
      expect(integration.consumedWh, 0);

      // Verify SOC increases and remains bounded
      final socEnd = socFilter.update(voltageV: 82.0);
      expect(socEnd.percent, greaterThan(50.0));
      expect(socEnd.percent, lessThanOrEqualTo(100.0));
    });

    test('Simulation 2: Stadtverkehr (Stop-and-Go)', () {
      // 5 stop-and-go cycles of 200 m at ~30 Wh/km each.
      for (int cycle = 0; cycle < 5; cycle++) {
        consumptionWindow.add(distanceKm: 0.2, netWh: 6.0);
      }

      expect(consumptionWindow.averageWhPerKm, isNotNull);
      expect(consumptionWindow.averageWhPerKm!, closeTo(30.0, 5.0));

      final estimate = RangeEstimate.estimate(
        socPercent: 80.0,
        usableCapacityWh: capacityLearner.capacityWh,
        consumptionWhPerKm: consumptionWindow.averageWhPerKm,
        confidence: 0.8,
      );

      expect(estimate.available, isTrue);
      expect(estimate.kilometers, greaterThan(40.0));
    });

    test('Simulation 3: Konstante Fahrt (Efficient Cruising)', () {
      // 10 km smooth drive at 20 Wh/km
      for (int i = 0; i < 10; i++) {
        consumptionWindow.add(distanceKm: 1.0, netWh: 20.0);
      }

      final avgWh = consumptionWindow.averageWhPerKm;
      expect(avgWh, 20.0);

      final estimate = RangeEstimate.estimate(
        socPercent: 100.0,
        usableCapacityWh: 2000.0,
        consumptionWhPerKm: avgWh,
        confidence: 0.9,
      );

      expect(estimate.kilometers, 100.0); // 2000 Wh / 20 Wh/km = 100 km
      expect(estimate.uncertainty, lessThanOrEqualTo(15.0));
    });

    test('Simulation 4: Sportliche Fahrt (High Consumption)', () {
      // Aggressive riding at 50 Wh/km
      for (int i = 0; i < 5; i++) {
        consumptionWindow.add(distanceKm: 1.0, netWh: 50.0);
      }

      final estimate = RangeEstimate.estimate(
        socPercent: 50.0,
        usableCapacityWh: 2000.0,
        consumptionWhPerKm: consumptionWindow.averageWhPerKm,
        confidence: 0.85,
      );

      // 1000 Wh remaining / 50 Wh/km = 20 km
      expect(estimate.kilometers, 20.0);
    });

    test('Simulation 6: Bergabfahrt / Rekuperation (Regen Recovery)', () {
      final integration = EnergyIntegration();

      // Uphill: 500 Wh consumed
      integration.add(const EnergySample(
        elapsed: Duration(minutes: 5),
        voltageV: 70.0,
        currentA: 85.7,
      ));

      // Downhill regen: 150 Wh recovered
      integration.add(const EnergySample(
        elapsed: Duration(minutes: 3),
        voltageV: 75.0,
        currentA: -40.0,
      ));

      expect(integration.consumedWh, greaterThan(490.0));
      expect(integration.recoveredWh, greaterThan(140.0));

      final netWh = integration.consumedWh - integration.recoveredWh;
      expect(netWh, lessThan(integration.consumedWh));

      // Observe cycle for capacity learning with net discharged energy
      capacityLearner.observeCycle(dischargedWh: netWh, qualified: true);
      expect(capacityLearner.capacityWh, isNotNull);
    });
  });
}

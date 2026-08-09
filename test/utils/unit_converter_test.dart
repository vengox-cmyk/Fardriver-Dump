import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/utils/unit_converter.dart';

void main() {
  group('UnitConverter', () {
    test(
        'measureSpeedToKph calculates speed accurately and handles zero rateRatio',
        () {
      final kph = UnitConverter.measureSpeedToKph(
        measureSpeed: 1000,
        wheelRadius: 10,
        wheelWidth: 100,
        wheelRatio: 80,
        rateRatio: 10,
      );
      expect(kph, greaterThan(0.0));

      final zeroKph = UnitConverter.measureSpeedToKph(
        measureSpeed: 1000,
        wheelRadius: 10,
        wheelWidth: 100,
        wheelRatio: 80,
        rateRatio: 0,
      );
      expect(zeroKph, 0.0);
    });

    test('powerKw calculates power in kW', () {
      expect(UnitConverter.powerKw(72.0, 100.0), 7.2);
    });

    test('batteryPercent calculates SOC clamp and zero delta edge case', () {
      final pct = UnitConverter.batteryPercent(
        voltageDeciVolts: 720.0,
        zeroBattCoeff: 600,
        fullBattCoeff: 840,
      );
      expect(pct, closeTo(50.0, 0.1));

      final zeroDelta = UnitConverter.batteryPercent(
        voltageDeciVolts: 720.0,
        zeroBattCoeff: 700,
        fullBattCoeff: 700,
      );
      expect(zeroDelta, 0.0);
    });

    test('estimatedRangeKm calculates range and guards zero consumption', () {
      final range = UnitConverter.estimatedRangeKm(
        batteryPercent: 50.0,
        battCapacityWh: 2000.0,
        avgConsumptionWhPerKm: 25.0,
      );
      expect(range, 40.0);

      final zeroRange = UnitConverter.estimatedRangeKm(
        batteryPercent: 50.0,
        battCapacityWh: 2000.0,
        avgConsumptionWhPerKm: 0.0,
      );
      expect(zeroRange, 0.0);
    });

    test('fmt1 and fmt0 format string representations', () {
      expect(UnitConverter.fmt1(12.34), '12.3');
      expect(UnitConverter.fmt0(12.6), '13');
    });
  });
}

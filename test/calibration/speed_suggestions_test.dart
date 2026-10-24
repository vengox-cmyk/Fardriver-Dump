import 'package:arcdash/models/speed_suggestions.dart';
import 'package:arcdash/models/gps_calibration.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ride_fixtures.dart';

void main() {
  // Owner's belt-drive scooter: 120/70-12 tire, RateRatio 4000 (pulley 4:1).
  const baseline = BleSpeedSettings(
      wheelRadius: 12, wheelWidth: 120, wheelRatio: 70, rateRatio: 4000);

  test('baseline k_BLE is 0.022280 km/h per rpm', () {
    expect(baseline.kBle, closeTo(kTrue, 0.000001));
    expect(baseline.gearRatio, 4.0);
  });

  group('RateRatio (app / BLE speed)', () {
    for (final (label, displayFactor, expected) in const [
      ('2 % high', 1.02, 4080),
      ('5 % high', 1.05, 4200),
      ('2 % low', 0.98, 3920),
      ('5 % low', 0.95, 3800),
    ]) {
      test('app reads $label → $expected', () {
        final kGps = baseline.kBle / displayFactor;
        final s = RateRatioSuggestion.compute(baseline, kGps);
        expect(s.suggested, expected);
        expect(s.error, closeTo(displayFactor - 1, 1e-9));
        expect(s.suggestedGearRatio, expected / 1000);
        expect(s.isSuspicious, isFalse);
      });
    }

    test('more than 30 % change is flagged', () {
      final s = RateRatioSuggestion.compute(baseline, baseline.kBle / 1.4);
      expect(s.suggested, 5600);
      expect(s.isSuspicious, isTrue);
    });

    test('result is clamped to 16 bits', () {
      final s = RateRatioSuggestion.compute(baseline, baseline.kBle / 20);
      expect(s.suggested, 65535);
      expect(s.clamped, isTrue);
      expect(s.isSuspicious, isTrue);
    });
  });

  group('DKD (Speed Pulses / SpdPulseNum)', () {
    test('DKD reads 3 % high → SpdPulseNum 39192', () {
      final s = DkdSuggestion.compute(
          speedPulses: 11, spdPulseNum: 38050, kDkd: kTrue * 1.03, kGps: kTrue);
      expect(s.suggestedSpeedPulses, 11);
      expect(s.suggestedSpdPulseNum, 39192);
      expect(s.changesSpeedPulses, isFalse);
    });

    test('DKD reads 2 % low → SpdPulseNum 37289', () {
      final s = DkdSuggestion.compute(
          speedPulses: 11, spdPulseNum: 38050, kDkd: kTrue * 0.98, kGps: kTrue);
      expect(s.suggestedSpdPulseNum, 37289);
      expect(s.ccFactor, closeTo(1 / 0.98, 1e-9));
    });

    test('above ~4 % error Speed Pulses steps first, SpdPulseNum trims', () {
      // 10 % high: SP 11 → round(11/1.1) = 10, SPN = 38050 × 10/11 × 1.1.
      final s = DkdSuggestion.compute(
          speedPulses: 11, spdPulseNum: 38050, kDkd: kTrue * 1.10, kGps: kTrue);
      expect(s.suggestedSpeedPulses, 10);
      expect(s.suggestedSpdPulseNum, 38050);
      expect(s.changesSpeedPulses, isTrue);
    });

    test('SpdPulseNum is clamped to 500…65530', () {
      final s = DkdSuggestion.compute(
          speedPulses: 1, spdPulseNum: 60000, kDkd: kTrue * 1.5, kGps: kTrue);
      expect(s.suggestedSpeedPulses, 1);
      expect(s.suggestedSpdPulseNum, 65530);
      expect(s.clamped, isTrue);
    });

    test('DKD fit from taps', () {
      final taps = [
        for (final (rpm, dkd) in const [
          (1500.0, 34.4),
          (2000.0, 45.9),
          (2500.0, 57.4)
        ])
          DkdSnapshot(
              at: t0,
              rpm: rpm,
              gpsKph: rpm * kTrue,
              controllerKph: 0,
              dkdKph: dkd),
        DkdSnapshot(at: t0, rpm: 1800, gpsKph: 40, controllerKph: 0),
      ];
      final fit = DkdFit.fromSnapshots(taps)!;
      expect(fit.taps, 3);
      expect(fit.kDkd, closeTo(kTrue * 1.03, kTrue * 0.002));
      expect(fit.ciRelative, isNotNull);
      expect(DkdFit.fromSnapshots([taps.last]), isNull);
    });

    test('DKD confidence needs ≥3 taps', () {
      const gps = CalibrationFit(
          kGps: kTrue,
          ciRelative: 0.003,
          segments: 8,
          cleanSeconds: 80,
          bands: {SpeedBand.kph20to40, SpeedBand.kph40to60},
          interceptKph: 0,
          kByBand: {});
      const two = DkdFit(kTrue, 2, 0.001);
      expect(two.confidence(gps), CalibrationConfidence.red);
      const five = DkdFit(kTrue, 5, 0.002);
      expect(five.confidence(gps), CalibrationConfidence.green);
    });
  });
}

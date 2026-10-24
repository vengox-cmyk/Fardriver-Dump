import 'package:arcdash/models/gps_calibration.dart';
import 'package:arcdash/models/speed_source.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ride_fixtures.dart';

void main() {
  const analyzer = CalibrationAnalyzer();

  group('sample filter', () {
    test('steady straight seconds are kept, ride edges have no window', () {
      final a = analyzer.analyze(ride([const Leg(12, 50)]));
      expect(a.verdicts.first, SampleVerdict.noWindow);
      expect(a.verdicts.last, SampleVerdict.noWindow);
      expect(a.verdicts.sublist(1, 11), everyElement(SampleVerdict.kept));
      expect(a.segments, hasLength(1));
      expect(a.cleanSeconds, 10);
    });

    test('20 km/h or slower is rejected', () {
      final a = analyzer.analyze(ride([const Leg(10, 18)]));
      expect(a.verdicts, everyElement(SampleVerdict.tooSlow));
      expect(a.segments, isEmpty);
    });

    test('speed accuracy above 0.5 m/s is rejected', () {
      final a = analyzer.analyze(ride([const Leg(10, 50, speedAccuracy: 0.8)]));
      expect(a.verdicts, everyElement(SampleVerdict.poorAccuracy));
    });

    test('without speed accuracy, horizontal accuracy ≤10 m decides', () {
      final bad = analyzer
          .analyze(ride([const Leg(10, 50, speedAccuracy: null, hAcc: 15)]));
      expect(bad.verdicts, everyElement(SampleVerdict.poorAccuracy));
      final ok = analyzer
          .analyze(ride([const Leg(10, 50, speedAccuracy: null, hAcc: 6)]));
      expect(ok.verdicts.sublist(1, 9), everyElement(SampleVerdict.kept));
    });

    test('braking, missing GPS and missing rpm are rejected', () {
      final a = analyzer.analyze(ride([
        const Leg.brake(3, 50),
        const Leg(3, 50, gps: false),
        const Leg(3, 50, rpm: false),
      ]));
      expect(a.verdicts.sublist(0, 3), everyElement(SampleVerdict.braking));
      expect(a.verdicts.sublist(3, 6), everyElement(SampleVerdict.noGps));
      expect(a.verdicts.sublist(6, 9), everyElement(SampleVerdict.noRpm));
    });

    test('acceleration of 0.3 m/s² or more is rejected', () {
      // +1.5 km/h per second ≈ 0.42 m/s².
      final legs = [for (var i = 0; i < 10; i++) Leg(1, 40 + 1.5 * i)];
      final a = analyzer.analyze(ride(legs, noiseKph: 0));
      expect(
          a.verdicts.sublist(1, 9), everyElement(SampleVerdict.accelerating));
    });

    test('gentle speed change below 0.3 m/s² is accepted', () {
      // +0.7 km/h per second ≈ 0.19 m/s².
      final legs = [for (var i = 0; i < 10; i++) Leg(1, 40 + 0.7 * i)];
      final a = analyzer.analyze(ride(legs, noiseKph: 0));
      expect(a.verdicts.sublist(1, 9), everyElement(SampleVerdict.kept));
    });

    test('rpm jitter (CV ≥ 2 %) with steady GPS is rejected', () {
      // At 22 km/h a 4.5 % rpm wobble stays under the 0.3 m/s² limit but
      // its coefficient of variation is ~2.3 %.
      final legs = [
        for (var i = 0; i < 10; i++)
          Leg(1, 22, ratioScale: i.isEven ? 1.0 : 1 / 1.045),
      ];
      final a = analyzer.analyze(ride(legs, noiseKph: 0));
      expect(a.verdicts.sublist(1, 9), everyElement(SampleVerdict.rpmUnsteady));
    });

    test('heading change of 5 °/s or more is rejected', () {
      final a = analyzer.analyze(ride([const Leg(10, 50, headingRate: 8)]));
      expect(a.verdicts.sublist(1, 9), everyElement(SampleVerdict.turning));
      final ok = analyzer.analyze(ride([const Leg(10, 50, headingRate: 2)]));
      expect(ok.verdicts.sublist(1, 9), everyElement(SampleVerdict.kept));
    });

    test('a gap over 1.5 s breaks the window', () {
      final samples = ride([const Leg(10, 50)]);
      final shifted = [
        ...samples.take(5),
        for (final s in samples.skip(5))
          CalibrationSample(
            at: s.at.add(const Duration(seconds: 3)),
            gps: s.gps,
            rpm: s.rpm,
            controllerKph: s.controllerKph,
            braking: s.braking,
          ),
      ];
      final a = analyzer.analyze(shifted);
      expect(a.verdicts[4], SampleVerdict.noWindow);
      expect(a.verdicts[5], SampleVerdict.noWindow);
    });

    test('runs shorter than 5 s become shortSegment', () {
      final a = analyzer.analyze(ride([
        const Leg(6, 50), // 1 edge + 5 kept... minus next window edge
        const Leg.brake(1, 50),
        const Leg(4, 50),
        const Leg.brake(1, 50),
      ]));
      // Second leg has 4 steady seconds → too short.
      expect(
          a.verdicts.sublist(7, 11), everyElement(SampleVerdict.shortSegment));
      expect(a.segments, hasLength(1));
    });

    test('a sustained ratio offset (wheel slip) is rejected as outlier', () {
      final a = analyzer.analyze(ride([
        ...steadyLegs(6, [30, 50]),
        const Leg(8, 50, ratioScale: 1.08),
        const Leg.brake(1, 50),
      ]));
      final slip = a.verdicts.sublist(66, 74);
      expect(slip.where((v) => v == SampleVerdict.outlier).length,
          greaterThanOrEqualTo(6));
      expect(a.segments, hasLength(6));
    });
  });

  group('fit and confidence', () {
    test('clean two-band ride recovers k and is green', () {
      final a = analyzer.analyze(ride(steadyLegs(8, [30, 50])));
      final fit = CalibrationFit.fromAnalysis(a)!;
      expect(fit.kGps, closeTo(kTrue, kTrue * 0.002));
      expect(fit.segments, 8);
      expect(fit.bands, {SpeedBand.kph20to40, SpeedBand.kph40to60});
      expect(fit.ciRelative, lessThan(0.005));
      expect(fit.confidence, CalibrationConfidence.green);
      expect(fit.interceptKph!.abs(), lessThan(1));
      expect(fit.kByBand.keys, hasLength(2));
    });

    test('one band is at most yellow even with tight CI', () {
      final a = analyzer.analyze(ride(steadyLegs(8, [50])));
      final fit = CalibrationFit.fromAnalysis(a)!;
      expect(fit.confidence, CalibrationConfidence.yellow);
    });

    test('fewer than 3 segments is red', () {
      final a = analyzer.analyze(ride(steadyLegs(2, [30, 50])));
      expect(CalibrationFit.fromAnalysis(a)!.confidence,
          CalibrationConfidence.red);
    });

    test('no segment → no fit', () {
      expect(
          CalibrationFit.fromAnalysis(
              analyzer.analyze(ride([const Leg(4, 50)]))),
          isNull);
    });

    test('bootstrap is deterministic for a seed', () {
      final a = analyzer.analyze(ride(steadyLegs(6, [30, 50]), noiseKph: 1));
      final f1 = CalibrationFit.fromAnalysis(a)!;
      final f2 = CalibrationFit.fromAnalysis(a)!;
      expect(f1.ciRelative, f2.ciRelative);
      expect(f1.ciRelative, greaterThan(0));
    });

    test('rateConfidence thresholds', () {
      expect(rateConfidence(ciRelative: 0.004, segments: 6, bands: 2),
          CalibrationConfidence.green);
      expect(rateConfidence(ciRelative: 0.004, segments: 5, bands: 2),
          CalibrationConfidence.yellow);
      expect(rateConfidence(ciRelative: 0.012, segments: 8, bands: 3),
          CalibrationConfidence.yellow);
      expect(rateConfidence(ciRelative: 0.02, segments: 8, bands: 3),
          CalibrationConfidence.red);
      expect(rateConfidence(ciRelative: null, segments: 8, bands: 3),
          CalibrationConfidence.red);
    });

    test('through-zero weights favour accurate seconds', () {
      CalibrationSample s(double v, double rpm, double sa) => CalibrationSample(
            at: t0,
            gps: GpsSpeedSample(
                speedKph: v,
                accuracyMeters: 3,
                speedAccuracyMps: sa,
                capturedAt: t0),
            rpm: rpm,
            controllerKph: v,
            braking: false,
          );
      final seg = CalibrationSegment([s(50, 2000, 0.1), s(55, 2000, 1.0)]);
      final k = CalibrationFit.throughZero([seg]);
      expect(k, closeTo(50 / 2000, 0.0002));
    });
  });

  group('helpers', () {
    test('median, CV and heading delta', () {
      expect(median([3, 1, 2]), 2);
      expect(median([4, 1, 2, 3]), 2.5);
      expect(coefficientOfVariation([10, 10, 10]), 0);
      expect(headingDelta(350, 10), 20);
      expect(headingDelta(10, 350), 20);
      expect(SpeedBand.of(39.9), SpeedBand.kph20to40);
      expect(SpeedBand.of(85), SpeedBand.kph80plus);
    });
  });
}

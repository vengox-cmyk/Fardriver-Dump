import 'dart:io';

import 'package:arcdash/models/gps_calibration.dart';
import 'package:arcdash/models/speed_suggestions.dart';
import 'package:arcdash/services/calibration_csv.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression test on a real ride: BLU View 2 (B131DL, Android 11) with a
/// FarDriver ND72530, 2026-11-01. v1.2.2 rejected every second of it
/// (gps_accuracy 173, too_slow 197, no_rpm 50, braking 4 → 0 clean s)
/// because the phone reports a speed accuracy of 1.2–1.9 m/s. The rider's
/// own hand fit of the same file gave GPS/BLE ≈ 0.965 (RateRatio ≈ 4145).
void main() {
  final saved = CalibrationCsv.parse(
      File('test/fixtures/calibration/blu_view2_ride.csv').readAsStringSync());
  final session = saved.toSessionState();
  final analysis = session.analysis!;
  final fit = session.fit;

  int count(SampleVerdict v) => analysis.verdicts.where((x) => x == v).length;

  test('fixture parses with its settings snapshot', () {
    expect(saved.samples, hasLength(424));
    expect(saved.settings.ble!.rateRatio, 4000);
    expect(saved.settings.speedPulses, 11);
    expect(saved.settings.spdPulseNum, 38050);
  });

  test('low-end phone accuracy no longer rejects the ride', () {
    expect(count(SampleVerdict.poorAccuracy), 0);
    expect(count(SampleVerdict.tooSlow), 197);
    expect(count(SampleVerdict.noRpm), 50);
    expect(count(SampleVerdict.braking), 4);
  });

  test('fit lands at GPS/BLE ≈ 0.96–0.975 with a reasonable clean count', () {
    expect(fit, isNotNull);
    expect(analysis.cleanSeconds, inInclusiveRange(60, 110));
    expect(fit!.segments, greaterThanOrEqualTo(5));
    final ble = saved.settings.ble!;
    final ratio = fit.kGps / ble.kBle;
    expect(ratio, inInclusiveRange(0.96, 0.975));
    final suggestion = RateRatioSuggestion.compute(ble, fit.kGps);
    expect(suggestion.suggested, inInclusiveRange(4100, 4170));
    expect(suggestion.isSuspicious, isFalse);
    expect(fit.confidence, isNot(CalibrationConfidence.red));
  });
}

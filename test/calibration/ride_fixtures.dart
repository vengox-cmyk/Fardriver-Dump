import 'dart:math' as math;

import 'package:arcdash/models/gps_calibration.dart';
import 'package:arcdash/models/speed_source.dart';

/// Baseline from issue #2: 120/70-12, RateRatio 4000 → k = 0.022280.
const double kTrue = 0.022280;
final DateTime t0 = DateTime.utc(2026, 10, 24, 12);

/// One leg of a synthetic ride.
class Leg {
  final int seconds;
  final double kph;

  /// rpm = kph / (kTrue × ratioScale); 1.1 = wheel turning 10 % "slower".
  final double ratioScale;
  final bool braking;
  final double? speedAccuracy;
  final double hAcc;
  final double headingRate;
  final bool gps;
  final bool rpm;

  const Leg(
    this.seconds,
    this.kph, {
    this.ratioScale = 1,
    this.braking = false,
    this.speedAccuracy = 0.3,
    this.hAcc = 4,
    this.headingRate = 0,
    this.gps = true,
    this.rpm = true,
  });

  const Leg.brake(int seconds, double kph) : this(seconds, kph, braking: true);
}

/// 1 Hz samples. [noiseKph] adds deterministic ±noise on GPS speed.
List<CalibrationSample> ride(List<Leg> legs,
    {double noiseKph = 0.1, int seed = 7, double k = kTrue}) {
  final random = math.Random(seed);
  final out = <CalibrationSample>[];
  var t = t0;
  var heading = 90.0;
  for (final leg in legs) {
    for (var i = 0; i < leg.seconds; i++) {
      heading = (heading + leg.headingRate) % 360;
      final v = leg.kph + (random.nextDouble() * 2 - 1) * noiseKph;
      out.add(CalibrationSample(
        at: t,
        gps: leg.gps
            ? GpsSpeedSample(
                speedKph: v,
                accuracyMeters: leg.hAcc,
                speedAccuracyMps: leg.speedAccuracy,
                headingDeg: heading,
                capturedAt: t,
              )
            : null,
        rpm: leg.rpm ? leg.kph / (k * leg.ratioScale) : null,
        controllerKph: leg.kph * 1.02,
        braking: leg.braking,
      ));
      t = t.add(const Duration(seconds: 1));
    }
  }
  return out;
}

/// [count] steady 10 s legs alternating between [speeds], separated by one
/// braking second at the same speed.
List<Leg> steadyLegs(int count, List<double> speeds) => [
      for (var i = 0; i < count; i++) ...[
        Leg(10, speeds[i % speeds.length]),
        Leg.brake(1, speeds[i % speeds.length]),
      ],
    ];

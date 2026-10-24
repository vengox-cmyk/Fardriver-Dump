import 'dart:math' as math;

import 'package:arcdash/models/gps_calibration.dart';

/// Read-only setting suggestions from a GPS calibration (issue #2, v1.2).
/// The rider applies them in the official FarDriver app; FarSure never
/// writes to the controller.

/// Controller wheel geometry (0xD0) that defines the BLE/app speed.
class BleSpeedSettings {
  final int wheelRadius;
  final int wheelWidth;
  final int wheelRatio;
  final int rateRatio;

  const BleSpeedSettings({
    required this.wheelRadius,
    required this.wheelWidth,
    required this.wheelRatio,
    required this.rateRatio,
  });

  /// 0.00376991136 × (WheelRadius×1270 + WheelWidth×WheelRatio): the
  /// km/h-per-rpm constant times RateRatio (89.1207 for 120/70-12).
  double get tireConstant =>
      0.00376991136 * (wheelRadius * 1270.0 + wheelWidth * wheelRatio);

  /// App/BLE km/h per rpm (k_BLE), same formula as UnitConverter.
  double get kBle => rateRatio == 0 ? 0 : tireConstant / rateRatio;

  /// What the official app shows as GearRatio.
  double get gearRatio => rateRatio / 1000.0;
}

/// Signed relative error of a display constant against GPS: +0.02 means the
/// display reads 2 % high.
double speedError({required double kDisplay, required double kGps}) =>
    kDisplay / kGps - 1;

class RateRatioSuggestion {
  static const int minValue = 1;
  static const int maxValue = 65535; // u16 in 0xD0
  static const double largeChange = 0.30;

  final BleSpeedSettings current;
  final double kGps;
  final int suggested;

  /// The raw suggestion was outside 1..65535 and has been clamped.
  final bool clamped;

  const RateRatioSuggestion._(
      this.current, this.kGps, this.suggested, this.clamped);

  /// RateRatio_new = RateRatio_old × k_BLE / k_gps.
  factory RateRatioSuggestion.compute(BleSpeedSettings current, double kGps) {
    final raw = current.rateRatio * current.kBle / kGps;
    final rounded = raw.isFinite ? raw.round() : maxValue;
    final value = rounded.clamp(minValue, maxValue);
    return RateRatioSuggestion._(current, kGps, value, value != rounded);
  }

  double get error => speedError(kDisplay: current.kBle, kGps: kGps);
  double get suggestedGearRatio => suggested / 1000.0;
  double get change => suggested / current.rateRatio - 1;

  /// More than 30 % usually means a bad GPS run or wrong wheel / pulley
  /// (belt) ratio settings, not a real calibration error.
  bool get isSuspicious => change.abs() > largeChange || clamped;
  bool get isChange => suggested != current.rateRatio;
}

/// A "DKD reads…" tap: what the controller and GPS said at that instant,
/// and the DKD number the rider entered after stopping.
class DkdSnapshot {
  final DateTime at;
  final double rpm;
  final double? gpsKph;
  final double controllerKph;
  final double? dkdKph;

  const DkdSnapshot({
    required this.at,
    required this.rpm,
    required this.gpsKph,
    required this.controllerKph,
    this.dkdKph,
  });

  DkdSnapshot withReading(double? kph) => DkdSnapshot(
      at: at,
      rpm: rpm,
      gpsKph: gpsKph,
      controllerKph: controllerKph,
      dkdKph: kph);

  bool get usable => dkdKph != null && dkdKph! > 0 && rpm > 0;
}

/// k_DKD = DKD km/h per controller rpm, through zero over the taps.
class DkdFit {
  final double kDkd;
  final int taps;

  /// 95 % CI half-width of the tap mean, relative (null for < 2 taps).
  final double? ciRelative;

  const DkdFit(this.kDkd, this.taps, this.ciRelative);

  static DkdFit? fromSnapshots(List<DkdSnapshot> snapshots) {
    final taps = snapshots.where((s) => s.usable).toList();
    if (taps.isEmpty) return null;
    var dr = 0.0, rr = 0.0;
    for (final t in taps) {
      dr += t.dkdKph! * t.rpm;
      rr += t.rpm * t.rpm;
    }
    final k = dr / rr;
    double? ci;
    if (taps.length >= 2) {
      final ratios = [for (final t in taps) t.dkdKph! / t.rpm];
      final mean = ratios.reduce((a, b) => a + b) / ratios.length;
      final variance =
          ratios.fold<double>(0, (sum, r) => sum + (r - mean) * (r - mean)) /
              (ratios.length - 1);
      ci = _t95(taps.length - 1) * math.sqrt(variance / ratios.length) / mean;
    }
    return DkdFit(k, taps.length, ci);
  }

  /// Confidence of the DKD error: tap spread combined with the GPS fit.
  CalibrationConfidence confidence(CalibrationFit gps) {
    final tapCi = ciRelative;
    final gpsCi = gps.ciRelative;
    if (tapCi == null || gpsCi == null || taps < 3) {
      return CalibrationConfidence.red;
    }
    final combined = math.sqrt(tapCi * tapCi + gpsCi * gpsCi);
    if (combined <= 0.005 &&
        taps >= 5 &&
        gps.confidence == CalibrationConfidence.green) {
      return CalibrationConfidence.green;
    }
    if (combined <= 0.015 && gps.confidence != CalibrationConfidence.red) {
      return CalibrationConfidence.yellow;
    }
    return CalibrationConfidence.red;
  }

  double? combinedCi(CalibrationFit gps) {
    if (ciRelative == null || gps.ciRelative == null) return null;
    return math
        .sqrt(ciRelative! * ciRelative! + gps.ciRelative! * gps.ciRelative!);
  }

  static double _t95(int df) => switch (df) {
        1 => 12.71,
        2 => 4.30,
        3 => 3.18,
        4 => 2.78,
        5 => 2.57,
        6 => 2.45,
        7 => 2.36,
        8 => 2.31,
        9 => 2.26,
        _ => df < 30 ? 2.1 : 1.96,
      };
}

/// One-wire DKD display trim via Speed Pulses (coarse) and SpdPulseNum
/// (fine). Confirmed in the field: larger SpdPulseNum = slower display.
/// Assumed shape (to be verified with ride data): display ∝ SP / SPN.
class DkdSuggestion {
  static const int minSpeedPulses = 1;
  static const int maxSpeedPulses = 31; // 5-bit field
  static const int minSpdPulseNum = 500;
  static const int maxSpdPulseNum = 65530;

  /// Above this error a Speed Pulses step comes first (one step ≈ 9 %).
  static const double coarseThreshold = 0.04;

  final int speedPulses;
  final int spdPulseNum;
  final double kDkd;
  final double kGps;
  final int suggestedSpeedPulses;
  final int suggestedSpdPulseNum;
  final bool clamped;

  const DkdSuggestion._({
    required this.speedPulses,
    required this.spdPulseNum,
    required this.kDkd,
    required this.kGps,
    required this.suggestedSpeedPulses,
    required this.suggestedSpdPulseNum,
    required this.clamped,
  });

  factory DkdSuggestion.compute({
    required int speedPulses,
    required int spdPulseNum,
    required double kDkd,
    required double kGps,
  }) {
    final error = speedError(kDisplay: kDkd, kGps: kGps);
    var sp = speedPulses;
    var clamped = false;
    if (error.abs() > coarseThreshold && speedPulses > 0) {
      final rawSp = (speedPulses * kGps / kDkd).round();
      sp = rawSp.clamp(minSpeedPulses, maxSpeedPulses);
      clamped = sp != rawSp;
    }
    final ratio = speedPulses > 0 ? sp / speedPulses : 1.0;
    final rawSpn = (spdPulseNum * ratio * kDkd / kGps).round();
    final spn = rawSpn.clamp(minSpdPulseNum, maxSpdPulseNum);
    return DkdSuggestion._(
      speedPulses: speedPulses,
      spdPulseNum: spdPulseNum,
      kDkd: kDkd,
      kGps: kGps,
      suggestedSpeedPulses: sp,
      suggestedSpdPulseNum: spn,
      clamped: clamped || spn != rawSpn,
    );
  }

  double get error => speedError(kDisplay: kDkd, kGps: kGps);
  bool get changesSpeedPulses => suggestedSpeedPulses != speedPulses;

  /// Fallback on the DKD itself (password 153): CC_new = CC_old × factor.
  double get ccFactor => kGps / kDkd;
}

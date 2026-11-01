import 'package:arcdash/models/speed_suggestions.dart';

/// Dash (one-wire DKD display) speed, v1.2.3.
///
/// What is known (sources: fardriver.hpp, FarDriver manual §6.1, forum):
/// * The controller sends a speed pulse count over the one-wire line; the
///   dash turns it into km/h with its own wheel/pole settings. FarSure
///   cannot see those dash settings, so no absolute formula from rpm,
///   SpeedPulse and SpdPulseNum alone is published anywhere we could find
///   (fardriver.hpp has the two fields but no formula).
/// * Direction of SpdPulseNum: VERIFIED by the owner's hands-on calibration
///   on their scooter (1 Nov 2026): a HIGHER SpdPulseNum makes the DKD show a
///   HIGHER speed, in fine steps. This matches the elektroroller-forum.de
///   data (t=37065, ND72530 + one-wire dash), which fits
///   display ∝ SpeedPulse × SpdPulseNum. The FarDriver manual's
///   "larger SpdPulseNum = slower display" is wrong for this dash.
/// * Speed Pulses is the coarse step (one step ≈ 1/SP, ≈ 9 % at 11). Its
///   direction (larger = faster display) is what both the manual and the
///   forum data say, but it has not been checked hands-on yet; kept as is.
///
/// So the dash speed is computed from a measured anchor — a stationary
/// "Dash speed check" (rear wheel lifted, rider types what the dash shows)
/// or older DKD readings: dash_kmh ≈ rpm × k_anchor at the anchor's
/// SpeedPulse/SpdPulseNum, scaled ∝ SP × SPN when the settings differ.
/// Without a dash-check anchor the column is labelled "estimated"; once a
/// stationary dash check has anchored it, it is "calibrated from dash
/// check". It is never used in a fit either way.
const String dashEstimateLabel = 'estimated';
const String dashCalibratedLabel = 'calibrated from dash check';

/// Status of the dash-speed column for [anchor] (see library comment).
String dashStatusLabel(DashAnchor? anchor) =>
    anchor != null && anchor.fromDashCheck
        ? '$dashCalibratedLabel (${anchor.source})'
        : dashEstimateLabel;

/// Empirical dash constant: dash km/h per controller rpm, measured at
/// [speedPulses] / [spdPulseNum].
class DashAnchor {
  final double kDash;
  final int? speedPulses;
  final int? spdPulseNum;
  final int points;
  final DateTime? measuredAt;
  final String source;

  /// True when the anchor comes from a stationary Dash speed check (then the
  /// column is shown as calibrated); false for in-ride DKD readings.
  final bool fromDashCheck;

  const DashAnchor({
    required this.kDash,
    required this.speedPulses,
    required this.spdPulseNum,
    required this.points,
    required this.source,
    this.measuredAt,
    this.fromDashCheck = false,
  });

  /// Through-zero fit over usable dash readings (stationary checks or DKD
  /// entries), all taken at the same settings. Null without a usable point.
  static DashAnchor? fromReadings(
    List<DkdSnapshot> readings, {
    required int? speedPulses,
    required int? spdPulseNum,
    required String source,
    bool fromDashCheck = false,
  }) {
    final fit = DkdFit.fromSnapshots(readings);
    if (fit == null || !fit.kDkd.isFinite || fit.kDkd <= 0) return null;
    final usable = readings.where((r) => r.usable).toList();
    return DashAnchor(
      kDash: fit.kDkd,
      speedPulses: speedPulses,
      spdPulseNum: spdPulseNum,
      points: fit.taps,
      source: source,
      measuredAt: usable.isEmpty ? null : usable.last.at,
      fromDashCheck: fromDashCheck,
    );
  }

  /// Dash km/h per rpm at [sp] / [spn]. Exact (empirical) when the settings
  /// equal the anchor's; otherwise scaled ∝ SP × SPN (higher SpdPulseNum =
  /// higher dash speed, verified hands-on by the owner — see above).
  /// Null when the scaling is impossible (unknown settings).
  double? kFor({int? sp, int? spn}) {
    final aSp = speedPulses, aSpn = spdPulseNum;
    if (sp == aSp && spn == aSpn) return kDash;
    if (sp == null || spn == null || aSp == null || aSpn == null) return null;
    if (sp <= 0 || spn <= 0 || aSp <= 0 || aSpn <= 0) return null;
    return kDash * (sp / aSp) * (spn / aSpn);
  }

  bool sameSettings({int? sp, int? spn}) =>
      sp == speedPulses && spn == spdPulseNum;

  /// Estimated dash km/h at [rpm] (null when unknown or rpm ≤ 0).
  double? estimateKph(double? rpm, {int? sp, int? spn}) {
    if (rpm == null || !rpm.isFinite || rpm <= 0) return null;
    final k = kFor(sp: sp, spn: spn);
    return k == null ? null : rpm * k;
  }
}

/// Result of a stationary dash check: dash vs a reference speed constant.
class DashCheckResult {
  final DkdFit fit;
  final double kReference;

  /// 'gps' (from a saved calibration ride) or 'app' (FarSure's own speed,
  /// itself only as good as RateRatio).
  final String referenceSource;
  final DkdSuggestion? suggestion;

  const DashCheckResult({
    required this.fit,
    required this.kReference,
    required this.referenceSource,
    required this.suggestion,
  });

  /// +0.03 = dash reads 3 % high.
  double get error => speedError(kDisplay: fit.kDkd, kGps: kReference);

  /// Needs 2+ points (3 recommended) and a reference.
  static DashCheckResult? compute({
    required List<DkdSnapshot> points,
    required double? kGps,
    required double? kApp,
    required int? speedPulses,
    required int? spdPulseNum,
  }) {
    final usable = points.where((p) => p.usable).toList();
    if (usable.length < 2) return null;
    final fit = DkdFit.fromSnapshots(usable);
    if (fit == null) return null;
    final (kRef, src) = kGps != null && kGps > 0
        ? (kGps, 'gps')
        : kApp != null && kApp > 0
            ? (kApp, 'app')
            : (null, '');
    if (kRef == null) return null;
    final suggestion = speedPulses != null && spdPulseNum != null
        ? DkdSuggestion.compute(
            speedPulses: speedPulses,
            spdPulseNum: spdPulseNum,
            kDkd: fit.kDkd,
            kGps: kRef)
        : null;
    return DashCheckResult(
        fit: fit,
        kReference: kRef,
        referenceSource: src,
        suggestion: suggestion);
  }
}

import 'dart:math' as math;

import 'package:arcdash/models/speed_source.dart';

/// GPS speed calibration maths (issue #2, v1.2). Pure Dart, no I/O, so every
/// step is unit-testable. FarSure only *suggests* values; it never writes.
///
/// Pipeline: per-second [CalibrationSample]s -> [CalibrationAnalyzer.analyze]
/// (filter + segments) -> [CalibrationFit] (through-zero k_gps + bootstrap
/// confidence) -> [SpeedSuggestions] (RateRatio / SpeedPulse / SpdPulseNum).

/// One controller rpm value (0xE2 MeasureSpeed) and when it arrived.
class RpmReading {
  final double rpm;
  final DateTime at;

  const RpmReading({required this.rpm, required this.at});
}

/// One paired second: the GPS fix of that second plus the mean controller
/// RPM (0xE2 MeasureSpeed) received during it.
class CalibrationSample {
  final DateTime at;
  final GpsSpeedSample? gps;

  /// Mean BLE rpm within this second, null if no 0xE2 frame arrived.
  final double? rpm;

  /// Controller (BLE) speed shown by FarSure at that time, for the CSV.
  final double controllerKph;
  final bool braking;

  const CalibrationSample({
    required this.at,
    required this.gps,
    required this.rpm,
    this.controllerKph = 0,
    this.braking = false,
  });

  double? get gpsKph => gps?.speedKph;

  /// v/rpm of this second (km/h per rpm), null when not computable.
  double? get ratio {
    final v = gps?.speedKph;
    final r = rpm;
    if (v == null || r == null || r <= 0) return null;
    return v / r;
  }
}

/// Why a second was kept or rejected. [code] is stable for CSV export.
enum SampleVerdict {
  kept('kept', 'Kept'),
  noGps('no_gps', 'No GPS fix'),
  noRpm('no_rpm', 'No controller RPM'),
  braking('braking', 'Braking'),
  tooSlow('too_slow', 'Below minimum speed'),
  poorAccuracy('gps_accuracy', 'GPS accuracy too low'),
  noWindow('no_window', 'Not enough neighbouring seconds'),
  accelerating('accelerating', 'Accelerating or braking'),
  rpmUnsteady('rpm_unsteady', 'RPM not steady'),
  turning('turning', 'Turning'),
  outlier('outlier', 'Outlier (v/rpm far from median)'),
  shortSegment('short_segment', 'Steady run shorter than minimum');

  final String code;
  final String label;

  const SampleVerdict(this.code, this.label);
}

/// Speed bands from issue #2. A result needs data from >= 2 of them.
enum SpeedBand {
  kph20to40('20–40 km/h'),
  kph40to60('40–60 km/h'),
  kph60to80('60–80 km/h'),
  kph80plus('80+ km/h');

  final String label;

  const SpeedBand(this.label);

  static SpeedBand of(double kph) {
    if (kph < 40) return kph20to40;
    if (kph < 60) return kph40to60;
    if (kph < 80) return kph60to80;
    return kph80plus;
  }
}

/// Thresholds of the sample filter.
///
/// v1.2.3: tuned for ordinary phones. The v1.2 spec gate (speed accuracy
/// ≤ 0.5 m/s, 1-second acceleration ≤ 0.3 m/s²) rejected every second of a
/// real ride on a BLU View 2 (reported speed accuracy 1.2–1.9 m/s). The
/// accuracy a phone reports is a per-second 1-sigma bound; that noise
/// averages out over a ≥5 s steady run and the fit weights each second by
/// 1/accuracy², so the gate only has to drop *bad* fixes, not average ones.
class CalibrationFilterConfig {
  final double minSpeedKph;

  /// A second is accepted when its reported speed accuracy is at most
  /// max([maxSpeedAccuracyMps], [maxRelativeSpeedAccuracy] × speed).
  final double maxSpeedAccuracyMps;

  /// Relative part of the accuracy gate (0.08 = 8 % of the GPS speed).
  final double maxRelativeSpeedAccuracy;
  final double maxHorizontalAccuracyM;

  /// |accel| limit for GPS speed and for rpm-derived speed (m/s²), measured
  /// across the 3 s window (next second vs previous second).
  final double maxAccelMps2;

  /// Max coefficient of variation of rpm over the 3 s window.
  final double maxRpmVariation;
  final double maxHeadingRateDegPerS;

  /// Outlier gate: |ratio - median| > [outlierMads] x MAD (scaled to sigma).
  final double outlierMads;

  /// MAD floor relative to the median, so a very clean ride does not reject
  /// ordinary 1 Hz noise.
  final double minRelativeMad;

  /// Outlier gate is only applied once this many candidate seconds exist.
  final int minOutlierPopulation;
  final int minSegmentSeconds;

  /// Two samples farther apart than this are not neighbours (s).
  final double maxGapSeconds;

  const CalibrationFilterConfig({
    this.minSpeedKph = 20,
    this.maxSpeedAccuracyMps = 2.5,
    this.maxRelativeSpeedAccuracy = 0.08,
    this.maxHorizontalAccuracyM = 10,
    this.maxAccelMps2 = 0.35,
    this.maxRpmVariation = 0.03,
    this.maxHeadingRateDegPerS = 5,
    this.outlierMads = 3,
    this.minRelativeMad = 0.003,
    this.minOutlierPopulation = 5,
    this.minSegmentSeconds = 5,
    this.maxGapSeconds = 1.5,
  });

  /// Speed-accuracy limit (m/s) at [speedKph].
  double speedAccuracyLimitMps(double speedKph) => math.max(
      maxSpeedAccuracyMps, maxRelativeSpeedAccuracy * speedKph / 3.6);

  /// Whether a single fix is precise enough to be used (same rule as the
  /// filter; also drives the live GPS lock colour).
  bool fixIsPrecise(GpsSpeedSample gps) {
    final speedAcc = gps.speedAccuracyMps;
    if (speedAcc != null && speedAcc > 0) {
      return speedAcc <= speedAccuracyLimitMps(gps.speedKph);
    }
    return gps.accuracyMeters.isFinite &&
        gps.accuracyMeters <= maxHorizontalAccuracyM;
  }
}

/// A run of consecutive kept seconds (>= 5 s); one independent estimate.
class CalibrationSegment {
  final List<CalibrationSample> samples;

  const CalibrationSegment(this.samples);

  int get seconds => samples.length;
  DateTime get start => samples.first.at;
  DateTime get end => samples.last.at;

  double get meanKph =>
      samples.fold<double>(0, (sum, s) => sum + s.gpsKph!) / samples.length;

  SpeedBand get band => SpeedBand.of(meanKph);

  /// Σ w·v·rpm and Σ w·rpm², w = 1/σ² (σ = GPS speed accuracy, km/h).
  double get sumVR => samples.fold<double>(
      0, (sum, s) => sum + _weight(s) * s.gpsKph! * s.rpm!);
  double get sumRR =>
      samples.fold<double>(0, (sum, s) => sum + _weight(s) * s.rpm! * s.rpm!);

  /// This segment's own through-zero k.
  double get k => sumVR / sumRR;

  static double _weight(CalibrationSample s) {
    // Seconds without a reported speed accuracy (old Android) count as a
    // typical phone fix.
    final sigmaMps = math.max(s.gps?.speedAccuracyMps ?? 1.0, 0.1);
    final sigmaKph = sigmaMps * 3.6;
    return 1 / (sigmaKph * sigmaKph);
  }
}

class CalibrationAnalysis {
  final List<CalibrationSample> samples;

  /// One verdict per sample, same order.
  final List<SampleVerdict> verdicts;
  final List<CalibrationSegment> segments;

  const CalibrationAnalysis({
    required this.samples,
    required this.verdicts,
    required this.segments,
  });

  int get cleanSeconds => segments.fold(0, (sum, s) => sum + s.seconds);
  Set<SpeedBand> get bands => segments.map((s) => s.band).toSet();

  Map<SampleVerdict, int> get verdictCounts {
    final counts = <SampleVerdict, int>{};
    for (final v in verdicts) {
      counts[v] = (counts[v] ?? 0) + 1;
    }
    return counts;
  }
}

/// Applies the issue #2 sample filter to a whole session. Deterministic and
/// cheap enough (O(n log n)) to re-run every second during a ride.
class CalibrationAnalyzer {
  final CalibrationFilterConfig config;

  const CalibrationAnalyzer([this.config = const CalibrationFilterConfig()]);

  CalibrationAnalysis analyze(List<CalibrationSample> input) {
    final samples = List<CalibrationSample>.unmodifiable(input);
    final verdicts = List<SampleVerdict>.filled(
        samples.length, SampleVerdict.kept,
        growable: false);

    for (var i = 0; i < samples.length; i++) {
      verdicts[i] = _basicVerdict(samples, i);
    }
    // Steadiness needs neighbours that passed the per-second checks above
    // (gps + rpm present); speed/accuracy of neighbours do not matter.
    for (var i = 0; i < samples.length; i++) {
      if (verdicts[i] != SampleVerdict.kept) continue;
      verdicts[i] = _windowVerdict(samples, i);
    }
    _rejectOutliers(samples, verdicts);
    final segments = _buildSegments(samples, verdicts);
    return CalibrationAnalysis(
        samples: samples, verdicts: verdicts, segments: segments);
  }

  SampleVerdict _basicVerdict(List<CalibrationSample> samples, int i) {
    final s = samples[i];
    final gps = s.gps;
    if (gps == null || !gps.speedKph.isFinite) return SampleVerdict.noGps;
    if (s.rpm == null || s.rpm! <= 0 || !s.rpm!.isFinite) {
      return SampleVerdict.noRpm;
    }
    if (s.braking) return SampleVerdict.braking;
    if (gps.speedKph <= config.minSpeedKph) return SampleVerdict.tooSlow;
    if (!config.fixIsPrecise(gps)) return SampleVerdict.poorAccuracy;
    return SampleVerdict.kept;
  }

  bool _usable(CalibrationSample s) =>
      s.gps != null && s.rpm != null && s.rpm! > 0;

  double _dt(CalibrationSample a, CalibrationSample b) =>
      b.at.difference(a.at).inMilliseconds / 1000.0;

  /// 3 s window centred on [i]: previous, this and next second.
  SampleVerdict _windowVerdict(List<CalibrationSample> samples, int i) {
    if (i == 0 || i == samples.length - 1) return SampleVerdict.noWindow;
    final prev = samples[i - 1];
    final cur = samples[i];
    final next = samples[i + 1];
    if (!_usable(prev) || !_usable(next)) return SampleVerdict.noWindow;
    final dt1 = _dt(prev, cur);
    final dt2 = _dt(cur, next);
    if (dt1 <= 0 ||
        dt2 <= 0 ||
        dt1 > config.maxGapSeconds ||
        dt2 > config.maxGapSeconds) {
      return SampleVerdict.noWindow;
    }

    // Acceleration over the whole 3 s window (central difference: next vs
    // previous second). One-second differences of a ±1.3 m/s phone GPS are
    // mostly noise; the two-second span halves that noise while still
    // catching real throttle/brake changes.
    final span = dt1 + dt2;
    final gpsAccel = (next.gpsKph! - prev.gpsKph!).abs() / 3.6 / span;
    // RPM acceleration expressed as speed using this second's own v/rpm.
    final kLocal = cur.ratio!;
    final rpmAccel = (next.rpm! - prev.rpm!).abs() * kLocal / 3.6 / span;
    if (gpsAccel >= config.maxAccelMps2 || rpmAccel >= config.maxAccelMps2) {
      return SampleVerdict.accelerating;
    }

    final rpms = [prev.rpm!, cur.rpm!, next.rpm!];
    if (coefficientOfVariation(rpms) >= config.maxRpmVariation) {
      return SampleVerdict.rpmUnsteady;
    }

    final h0 = prev.gps!.headingDeg;
    final h1 = cur.gps!.headingDeg;
    final h2 = next.gps!.headingDeg;
    if (h0 != null && h1 != null && h2 != null) {
      final rate = math.max(
        headingDelta(h0, h1) / dt1,
        headingDelta(h1, h2) / dt2,
      );
      if (rate >= config.maxHeadingRateDegPerS) return SampleVerdict.turning;
    }
    return SampleVerdict.kept;
  }

  void _rejectOutliers(
      List<CalibrationSample> samples, List<SampleVerdict> verdicts) {
    final candidates = <int>[
      for (var i = 0; i < samples.length; i++)
        if (verdicts[i] == SampleVerdict.kept) i,
    ];
    if (candidates.length < config.minOutlierPopulation) return;
    final ratios = [for (final i in candidates) samples[i].ratio!];
    final med = median(ratios);
    final mad = median([for (final r in ratios) (r - med).abs()]);
    // 1.4826·MAD estimates sigma for normal noise.
    final sigma = math.max(1.4826 * mad, config.minRelativeMad * med);
    final limit = config.outlierMads * sigma;
    for (final i in candidates) {
      if ((samples[i].ratio! - med).abs() > limit) {
        verdicts[i] = SampleVerdict.outlier;
      }
    }
  }

  List<CalibrationSegment> _buildSegments(
      List<CalibrationSample> samples, List<SampleVerdict> verdicts) {
    final segments = <CalibrationSegment>[];
    var run = <int>[];
    void close() {
      if (run.isEmpty) return;
      if (run.length >= config.minSegmentSeconds) {
        segments.add(CalibrationSegment([for (final i in run) samples[i]]));
      } else {
        for (final i in run) {
          verdicts[i] = SampleVerdict.shortSegment;
        }
      }
      run = <int>[];
    }

    for (var i = 0; i < samples.length; i++) {
      if (verdicts[i] != SampleVerdict.kept) {
        close();
        continue;
      }
      if (run.isNotEmpty &&
          _dt(samples[run.last], samples[i]) > config.maxGapSeconds) {
        close();
      }
      run.add(i);
    }
    close();
    return segments;
  }
}

enum CalibrationConfidence {
  green('High'),
  yellow('Medium'),
  red('Low');

  final String label;

  const CalibrationConfidence(this.label);
}

/// Confidence rule from issue #2: green = CI ≤ ±0.5 %, ≥ 6 segments and
/// ≥ 2 bands; yellow = CI ≤ ±1.5 %; red otherwise. A bootstrap over fewer
/// than 3 segments says nothing, so that is always red.
CalibrationConfidence rateConfidence({
  required double? ciRelative,
  required int segments,
  required int bands,
}) {
  if (ciRelative == null || !ciRelative.isFinite || segments < 3) {
    return CalibrationConfidence.red;
  }
  if (ciRelative <= 0.005 && segments >= 6 && bands >= 2) {
    return CalibrationConfidence.green;
  }
  if (ciRelative <= 0.015) return CalibrationConfidence.yellow;
  return CalibrationConfidence.red;
}

/// Through-zero fit of GPS km/h on controller rpm: k_gps.
class CalibrationFit {
  /// True km/h per controller rpm.
  final double kGps;

  /// 95 % bootstrap CI half-width relative to [kGps] (0.004 = ±0.4 %), null
  /// with fewer than 2 segments.
  final double? ciRelative;
  final int segments;
  final int cleanSeconds;
  final Set<SpeedBand> bands;

  /// Diagnostic ordinary least-squares fit with intercept (km/h). Should be
  /// ≈ 0; a large intercept hints at lag or slip.
  final double? interceptKph;

  /// Per-band k, to spot tyre growth / slip.
  final Map<SpeedBand, double> kByBand;

  const CalibrationFit({
    required this.kGps,
    required this.ciRelative,
    required this.segments,
    required this.cleanSeconds,
    required this.bands,
    required this.interceptKph,
    required this.kByBand,
  });

  CalibrationConfidence get confidence => rateConfidence(
      ciRelative: ciRelative, segments: segments, bands: bands.length);

  static const int bootstrapRounds = 1000;

  /// Null when there is no clean segment yet.
  static CalibrationFit? fromAnalysis(CalibrationAnalysis analysis,
      {int seed = 2026}) {
    final segments = analysis.segments;
    if (segments.isEmpty) return null;
    final k = throughZero(segments);

    double? ci;
    if (segments.length >= 2) {
      final random = math.Random(seed);
      final ks = <double>[];
      for (var b = 0; b < bootstrapRounds; b++) {
        var vr = 0.0, rr = 0.0;
        for (var j = 0; j < segments.length; j++) {
          final s = segments[random.nextInt(segments.length)];
          vr += s.sumVR;
          rr += s.sumRR;
        }
        ks.add(vr / rr);
      }
      ks.sort();
      final lo = _percentile(ks, 0.025);
      final hi = _percentile(ks, 0.975);
      ci = (hi - lo) / 2 / k;
    }

    final byBand = <SpeedBand, List<CalibrationSegment>>{};
    for (final s in segments) {
      byBand.putIfAbsent(s.band, () => []).add(s);
    }

    return CalibrationFit(
      kGps: k,
      ciRelative: ci,
      segments: segments.length,
      cleanSeconds: analysis.cleanSeconds,
      bands: byBand.keys.toSet(),
      interceptKph: _intercept(segments),
      kByBand: {
        for (final e in byBand.entries) e.key: throughZero(e.value),
      },
    );
  }

  /// k = Σ(w·v·rpm) / Σ(w·rpm²).
  static double throughZero(List<CalibrationSegment> segments) {
    var vr = 0.0, rr = 0.0;
    for (final s in segments) {
      vr += s.sumVR;
      rr += s.sumRR;
    }
    return vr / rr;
  }

  static double? _intercept(List<CalibrationSegment> segments) {
    final xs = <double>[], ys = <double>[];
    for (final seg in segments) {
      for (final s in seg.samples) {
        xs.add(s.rpm!);
        ys.add(s.gpsKph!);
      }
    }
    if (xs.length < 3) return null;
    final mx = xs.reduce((a, b) => a + b) / xs.length;
    final my = ys.reduce((a, b) => a + b) / ys.length;
    var sxy = 0.0, sxx = 0.0;
    for (var i = 0; i < xs.length; i++) {
      sxy += (xs[i] - mx) * (ys[i] - my);
      sxx += (xs[i] - mx) * (xs[i] - mx);
    }
    if (sxx <= 0) return null; // a single speed: intercept undefined
    return my - (sxy / sxx) * mx;
  }

  static double _percentile(List<double> sorted, double p) {
    final pos = p * (sorted.length - 1);
    final lo = pos.floor();
    final hi = pos.ceil();
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
  }
}

double median(List<double> values) {
  if (values.isEmpty) return double.nan;
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Population standard deviation / mean.
double coefficientOfVariation(List<double> values) {
  final mean = values.reduce((a, b) => a + b) / values.length;
  if (mean == 0) return double.infinity;
  final variance =
      values.fold<double>(0, (sum, v) => sum + (v - mean) * (v - mean)) /
          values.length;
  return math.sqrt(variance) / mean.abs();
}

/// Smallest absolute angle between two headings, in degrees (0..180).
double headingDelta(double a, double b) {
  final d = ((b - a) % 360 + 360) % 360;
  return d > 180 ? 360 - d : d;
}

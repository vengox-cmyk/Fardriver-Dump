import 'dart:math' as math;

import 'package:arcdash/models/drive_state.dart';
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

  /// Gear + boost in that second (null when unknown / older files).
  final GearStatus? gear;

  const CalibrationSample({
    required this.at,
    required this.gps,
    required this.rpm,
    this.controllerKph = 0,
    this.braking = false,
    this.gear,
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
  /// Legacy (v1.2/v1.3 files). Since v1.4 only very hard acceleration is
  /// rejected this way; ordinary throttle changes are judged by
  /// [inconsistent].
  accelerating('accelerating', 'Accelerating or braking hard'),
  inconsistent('inconsistent', 'GPS and motor speed disagree'),
  gpsLag('gps_lag', 'GPS trailing the motor'),
  /// Legacy (v1.2/v1.3 files only; no longer produced).
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

  /// v1.4: hard limit on |GPS accel| across the 3 s window (m/s²). Only
  /// really hard throttle/brake is rejected outright, because the phone's
  /// GPS speed lags the motor there. Ordinary speed changes (hills, bumps,
  /// wind, throttle wobble) are fine as long as GPS and rpm agree.
  final double maxAccelMps2;

  /// v1.4 consistency gate: across the 3 s window, the change of GPS speed
  /// and the change of rpm-derived speed may differ by at most this much
  /// (m/s²). A disagreement means wheel slip, lag or a GPS glitch.
  final double maxDisagreementMps2;

  /// v1.4 consistency gate: this second's v/rpm may differ from the mean of
  /// its two neighbours by at most this fraction (one-second GPS glitch).
  final double maxRatioJump;

  /// v1.4 lag gate: a phone's GPS speed trails the motor by about
  /// [gpsLagSeconds]. While rpm changes, that lag alone makes v/rpm wrong by
  /// (rpm change per second / rpm) × lag; seconds where this estimated error
  /// exceeds [maxLagError] are rejected as [SampleVerdict.accelerating].
  final double gpsLagSeconds;
  final double maxLagError;

  /// v1.4 trailing gate: a phone's GPS speed reflects the motor of the
  /// seconds before it. If rpm moved by more than this fraction over the
  /// [trailSeconds] before a second, GPS has not caught up yet and that
  /// second is rejected as [SampleVerdict.gpsLag]. Hills, bumps and small
  /// throttle wobble stay well under 5 % and pass.
  final double maxTrailError;

  /// How many seconds before a sample the trailing gate looks back.
  final int trailSeconds;
  final double maxHeadingRateDegPerS;

  /// Outlier gate: |ratio - median| > [outlierMads] x MAD (scaled to sigma).
  final double outlierMads;

  /// MAD floor relative to the median, so a very clean ride does not reject
  /// ordinary 1 Hz noise.
  final double minRelativeMad;

  /// Outlier gate is only applied once this many candidate seconds exist.
  final int minOutlierPopulation;

  /// Floor of the stretch-level outlier gate, relative to the median k.
  final double minSegmentOutlier;
  /// Minimum steady stretch at low speed (s).
  final int minSegmentSeconds;

  /// Minimum steady stretch when its mean speed is at or above
  /// [fastSegmentKph] (s). Fast stretches on back roads are short, and at
  /// speed one second carries more signal.
  final int minFastSegmentSeconds;
  final double fastSegmentKph;

  /// Two samples farther apart than this are not neighbours (s).
  final double maxGapSeconds;

  const CalibrationFilterConfig({
    this.minSpeedKph = 20,
    this.maxSpeedAccuracyMps = 2.5,
    this.maxRelativeSpeedAccuracy = 0.08,
    this.maxHorizontalAccuracyM = 10,
    this.maxAccelMps2 = 2.0,
    this.maxDisagreementMps2 = 0.5,
    this.maxRatioJump = 0.06,
    this.gpsLagSeconds = 1.0,
    this.maxLagError = 0.04,
    this.maxTrailError = 0.05,
    this.trailSeconds = 2,
    this.maxHeadingRateDegPerS = 5,
    this.outlierMads = 3,
    this.minRelativeMad = 0.003,
    this.minOutlierPopulation = 5,
    this.minSegmentOutlier = 0.025,
    this.minSegmentSeconds = 5,
    this.minFastSegmentSeconds = 3,
    this.fastSegmentKph = 64,
    this.maxGapSeconds = 1.5,
  });

  /// Minimum stretch length for a stretch averaging [meanKph].
  int minSegmentSecondsAt(double meanKph) =>
      meanKph >= fastSegmentKph ? minFastSegmentSeconds : minSegmentSeconds;

  /// Speed-accuracy limit (m/s) at [speedKph].
  double speedAccuracyLimitMps(double speedKph) =>
      math.max(maxSpeedAccuracyMps, maxRelativeSpeedAccuracy * speedKph / 3.6);

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

  /// Splits this stretch into consecutive blocks of about [seconds] each
  /// (the remainder joins the last block) for the block bootstrap.
  List<CalibrationSegment> blocks(
      [int seconds = CalibrationFit.bootstrapBlockSeconds]) {
    final n = samples.length ~/ seconds;
    if (n <= 1) return [this];
    return [
      for (var i = 0; i < n; i++)
        CalibrationSegment(samples.sublist(
            i * seconds, i == n - 1 ? samples.length : (i + 1) * seconds)),
    ];
  }

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
    final segments = _rejectOutlierSegments(
        _buildSegments(samples, verdicts), samples, verdicts);
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

    // v1.4: consistency instead of steadiness. Across the 3 s window
    // (next vs previous second) the GPS speed change and the rpm-derived
    // speed change must agree. Both ride up a hill or over a bump
    // together; slip, GPS lag under hard throttle and GPS glitches make
    // them disagree.
    final span = dt1 + dt2;
    final dGps = next.gpsKph! - prev.gpsKph!;
    final kLocal = cur.ratio!;
    final dRpmKph = (next.rpm! - prev.rpm!) * kLocal;
    if (dGps.abs() / 3.6 / span >= config.maxAccelMps2) {
      return SampleVerdict.accelerating;
    }
    final lagError =
        (next.rpm! - prev.rpm!).abs() / span / cur.rpm! * config.gpsLagSeconds;
    if (lagError > config.maxLagError) return SampleVerdict.accelerating;
    if (_gpsTrails(samples, i)) return SampleVerdict.gpsLag;
    if ((dGps - dRpmKph).abs() / 3.6 / span >= config.maxDisagreementMps2) {
      return SampleVerdict.inconsistent;
    }
    final rp = prev.ratio, rn = next.ratio;
    if (rp != null && rn != null) {
      final ref = (rp + rn) / 2;
      if (ref > 0 && (kLocal - ref).abs() / ref > config.maxRatioJump) {
        return SampleVerdict.inconsistent;
      }
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

  /// GPS trails the motor: the GPS speed of second [i] still reflects the
  /// rpm of the seconds before it. If rpm moved over the
  /// [trailSeconds] before [i] by more than [CalibrationFilterConfig.maxTrailError]
  /// (relative), GPS has not caught up yet and v/rpm is biased.
  bool _gpsTrails(List<CalibrationSample> samples, int i) {
    final cur = samples[i];
    final r1 = cur.rpm!;
    if (r1 <= 0) return false;
    var lo = r1, hi = r1;
    for (var j = i - 1; j >= 0 && j >= i - config.trailSeconds; j--) {
      final s = samples[j];
      if (!_usable(s) || _dt(s, cur) > config.maxGapSeconds * (i - j)) break;
      lo = math.min(lo, s.rpm!);
      hi = math.max(hi, s.rpm!);
    }
    return (hi - lo) / r1 > config.maxTrailError;
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

  /// v1.4: a whole stretch whose own k is far from the other stretches
  /// (GPS still settling, a gust of slip) is dropped as [SampleVerdict.outlier].
  List<CalibrationSegment> _rejectOutlierSegments(
      List<CalibrationSegment> segments,
      List<CalibrationSample> samples,
      List<SampleVerdict> verdicts) {
    if (segments.length < config.minOutlierPopulation) return segments;
    final ks = [for (final s in segments) s.k];
    final med = median(ks);
    final mad = median([for (final k in ks) (k - med).abs()]);
    final limit = math.max(
        config.outlierMads * 1.4826 * mad, config.minSegmentOutlier * med);
    final kept = <CalibrationSegment>[];
    for (final seg in segments) {
      if ((seg.k - med).abs() <= limit) {
        kept.add(seg);
        continue;
      }
      for (var i = 0; i < samples.length; i++) {
        if (seg.samples.contains(samples[i])) {
          verdicts[i] = SampleVerdict.outlier;
        }
      }
    }
    return kept;
  }

  List<CalibrationSegment> _buildSegments(
      List<CalibrationSample> samples, List<SampleVerdict> verdicts) {
    final segments = <CalibrationSegment>[];
    var run = <int>[];
    void close() {
      if (run.isEmpty) return;
      final seg = CalibrationSegment([for (final i in run) samples[i]]);
      if (run.length >= config.minSegmentSecondsAt(seg.meanKph)) {
        segments.add(seg);
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

/// A speed band whose own k differs from the bands above it.
class BandDisagreement {
  final SpeedBand band;

  /// k_band / k_above − 1 (−0.012 = this band reads 1.2 % lower).
  final double relative;
  const BandDisagreement(this.band, this.relative);
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

  /// Per-band k, to spot tyre growth / slip (all bands, used or not).
  final Map<SpeedBand, double> kByBand;

  /// Lower bands left out of [kGps] because they disagree with the bands
  /// above them by more than the CI.
  final List<BandDisagreement> disagreements;

  const CalibrationFit({
    required this.kGps,
    required this.ciRelative,
    required this.segments,
    required this.cleanSeconds,
    required this.bands,
    required this.interceptKph,
    required this.kByBand,
    this.disagreements = const [],
  });

  CalibrationConfidence get confidence => rateConfidence(
      ciRelative: ciRelative, segments: segments, bands: bands.length);

  static const int bootstrapRounds = 1000;
  static const int bootstrapBlockSeconds = 5;

  /// v1.4: how much each speed band counts in the combined k. At higher
  /// speed GPS noise is a smaller share of the speed and the fit is less
  /// sensitive to lag, so higher bands count more.
  static double bandWeight(SpeedBand b) => switch (b) {
        SpeedBand.kph20to40 => 1,
        SpeedBand.kph40to60 => 2,
        SpeedBand.kph60to80 => 3,
        SpeedBand.kph80plus => 3,
      };

  /// A lower band is left out of the combined k when it disagrees with the
  /// bands above it by more than this (relative) or the CI, whichever is
  /// larger, and the bands above have at least [minSegmentsAbove] stretches.
  static const double disagreementFloor = 0.005;
  static const int minSegmentsAbove = 3;

  /// Null when there is no clean segment yet.
  ///
  /// v1.4: fit per speed band, combine the bands (higher bands weigh more)
  /// and bootstrap within each band, so differences *between* bands do not
  /// inflate the CI. A low band that systematically disagrees with the
  /// bands above it is reported in [disagreements] and left out of [kGps].
  static CalibrationFit? fromAnalysis(CalibrationAnalysis analysis,
      {int seed = 2026}) {
    final segments = analysis.segments;
    if (segments.isEmpty) return null;

    final byBand = <SpeedBand, List<CalibrationSegment>>{};
    for (final s in segments) {
      byBand.putIfAbsent(s.band, () => []).add(s);
    }
    final kByBand = {
      for (final e in byBand.entries) e.key: throughZero(e.value),
    };

    final random = math.Random(seed);
    final ordered = byBand.keys.toList()..sort((a, b) => a.index - b.index);
    var included = ordered.toList();
    final disagreements = <BandDisagreement>[];
    // Only the low band (below 40 km/h) can be left out: that is where
    // slip, lag and GPS noise are largest relative to the speed. Higher
    // bands always count (they are weighted up instead).
    for (final band in ordered.where((b) => b == SpeedBand.kph20to40)) {
      final above = included.where((b) => b.index > band.index).toList();
      final aboveSegments =
          above.fold<int>(0, (n, b) => n + byBand[b]!.length);
      if (above.isEmpty || aboveSegments < minSegmentsAbove) break;
      final kAbove = _combine({for (final b in above) b: byBand[b]!});
      final ciAbove = _bootstrapCi(
          {for (final b in above) b: byBand[b]!}, kAbove, random);
      final diff = kByBand[band]! / kAbove - 1;
      final limit = math.max(disagreementFloor, ciAbove ?? 0);
      if (diff.abs() > limit) {
        disagreements.add(BandDisagreement(band, diff));
        included = included.where((b) => b != band).toList();
      } else {
        break;
      }
    }

    final used = {for (final b in included) b: byBand[b]!};
    final k = _combine(used);
    final usedSegments = used.values.fold<int>(0, (n, l) => n + l.length);
    final ci = usedSegments >= 2 ? _bootstrapCi(used, k, random) : null;
    final usedList = [for (final l in used.values) ...l];

    return CalibrationFit(
      kGps: k,
      ciRelative: ci,
      segments: usedSegments,
      cleanSeconds: usedList.fold(0, (n, s) => n + s.seconds),
      bands: used.keys.toSet(),
      interceptKph: _intercept(usedList),
      kByBand: kByBand,
      disagreements: disagreements,
    );
  }

  static double _combine(Map<SpeedBand, List<CalibrationSegment>> bands) {
    var num = 0.0, den = 0.0;
    for (final e in bands.entries) {
      final rr = e.value.fold<double>(0, (sum, s) => sum + s.sumRR);
      final vr = e.value.fold<double>(0, (sum, s) => sum + s.sumVR);
      final w = rr * bandWeight(e.key);
      num += w * (vr / rr);
      den += w;
    }
    return num / den;
  }

  /// 95 % CI half-width relative to [k], resampling stretches within each
  /// band. Null when there are fewer than 2 stretches in total.
  static double? _bootstrapCi(Map<SpeedBand, List<CalibrationSegment>> bands,
      double k, math.Random random) {
    final total = bands.values.fold<int>(0, (n, l) => n + l.length);
    if (total < 2) return null;
    // A band with a single stretch has no spread of its own; pool those
    // with the nearest band so their uncertainty is not ignored.
    final strata = <SpeedBand, List<CalibrationSegment>>{};
    final keys = bands.keys.toList()..sort((a, b) => a.index - b.index);
    for (final b in keys) {
      final list = bands[b]!;
      if (list.length >= 2 || keys.length == 1) {
        strata.putIfAbsent(b, () => []).addAll(list);
      } else {
        final near = keys.where((x) => x != b && bands[x]!.length >= 2).toList()
          ..sort((x, y) =>
              (x.index - b.index).abs().compareTo((y.index - b.index).abs()));
        final into = near.isEmpty ? b : near.first;
        strata.putIfAbsent(into, () => []).addAll(list);
      }
    }
    // Resample blocks of about [bootstrapBlockSeconds] rather than whole
    // stretches (a block bootstrap): GPS errors are correlated over a few
    // seconds, not over a whole 30 s stretch, so one long stretch is
    // several independent pieces of evidence.
    for (final key in strata.keys.toList()) {
      strata[key] = [for (final seg in strata[key]!) ...seg.blocks()];
    }
    final ks = <double>[];
    for (var r = 0; r < bootstrapRounds; r++) {
      var num = 0.0, den = 0.0;
      for (final e in strata.entries) {
        final l = e.value;
        for (var j = 0; j < l.length; j++) {
          final s = l[random.nextInt(l.length)];
          final w = bandWeight(s.band);
          num += w * s.sumVR;
          den += w * s.sumRR;
        }
      }
      ks.add(num / den);
    }
    ks.sort();
    final lo = _percentile(ks, 0.025);
    final hi = _percentile(ks, 0.975);
    return (hi - lo) / 2 / k;
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

import 'package:arcdash/models/gps_calibration.dart';
import 'package:arcdash/models/speed_suggestions.dart';

/// Plain-language explanations of a calibration ride (v1.2.3): why seconds
/// were not used, what to do about it, and how far the ride is from a
/// usable result. Pure functions, so the live screen, the results screen and
/// tests share the same wording and thresholds.

/// What a rejected second means and what to do about it.
class VerdictAdvice {
  final SampleVerdict verdict;
  final String what;
  final String fix;
  const VerdictAdvice(this.verdict, this.what, this.fix);
}

const _config = CalibrationFilterConfig();

VerdictAdvice adviceFor(SampleVerdict v) => switch (v) {
      SampleVerdict.kept => const VerdictAdvice(
          SampleVerdict.kept, 'used for the fit', 'Nothing to do.'),
      SampleVerdict.noGps => const VerdictAdvice(
          SampleVerdict.noGps,
          'no GPS fix',
          'Give the phone a clear view of the sky and wait for the green GPS lock before riding off.'),
      SampleVerdict.noRpm => const VerdictAdvice(
          SampleVerdict.noRpm,
          'no motor RPM from the controller (stopped or not connected)',
          'Usually standing still. If you were moving, keep FarSure connected to the controller.'),
      SampleVerdict.braking => const VerdictAdvice(SampleVerdict.braking,
          'brake applied', 'Avoid braking during the steady stretches.'),
      SampleVerdict.tooSlow => VerdictAdvice(
          SampleVerdict.tooSlow,
          'slower than ${_config.minSpeedKph.round()} km/h',
          'Ride above ${_config.minSpeedKph.round()} km/h — ideally 30–60 km/h.'),
      SampleVerdict.poorAccuracy => VerdictAdvice(
          SampleVerdict.poorAccuracy,
          'GPS speed too uncertain (worse than ±${_config.maxSpeedAccuracyMps} m/s)',
          'Ride in the open, away from tall buildings, trees and tunnels.'),
      SampleVerdict.noWindow => const VerdictAdvice(
          SampleVerdict.noWindow,
          'first/last second of a stretch or a gap in the data',
          'Nothing to do; this always costs a second or two.'),
      SampleVerdict.accelerating => VerdictAdvice(
          SampleVerdict.accelerating,
          'speeding up or slowing down (more than ${(_config.maxAccelMps2 * 3.6 * 2).toStringAsFixed(1)} km/h over 2 s)',
          'Hold the throttle still for 10 seconds or more at a time.'),
      SampleVerdict.rpmUnsteady => VerdictAdvice(
          SampleVerdict.rpmUnsteady,
          'motor RPM jumping by more than ${(_config.maxRpmVariation * 100).round()} %',
          'Keep a steady throttle on a smooth road (no wheel spin or bumps).'),
      SampleVerdict.turning => VerdictAdvice(
          SampleVerdict.turning,
          'turning (more than ${_config.maxHeadingRateDegPerS.round()}° per second)',
          'Use a straight road.'),
      SampleVerdict.outlier => const VerdictAdvice(
          SampleVerdict.outlier,
          'did not match the rest of the ride (GPS glitch)',
          'Nothing to do; a few of these are normal.'),
      SampleVerdict.shortSegment => VerdictAdvice(
          SampleVerdict.shortSegment,
          'steady, but for less than ${_config.minSegmentSeconds} seconds in a row',
          'Hold each steady speed a little longer (10 s or more).'),
    };

/// One line of the "why nothing / little was used" breakdown.
class RejectionLine {
  final VerdictAdvice advice;
  final int seconds;
  const RejectionLine(this.advice, this.seconds);
}

/// Rejected seconds grouped by reason, largest first.
List<RejectionLine> rejectionBreakdown(CalibrationAnalysis analysis) {
  final counts = <SampleVerdict, int>{};
  for (final v in analysis.verdicts) {
    if (v == SampleVerdict.kept) continue;
    counts[v] = (counts[v] ?? 0) + 1;
  }
  final lines = [
    for (final e in counts.entries) RejectionLine(adviceFor(e.key), e.value)
  ]..sort((a, b) => b.seconds.compareTo(a.seconds));
  return lines;
}

/// Short summary of a ride with no usable fit.
String noFitSummary(CalibrationAnalysis analysis) {
  final total = analysis.samples.length;
  if (total == 0) return 'Nothing was recorded yet.';
  final lines = rejectionBreakdown(analysis);
  final top = lines.isEmpty ? null : lines.first;
  return 'None of the $total recorded seconds could be used yet. '
      '${top == null ? '' : 'Most were ${top.advice.what} (${top.seconds} s). '}'
      'A result needs at least ${_config.minSegmentSeconds} steady seconds in a row '
      'above ${_config.minSpeedKph.round()} km/h.';
}

/// Plain-words summary of a ride with a fit.
String fitSummary(CalibrationFit fit, {BleSpeedSettings? ble}) {
  final buf = StringBuffer();
  if (ble != null && ble.kBle > 0) {
    final s = RateRatioSuggestion.compute(ble, fit.kGps);
    final pct = (s.error * 100).abs().toStringAsFixed(1);
    final dir = s.error >= 0 ? 'high' : 'low';
    if (s.isChange) {
      buf.write('FarSure\'s speed reads $pct % $dir compared with GPS. '
          'Suggested RateRatio: ${s.suggested} (now ${ble.rateRatio}). ');
    } else {
      buf.write('FarSure\'s speed matches GPS within $pct %; '
          'keep RateRatio ${ble.rateRatio}. ');
    }
  }
  buf.write('Based on ${fit.cleanSeconds} clean seconds in ${fit.segments} '
      'steady stretch${fit.segments == 1 ? '' : 'es'}');
  final ci = fit.ciRelative;
  if (ci != null) {
    buf.write(', precise to about ±${(ci * 100).toStringAsFixed(1)} %');
  }
  buf.write('. Confidence: ${fit.confidence.label.toLowerCase()}.');
  return buf.toString();
}

/// One requirement of the capture checklist.
class CaptureRequirement {
  final String title;

  /// 0..1
  final double progress;
  final bool done;

  /// Plain words, e.g. "Need ~20 more steady seconds above 40 km/h".
  final String hint;
  const CaptureRequirement(
      {required this.title,
      required this.progress,
      required this.done,
      required this.hint});
}

/// The real fit requirements (same numbers the fit and confidence use):
/// * clean seconds: target [targetCleanSeconds] (90);
/// * steady stretches (≥ 5 s each): ≥ 3 for any confidence, 6 for high;
/// * speed bands: ≥ 2 for high confidence;
/// * precision (95 % bootstrap CI): ≤ ±1.5 % medium, ≤ ±0.5 % high.
class CaptureProgress {
  static const int targetCleanSeconds = 90;
  static const int minSegments = 3;
  static const int highSegments = 6;
  static const int highBands = 2;
  static const double mediumCi = 0.015;
  static const double highCi = 0.005;

  final List<CaptureRequirement> requirements;
  const CaptureProgress(this.requirements);

  bool get allDone => requirements.every((r) => r.done);

  factory CaptureProgress.of(
      CalibrationAnalysis analysis, CalibrationFit? fit) {
    final clean = analysis.cleanSeconds;
    final segments = analysis.segments.length;
    final bands = analysis.bands;
    final missing = targetCleanSeconds - clean;
    final nextBand = _suggestBand(bands);

    String secondsHint() {
      if (missing <= 0) return 'Enough steady seconds.';
      if (bands.length < highBands && clean > 0 && nextBand != null) {
        return 'Need ~$missing more steady seconds — some of them '
            '${_bandWords(nextBand)}.';
      }
      return 'Need ~$missing more steady seconds above '
          '${_config.minSpeedKph.round()} km/h.';
    }

    final ci = fit?.ciRelative;
    return CaptureProgress([
      CaptureRequirement(
        title: 'Steady seconds $clean / $targetCleanSeconds',
        progress: (clean / targetCleanSeconds).clamp(0.0, 1.0),
        done: missing <= 0,
        hint: secondsHint(),
      ),
      CaptureRequirement(
        title: 'Steady stretches $segments / $highSegments',
        progress: (segments / highSegments).clamp(0.0, 1.0),
        done: segments >= highSegments,
        hint: segments >= highSegments
            ? 'Enough separate stretches.'
            : segments < minSegments
                ? 'Need ${minSegments - segments} more stretch${minSegments - segments == 1 ? '' : 'es'} of '
                    '${_config.minSegmentSeconds}+ s for any result, ${highSegments - segments} for high confidence.'
                : 'Need ${highSegments - segments} more stretch${highSegments - segments == 1 ? '' : 'es'} of '
                    '${_config.minSegmentSeconds}+ s for high confidence.',
      ),
      CaptureRequirement(
        title: 'Speed bands ${bands.length} / $highBands',
        progress: (bands.length / highBands).clamp(0.0, 1.0),
        done: bands.length >= highBands,
        hint: bands.length >= highBands
            ? 'Two or more speed bands covered.'
            : nextBand == null
                ? 'Hold steady speeds in two bands (20–40, 40–60, 60–80, 80+ km/h).'
                : 'Also hold a steady speed ${_bandWords(nextBand)}.',
      ),
      CaptureRequirement(
        title: ci == null
            ? 'Precision: not known yet'
            : 'Precision ±${(ci * 100).toStringAsFixed(1)} %',
        progress: ci == null ? 0 : (highCi / ci).clamp(0.0, 1.0),
        done: ci != null && ci <= highCi,
        hint: ci == null
            ? 'Shown after 2 steady stretches.'
            : ci <= highCi
                ? 'High precision reached.'
                : ci <= mediumCi
                    ? 'Usable (≤ ±1.5 %). More steady stretches bring it to ±0.5 % for high confidence.'
                    : 'Too scattered so far (needs ≤ ±1.5 %). Keep collecting steady stretches.',
      ),
    ]);
  }

  static SpeedBand? _suggestBand(Set<SpeedBand> have) {
    if (have.isEmpty) return null;
    // Prefer the band just above the highest one covered, else below.
    final sorted = have.toList()..sort((a, b) => a.index - b.index);
    final above = sorted.last.index + 1;
    if (above < SpeedBand.values.length) return SpeedBand.values[above];
    for (var i = sorted.first.index - 1; i >= 0; i--) {
      if (!have.contains(SpeedBand.values[i])) return SpeedBand.values[i];
    }
    return null;
  }

  static String _bandWords(SpeedBand b) => switch (b) {
        SpeedBand.kph20to40 => 'between 20 and 40 km/h',
        SpeedBand.kph40to60 => 'between 40 and 60 km/h',
        SpeedBand.kph60to80 => 'between 60 and 80 km/h',
        SpeedBand.kph80plus => 'above 80 km/h',
      };
}

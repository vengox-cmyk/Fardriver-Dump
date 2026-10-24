import 'package:arcdash/models/gps_calibration.dart';
import 'package:arcdash/models/speed_suggestions.dart';
import 'package:arcdash/services/calibration_settings.dart';
import 'package:arcdash/services/parameter_csv.dart';

/// Session export of a GPS calibration ride: one CSV with sections
/// (summary, current settings, fit, DKD snapshots, per-second samples),
/// each with its own header row, separated by a blank line.
class CalibrationCsv {
  CalibrationCsv._();

  static String build({
    required List<CalibrationSample> samples,
    required CalibrationAnalysis analysis,
    required CalibrationFit? fit,
    required List<DkdSnapshot> dkdSnapshots,
    required CalibrationSettings settings,
    required String appVersion,
    required DateTime exportedAt,
    DateTime? startedAt,
  }) {
    final out = StringBuffer();
    void section(List<List<String>> rows) {
      if (out.isNotEmpty) out.write('\n');
      out.write(FlatCsv.encode(rows));
    }

    section([
      ['section', 'key', 'value'],
      ['summary', 'app', 'FarSure $appVersion'],
      ['summary', 'exported_at', exportedAt.toIso8601String()],
      if (startedAt != null)
        ['summary', 'started_at', startedAt.toIso8601String()],
      ['summary', 'seconds_recorded', '${samples.length}'],
      ['summary', 'clean_seconds', '${analysis.cleanSeconds}'],
      ['summary', 'segments', '${analysis.segments.length}'],
      [
        'summary',
        'bands',
        (analysis.bands.toList()..sort((a, b) => a.index - b.index))
            .map((b) => b.label)
            .join(' | ')
      ],
      for (final e in analysis.verdictCounts.entries)
        ['verdicts', e.key.code, '${e.value}'],
    ]);

    final ble = settings.ble;
    section([
      ['section', 'key', 'value'],
      ['settings', 'source', settings.source],
      ['settings', 'WheelRadius', _int(ble?.wheelRadius)],
      ['settings', 'WheelWidth', _int(ble?.wheelWidth)],
      ['settings', 'WheelRatio', _int(ble?.wheelRatio)],
      ['settings', 'RateRatio', _int(ble?.rateRatio)],
      ['settings', 'GearRatio', ble == null ? '' : _f(ble.gearRatio, 3)],
      ['settings', 'k_ble_kmh_per_rpm', ble == null ? '' : _f(ble.kBle, 6)],
      ['settings', 'SpeedPulse', _int(settings.speedPulses)],
      ['settings', 'SpdPulseNum', _int(settings.spdPulseNum)],
    ]);

    final fitRows = <List<String>>[
      ['section', 'key', 'value'],
    ];
    if (fit != null) {
      fitRows.addAll([
        ['fit', 'k_gps_kmh_per_rpm', _f(fit.kGps, 6)],
        [
          'fit',
          'ci95_relative_pct',
          fit.ciRelative == null ? '' : _f(fit.ciRelative! * 100, 2)
        ],
        ['fit', 'confidence', fit.confidence.name],
        [
          'fit',
          'intercept_kmh_diagnostic',
          fit.interceptKph == null ? '' : _f(fit.interceptKph!, 2)
        ],
        for (final e in fit.kByBand.entries)
          ['fit', 'k_gps_${e.key.name}', _f(e.value, 6)],
      ]);
      if (ble != null) {
        final s = RateRatioSuggestion.compute(ble, fit.kGps);
        fitRows.addAll([
          ['ble', 'error_pct', _f(s.error * 100, 2)],
          ['ble', 'suggested_RateRatio', '${s.suggested}'],
          ['ble', 'suggested_GearRatio', _f(s.suggestedGearRatio, 3)],
          ['ble', 'warning', s.isSuspicious ? 'change_over_30pct' : ''],
        ]);
      }
      final dkd = DkdFit.fromSnapshots(dkdSnapshots);
      if (dkd != null) {
        fitRows.addAll([
          ['dkd', 'k_dkd_kmh_per_rpm', _f(dkd.kDkd, 6)],
          ['dkd', 'taps', '${dkd.taps}'],
          ['dkd', 'confidence', dkd.confidence(fit).name],
        ]);
        if (settings.speedPulses != null && settings.spdPulseNum != null) {
          final s = DkdSuggestion.compute(
            speedPulses: settings.speedPulses!,
            spdPulseNum: settings.spdPulseNum!,
            kDkd: dkd.kDkd,
            kGps: fit.kGps,
          );
          fitRows.addAll([
            ['dkd', 'error_pct', _f(s.error * 100, 2)],
            ['dkd', 'suggested_SpeedPulse', '${s.suggestedSpeedPulses}'],
            ['dkd', 'suggested_SpdPulseNum', '${s.suggestedSpdPulseNum}'],
            ['dkd', 'fallback_dkd_cc_factor', _f(s.ccFactor, 4)],
          ]);
        }
      }
    } else {
      fitRows.add(['fit', 'status', 'no clean segment yet']);
    }
    section(fitRows);

    section([
      ['dkd_snapshot', 'time', 'rpm', 'gps_kmh', 'controller_kmh', 'dkd_kmh'],
      for (var i = 0; i < dkdSnapshots.length; i++)
        [
          '${i + 1}',
          dkdSnapshots[i].at.toIso8601String(),
          _f(dkdSnapshots[i].rpm, 1),
          _opt(dkdSnapshots[i].gpsKph, 2),
          _f(dkdSnapshots[i].controllerKph, 2),
          _opt(dkdSnapshots[i].dkdKph, 1),
        ],
    ]);

    final segmentOf = <CalibrationSample, int>{};
    for (var s = 0; s < analysis.segments.length; s++) {
      for (final sample in analysis.segments[s].samples) {
        segmentOf[sample] = s + 1;
      }
    }
    section([
      [
        'time',
        'gps_kmh',
        'speed_acc_mps',
        'h_acc_m',
        'heading_deg',
        'rpm',
        'controller_kmh',
        'braking',
        'kept',
        'reason',
        'segment',
      ],
      for (var i = 0; i < samples.length; i++)
        _sampleRow(samples[i], analysis.verdicts[i], segmentOf[samples[i]]),
    ]);
    return out.toString();
  }

  static List<String> _sampleRow(
      CalibrationSample s, SampleVerdict verdict, int? segment) {
    final gps = s.gps;
    return [
      s.at.toIso8601String(),
      _opt(gps?.speedKph, 2),
      _opt(gps?.speedAccuracyMps, 2),
      _opt(gps?.accuracyMeters, 1),
      _opt(gps?.headingDeg, 1),
      _opt(s.rpm, 1),
      _f(s.controllerKph, 2),
      s.braking ? '1' : '0',
      verdict == SampleVerdict.kept ? '1' : '0',
      verdict.code,
      segment == null ? '' : '$segment',
    ];
  }

  static String _int(int? v) => v == null ? '' : '$v';
  static String _f(double v, int digits) => v.toStringAsFixed(digits);
  static String _opt(double? v, int digits) =>
      v == null || !v.isFinite ? '' : v.toStringAsFixed(digits);
}

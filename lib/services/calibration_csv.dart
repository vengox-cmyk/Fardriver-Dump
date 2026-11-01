import 'package:arcdash/models/gps_calibration.dart';
import 'package:arcdash/models/speed_source.dart';
import 'package:arcdash/models/speed_suggestions.dart';
import 'package:arcdash/models/dash_speed.dart';
import 'package:arcdash/services/calibration_settings.dart';
import 'package:arcdash/services/gps_calibration_session.dart';
import 'package:arcdash/services/parameter_csv.dart';
import 'package:arcdash/utils/speed_units.dart';

/// Session export of a GPS calibration ride: one CSV with sections
/// (summary, current settings, fit, DKD snapshots, per-second samples),
/// each with its own header row, separated by a blank line.
///
/// The same file is the permanent record in `farsure/calibrations/`: raw
/// values are written at full precision so [parse] rebuilds the ride and
/// re-running the (deterministic) analysis gives the same suggestions.
class CalibrationCsv {
  CalibrationCsv._();

  static const format = 'farsure-gps-calibration-v1';

  /// `summary,status` while the ride is still recording (incremental
  /// auto-save) and after Stop.
  static const statusRecording = 'recording';
  static const statusStopped = 'stopped';

  static String build({
    required List<CalibrationSample> samples,
    required CalibrationAnalysis analysis,
    required CalibrationFit? fit,
    required List<DkdSnapshot> dkdSnapshots,
    required CalibrationSettings settings,
    required String appVersion,
    required DateTime exportedAt,
    DashAnchor? dashAnchor,
    DateTime? startedAt,
    DateTime? stoppedAt,
    String? controllerId,
    String? status,
  }) {
    final out = StringBuffer();
    void section(List<List<String>> rows) {
      if (out.isNotEmpty) out.write('\n');
      out.write(FlatCsv.encode(rows));
    }

    section([
      ['section', 'key', 'value'],
      ['summary', 'format', format],
      [
        'summary',
        'app',
        appVersion.startsWith('FarSure') ? appVersion : 'FarSure $appVersion'
      ],
      ['summary', 'exported_at', exportedAt.toIso8601String()],
      if (startedAt != null)
        ['summary', 'started_at', startedAt.toIso8601String()],
      if (stoppedAt != null)
        ['summary', 'stopped_at', stoppedAt.toIso8601String()],
      if (startedAt != null)
        [
          'summary',
          'duration_s',
          '${_duration(startedAt, stoppedAt, samples)}',
        ],
      if (status != null) ['summary', 'status', status],
      if (controllerId != null) ['summary', 'controller_id', controllerId],
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
          _raw(dkdSnapshots[i].rpm),
          _raw(dkdSnapshots[i].gpsKph),
          _raw(dkdSnapshots[i].controllerKph),
          _raw(dkdSnapshots[i].dkdKph),
        ],
    ]);

    // Estimated dash speed (never used in any fit): see DashAnchor.
    final sp = settings.speedPulses, spn = settings.spdPulseNum;
    final dashK = dashAnchor?.kFor(sp: sp, spn: spn);
    section([
      ['section', 'key', 'value'],
      ['dash_est', 'status', dashEstimateLabel],
      ['dash_est', 'used_in_fit', 'no'],
      [
        'dash_est',
        'anchor',
        dashAnchor == null
            ? 'none (run a Dash speed check to fill dash_kmh_est)'
            : '${dashAnchor.source}, ${dashAnchor.points} point(s)'
      ],
      if (dashAnchor != null) ...[
        ['dash_est', 'anchor_SpeedPulse', _int(dashAnchor.speedPulses)],
        ['dash_est', 'anchor_SpdPulseNum', _int(dashAnchor.spdPulseNum)],
        [
          'dash_est',
          'scaling',
          dashAnchor.sameSettings(sp: sp, spn: spn)
              ? 'same settings as anchor (measured)'
              : dashK == null
                  ? 'settings unknown: no estimate'
                  : 'scaled by SpeedPulse/SpdPulseNum (unverified)'
        ],
        if (dashK != null) ['dash_est', 'k_dash_kmh_per_rpm', _f(dashK, 6)],
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
        'gps_mph',
        'controller_mph',
        'dash_kmh_est',
      ],
      for (var i = 0; i < samples.length; i++)
        [
          ..._sampleRow(
              samples[i], analysis.verdicts[i], segmentOf[samples[i]]),
          _opt(
              dashK == null || (samples[i].rpm ?? 0) <= 0
                  ? null
                  : samples[i].rpm! * dashK,
              2),
        ],
    ]);
    return out.toString();
  }

  static List<String> _sampleRow(
      CalibrationSample s, SampleVerdict verdict, int? segment) {
    final gps = s.gps;
    return [
      s.at.toIso8601String(),
      _raw(gps?.speedKph),
      _raw(gps?.speedAccuracyMps),
      _raw(gps?.accuracyMeters),
      _raw(gps?.headingDeg),
      _raw(s.rpm),
      _raw(s.controllerKph),
      s.braking ? '1' : '0',
      verdict == SampleVerdict.kept ? '1' : '0',
      verdict.code,
      segment == null ? '' : '$segment',
      _opt(gps == null ? null : SpeedUnit.mph.fromKph(gps.speedKph), 2),
      _f(SpeedUnit.mph.fromKph(s.controllerKph), 2),
    ];
  }

  static int _duration(
      DateTime startedAt, DateTime? stoppedAt, List<CalibrationSample> s) {
    final end = stoppedAt ?? (s.isEmpty ? startedAt : s.last.at);
    final seconds = end.difference(startedAt).inSeconds;
    return seconds < 0 ? 0 : seconds;
  }

  /// Full precision (Dart doubles round-trip through toString).
  static String _raw(double? v) => v == null || !v.isFinite ? '' : '$v';

  /// Reads a file written by [build] (also the rounded v1.2 export) back
  /// into samples, DKD readings, settings and metadata.
  static SavedCalibration parse(String text) {
    final kv = <String, String>{};
    final samples = <CalibrationSample>[];
    final dkd = <DkdSnapshot>[];
    var mode = '';
    var header = <String, int>{};
    String cell(List<String> row, String name) {
      final i = header[name];
      return i == null || i >= row.length ? '' : row[i].trim();
    }

    double? number(List<String> row, String name) =>
        double.tryParse(cell(row, name));

    for (final row in FlatCsv.decode(text)) {
      if (row.isEmpty) continue;
      final first = row.first.trim();
      if (first == 'section') {
        mode = 'kv';
        continue;
      }
      if (first == 'dkd_snapshot' || first == 'time') {
        mode = first == 'time' ? 'samples' : 'dkd';
        header = {for (var i = 0; i < row.length; i++) row[i].trim(): i};
        continue;
      }
      switch (mode) {
        case 'kv':
          if (row.length >= 3) kv['$first.${row[1].trim()}'] = row[2];
        case 'dkd':
          final at = DateTime.tryParse(cell(row, 'time'));
          final rpm = number(row, 'rpm');
          if (at == null || rpm == null) continue;
          dkd.add(DkdSnapshot(
            at: at,
            rpm: rpm,
            gpsKph: number(row, 'gps_kmh'),
            controllerKph: number(row, 'controller_kmh') ?? 0,
            dkdKph: number(row, 'dkd_kmh'),
          ));
        case 'samples':
          final at = DateTime.tryParse(cell(row, 'time'));
          if (at == null) continue;
          final gpsKph = number(row, 'gps_kmh');
          samples.add(CalibrationSample(
            at: at,
            gps: gpsKph == null
                ? null
                : GpsSpeedSample(
                    speedKph: gpsKph,
                    accuracyMeters: number(row, 'h_acc_m') ?? 0,
                    speedAccuracyMps: number(row, 'speed_acc_mps'),
                    headingDeg: number(row, 'heading_deg'),
                    capturedAt: at,
                  ),
            rpm: number(row, 'rpm'),
            controllerKph: number(row, 'controller_kmh') ?? 0,
            braking: cell(row, 'braking') == '1',
          ));
      }
    }
    if (kv.isEmpty && samples.isEmpty) {
      throw const FormatException('not a FarSure calibration file');
    }
    int? integer(String key) => int.tryParse(kv[key] ?? '');
    final radius = integer('settings.WheelRadius');
    final width = integer('settings.WheelWidth');
    final ratio = integer('settings.WheelRatio');
    final rate = integer('settings.RateRatio');
    final settings = CalibrationSettings(
      ble: radius == null || width == null || ratio == null || rate == null
          ? null
          : BleSpeedSettings(
              wheelRadius: radius,
              wheelWidth: width,
              wheelRatio: ratio,
              rateRatio: rate),
      speedPulses: integer('settings.SpeedPulse'),
      spdPulseNum: integer('settings.SpdPulseNum'),
      source: kv['settings.source'] ?? 'saved file',
    );
    return SavedCalibration(
      samples: samples,
      dkdSnapshots: dkd,
      settings: settings,
      startedAt: DateTime.tryParse(kv['summary.started_at'] ?? ''),
      stoppedAt: DateTime.tryParse(kv['summary.stopped_at'] ?? ''),
      controllerId: kv['summary.controller_id'] ?? '',
      status: kv['summary.status'] ?? statusStopped,
      appVersion: kv['summary.app'] ?? '',
    );
  }

  static String _int(int? v) => v == null ? '' : '$v';
  static String _f(double v, int digits) => v.toStringAsFixed(digits);
  static String _opt(double? v, int digits) =>
      v == null || !v.isFinite ? '' : v.toStringAsFixed(digits);
}

/// A calibration ride read back from its saved file.
class SavedCalibration {
  final List<CalibrationSample> samples;
  final List<DkdSnapshot> dkdSnapshots;
  final CalibrationSettings settings;
  final DateTime? startedAt;
  final DateTime? stoppedAt;
  final String controllerId;

  /// [CalibrationCsv.statusRecording] if the app died mid-ride.
  final String status;
  final String appVersion;

  const SavedCalibration({
    required this.samples,
    required this.dkdSnapshots,
    required this.settings,
    required this.startedAt,
    required this.stoppedAt,
    required this.controllerId,
    required this.status,
    required this.appVersion,
  });

  /// Re-runs the analysis (deterministic) and returns a stopped session.
  CalibrationSessionState toSessionState(
      {CalibrationAnalyzer analyzer = const CalibrationAnalyzer()}) {
    final analysis = analyzer.analyze(samples);
    return CalibrationSessionState(
      status: CalibrationStatus.stopped,
      startedAt: startedAt,
      stoppedAt: stoppedAt ?? (samples.isEmpty ? startedAt : samples.last.at),
      samples: samples,
      analysis: analysis,
      fit: CalibrationFit.fromAnalysis(analysis),
      dkdSnapshots: dkdSnapshots,
    );
  }
}

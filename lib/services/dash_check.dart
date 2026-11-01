import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arcdash/models/dash_speed.dart';
import 'package:arcdash/models/gps_calibration.dart';
import 'package:arcdash/models/speed_source.dart';
import 'package:arcdash/models/speed_suggestions.dart';
import 'package:arcdash/services/calibration_csv.dart';
import 'package:arcdash/services/gps_calibration_session.dart';
import 'package:arcdash/services/gps_location_service.dart';
import 'package:arcdash/services/parameter_csv.dart';
import 'package:arcdash/services/saved_files.dart';

/// Stationary "Dash speed check" (v1.2.3): drive wheel lifted on a stand,
/// FarSure shows live rpm, the rider types what the one-wire dash shows.
/// Replaces the in-ride "DKD reads…" tap — nothing to tap while riding.

/// One check session (one file, rewritten in place).
class DashCheckRecord {
  final DateTime startedAt;
  final List<DkdSnapshot> points;
  final int? speedPulses;
  final int? spdPulseNum;
  final BleSpeedSettings? ble;
  final String controllerId;

  /// GPS km/h per rpm from the latest saved calibration ride (null: none).
  final double? kGps;
  final String kGpsSource;

  const DashCheckRecord({
    required this.startedAt,
    required this.points,
    this.speedPulses,
    this.spdPulseNum,
    this.ble,
    this.controllerId = '',
    this.kGps,
    this.kGpsSource = '',
  });

  DashCheckResult? get result => DashCheckResult.compute(
        points: points,
        kGps: kGps,
        kApp: ble?.kBle,
        speedPulses: speedPulses,
        spdPulseNum: spdPulseNum,
      );

  DashAnchor? get anchor => DashAnchor.fromReadings(points,
      speedPulses: speedPulses,
      spdPulseNum: spdPulseNum,
      fromDashCheck: true,
      source: 'dash check ${SavedFilesStore.stamp(startedAt)}');
}

class DashCheckCsv {
  DashCheckCsv._();

  static const format = 'farsure-dash-check-v1';

  static String fileNameFor(DateTime startedAt) =>
      'dash_check_${SavedFilesStore.stamp(startedAt)}.csv';

  static String build(DashCheckRecord r,
      {required String appVersion, required DateTime exportedAt}) {
    String n(double? v) => v == null || !v.isFinite ? '' : '$v';
    final result = r.result;
    final usable = r.points.where((p) => p.usable).length;
    final rows = <List<String>>[
      ['section', 'key', 'value'],
      ['summary', 'format', format],
      [
        'summary',
        'app',
        appVersion.startsWith('FarSure') ? appVersion : 'FarSure $appVersion'
      ],
      ['summary', 'exported_at', exportedAt.toIso8601String()],
      ['summary', 'started_at', r.startedAt.toIso8601String()],
      ['summary', 'controller_id', r.controllerId],
      ['summary', 'points', '$usable'],
      [
        'summary',
        'method',
        'stationary, drive wheel lifted; dash typed by rider'
      ],
      ['settings', 'SpeedPulse', r.speedPulses?.toString() ?? ''],
      ['settings', 'SpdPulseNum', r.spdPulseNum?.toString() ?? ''],
      if (r.ble != null) ...[
        ['settings', 'WheelRadius', '${r.ble!.wheelRadius}'],
        ['settings', 'WheelWidth', '${r.ble!.wheelWidth}'],
        ['settings', 'WheelRatio', '${r.ble!.wheelRatio}'],
        ['settings', 'RateRatio', '${r.ble!.rateRatio}'],
      ],
      ['reference', 'k_gps_kmh_per_rpm', n(r.kGps)],
      ['reference', 'k_gps_source', r.kGpsSource],
      if (result != null) ...[
        ['result', 'reference', result.referenceSource],
        ['result', 'k_dash_kmh_per_rpm', result.fit.kDkd.toStringAsFixed(6)],
        ['result', 'dash_error_pct', (result.error * 100).toStringAsFixed(2)],
        if (result.suggestion != null) ...[
          [
            'result',
            'suggested_SpeedPulse',
            '${result.suggestion!.suggestedSpeedPulses}'
          ],
          [
            'result',
            'suggested_SpdPulseNum',
            '${result.suggestion!.suggestedSpdPulseNum}'
          ],
          [
            'result',
            'assumption',
            'display ∝ SpeedPulse × SpdPulseNum (SpdPulseNum direction verified hands-on)'
          ],
        ],
      ],
    ];
    final points = <List<String>>[
      ['dkd_snapshot', 'time', 'rpm', 'gps_kmh', 'controller_kmh', 'dkd_kmh'],
      for (var i = 0; i < r.points.length; i++)
        [
          '${i + 1}',
          r.points[i].at.toIso8601String(),
          n(r.points[i].rpm),
          n(r.points[i].gpsKph),
          n(r.points[i].controllerKph),
          n(r.points[i].dkdKph),
        ],
    ];
    return '${FlatCsv.encode(rows)}\n${FlatCsv.encode(points)}';
  }

  static DashCheckRecord parse(String text) {
    // Same layout as a calibration file (kv rows + dkd_snapshot section).
    final saved = CalibrationCsv.parse(text);
    final kv = <String, String>{};
    for (final row in FlatCsv.decode(text)) {
      if (row.length >= 3 && row[0] != 'dkd_snapshot') {
        kv['${row[0].trim()}.${row[1].trim()}'] = row[2];
      }
    }
    if (kv['summary.format'] != format) {
      throw const FormatException('not a FarSure dash check file');
    }
    final started = DateTime.tryParse(kv['summary.started_at'] ?? '');
    return DashCheckRecord(
      startedAt: started ?? DateTime.fromMillisecondsSinceEpoch(0),
      points: saved.dkdSnapshots,
      speedPulses: saved.settings.speedPulses,
      spdPulseNum: saved.settings.spdPulseNum,
      ble: saved.settings.ble,
      controllerId: kv['summary.controller_id'] ?? '',
      kGps: double.tryParse(kv['reference.k_gps_kmh_per_rpm'] ?? ''),
      kGpsSource: kv['reference.k_gps_source'] ?? '',
    );
  }
}

/// Saved dash checks and calibration rides as references.
class DashCheckArchive {
  DashCheckArchive(this.store, {required this.appVersion});

  final SavedFilesStore store;
  final Future<String> Function() appVersion;

  Future<String> save(DashCheckRecord r) async {
    final csv = DashCheckCsv.build(r,
        appVersion: await appVersion(), exportedAt: DateTime.now());
    final f = await store.write(
        SavedFileKind.dashCheck, DashCheckCsv.fileNameFor(r.startedAt), csv);
    return f.path;
  }

  /// Newest saved dash check with usable readings → anchor for the
  /// estimated dash speed column. Null when there is none.
  static Future<DashAnchor?> latestAnchor(SavedFilesStore store) async {
    for (final e in await store.list(kind: SavedFileKind.dashCheck)) {
      try {
        final anchor = DashCheckCsv.parse(await e.file.readAsString()).anchor;
        if (anchor != null) return anchor;
      } on Object {
        continue;
      }
    }
    return null;
  }

  /// k_gps of the newest saved calibration ride with a fit (km/h per rpm is
  /// physical: it only depends on tire and pulleys, not on settings).
  static Future<({double kGps, String source})?> latestGpsReference(
      SavedFilesStore store) async {
    for (final e in await store.list(kind: SavedFileKind.calibration)) {
      if ((e.info['confidence'] ?? '').isEmpty) continue;
      try {
        final fit = CalibrationCsv.parse(await e.file.readAsString())
            .toSessionState()
            .fit;
        if (fit != null && fit.confidence != CalibrationConfidence.red) {
          return (kGps: fit.kGps, source: e.name);
        }
      } on Object {
        continue;
      }
    }
    return null;
  }
}

class DashCheckState {
  final bool ready;
  final GpsAvailability? gpsProblem;
  final GpsSpeedSample? gps;
  final double? rpm;
  final double appKph;
  final DkdSnapshot? pending;
  final DashCheckRecord? record;
  final String? savedPath;

  const DashCheckState({
    this.ready = false,
    this.gpsProblem,
    this.gps,
    this.rpm,
    this.appKph = 0,
    this.pending,
    this.record,
    this.savedPath,
  });

  /// GPS below this = standing still.
  static const double stationaryKph = 3;
  static const Duration gpsMaxAge = Duration(seconds: 3);

  bool stationaryAt(DateTime now) {
    final g = gps;
    return g != null &&
        now.difference(g.capturedAt) <= gpsMaxAge &&
        g.speedKph < stationaryKph;
  }

  List<DkdSnapshot> get points => record?.points ?? const [];

  DashCheckState copyWith({
    bool? ready,
    GpsAvailability? gpsProblem,
    GpsSpeedSample? gps,
    double? rpm,
    bool clearRpm = false,
    double? appKph,
    DkdSnapshot? pending,
    bool clearPending = false,
    DashCheckRecord? record,
    String? savedPath,
  }) =>
      DashCheckState(
        ready: ready ?? this.ready,
        gpsProblem: gpsProblem ?? this.gpsProblem,
        gps: gps ?? this.gps,
        rpm: clearRpm ? null : rpm ?? this.rpm,
        appKph: appKph ?? this.appKph,
        pending: clearPending ? null : pending ?? this.pending,
        record: record ?? this.record,
        savedPath: savedPath ?? this.savedPath,
      );
}

/// Live state of the Dash speed check screen.
class DashCheckNotifier extends StateNotifier<DashCheckState> {
  DashCheckNotifier({
    required GpsSource gps,
    required Stream<RpmReading> rpm,
    required ControllerReadout Function() controller,
    required Future<DashCheckRecord> Function(DateTime startedAt) newRecord,
    Future<String> Function(DashCheckRecord)? saver,
    DateTime Function()? clock,
  })  : _gps = gps,
        _rpmStream = rpm,
        _controller = controller,
        _newRecord = newRecord,
        _saver = saver,
        _clock = clock ?? DateTime.now,
        super(const DashCheckState());

  final GpsSource _gps;
  final Stream<RpmReading> _rpmStream;
  final ControllerReadout Function() _controller;
  final Future<DashCheckRecord> Function(DateTime) _newRecord;
  final Future<String> Function(DashCheckRecord)? _saver;
  final DateTime Function() _clock;
  final List<RpmReading> _recent = [];
  StreamSubscription<RpmReading>? _rpmSub;
  StreamSubscription<GpsSpeedSample>? _gpsSub;
  Timer? _tick;

  /// rpm is averaged over this window when captured.
  static const window = Duration(seconds: 3);

  Future<void> begin() async {
    final availability = await _gps.ensureReady();
    if (!mounted) return;
    if (availability != GpsAvailability.ready) {
      state = state.copyWith(gpsProblem: availability);
      return;
    }
    final record = await _newRecord(_clock());
    if (!mounted) return;
    state = state.copyWith(ready: true, record: record);
    _rpmSub = _rpmStream.listen(onRpm);
    _gpsSub = _gps.fixes().listen(onFix, onError: (_) {});
    _tick =
        Timer.periodic(const Duration(milliseconds: 500), (_) => _refresh());
  }

  void onRpm(RpmReading r) {
    _recent.add(r);
    _refresh();
  }

  void onFix(GpsSpeedSample g) {
    if (!mounted) return;
    state = state.copyWith(gps: g);
  }

  void _refresh() {
    if (!mounted) return;
    final now = _clock();
    _recent.removeWhere((r) => now.difference(r.at) > window);
    final rpm = _recent.isEmpty
        ? null
        : _recent.fold<double>(0, (s, r) => s + r.rpm) / _recent.length;
    state = state.copyWith(
        rpm: rpm, clearRpm: rpm == null, appKph: _controller().speedKph);
  }

  /// Takes the rpm (3 s mean) now. Only while standing still with motor
  /// rpm. Returns false when not allowed.
  bool capture() {
    _refresh();
    final now = _clock();
    final rpm = state.rpm;
    if (!state.ready || rpm == null || rpm <= 0 || !state.stationaryAt(now)) {
      return false;
    }
    state = state.copyWith(
        pending: DkdSnapshot(
            at: now,
            rpm: rpm,
            gpsKph: state.gps?.speedKph,
            controllerKph: state.appKph));
    return true;
  }

  /// Stores the dash number for the pending capture (null = discard).
  Future<void> enterDash(double? kph) async {
    final p = state.pending;
    final r = state.record;
    state = state.copyWith(clearPending: true);
    if (p == null || r == null || kph == null || kph <= 0) return;
    await _update(DashCheckRecord(
      startedAt: r.startedAt,
      points: [...r.points, p.withReading(kph)],
      speedPulses: r.speedPulses,
      spdPulseNum: r.spdPulseNum,
      ble: r.ble,
      controllerId: r.controllerId,
      kGps: r.kGps,
      kGpsSource: r.kGpsSource,
    ));
  }

  Future<void> removePoint(int index) async {
    final r = state.record;
    if (r == null || index < 0 || index >= r.points.length) return;
    await _update(DashCheckRecord(
      startedAt: r.startedAt,
      points: [...r.points]..removeAt(index),
      speedPulses: r.speedPulses,
      spdPulseNum: r.spdPulseNum,
      ble: r.ble,
      controllerId: r.controllerId,
      kGps: r.kGps,
      kGpsSource: r.kGpsSource,
    ));
  }

  Future<void> _update(DashCheckRecord r) async {
    state = state.copyWith(record: r);
    final saver = _saver;
    if (saver == null) return;
    try {
      final path = await saver(r);
      if (mounted) state = state.copyWith(savedPath: path);
    } catch (e) {
      debugPrint('Dash check save failed: $e');
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    unawaited(_rpmSub?.cancel());
    unawaited(_gpsSub?.cancel());
    super.dispose();
  }
}

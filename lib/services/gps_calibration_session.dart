import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arcdash/models/gps_calibration.dart';
import 'package:arcdash/models/speed_source.dart';
import 'package:arcdash/models/speed_suggestions.dart';
import 'package:arcdash/services/gps_location_service.dart';

/// Bins controller rpm readings into the GPS second they belong to.
class CalibrationPairer {
  final List<RpmReading> _pending = [];
  RpmReading? _last;

  /// Reuse the last rpm reading for a second without one if it is at most
  /// this old (BLE frames can bunch up).
  final Duration maxRpmAge;

  CalibrationPairer({this.maxRpmAge = const Duration(milliseconds: 1500)});

  RpmReading? get lastRpm => _last;

  void addRpm(RpmReading reading) {
    _pending.add(reading);
    _last = reading;
  }

  /// Closes the current second: mean rpm since the previous call.
  double? takeSecond(DateTime at) {
    if (_pending.isNotEmpty) {
      final mean =
          _pending.fold<double>(0, (sum, r) => sum + r.rpm) / _pending.length;
      _pending.clear();
      return mean;
    }
    final last = _last;
    if (last != null && at.difference(last.at) <= maxRpmAge) return last.rpm;
    return null;
  }

  void reset() {
    _pending.clear();
    _last = null;
  }
}

enum CalibrationStatus { idle, starting, recording, stopped, unavailable }

class CalibrationSessionState {
  final CalibrationStatus status;
  final GpsAvailability? gpsProblem;
  final DateTime? startedAt;
  final DateTime? stoppedAt;
  final List<CalibrationSample> samples;
  final CalibrationAnalysis analysis;
  final CalibrationFit? fit;
  final List<DkdSnapshot> dkdSnapshots;
  final GpsSpeedSample? latestGps;

  const CalibrationSessionState({
    this.status = CalibrationStatus.idle,
    this.gpsProblem,
    this.startedAt,
    this.stoppedAt,
    this.samples = const [],
    this.analysis =
        const CalibrationAnalysis(samples: [], verdicts: [], segments: []),
    this.fit,
    this.dkdSnapshots = const [],
    this.latestGps,
  });

  bool get isRecording => status == CalibrationStatus.recording;
  bool get hasData => samples.isNotEmpty;
  int get cleanSeconds => analysis.cleanSeconds;

  /// Spec target: 60–120 clean seconds over ≥ 2 speed bands.
  static const int targetCleanSeconds = 90;

  CalibrationSessionState copyWith({
    CalibrationStatus? status,
    GpsAvailability? gpsProblem,
    bool clearGpsProblem = false,
    DateTime? startedAt,
    DateTime? stoppedAt,
    List<CalibrationSample>? samples,
    CalibrationAnalysis? analysis,
    CalibrationFit? fit,
    bool clearFit = false,
    List<DkdSnapshot>? dkdSnapshots,
    GpsSpeedSample? latestGps,
  }) =>
      CalibrationSessionState(
        status: status ?? this.status,
        gpsProblem: clearGpsProblem ? null : gpsProblem ?? this.gpsProblem,
        startedAt: startedAt ?? this.startedAt,
        stoppedAt: stoppedAt ?? this.stoppedAt,
        samples: samples ?? this.samples,
        analysis: analysis ?? this.analysis,
        fit: clearFit ? null : fit ?? this.fit,
        dkdSnapshots: dkdSnapshots ?? this.dkdSnapshots,
        latestGps: latestGps ?? this.latestGps,
      );
}

/// Live telemetry the session needs from the controller, read on demand.
class ControllerReadout {
  final double speedKph;
  final bool braking;

  const ControllerReadout({required this.speedKph, required this.braking});
}

/// Calibration ride: pairs GPS fixes with controller rpm at ~1 Hz and keeps
/// the analysis/fit up to date. Read-only: it never talks to the controller.
class GpsCalibrationNotifier extends StateNotifier<CalibrationSessionState> {
  final GpsSource _gps;
  final Stream<RpmReading> _rpm;
  final ControllerReadout Function() _controller;
  final DateTime Function() _clock;
  final CalibrationAnalyzer _analyzer;
  final CalibrationPairer _pairer = CalibrationPairer();

  StreamSubscription<GpsSpeedSample>? _gpsSub;
  StreamSubscription<RpmReading>? _rpmSub;
  Timer? _watchdog;
  DateTime? _lastSampleAt;

  /// Without a fix for this long a "no GPS" second is recorded, so lost
  /// lock shows up live and in the CSV.
  static const _gpsTimeout = Duration(milliseconds: 2000);

  GpsCalibrationNotifier({
    required GpsSource gps,
    required Stream<RpmReading> rpm,
    required ControllerReadout Function() controller,
    DateTime Function()? clock,
    CalibrationAnalyzer analyzer = const CalibrationAnalyzer(),
  })  : _gps = gps,
        _rpm = rpm,
        _controller = controller,
        _clock = clock ?? DateTime.now,
        _analyzer = analyzer,
        super(const CalibrationSessionState());

  GpsSource get gpsSource => _gps;

  /// Starts a fresh ride. Returns the GPS availability (permission etc.).
  Future<GpsAvailability> start() async {
    await _cancel();
    state = const CalibrationSessionState(status: CalibrationStatus.starting);
    final availability = await _gps.ensureReady();
    if (!mounted) return availability;
    if (availability != GpsAvailability.ready) {
      state = CalibrationSessionState(
          status: CalibrationStatus.unavailable, gpsProblem: availability);
      return availability;
    }
    _pairer.reset();
    _lastSampleAt = null;
    state = CalibrationSessionState(
        status: CalibrationStatus.recording, startedAt: _clock());
    _rpmSub = _rpm.listen(_pairer.addRpm);
    _gpsSub = _gps.fixes().listen(onFix, onError: (_) {});
    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) => onTick());
    return availability;
  }

  /// One GPS fix = one calibration second.
  void onFix(GpsSpeedSample fix) {
    if (!state.isRecording) return;
    _addSample(fix, fix.capturedAt);
  }

  /// Records a "no GPS" second if fixes stopped arriving.
  void onTick() {
    if (!state.isRecording) return;
    final now = _clock();
    final last = _lastSampleAt ?? state.startedAt ?? now;
    if (now.difference(last) >= _gpsTimeout) _addSample(null, now);
  }

  void _addSample(GpsSpeedSample? fix, DateTime at) {
    final readout = _controller();
    final sample = CalibrationSample(
      at: at,
      gps: fix,
      rpm: _pairer.takeSecond(at),
      controllerKph: readout.speedKph,
      braking: readout.braking,
    );
    _lastSampleAt = at;
    final samples = [...state.samples, sample];
    final analysis = _analyzer.analyze(samples);
    state = state.copyWith(
      samples: samples,
      analysis: analysis,
      fit: CalibrationFit.fromAnalysis(analysis),
      clearFit: analysis.segments.isEmpty,
      latestGps: fix,
    );
  }

  /// "DKD reads…" tap: snapshot GPS speed and rpm now; the DKD number is
  /// entered later, after stopping. Returns false if there is no rpm.
  bool tapDkd() {
    if (!state.isRecording) return false;
    final now = _clock();
    final rpm = _pairer.lastRpm;
    if (rpm == null || now.difference(rpm.at) > const Duration(seconds: 2)) {
      return false;
    }
    final gps = state.latestGps;
    final gpsFresh =
        gps != null && now.difference(gps.capturedAt) <= _gpsTimeout;
    state = state.copyWith(dkdSnapshots: [
      ...state.dkdSnapshots,
      DkdSnapshot(
        at: now,
        rpm: rpm.rpm,
        gpsKph: gpsFresh ? gps.speedKph : null,
        controllerKph: _controller().speedKph,
      ),
    ]);
    return true;
  }

  void setDkdReading(int index, double? kph) {
    if (index < 0 || index >= state.dkdSnapshots.length) return;
    final snapshots = [...state.dkdSnapshots];
    snapshots[index] = snapshots[index].withReading(kph);
    state = state.copyWith(dkdSnapshots: snapshots);
  }

  void removeDkdSnapshot(int index) {
    if (index < 0 || index >= state.dkdSnapshots.length) return;
    state =
        state.copyWith(dkdSnapshots: [...state.dkdSnapshots]..removeAt(index));
  }

  Future<void> stop() async {
    await _cancel();
    if (state.status == CalibrationStatus.recording ||
        state.status == CalibrationStatus.starting) {
      state = state.copyWith(
          status: CalibrationStatus.stopped, stoppedAt: _clock());
    }
  }

  /// Stops listening. Cancel futures are not awaited: the session state
  /// must change immediately (and nothing is pending on them).
  Future<void> _cancel() async {
    _watchdog?.cancel();
    _watchdog = null;
    unawaited(_gpsSub?.cancel());
    _gpsSub = null;
    unawaited(_rpmSub?.cancel());
    _rpmSub = null;
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _gpsSub?.cancel();
    _rpmSub?.cancel();
    super.dispose();
  }
}

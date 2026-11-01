import 'dart:io';

import 'package:arcdash/models/dash_speed.dart';
import 'package:arcdash/models/speed_suggestions.dart';
import 'package:arcdash/services/calibration_csv.dart';
import 'package:arcdash/services/calibration_settings.dart';
import 'package:arcdash/services/gps_calibration_session.dart';
import 'package:arcdash/services/saved_files.dart';

/// Permanent storage of GPS calibration rides in `farsure/calibrations/`.
///
/// One file per ride (named after its start time), rewritten on every
/// auto-save, on Stop, when the app goes to the background and whenever a
/// DKD reading changes. The file is the full calibration CSV (raw samples,
/// fit, suggestions, settings snapshot, DKD readings) plus metadata.
class CalibrationArchive {
  CalibrationArchive({
    required SavedFilesStore store,
    required Future<CalibrationSettings> Function() settings,
    required String Function() controllerId,
    required Future<String> Function() appVersion,
    Future<DashAnchor?> Function()? dashAnchor,
    DateTime Function()? clock,
  })  : _store = store,
        _dashAnchor = dashAnchor,
        _settings = settings,
        _controllerId = controllerId,
        _appVersion = appVersion,
        _clock = clock ?? DateTime.now;

  final SavedFilesStore _store;
  final Future<CalibrationSettings> Function() _settings;
  final String Function() _controllerId;
  final Future<String> Function() _appVersion;
  final DateTime Function() _clock;
  final Future<DashAnchor?> Function()? _dashAnchor;

  // Per ride: keep what was known while connected after a disconnect.
  DateTime? _rideStart;
  String _rideControllerId = '';
  CalibrationSettings? _rideSettings;
  DashAnchor? _rideAnchor;
  bool _anchorLoaded = false;

  static String fileNameFor(DateTime startedAt) =>
      'calibration_${SavedFilesStore.stamp(startedAt)}.csv';

  /// [CalibrationSaver] for [GpsCalibrationNotifier].
  Future<String?> save(CalibrationSessionState state) async {
    final startedAt = state.startedAt;
    if (startedAt == null) return null;
    if (_rideStart != startedAt) {
      _rideStart = startedAt;
      _rideControllerId = '';
      _rideSettings = null;
      _rideAnchor = null;
      _anchorLoaded = false;
    }
    if (!_anchorLoaded && _dashAnchor != null) {
      _anchorLoaded = true; // once per ride; never blocks a save
      try {
        _rideAnchor = await _dashAnchor();
      } on Object {
        _rideAnchor = null;
      }
    }
    final id = _controllerId().trim();
    if (id.isNotEmpty) _rideControllerId = id;

    CalibrationSettings settings;
    try {
      settings = await _settings();
    } on Object {
      settings = CalibrationSettings.none;
    }
    final known = _rideSettings;
    if (settings.ble == null && known != null && known.ble != null) {
      settings = known;
    } else {
      _rideSettings = settings;
    }

    final csv = CalibrationCsv.build(
      samples: state.samples,
      analysis: state.analysis,
      fit: state.fit,
      dkdSnapshots: state.dkdSnapshots,
      settings: settings,
      // A stationary dash check (calibrated) wins over in-ride DKD readings.
      dashAnchor: _rideAnchor ?? rideDashAnchor(state.dkdSnapshots, settings),
      appVersion: await _appVersion(),
      exportedAt: _clock(),
      startedAt: startedAt,
      stoppedAt: state.stoppedAt,
      controllerId: _rideControllerId,
      status: state.isRecording
          ? CalibrationCsv.statusRecording
          : CalibrationCsv.statusStopped,
    );
    final file = await _store.write(
        SavedFileKind.calibration, fileNameFor(startedAt), csv);
    return file.path;
  }

  /// Anchor from DKD readings stored with the ride itself (older rides).
  static DashAnchor? rideDashAnchor(
          List<DkdSnapshot> readings, CalibrationSettings settings) =>
      DashAnchor.fromReadings(readings,
          speedPulses: settings.speedPulses,
          spdPulseNum: settings.spdPulseNum,
          source: 'DKD readings in this ride');

  /// Rewrites a ride opened from Saved files with new DKD readings, keeping
  /// its original settings snapshot and metadata.
  static Future<File> rewrite(
    File file,
    SavedCalibration saved, {
    required List<DkdSnapshot> dkdSnapshots,
    required String appVersion,
    DateTime? now,
  }) {
    final session = saved.toSessionState();
    final csv = CalibrationCsv.build(
      samples: session.samples,
      analysis: session.analysis,
      fit: session.fit,
      dkdSnapshots: dkdSnapshots,
      settings: saved.settings,
      dashAnchor: rideDashAnchor(dkdSnapshots, saved.settings),
      appVersion: appVersion,
      exportedAt: now ?? DateTime.now(),
      startedAt: saved.startedAt,
      stoppedAt: session.stoppedAt,
      controllerId: saved.controllerId,
      status: saved.status,
    );
    return SavedFilesStore.writeAtomically(file, csv);
  }
}

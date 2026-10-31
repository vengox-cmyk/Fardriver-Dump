import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arcdash/models/controller_state.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/saved_files_provider.dart';
import 'package:arcdash/services/calibration_archive.dart';
import 'package:arcdash/services/calibration_settings.dart';
import 'package:arcdash/services/parameter_dump_io.dart';
import 'package:arcdash/services/gps_calibration_session.dart';
import 'package:arcdash/services/gps_location_service.dart';

final gpsSourceProvider =
    Provider<GpsSource>((ref) => const GeolocatorGpsSource());

/// The current (or last) GPS calibration ride.
final gpsCalibrationProvider =
    StateNotifierProvider<GpsCalibrationNotifier, CalibrationSessionState>(
        (ref) {
  final controller = ref.watch(controllerProvider.notifier);
  final archive = ref.watch(calibrationArchiveProvider);
  return GpsCalibrationNotifier(
    saver: archive?.save,
    gps: ref.watch(gpsSourceProvider),
    rpm: controller.rpmReadings,
    controller: () {
      final state = ref.read(controllerProvider);
      return ControllerReadout(
          speedKph: state.speedKph, braking: state.isBraking);
    },
  );
});

/// Permanent storage of calibration rides (null disables auto-save).
final calibrationArchiveProvider = Provider<CalibrationArchive?>((ref) {
  return CalibrationArchive(
    store: ref.watch(savedFilesStoreProvider),
    settings: () => resolveCalibrationSettings(ref),
    controllerId: () => ref.read(connectedDeviceIdProvider) ?? '',
    appVersion: ParameterDumpIo.appVersion,
  );
});

/// Controller values to compare against. Read on demand (refresh after a
/// snapshot completes); never written.
final calibrationSettingsProvider =
    FutureProvider.autoDispose<CalibrationSettings>(
        (ref) => resolveCalibrationSettings(ref));

/// Latest complete snapshot (in memory, else stored), else live geometry.
Future<CalibrationSettings> resolveCalibrationSettings(Ref ref) async {
  final storage = ref.read(storageServiceProvider);
  var snapshot = ref.read(parameterCaptureProvider).latest;
  if (snapshot == null) {
    try {
      snapshot = await storage.parameterSnapshots?.loadComplete();
    } on Object {
      snapshot = null;
    }
  }
  final live = ref.read(controllerProvider);
  return CalibrationSettings.resolve(
    snapshot: snapshot,
    live: live,
    liveGeometryReceived: _hasLiveGeometry(live),
  );
}

/// ControllerState starts with placeholder geometry 10/3/1/1000 until the
/// first 0xD0 block arrives.
bool _hasLiveGeometry(ControllerState s) => !(s.wheelRadius == 10 &&
    s.wheelWidth == 3 &&
    s.wheelRatio == 1 &&
    s.rateRatio == 1000);

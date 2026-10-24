import 'package:geolocator/geolocator.dart';

import 'package:arcdash/models/speed_source.dart';

enum GpsAvailability {
  ready,
  serviceDisabled,
  denied,
  deniedForever;

  String get message => switch (this) {
        ready => 'GPS ready',
        serviceDisabled =>
          'Location is switched off. Turn on location (GPS) in Android settings.',
        denied => 'Location permission was denied. GPS calibration needs it.',
        deniedForever =>
          'Location permission is blocked. Allow it for FarSure in Android app settings.',
      };
}

/// Phone GPS used only by the speed calibration ride.
abstract interface class GpsSource {
  /// Checks the location service and asks for the "while in use" location
  /// permission if needed.
  Future<GpsAvailability> ensureReady();

  /// About one fix per second while listened to.
  Stream<GpsSpeedSample> fixes();

  Future<void> openSettings(GpsAvailability availability);
}

class GeolocatorGpsSource implements GpsSource {
  const GeolocatorGpsSource();

  @override
  Future<GpsAvailability> ensureReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return GpsAvailability.serviceDisabled;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse =>
        GpsAvailability.ready,
      LocationPermission.deniedForever => GpsAvailability.deniedForever,
      _ => GpsAvailability.denied,
    };
  }

  @override
  Stream<GpsSpeedSample> fixes() => Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
          intervalDuration: const Duration(seconds: 1),
        ),
      ).map(fromPosition);

  @override
  Future<void> openSettings(GpsAvailability availability) async {
    if (availability == GpsAvailability.serviceDisabled) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  /// Uses the phone's receive time (not the GPS clock) so fixes line up with
  /// the BLE rpm readings, which are stamped the same way.
  static GpsSpeedSample fromPosition(Position p) => GpsSpeedSample(
        speedKph: p.speed >= 0 ? p.speed * 3.6 : double.nan,
        accuracyMeters: p.accuracy,
        speedAccuracyMps: p.speedAccuracy > 0 ? p.speedAccuracy : null,
        headingDeg: p.heading >= 0 && p.speed > 1 ? p.heading : null,
        capturedAt: DateTime.now(),
      );
}

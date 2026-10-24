/// Where a displayed speed comes from. FarSure never blends the two: the
/// controller (BLE) speed and the phone's GPS speed are always shown as
/// separate, labelled values.
enum SpeedSource {
  gps('GPS speed'),
  controller('Controller speed');

  final String label;

  const SpeedSource(this.label);
}

/// One GPS fix from the phone, reduced to what speed calibration needs.
class GpsSpeedSample {
  /// Doppler ground speed in km/h.
  final double speedKph;

  /// Horizontal position accuracy (1 sigma) in metres.
  final double accuracyMeters;

  /// Speed accuracy (1 sigma) in m/s, or null when the phone does not report
  /// it (Android < 8 or some chipsets).
  final double? speedAccuracyMps;

  /// Course over ground in degrees (0..360), or null when unknown.
  final double? headingDeg;

  final DateTime capturedAt;

  const GpsSpeedSample({
    required this.speedKph,
    required this.accuracyMeters,
    required this.capturedAt,
    this.speedAccuracyMps,
    this.headingDeg,
  });
}

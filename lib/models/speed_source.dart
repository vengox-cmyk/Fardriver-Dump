enum SpeedSource { gps, controller }

class GpsSpeedSample {
  final double speedKph;
  final double accuracyMeters;
  final DateTime capturedAt;

  const GpsSpeedSample({
    required this.speedKph,
    required this.accuracyMeters,
    required this.capturedAt,
  });
}

class SpeedReading {
  final double speedKph;
  final SpeedSource source;
  final DateTime capturedAt;

  const SpeedReading({
    required this.speedKph,
    required this.source,
    required this.capturedAt,
  });
}

class SpeedSourceResolver {
  static const _maxAccuracyMeters = 25.0;
  static const _maxGpsAge = Duration(seconds: 3);
  static const _maxAccelerationKphPerSecond = 15.0;

  const SpeedSourceResolver();

  SpeedReading resolve({
    required DateTime now,
    required double controllerSpeedKph,
    GpsSpeedSample? gps,
    SpeedReading? previous,
    bool locationPermissionGranted = true,
  }) {
    if (gps != null &&
        locationPermissionGranted &&
        gps.accuracyMeters <= _maxAccuracyMeters &&
        now.difference(gps.capturedAt) >= Duration.zero &&
        now.difference(gps.capturedAt) <= _maxGpsAge &&
        gps.speedKph.isFinite &&
        gps.speedKph >= 0 &&
        _plausibleAcceleration(gps, now, previous)) {
      return SpeedReading(
        speedKph: gps.speedKph < 0.5 ? 0 : gps.speedKph,
        source: SpeedSource.gps,
        capturedAt: gps.capturedAt,
      );
    }
    return SpeedReading(
      speedKph: controllerSpeedKph.isFinite && controllerSpeedKph >= 0
          ? controllerSpeedKph
          : 0,
      source: SpeedSource.controller,
      capturedAt: now,
    );
  }

  bool _plausibleAcceleration(
    GpsSpeedSample current,
    DateTime now,
    SpeedReading? previous,
  ) {
    if (previous == null || previous.source != SpeedSource.gps) return true;
    final seconds =
        current.capturedAt.difference(previous.capturedAt).inMilliseconds /
            1000;
    if (seconds <= 0) return true;
    return (current.speedKph - previous.speedKph).abs() / seconds <=
        _maxAccelerationKphPerSecond;
  }
}

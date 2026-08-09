import 'dart:math' as math;

class GpsPoint {
  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime at;

  const GpsPoint({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.at,
  });
}

class DistanceSample {
  final double meters;
  final bool accepted;
  final String reason;

  const DistanceSample({
    required this.meters,
    required this.accepted,
    required this.reason,
  });
}

class GpsDistanceFilter {
  final double maxAccuracyMeters;
  final double maxSpeedMps;
  final Duration maxAge;
  GpsPoint? _previous;
  double _distanceMeters = 0;

  GpsDistanceFilter({
    this.maxAccuracyMeters = 30,
    this.maxSpeedMps = 100,
    this.maxAge = const Duration(seconds: 5),
  });

  double get distanceMeters => _distanceMeters;

  DistanceSample add(GpsPoint point, {required DateTime now}) {
    if (!point.latitude.isFinite ||
        !point.longitude.isFinite ||
        point.latitude.abs() > 90 ||
        point.longitude.abs() > 180) {
      return const DistanceSample(
          meters: 0, accepted: false, reason: 'invalid');
    }
    if (!point.accuracyMeters.isFinite ||
        point.accuracyMeters > maxAccuracyMeters) {
      return const DistanceSample(
          meters: 0, accepted: false, reason: 'accuracy');
    }
    if (now.difference(point.at) > maxAge || point.at.isAfter(now)) {
      return const DistanceSample(meters: 0, accepted: false, reason: 'stale');
    }
    final previous = _previous;
    _previous = point;
    if (previous == null) {
      return const DistanceSample(
          meters: 0, accepted: false, reason: 'initial');
    }
    final elapsed = point.at.difference(previous.at).inMilliseconds / 1000;
    if (elapsed <= 0) {
      return const DistanceSample(meters: 0, accepted: false, reason: 'time');
    }
    final meters = _haversine(previous, point);
    if (meters / elapsed > maxSpeedMps) {
      return const DistanceSample(
          meters: 0, accepted: false, reason: 'teleport');
    }
    _distanceMeters += meters;
    return DistanceSample(meters: meters, accepted: true, reason: 'accepted');
  }

  static double _haversine(GpsPoint left, GpsPoint right) {
    const earthRadius = 6371000.0;
    final lat1 = left.latitude * math.pi / 180;
    final lat2 = right.latitude * math.pi / 180;
    final dLat = (right.latitude - left.latitude) * math.pi / 180;
    final dLon = (right.longitude - left.longitude) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}

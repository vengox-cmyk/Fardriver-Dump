import 'package:arcdash/models/gps_distance_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts plausible movement and keeps distance monotonic', () {
    final filter = GpsDistanceFilter();
    final now = DateTime.utc(2026, 1, 1);
    filter.add(
        GpsPoint(latitude: 52, longitude: 13, accuracyMeters: 5, at: now),
        now: now);
    final sample = filter.add(
      GpsPoint(
          latitude: 52.0001,
          longitude: 13,
          accuracyMeters: 5,
          at: now.add(const Duration(seconds: 2))),
      now: now.add(const Duration(seconds: 2)),
    );
    expect(sample.accepted, isTrue);
    expect(filter.distanceMeters, greaterThan(0));
  });

  test('rejects poor accuracy, stale points, and teleports', () {
    final now = DateTime.utc(2026, 1, 1);
    final filter = GpsDistanceFilter();
    expect(
      filter
          .add(
              GpsPoint(
                  latitude: 52, longitude: 13, accuracyMeters: 100, at: now),
              now: now)
          .reason,
      'accuracy',
    );
    expect(
      filter
          .add(
              GpsPoint(
                  latitude: 52,
                  longitude: 13,
                  accuracyMeters: 5,
                  at: now.subtract(const Duration(minutes: 1))),
              now: now)
          .reason,
      'stale',
    );
  });
}

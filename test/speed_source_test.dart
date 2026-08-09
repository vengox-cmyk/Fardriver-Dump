import 'package:arcdash/models/speed_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 2, 12);
  final resolver = SpeedSourceResolver();

  test('prefers a fresh accurate GPS value', () {
    final result = resolver.resolve(
      now: now,
      controllerSpeedKph: 18,
      gps: GpsSpeedSample(
        speedKph: 20,
        accuracyMeters: 4,
        capturedAt: now,
      ),
    );

    expect(result.source, SpeedSource.gps);
    expect(result.speedKph, 20);
  });

  test('falls back when permission, freshness or accuracy is bad', () {
    final gps = GpsSpeedSample(
      speedKph: 80,
      accuracyMeters: 100,
      capturedAt: now.subtract(const Duration(seconds: 4)),
    );

    final result = resolver.resolve(
      now: now,
      controllerSpeedKph: 12,
      gps: gps,
      locationPermissionGranted: false,
    );

    expect(result.source, SpeedSource.controller);
    expect(result.speedKph, 12);
  });

  test('rejects an implausible jump and keeps stillness stable', () {
    final first = resolver.resolve(
      now: now,
      controllerSpeedKph: 0,
      gps: GpsSpeedSample(
        speedKph: 0.2,
        accuracyMeters: 3,
        capturedAt: now,
      ),
    );
    final second = resolver.resolve(
      now: now.add(const Duration(seconds: 1)),
      controllerSpeedKph: 0,
      gps: GpsSpeedSample(
        speedKph: 80,
        accuracyMeters: 3,
        capturedAt: now.add(const Duration(seconds: 1)),
      ),
      previous: first,
    );

    expect(first.speedKph, 0);
    expect(second.source, SpeedSource.controller);
    expect(second.speedKph, 0);
  });
}

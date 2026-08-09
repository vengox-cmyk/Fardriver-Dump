import 'package:arcdash/models/telemetry_quality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 2, 12);

  test('fresh samples expose source, raw value and smoothed display value', () {
    final sample = TelemetrySample(
      value: 42,
      source: TelemetrySource.controller,
      capturedAt: now.subtract(const Duration(milliseconds: 100)),
      smoothedValue: 40,
    );

    expect(sample.rawValue, 42);
    expect(sample.displayValue, 40);
    expect(sample.quality(now: now), TelemetryFreshness.fresh);
  });

  test('slow samples become stale after their configured window', () {
    final sample = TelemetrySample(
      value: 50,
      source: TelemetrySource.controller,
      capturedAt: now.subtract(const Duration(seconds: 6)),
    );

    expect(
      sample.quality(now: now, maxAge: const Duration(seconds: 5)),
      TelemetryFreshness.stale,
    );
  });

  test('non-finite and out-of-range values are invalid', () {
    final nan = TelemetrySample(
      value: double.nan,
      source: TelemetrySource.controller,
      capturedAt: now,
    );
    final impossible = TelemetrySample(
      value: 181,
      source: TelemetrySource.controller,
      capturedAt: now,
    );

    expect(nan.quality(now: now), TelemetryFreshness.invalid);
    expect(
      impossible.quality(now: now, minimum: -180, maximum: 180),
      TelemetryFreshness.invalid,
    );
  });

  test('disconnect never presents the last value as live', () {
    final sample = TelemetrySample(
      value: 12,
      source: TelemetrySource.controller,
      capturedAt: now,
    );

    expect(
      sample.quality(now: now, connected: false),
      TelemetryFreshness.disconnected,
    );
  });
}

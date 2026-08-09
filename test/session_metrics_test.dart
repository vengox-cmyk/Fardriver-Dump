import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/models/session_metrics.dart';
import 'package:arcdash/utils/packet_parser.dart';

void main() {
  group('T071 - Aggregation von Sessionmetriken', () {
    late SessionMetricsAggregator aggregator;
    final now = DateTime(2026, 8, 3, 12, 0, 0);

    setUp(() {
      aggregator = SessionMetricsAggregator(startTime: now);
    });

    test('calculates distance, duration, speeds, and time-weighted averages',
        () {
      // 10 sec at 30 km/h
      aggregator.addSample(
        timestamp: now.add(const Duration(seconds: 10)),
        speedKph: 30.0,
        voltageV: 72.0,
        currentA: 10.0,
      );

      // 10 sec at 60 km/h
      aggregator.addSample(
        timestamp: now.add(const Duration(seconds: 20)),
        speedKph: 60.0,
        voltageV: 72.0,
        currentA: 20.0,
      );

      final metrics = aggregator.computeMetrics(
          endTime: now.add(const Duration(seconds: 20)));

      expect(metrics.duration, const Duration(seconds: 20));
      expect(metrics.maxSpeedKph, 60.0);
      expect(metrics.avgSpeedKph, closeTo(45.0, 0.1));
      expect(metrics.distanceKm, greaterThan(0));
    });

    test(
        'separates consumed, recovered, and net energy without negative consumed Wh',
        () {
      // Discharge 72V * 20A * (10s / 3600s) = 4 Wh
      aggregator.addSample(
        timestamp: now.add(const Duration(seconds: 10)),
        speedKph: 50.0,
        voltageV: 72.0,
        currentA: 20.0, // positive = consumed
      );

      // Regen 75V * (-10A) * (10s / 3600s) = -2.083 Wh -> 2.083 Wh recovered
      aggregator.addSample(
        timestamp: now.add(const Duration(seconds: 20)),
        speedKph: 30.0,
        voltageV: 75.0,
        currentA: -10.0, // negative = regen
      );

      final metrics = aggregator.computeMetrics(
          endTime: now.add(const Duration(seconds: 20)));

      expect(metrics.consumedWh, closeTo(4.0, 0.1));
      expect(metrics.recoveredWh, closeTo(2.08, 0.1));
      expect(metrics.netWh, closeTo(1.92, 0.1));
    });

    test('tracks max power and max temperatures accurately', () {
      // 72V * 100A = 7200W = 7.2 kW
      aggregator.addSample(
        timestamp: now.add(const Duration(seconds: 5)),
        speedKph: 40.0,
        voltageV: 72.0,
        currentA: 100.0,
        telemetry: TelemetryUpdate(
          capturedAt: now.add(const Duration(seconds: 5)),
          motorTempC: 55.0,
          mosTempC: 42.0,
        ),
      );

      final metrics = aggregator.computeMetrics();

      expect(metrics.maxPowerKw, closeTo(7.2, 0.01));
      expect(metrics.maxMotorTempC, 55.0);
      expect(metrics.maxMosTempC, 42.0);
    });

    test('stale and invalid samples are ignored and flag incomplete metrics',
        () {
      // Valid
      aggregator.addSample(
        timestamp: now.add(const Duration(seconds: 5)),
        speedKph: 30.0,
        voltageV: 72.0,
        currentA: 10.0,
      );

      // Invalid infinite values
      aggregator.addSample(
        timestamp: now.add(const Duration(seconds: 10)),
        speedKph: double.nan,
        voltageV: 72.0,
        currentA: double.infinity,
      );

      // Stale gap (> 10 seconds)
      aggregator.addSample(
        timestamp: now.add(const Duration(seconds: 30)),
        speedKph: 30.0,
        voltageV: 72.0,
        currentA: 10.0,
      );

      final metrics = aggregator.computeMetrics();
      expect(metrics.isIncomplete, isTrue);
    });
  });
}

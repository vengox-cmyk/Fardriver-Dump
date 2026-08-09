enum TelemetrySource { controller, gps, derived }

enum TelemetryFreshness { fresh, stale, invalid, disconnected }

/// A measured value with enough metadata to avoid presenting stale data as live.
class TelemetrySample {
  final double rawValue;
  final TelemetrySource source;
  final DateTime capturedAt;
  final double? smoothedValue;

  const TelemetrySample({
    required double value,
    required this.source,
    required this.capturedAt,
    this.smoothedValue,
  }) : rawValue = value;

  double get displayValue => smoothedValue ?? rawValue;

  TelemetryFreshness quality({
    required DateTime now,
    bool connected = true,
    Duration maxAge = const Duration(seconds: 2),
    double? minimum,
    double? maximum,
  }) {
    if (!connected) return TelemetryFreshness.disconnected;
    if (!rawValue.isFinite ||
        (smoothedValue != null && !smoothedValue!.isFinite) ||
        (minimum != null && rawValue < minimum) ||
        (maximum != null && rawValue > maximum)) {
      return TelemetryFreshness.invalid;
    }
    final age = now.difference(capturedAt);
    if (age.isNegative || age > maxAge) return TelemetryFreshness.stale;
    return TelemetryFreshness.fresh;
  }
}

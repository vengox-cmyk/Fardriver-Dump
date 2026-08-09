import 'package:arcdash/utils/packet_parser.dart';

class SessionMetrics {
  final Duration duration;
  final double distanceKm;
  final double avgSpeedKph;
  final double maxSpeedKph;
  final double consumedWh;
  final double recoveredWh;
  final double netWh;
  final double whPerKm;
  final double maxPowerKw;
  final double? maxMotorTempC;
  final double? maxMosTempC;
  final bool isIncomplete;

  const SessionMetrics({
    required this.duration,
    required this.distanceKm,
    required this.avgSpeedKph,
    required this.maxSpeedKph,
    required this.consumedWh,
    required this.recoveredWh,
    required this.netWh,
    required this.whPerKm,
    required this.maxPowerKw,
    this.maxMotorTempC,
    this.maxMosTempC,
    required this.isIncomplete,
  });
}

class SessionMetricsAggregator {
  final DateTime startTime;
  DateTime? _lastTimestamp;

  double _totalDistanceMeters = 0.0;
  double _maxSpeedKph = 0.0;
  double _consumedWh = 0.0;
  double _recoveredWh = 0.0;
  double _maxPowerKw = 0.0;

  double? _maxMotorTempC;
  double? _maxMosTempC;

  double _weightedSpeedSum = 0.0;
  double _totalWeightedSeconds = 0.0;
  bool _isIncomplete = false;

  SessionMetricsAggregator({required this.startTime});

  void addSample({
    required DateTime timestamp,
    required double speedKph,
    required double voltageV,
    required double currentA,
    TelemetryUpdate? telemetry,
  }) {
    if (!speedKph.isFinite ||
        !voltageV.isFinite ||
        !currentA.isFinite ||
        speedKph < 0 ||
        voltageV < 0) {
      _isIncomplete = true;
      return;
    }

    final prevTime = _lastTimestamp ?? startTime;
    final elapsed = timestamp.difference(prevTime);
    _lastTimestamp = timestamp;

    if (elapsed <= Duration.zero) return;
    if (elapsed > const Duration(seconds: 15)) {
      _isIncomplete = true; // Gap detected
    }

    final seconds = elapsed.inMicroseconds / 1000000.0;
    final hours = seconds / 3600.0;

    if (speedKph > _maxSpeedKph) _maxSpeedKph = speedKph;
    _totalDistanceMeters += speedKph * (1000.0 / 3600.0) * seconds;

    _weightedSpeedSum += speedKph * seconds;
    _totalWeightedSeconds += seconds;

    final powerKw = (voltageV * currentA) / 1000.0;
    if (powerKw > _maxPowerKw) _maxPowerKw = powerKw;

    final wh = powerKw * 1000.0 * hours;
    if (wh >= 0) {
      _consumedWh += wh;
    } else {
      _recoveredWh += -wh;
    }

    if (telemetry != null) {
      if (telemetry.motorTempC != null) {
        if (_maxMotorTempC == null || telemetry.motorTempC! > _maxMotorTempC!) {
          _maxMotorTempC = telemetry.motorTempC;
        }
      }
      if (telemetry.mosTempC != null) {
        if (_maxMosTempC == null || telemetry.mosTempC! > _maxMosTempC!) {
          _maxMosTempC = telemetry.mosTempC;
        }
      }
    }
  }

  SessionMetrics computeMetrics({DateTime? endTime}) {
    final end = endTime ?? _lastTimestamp ?? DateTime.now();
    final duration = end.difference(startTime);
    final distanceKm = _totalDistanceMeters / 1000.0;
    final avgSpeed = _totalWeightedSeconds > 0
        ? _weightedSpeedSum / _totalWeightedSeconds
        : 0.0;
    final netWh = _consumedWh - _recoveredWh;
    final whPerKm = distanceKm > 0.01 ? netWh / distanceKm : 0.0;

    return SessionMetrics(
      duration: duration,
      distanceKm: distanceKm,
      avgSpeedKph: avgSpeed,
      maxSpeedKph: _maxSpeedKph,
      consumedWh: _consumedWh,
      recoveredWh: _recoveredWh,
      netWh: netWh,
      whPerKm: whPerKm,
      maxPowerKw: _maxPowerKw,
      maxMotorTempC: _maxMotorTempC,
      maxMosTempC: _maxMosTempC,
      isIncomplete: _isIncomplete,
    );
  }
}

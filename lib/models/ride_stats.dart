/// A single ride session's statistics.
class RideSession {
  final String id;
  final DateTime startTime;
  DateTime? endTime;

  double distanceKm;
  double maxSpeedKph;
  double totalWhUsed;
  final List<SpeedSample> speedHistory;

  double _avgSpeedSum = 0.0;
  int _avgSpeedSamples = 0;

  RideSession({
    required this.id,
    required this.startTime,
    this.distanceKm = 0.0,
    this.maxSpeedKph = 0.0,
    this.totalWhUsed = 0.0,
    List<SpeedSample>? speedHistory,
  }) : speedHistory = speedHistory ?? [];

  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }

  double get avgSpeedKph {
    if (_avgSpeedSamples == 0) return 0.0;
    return _avgSpeedSum / _avgSpeedSamples;
  }

  void addSample({
    required double speedKph,
    required double voltageV,
    required double currentA,
    required double deltaTimeSeconds,
  }) {
    if (speedKph > maxSpeedKph) maxSpeedKph = speedKph;

    // Accumulate distance (speed in km/h * time in hours)
    distanceKm += speedKph * (deltaTimeSeconds / 3600.0);

    // Accumulate energy (power in kW * time in hours = kWh → × 1000 = Wh)
    final powerKw = voltageV * currentA / 1000.0;
    totalWhUsed += powerKw * 1000.0 * (deltaTimeSeconds / 3600.0);

    // Running avg speed
    _avgSpeedSum += speedKph;
    _avgSpeedSamples++;

    // Record speed history (max 500 samples)
    if (speedHistory.length < 500) {
      speedHistory.add(SpeedSample(
        timestamp: DateTime.now(),
        speedKph: speedKph,
      ));
    }
  }

  void end() {
    endTime = DateTime.now();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime?.toIso8601String(),
        'distanceKm': distanceKm,
        'maxSpeedKph': maxSpeedKph,
        'avgSpeedKph': avgSpeedKph,
        'totalWhUsed': totalWhUsed,
        'durationSeconds': duration.inSeconds,
      };

  List<List<String>> toCsvRows() => [
        ['Time', 'Speed (km/h)'],
        ...speedHistory.map((s) => [
              s.timestamp.toIso8601String(),
              s.speedKph.toStringAsFixed(1),
            ]),
      ];
}

class SpeedSample {
  final DateTime timestamp;
  final double speedKph;

  const SpeedSample({required this.timestamp, required this.speedKph});
}

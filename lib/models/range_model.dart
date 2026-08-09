class RangeEstimate {
  final double? kilometers;
  final double? uncertainty;
  final String status;
  final double confidence;

  const RangeEstimate({
    required this.kilometers,
    required this.uncertainty,
    required this.status,
    required this.confidence,
  });

  bool get available => kilometers != null && uncertainty != null;

  static RangeEstimate estimate({
    required double socPercent,
    required double? usableCapacityWh,
    required double? consumptionWhPerKm,
    double confidence = 0,
  }) {
    if (!socPercent.isFinite || socPercent < 0 || socPercent > 100) {
      throw ArgumentError.value(socPercent, 'socPercent');
    }
    if (usableCapacityWh == null || consumptionWhPerKm == null) {
      return const RangeEstimate(
        kilometers: null,
        uncertainty: null,
        status: 'Noch keine Reichweitendaten',
        confidence: 0,
      );
    }
    if (!usableCapacityWh.isFinite ||
        usableCapacityWh <= 0 ||
        !consumptionWhPerKm.isFinite ||
        consumptionWhPerKm <= 0) {
      return const RangeEstimate(
        kilometers: null,
        uncertainty: null,
        status: 'Messdaten ungueltig',
        confidence: 0,
      );
    }
    final km = usableCapacityWh * socPercent / 100 / consumptionWhPerKm;
    final boundedConfidence = confidence.clamp(0.0, 1.0).toDouble();
    final uncertainty = km * (1.0 - boundedConfidence).clamp(0.15, 0.8);
    return RangeEstimate(
      kilometers: km,
      uncertainty: uncertainty,
      status: boundedConfidence < 0.5 ? 'Vorlaeufige Schaetzung' : 'Gelernt',
      confidence: boundedConfidence,
    );
  }
}

class EnergySample {
  final Duration elapsed;
  final double voltageV;
  final double currentA;

  const EnergySample({
    required this.elapsed,
    required this.voltageV,
    required this.currentA,
  });
}

class EnergyIntegration {
  final Duration maxGap;
  double consumedWh = 0;
  double recoveredWh = 0;
  double consumedAh = 0;
  bool hasGap = false;

  EnergyIntegration({this.maxGap = const Duration(seconds: 5)});

  void add(EnergySample sample) {
    if (!sample.voltageV.isFinite ||
        !sample.currentA.isFinite ||
        sample.elapsed <= Duration.zero) return;
    if (sample.elapsed > maxGap) hasGap = true;
    final hours = sample.elapsed.inMicroseconds / Duration.microsecondsPerHour;
    final wh = sample.voltageV * sample.currentA * hours;
    final ah = sample.currentA * hours;
    if (wh >= 0) {
      consumedWh += wh;
      consumedAh += ah;
    } else {
      recoveredWh += -wh;
    }
  }
}

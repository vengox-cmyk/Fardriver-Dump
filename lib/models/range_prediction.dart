import 'range_model.dart';

class OcvPoint {
  final double voltageV;
  final double socPercent;

  const OcvPoint(this.voltageV, this.socPercent);
}

class SocEstimate {
  final double percent;
  final double confidence;

  const SocEstimate(this.percent, this.confidence);
}

class SocFilter {
  final List<OcvPoint>? curve;
  double? _soc;

  SocFilter({this.curve});

  SocEstimate update({required double voltageV, double? coulombSoc}) {
    if (curve == null || curve!.length < 2) {
      return SocEstimate(
          (_soc ?? coulombSoc ?? 0).clamp(0, 100).toDouble(), 0.1);
    }
    final voltageSoc = _interpolate(voltageV);
    final combined = coulombSoc == null
        ? voltageSoc
        : (voltageSoc * 0.35 + coulombSoc * 0.65);
    _soc = combined.clamp(0, 100).toDouble();
    return SocEstimate(_soc!, 0.55);
  }

  double _interpolate(double voltage) {
    final points = curve!;
    if (voltage <= points.first.voltageV) return points.first.socPercent;
    if (voltage >= points.last.voltageV) return points.last.socPercent;
    for (var i = 1; i < points.length; i++) {
      final low = points[i - 1];
      final high = points[i];
      if (voltage <= high.voltageV) {
        final fraction =
            (voltage - low.voltageV) / (high.voltageV - low.voltageV);
        return low.socPercent + fraction * (high.socPercent - low.socPercent);
      }
    }
    return 0;
  }
}

class ConsumptionWindow {
  final int maxSamples;
  final List<double> _whPerKm = [];

  ConsumptionWindow({this.maxSamples = 30});

  List<double> get samples => List.unmodifiable(_whPerKm);

  void add({required double distanceKm, required double netWh}) {
    if (!distanceKm.isFinite ||
        distanceKm <= 0.01 ||
        !netWh.isFinite ||
        netWh < 0) return;
    _whPerKm.add(netWh / distanceKm);
    if (_whPerKm.length > maxSamples) _whPerKm.removeAt(0);
  }

  double? get averageWhPerKm => _whPerKm.isEmpty
      ? null
      : _whPerKm.reduce((a, b) => a + b) / _whPerKm.length;
}

class CapacityLearner {
  final double minWh;
  final double maxWh;
  double? capacityWh;

  CapacityLearner({this.minWh = 100, this.maxWh = 100000});

  void observeCycle({required double dischargedWh, required bool qualified}) {
    if (!qualified ||
        !dischargedWh.isFinite ||
        dischargedWh < minWh ||
        dischargedWh > maxWh) return;
    capacityWh = capacityWh == null
        ? dischargedWh
        : capacityWh! * 0.8 + dischargedWh * 0.2;
  }
}

class RangePrediction {
  final RangeEstimate estimate;
  final String learningStatus;

  const RangePrediction({required this.estimate, required this.learningStatus});
}

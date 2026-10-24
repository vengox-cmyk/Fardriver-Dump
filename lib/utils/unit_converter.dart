class UnitConverter {
  // Speed from raw MeasureSpeed + wheel geometry (returns km/h)
  static double measureSpeedToKph({
    required int measureSpeed,
    required int wheelRadius,
    required int wheelWidth,
    required int wheelRatio,
    required int rateRatio,
  }) {
    if (rateRatio == 0) return 0.0;
    // fardriver.hpp / official app formula. Until v1.0 the 0xD0 parser read
    // the wheel bytes shifted (radius<-ratio, ratio<-radius, width<-AVGSpeed)
    // and an empirical /10 x1.21 "calibration" compensated for that on one
    // bike. With the parser fixed the plain formula applies (also used by
    // ProtocolService.kphToMaxSpeedRaw for the inverse).
    return measureSpeed *
        (0.00376991136 *
            (wheelRadius * 1270.0 + wheelWidth * wheelRatio) /
            rateRatio);
  }

  // Power in kW
  static double powerKw(double voltageV, double currentA) =>
      (voltageV * currentA) / 1000.0;

  // Battery percentage from raw voltage coefficients
  static double batteryPercent({
    required double voltageDeciVolts,
    required int zeroBattCoeff,
    required int fullBattCoeff,
  }) {
    if (fullBattCoeff == zeroBattCoeff) return 0.0;
    final pct = 100.0 *
        (voltageDeciVolts - zeroBattCoeff) /
        (fullBattCoeff - zeroBattCoeff);
    return pct.clamp(0.0, 100.0);
  }

  // Estimated range in km (very rough: based on Wh/km average consumption)
  static double estimatedRangeKm({
    required double batteryPercent,
    required double battCapacityWh,
    required double avgConsumptionWhPerKm,
  }) {
    if (avgConsumptionWhPerKm <= 0) return 0.0;
    return (batteryPercent / 100.0) * battCapacityWh / avgConsumptionWhPerKm;
  }

  // Format a number with 1 decimal place
  static String fmt1(double val) => val.toStringAsFixed(1);

  // Format a number with no decimal place
  static String fmt0(double val) => val.toStringAsFixed(0);
}

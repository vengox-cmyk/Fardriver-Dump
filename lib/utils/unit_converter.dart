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
    // Scale for Arctic Leopard XE Pro controllers (calibrated 40 km/h real = 40 km/h displayed)
    return (measureSpeed *
            (0.00456958953 *
                (wheelRadius * 1270.0 + wheelWidth * wheelRatio) /
                rateRatio)) /
        10.0;
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

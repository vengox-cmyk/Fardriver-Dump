import 'package:biketunes/utils/unit_converter.dart';

enum RideMode { eco, trail, sport, race }

extension RideModeName on RideMode {
  String get displayName {
    switch (this) {
      case RideMode.eco:
        return 'ECO';
      case RideMode.trail:
        return 'TRAIL';
      case RideMode.sport:
        return 'SPORT';
      case RideMode.race:
        return 'RACE';
    }
  }

  /// ThrottleResponse value written to controller (0x1A addr).
  /// ECO=2, Sport=1, Line/Race=0
  int get throttleResponseValue {
    switch (this) {
      case RideMode.eco:
        return 2;
      case RideMode.trail:
        return 1;
      case RideMode.sport:
        return 1;
      case RideMode.race:
        return 0;
    }
  }
}

/// Immutable snapshot of all live controller telemetry.
class ControllerState {
  // Live telemetry
  final double speedKph;
  final double voltageV;
  final double currentA;
  final double phaseACurrA;
  final double phaseCCurrA;
  final double motorTempC;
  final double controllerTempC;
  final int battCapPercent;
  final int gear;
  final bool isForward;
  final bool isBraking;

  // Fault flags
  final bool motorHallError;
  final bool throttleError;
  final bool motorTempProtect;
  final bool controllerTempProtect;

  // Wheel geometry (for speed calculation)
  final int wheelRadius;
  final int wheelWidth;
  final int wheelRatio;
  final int rateRatio;

  // Tunable parameters (read from controller)
  final int maxSpeedRaw;       // raw RPM value
  final int maxLineCurrRaw;    // raw, divide by 4 for amps
  final int zeroBattCoeff;
  final int fullBattCoeff;

  // Computed values
  final double powerKw;
  final double batteryPercent;

  // Session state
  final RideMode rideMode;
  final DateTime lastUpdate;

  const ControllerState({
    this.speedKph = 0.0,
    this.voltageV = 0.0,
    this.currentA = 0.0,
    this.phaseACurrA = 0.0,
    this.phaseCCurrA = 0.0,
    this.motorTempC = 0.0,
    this.controllerTempC = 0.0,
    this.battCapPercent = 0,
    this.gear = 0,
    this.isForward = true,
    this.isBraking = false,
    this.motorHallError = false,
    this.throttleError = false,
    this.motorTempProtect = false,
    this.controllerTempProtect = false,
    this.wheelRadius = 10,
    this.wheelWidth = 3,
    this.wheelRatio = 1,
    this.rateRatio = 1000,
    this.maxSpeedRaw = 0,
    this.maxLineCurrRaw = 0,
    this.zeroBattCoeff = 420,
    this.fullBattCoeff = 590,
    this.powerKw = 0.0,
    this.batteryPercent = 0.0,
    this.rideMode = RideMode.trail,
    required this.lastUpdate,
  });

  static ControllerState initial() => ControllerState(
        lastUpdate: DateTime.now(),
      );

  double get maxLineCurrA => maxLineCurrRaw / 4.0;
  bool get hasAnyFault =>
      motorHallError || throttleError || motorTempProtect || controllerTempProtect;

  ControllerState copyWith({
    double? speedKph,
    double? voltageV,
    double? currentA,
    double? phaseACurrA,
    double? phaseCCurrA,
    double? motorTempC,
    double? controllerTempC,
    int? battCapPercent,
    int? gear,
    bool? isForward,
    bool? isBraking,
    bool? motorHallError,
    bool? throttleError,
    bool? motorTempProtect,
    bool? controllerTempProtect,
    int? wheelRadius,
    int? wheelWidth,
    int? wheelRatio,
    int? rateRatio,
    int? maxSpeedRaw,
    int? maxLineCurrRaw,
    int? zeroBattCoeff,
    int? fullBattCoeff,
    double? powerKw,
    double? batteryPercent,
    RideMode? rideMode,
    DateTime? lastUpdate,
  }) {
    return ControllerState(
      speedKph: speedKph ?? this.speedKph,
      voltageV: voltageV ?? this.voltageV,
      currentA: currentA ?? this.currentA,
      phaseACurrA: phaseACurrA ?? this.phaseACurrA,
      phaseCCurrA: phaseCCurrA ?? this.phaseCCurrA,
      motorTempC: motorTempC ?? this.motorTempC,
      controllerTempC: controllerTempC ?? this.controllerTempC,
      battCapPercent: battCapPercent ?? this.battCapPercent,
      gear: gear ?? this.gear,
      isForward: isForward ?? this.isForward,
      isBraking: isBraking ?? this.isBraking,
      motorHallError: motorHallError ?? this.motorHallError,
      throttleError: throttleError ?? this.throttleError,
      motorTempProtect: motorTempProtect ?? this.motorTempProtect,
      controllerTempProtect:
          controllerTempProtect ?? this.controllerTempProtect,
      wheelRadius: wheelRadius ?? this.wheelRadius,
      wheelWidth: wheelWidth ?? this.wheelWidth,
      wheelRatio: wheelRatio ?? this.wheelRatio,
      rateRatio: rateRatio ?? this.rateRatio,
      maxSpeedRaw: maxSpeedRaw ?? this.maxSpeedRaw,
      maxLineCurrRaw: maxLineCurrRaw ?? this.maxLineCurrRaw,
      zeroBattCoeff: zeroBattCoeff ?? this.zeroBattCoeff,
      fullBattCoeff: fullBattCoeff ?? this.fullBattCoeff,
      powerKw: powerKw ?? this.powerKw,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      rideMode: rideMode ?? this.rideMode,
      lastUpdate: lastUpdate ?? this.lastUpdate,
    );
  }

  /// Returns a new state with speed recalculated from raw RPM.
  ControllerState withMeasureSpeed(int measureSpeed) {
    final kph = UnitConverter.measureSpeedToKph(
      measureSpeed: measureSpeed,
      wheelRadius: wheelRadius,
      wheelWidth: wheelWidth,
      wheelRatio: wheelRatio,
      rateRatio: rateRatio,
    );
    return copyWith(speedKph: kph, lastUpdate: DateTime.now());
  }

  /// Returns a new state with power and battery % recomputed.
  ControllerState withComputedFields() {
    final kw = UnitConverter.powerKw(voltageV, currentA);
    final batt = (voltageV > 0 && fullBattCoeff != zeroBattCoeff)
        ? UnitConverter.batteryPercent(
            voltageDeciVolts: voltageV * 10,
            zeroBattCoeff: zeroBattCoeff,
            fullBattCoeff: fullBattCoeff,
          )
        : batteryPercent;
    return copyWith(powerKw: kw, batteryPercent: batt);
  }
}

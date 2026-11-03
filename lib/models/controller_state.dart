import 'package:arcdash/models/drive_state.dart';
import 'package:arcdash/utils/unit_converter.dart';
import 'package:arcdash/models/telemetry_quality.dart';

enum ControllerTelemetry {
  speed,
  power,
  voltage,
  current,
  soc,
  range,
  profile,
  gear,
  motorTemperature,
  controllerTemperature,
  errors,
  trip,
}

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

  /// Raw motor rpm from 0xE2 MeasureSpeed (speedKph is derived from it).
  final int motorRpm;
  final double voltageV;
  final double currentA;
  final double phaseACurrA;
  final double phaseCCurrA;
  final double motorTempC;
  final double controllerTempC;
  final int battCapPercent;

  /// Speed level bits from 0xE2: 0 = low, 1 = mid, 2 = high (3 = high).
  final int gear;
  final bool isForward;
  final bool isBraking;

  /// N / D / R from 0xE2 (unknown until the first frame).
  final DriveDirection driveDirection;
  final bool wheelMoving;

  /// Last 0xD6 boost bit, held between frames (~1.5 s cadence).
  final bool boostActive;
  final DateTime? boostAt;

  /// Live extras for the ride telemetry CSV (official GraphPage fields).
  final int throttleDepth;
  final bool fieldWeakening;
  final double modulation;

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
  final int maxSpeedRaw; // raw RPM value
  final int maxLineCurrRaw; // raw, divide by 4 for amps
  final int zeroBattCoeff;
  final int fullBattCoeff;

  // Computed values
  final double powerKw;
  final double batteryPercent;
  final double rangeKm;
  final double rangeUncertaintyKm;
  final double? tripDistanceKm;

  // Session state
  final RideMode rideMode;
  final DateTime lastUpdate;
  final Map<ControllerTelemetry, TelemetrySample> telemetrySamples;

  const ControllerState({
    this.speedKph = 0.0,
    this.motorRpm = 0,
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
    this.driveDirection = DriveDirection.unknown,
    this.wheelMoving = false,
    this.boostActive = false,
    this.boostAt,
    this.throttleDepth = 0,
    this.fieldWeakening = false,
    this.modulation = 0,
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
    this.rangeKm = 0.0,
    this.rangeUncertaintyKm = 0.0,
    this.tripDistanceKm,
    this.rideMode = RideMode.trail,
    this.telemetrySamples = const {},
    required this.lastUpdate,
  });

  static ControllerState initial() => ControllerState(
        lastUpdate: DateTime.now(),
      );

  double get maxLineCurrA => maxLineCurrRaw / 4.0;
  bool get hasAnyFault =>
      motorHallError ||
      throttleError ||
      motorTempProtect ||
      controllerTempProtect;

  ControllerState copyWith({
    double? speedKph,
    int? motorRpm,
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
    DriveDirection? driveDirection,
    bool? wheelMoving,
    bool? boostActive,
    DateTime? boostAt,
    int? throttleDepth,
    bool? fieldWeakening,
    double? modulation,
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
    double? rangeKm,
    double? rangeUncertaintyKm,
    double? tripDistanceKm,
    RideMode? rideMode,
    DateTime? lastUpdate,
    Map<ControllerTelemetry, TelemetrySample>? telemetrySamples,
  }) {
    return ControllerState(
      speedKph: speedKph ?? this.speedKph,
      motorRpm: motorRpm ?? this.motorRpm,
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
      driveDirection: driveDirection ?? this.driveDirection,
      wheelMoving: wheelMoving ?? this.wheelMoving,
      boostActive: boostActive ?? this.boostActive,
      boostAt: boostAt ?? this.boostAt,
      throttleDepth: throttleDepth ?? this.throttleDepth,
      fieldWeakening: fieldWeakening ?? this.fieldWeakening,
      modulation: modulation ?? this.modulation,
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
      rangeKm: rangeKm ?? this.rangeKm,
      rangeUncertaintyKm: rangeUncertaintyKm ?? this.rangeUncertaintyKm,
      tripDistanceKm: tripDistanceKm ?? this.tripDistanceKm,
      rideMode: rideMode ?? this.rideMode,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      telemetrySamples: telemetrySamples ?? this.telemetrySamples,
    );
  }

  TelemetrySample? sample(ControllerTelemetry telemetry) =>
      telemetrySamples[telemetry];

  /// Gear older than this is not shown (link lost / frames stopped).
  static const gearMaxAge = Duration(seconds: 5);

  /// Boost is held this long after the last 0xD6 frame (sent ~every 1.5 s).
  static const boostMaxAge = Duration(seconds: 5);

  /// Current gear + boost for the status chip, or null when no fresh 0xE2
  /// frame has arrived.
  GearStatus? gearStatus(DateTime now) {
    final gearSample = sample(ControllerTelemetry.gear);
    if (gearSample == null ||
        driveDirection == DriveDirection.unknown ||
        now.difference(gearSample.capturedAt) > gearMaxAge) {
      return null;
    }
    final boostFresh =
        boostAt != null && now.difference(boostAt!) <= boostMaxAge;
    return GearStatus(
      direction: driveDirection,
      level: SpeedLevel.fromBits(gear),
      wheelMoving: wheelMoving,
      boost: boostFresh && boostActive,
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
    return copyWith(
        speedKph: kph, motorRpm: measureSpeed, lastUpdate: DateTime.now());
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

import 'package:arcdash/models/drive_state.dart';

/// A single ride session's statistics.
class RideSession {
  final String id;
  final DateTime startTime;
  DateTime? endTime;

  double distanceKm;
  double maxSpeedKph;
  double totalWhUsed;
  final List<SpeedSample> speedHistory;

  /// Peaks / sag / temps / gear time for the ride record and callouts.
  final RideTelemetry telemetry;

  double _avgSpeedSum = 0.0;
  int _avgSpeedSamples = 0;

  RideSession({
    required this.id,
    required this.startTime,
    this.distanceKm = 0.0,
    this.maxSpeedKph = 0.0,
    this.totalWhUsed = 0.0,
    List<SpeedSample>? speedHistory,
    RideTelemetry? telemetry,
  })  : speedHistory = speedHistory ?? [],
        telemetry = telemetry ?? RideTelemetry();

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
    double phaseACurrA = 0,
    double phaseCCurrA = 0,
    double motorTempC = 0,
    double controllerTempC = 0,
    GearStatus? gear,
    DateTime? at,
  }) {
    telemetry.add(
      speedKph: speedKph,
      voltageV: voltageV,
      currentA: currentA,
      phaseACurrA: phaseACurrA,
      phaseCCurrA: phaseCCurrA,
      motorTempC: motorTempC,
      controllerTempC: controllerTempC,
      gear: gear,
      deltaTimeSeconds: deltaTimeSeconds,
    );

    if (speedKph > maxSpeedKph) maxSpeedKph = speedKph;

    // Accumulate distance (speed in km/h * time in hours)
    distanceKm += speedKph * (deltaTimeSeconds / 3600.0);

    // Accumulate energy (power in kW * time in hours = kWh → × 1000 = Wh)
    final powerKw = voltageV * currentA / 1000.0;
    totalWhUsed += powerKw * 1000.0 * (deltaTimeSeconds / 3600.0);

    // Running avg speed
    _avgSpeedSum += speedKph;
    _avgSpeedSamples++;

    // Recent speed history for the live chart: the newest
    // [chartSamples] only, so memory stays flat on a long ride. Every
    // sample is streamed to the ride CSV on disk by the ride recorder.
    if (speedHistory.length >= chartSamples) {
      speedHistory.removeRange(0, speedHistory.length - chartSamples + 1);
    }
    speedHistory.add(SpeedSample(
      timestamp: at ?? DateTime.now(),
      speedKph: speedKph,
      gear: gear,
    ));
    sampleCount++;
  }

  /// Samples kept in memory for the live chart (about 8 minutes at 1 Hz).
  static const chartSamples = 500;

  /// All samples taken, including those no longer in [speedHistory].
  int sampleCount = 0;

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

  /// Per-sample export. `Gear` is N / R / D-LOW / D-MID / D-HIGH (blank when
  /// unknown), `Boost` 1 while boost (D6 Global_state3 bit 2) was active.

  /// Rows of [speedHistory] (the newest [chartSamples]); the full ride is
  /// streamed to disk by the ride recorder with the same columns.
  List<List<String>> toCsvRows() => [
        csvHeader,
        ...speedHistory.map(csvRow),
      ];

  static const csvHeader = ['Time', 'Speed (km/h)', 'Gear', 'Boost'];

  static List<String> csvRow(SpeedSample s) => [
        s.timestamp.toIso8601String(),
        s.speedKph.toStringAsFixed(1),
        s.gearCode,
        s.gear == null ? '' : (s.gear!.showsBoost ? '1' : '0'),
      ];
}

class SpeedSample {
  final DateTime timestamp;
  final double speedKph;

  /// Gear + boost at that second (null when unknown).
  final GearStatus? gear;

  const SpeedSample(
      {required this.timestamp, required this.speedKph, this.gear});

  /// `N`, `R`, `D-LOW`, `D-MID`, `D-HIGH` or blank (plain ASCII for CSV).
  String get gearCode => gearBucket(gear) ?? '';
}

/// Time-in-gear bucket for a sample: `N`, `R`, `D-LOW`, `D-MID`, `D-HIGH`.
/// Boost is tracked separately. Null when the gear is unknown.
String? gearBucket(GearStatus? g) => switch (g?.direction) {
      DriveDirection.neutral => 'N',
      DriveDirection.reverse => 'R',
      DriveDirection.drive => 'D-${g!.level.word}',
      _ => null,
    };

/// Running peaks of one ride, kept small (no per-sample arrays) so the
/// saved ride record stays a few hundred bytes.
class RideTelemetry {
  RideTelemetry();

  /// Below this line current the pack counts as "resting" for sag.
  static const restCurrentA = 3.0;

  /// Above this line current the pack counts as "loaded" for sag.
  static const loadCurrentA = 10.0;

  int samples = 0;
  double maxLineA = 0;
  double maxPhaseA = 0;
  double? minV;
  double? maxV;
  double? _restV;
  double maxSagV = 0;
  double maxMotorC = 0;
  double maxControllerC = 0;
  double _powerSumW = 0;
  double _movingSeconds = 0;
  double peakPowerW = 0;
  double boostSeconds = 0;
  final Map<String, double> gearSeconds = {};

  /// Average battery power while moving (W), null without moving samples.
  double? get avgPowerW =>
      _movingSeconds <= 0 ? null : _powerSumW / _movingSeconds;

  void add({
    required double speedKph,
    required double voltageV,
    required double currentA,
    double phaseACurrA = 0,
    double phaseCCurrA = 0,
    double motorTempC = 0,
    double controllerTempC = 0,
    GearStatus? gear,
    double deltaTimeSeconds = 1,
  }) {
    samples++;
    final dt = deltaTimeSeconds > 0 && deltaTimeSeconds < 10
        ? deltaTimeSeconds
        : 1.0; // first sample / long gaps count as one second
    if (currentA > maxLineA) maxLineA = currentA;
    final phase =
        [phaseACurrA.abs(), phaseCCurrA.abs()].reduce((a, b) => a > b ? a : b);
    if (phase > maxPhaseA) maxPhaseA = phase;
    if (motorTempC > maxMotorC) maxMotorC = motorTempC;
    if (controllerTempC > maxControllerC) maxControllerC = controllerTempC;
    if (voltageV > 1) {
      if (minV == null || voltageV < minV!) minV = voltageV;
      if (maxV == null || voltageV > maxV!) maxV = voltageV;
      if (currentA.abs() < restCurrentA) {
        _restV = voltageV;
      } else if (currentA > loadCurrentA && _restV != null) {
        final sag = _restV! - voltageV;
        if (sag > maxSagV) maxSagV = sag;
      }
      final power = voltageV * currentA;
      if (power > peakPowerW) peakPowerW = power;
      if (speedKph >= 1) {
        _powerSumW += power * dt;
        _movingSeconds += dt;
      }
    }
    final bucket = gearBucket(gear);
    if (bucket != null) {
      gearSeconds[bucket] = (gearSeconds[bucket] ?? 0) + dt;
    }
    if (gear?.showsBoost ?? false) boostSeconds += dt;
  }

  Map<String, dynamic> toJson() => {
        'samples': samples,
        'maxLineA': _r(maxLineA),
        'maxPhaseA': _r(maxPhaseA),
        'minV': minV == null ? null : _r(minV!),
        'maxV': maxV == null ? null : _r(maxV!),
        'maxSagV': _r(maxSagV),
        'maxMotorC': _r(maxMotorC),
        'maxControllerC': _r(maxControllerC),
        'avgPowerW': avgPowerW == null ? null : _r(avgPowerW!),
        'peakPowerW': _r(peakPowerW),
        'boostSeconds': _r(boostSeconds),
        'gearSeconds': {
          for (final e in gearSeconds.entries) e.key: _r(e.value)
        },
      };

  static double _r(double v) => (v * 10).roundToDouble() / 10;
}

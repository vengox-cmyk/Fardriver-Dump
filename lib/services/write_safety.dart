import 'package:arcdash/models/controller_identity.dart';

enum ParameterRisk { comfort, safetyCritical, hardware }

class ParameterDefinition {
  final String name;
  final int address;
  final int? minRaw;
  final int? maxRaw;
  final int mask;
  final int shift;
  final ParameterRisk risk;
  final bool readable;
  final bool hardwareBoundsConfirmed;

  const ParameterDefinition({
    required this.name,
    required this.address,
    required this.minRaw,
    required this.maxRaw,
    this.mask = 0xFFFF,
    this.shift = 0,
    required this.risk,
    required this.readable,
    required this.hardwareBoundsConfirmed,
  });

  bool get writable =>
      readable && hardwareBoundsConfirmed && minRaw != null && maxRaw != null;

  int? validateRaw(int value) {
    if (!writable || value < minRaw! || value > maxRaw!) return null;
    return value;
  }

  int applyToWord(int currentWord, int value) {
    final checked = validateRaw(value);
    if (checked == null) {
      throw StateError('$name has no confirmed writable bounds');
    }
    return (currentWord & ~mask) | ((checked << shift) & mask);
  }
}

class ParameterCatalog {
  // Limits remain locked until controller, motor, battery, and BMS values exist.
  static const definitions = <String, ParameterDefinition>{
    'maxSpeed': ParameterDefinition(
      name: 'maxSpeed',
      address: 0x15,
      minRaw: null,
      maxRaw: null,
      risk: ParameterRisk.safetyCritical,
      readable: true,
      hardwareBoundsConfirmed: false,
    ),
    'maxLineCurrent': ParameterDefinition(
      name: 'maxLineCurrent',
      address: 0x19,
      minRaw: null,
      maxRaw: null,
      risk: ParameterRisk.safetyCritical,
      readable: true,
      hardwareBoundsConfirmed: false,
    ),
    'throttleResponse': ParameterDefinition(
      name: 'throttleResponse',
      address: 0x1A,
      minRaw: null,
      maxRaw: null,
      mask: 0x000C,
      shift: 2,
      risk: ParameterRisk.hardware,
      readable: true,
      hardwareBoundsConfirmed: false,
    ),
  };

  const ParameterCatalog();

  ParameterDefinition operator [](String name) {
    final definition = definitions[name];
    if (definition == null) throw ArgumentError.value(name, 'name');
    return definition;
  }
}

enum SafetyRejection {
  disconnected,
  unknownIdentity,
  staleTelemetry,
  insufficientSamples,
  moving,
  motorRunning,
  directionUnknown,
  brakeActive,
  throttleNotZero,
  missingBackup,
}

class SafetySample {
  final DateTime at;
  final int rpm;
  final bool motorRunning;
  final bool directionKnown;
  final bool brakeActive;
  final bool throttleZero;

  const SafetySample({
    required this.at,
    required this.rpm,
    required this.motorRunning,
    required this.directionKnown,
    required this.brakeActive,
    required this.throttleZero,
  });
}

class SafetyDecision {
  final bool allowed;
  final Set<SafetyRejection> rejections;

  const SafetyDecision({required this.allowed, required this.rejections});
}

class SafetyEvaluator {
  final Duration maxTelemetryAge;
  final int requiredSamples;

  const SafetyEvaluator({
    this.maxTelemetryAge = const Duration(milliseconds: 500),
    this.requiredSamples = 3,
  });

  SafetyDecision evaluate({
    required DateTime now,
    required bool connected,
    required ControllerIdentity identity,
    required bool backupAvailable,
    required List<SafetySample> samples,
  }) {
    final rejections = <SafetyRejection>{};
    if (!connected) rejections.add(SafetyRejection.disconnected);
    if (!identity.isComplete) rejections.add(SafetyRejection.unknownIdentity);
    if (!backupAvailable) rejections.add(SafetyRejection.missingBackup);
    if (samples.length < requiredSamples) {
      rejections.add(SafetyRejection.insufficientSamples);
    }
    if (samples.isEmpty || now.difference(samples.last.at) > maxTelemetryAge) {
      rejections.add(SafetyRejection.staleTelemetry);
    }
    for (final sample in samples) {
      if (sample.rpm != 0) rejections.add(SafetyRejection.moving);
      if (sample.motorRunning) rejections.add(SafetyRejection.motorRunning);
      if (!sample.directionKnown) {
        rejections.add(SafetyRejection.directionUnknown);
      }
      if (sample.brakeActive) rejections.add(SafetyRejection.brakeActive);
      if (!sample.throttleZero) rejections.add(SafetyRejection.throttleNotZero);
    }
    return SafetyDecision(
      allowed: rejections.isEmpty,
      rejections: Set.unmodifiable(rejections),
    );
  }
}

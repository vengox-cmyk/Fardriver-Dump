import 'dart:convert';

/// A named set of controller parameters that can be saved, loaded, and applied.
class TuningProfile {
  final String name;
  final String description;

  /// Max speed in km/h (converted to raw RPM when writing).
  final double maxSpeedKph;

  /// Max line current in amps.
  final double maxLineCurrA;

  /// Max phase current in amps (stored for display; derived from phase coeff).
  final double maxPhaseCurrA;

  /// Regen strength 0.0–1.0.
  final double regenStrength;

  /// ThrottleResponse: 0=Line/Race, 1=Sport, 2=ECO.
  final int throttleResponse;

  /// 3-point power curve: [(rpm%, torque%), ...] for low/mid/high.
  final List<PowerPoint> powerCurve;

  final DateTime createdAt;
  final bool isStock;

  const TuningProfile({
    required this.name,
    required this.description,
    required this.maxSpeedKph,
    required this.maxLineCurrA,
    required this.maxPhaseCurrA,
    required this.regenStrength,
    required this.throttleResponse,
    required this.powerCurve,
    required this.createdAt,
    this.isStock = false,
  });

  // Preset profiles
  static TuningProfile stock() => TuningProfile(
        name: 'Stock',
        description: 'Factory default settings',
        maxSpeedKph: 45.0,
        maxLineCurrA: 60.0,
        maxPhaseCurrA: 120.0,
        regenStrength: 0.3,
        throttleResponse: 1,
        powerCurve: PowerPoint.defaultCurve(),
        createdAt: DateTime.now(),
        isStock: true,
      );

  static TuningProfile street() => TuningProfile(
        name: 'Street',
        description: 'Smooth power for road riding',
        maxSpeedKph: 55.0,
        maxLineCurrA: 80.0,
        maxPhaseCurrA: 160.0,
        regenStrength: 0.4,
        throttleResponse: 2, // ECO
        powerCurve: PowerPoint.smoothCurve(),
        createdAt: DateTime.now(),
      );

  static TuningProfile trail() => TuningProfile(
        name: 'Trail',
        description: 'Balanced power for off-road',
        maxSpeedKph: 65.0,
        maxLineCurrA: 100.0,
        maxPhaseCurrA: 200.0,
        regenStrength: 0.2,
        throttleResponse: 1, // Sport
        powerCurve: PowerPoint.defaultCurve(),
        createdAt: DateTime.now(),
      );

  static TuningProfile fullSend() => TuningProfile(
        name: 'Full Send',
        description: '⚠ Maximum power — race use only',
        maxSpeedKph: 85.0,
        maxLineCurrA: 150.0,
        maxPhaseCurrA: 300.0,
        regenStrength: 0.1,
        throttleResponse: 0, // Line/Race
        powerCurve: PowerPoint.aggressiveCurve(),
        createdAt: DateTime.now(),
      );

  TuningProfile copyWith({
    String? name,
    String? description,
    double? maxSpeedKph,
    double? maxLineCurrA,
    double? maxPhaseCurrA,
    double? regenStrength,
    int? throttleResponse,
    List<PowerPoint>? powerCurve,
    DateTime? createdAt,
    bool? isStock,
  }) {
    return TuningProfile(
      name: name ?? this.name,
      description: description ?? this.description,
      maxSpeedKph: maxSpeedKph ?? this.maxSpeedKph,
      maxLineCurrA: maxLineCurrA ?? this.maxLineCurrA,
      maxPhaseCurrA: maxPhaseCurrA ?? this.maxPhaseCurrA,
      regenStrength: regenStrength ?? this.regenStrength,
      throttleResponse: throttleResponse ?? this.throttleResponse,
      powerCurve: powerCurve ?? this.powerCurve,
      createdAt: createdAt ?? this.createdAt,
      isStock: isStock ?? this.isStock,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'maxSpeedKph': maxSpeedKph,
        'maxLineCurrA': maxLineCurrA,
        'maxPhaseCurrA': maxPhaseCurrA,
        'regenStrength': regenStrength,
        'throttleResponse': throttleResponse,
        'powerCurve': powerCurve.map((p) => p.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'isStock': isStock,
      };

  factory TuningProfile.fromJson(Map<String, dynamic> json) => TuningProfile(
        name: json['name'] as String,
        description: json['description'] as String,
        maxSpeedKph: (json['maxSpeedKph'] as num).toDouble(),
        maxLineCurrA: (json['maxLineCurrA'] as num).toDouble(),
        maxPhaseCurrA: (json['maxPhaseCurrA'] as num).toDouble(),
        regenStrength: (json['regenStrength'] as num).toDouble(),
        throttleResponse: json['throttleResponse'] as int,
        powerCurve: (json['powerCurve'] as List)
            .map((p) => PowerPoint.fromJson(p as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.parse(json['createdAt'] as String),
        isStock: json['isStock'] as bool? ?? false,
      );

  String toJsonString() => jsonEncode(toJson());

  factory TuningProfile.fromJsonString(String s) =>
      TuningProfile.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

/// A point on the 3-point power curve.
class PowerPoint {
  /// RPM fraction 0.0–1.0 (low / mid / high).
  final double rpmFraction;

  /// Torque fraction 0.0–1.0.
  final double torqueFraction;

  const PowerPoint({required this.rpmFraction, required this.torqueFraction});

  static List<PowerPoint> defaultCurve() => const [
        PowerPoint(rpmFraction: 0.0, torqueFraction: 0.6),
        PowerPoint(rpmFraction: 0.5, torqueFraction: 0.85),
        PowerPoint(rpmFraction: 1.0, torqueFraction: 1.0),
      ];

  static List<PowerPoint> smoothCurve() => const [
        PowerPoint(rpmFraction: 0.0, torqueFraction: 0.4),
        PowerPoint(rpmFraction: 0.5, torqueFraction: 0.7),
        PowerPoint(rpmFraction: 1.0, torqueFraction: 0.9),
      ];

  static List<PowerPoint> aggressiveCurve() => const [
        PowerPoint(rpmFraction: 0.0, torqueFraction: 0.9),
        PowerPoint(rpmFraction: 0.5, torqueFraction: 1.0),
        PowerPoint(rpmFraction: 1.0, torqueFraction: 1.0),
      ];

  Map<String, dynamic> toJson() => {
        'rpmFraction': rpmFraction,
        'torqueFraction': torqueFraction,
      };

  factory PowerPoint.fromJson(Map<String, dynamic> json) => PowerPoint(
        rpmFraction: (json['rpmFraction'] as num).toDouble(),
        torqueFraction: (json['torqueFraction'] as num).toDouble(),
      );
}

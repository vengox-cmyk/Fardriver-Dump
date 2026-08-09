class RangePredictionState {
  final int schemaVersion;
  final String controllerId;
  final double? learnedCapacityWh;
  final List<double> consumptionHistoryWhPerKm;
  final double socConfidence;
  final double? maxVoltageV;
  final double? minVoltageV;

  const RangePredictionState({
    this.schemaVersion = 1,
    required this.controllerId,
    this.learnedCapacityWh,
    this.consumptionHistoryWhPerKm = const [],
    this.socConfidence = 0.0,
    this.maxVoltageV,
    this.minVoltageV,
  });

  RangePredictionState copyWith({
    int? schemaVersion,
    String? controllerId,
    double? learnedCapacityWh,
    List<double>? consumptionHistoryWhPerKm,
    double? socConfidence,
    double? maxVoltageV,
    double? minVoltageV,
  }) {
    return RangePredictionState(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      controllerId: controllerId ?? this.controllerId,
      learnedCapacityWh: learnedCapacityWh ?? this.learnedCapacityWh,
      consumptionHistoryWhPerKm:
          consumptionHistoryWhPerKm ?? this.consumptionHistoryWhPerKm,
      socConfidence: socConfidence ?? this.socConfidence,
      maxVoltageV: maxVoltageV ?? this.maxVoltageV,
      minVoltageV: minVoltageV ?? this.minVoltageV,
    );
  }

  /// Returns a new state with [voltageV] folded into the learned calibration
  /// range (expanding max/min as needed). Returns `this` when the reading is
  /// invalid or already inside the learned range.
  RangePredictionState learnVoltage(double voltageV) {
    if (!voltageV.isFinite || voltageV <= 0) return this;
    final newMax =
        maxVoltageV == null || voltageV > maxVoltageV! ? voltageV : maxVoltageV;
    final newMin =
        minVoltageV == null || voltageV < minVoltageV! ? voltageV : minVoltageV;
    if (newMax == maxVoltageV && newMin == minVoltageV) return this;
    return copyWith(maxVoltageV: newMax, minVoltageV: newMin);
  }

  /// Returns a new state with the learned voltage calibration cleared.
  RangePredictionState clearVoltageCalibration() => RangePredictionState(
        schemaVersion: schemaVersion,
        controllerId: controllerId,
        learnedCapacityWh: learnedCapacityWh,
        consumptionHistoryWhPerKm: consumptionHistoryWhPerKm,
        socConfidence: socConfidence,
      );

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'controllerId': controllerId,
        'learnedCapacityWh': learnedCapacityWh,
        'consumptionHistoryWhPerKm': consumptionHistoryWhPerKm,
        'socConfidence': socConfidence,
        'maxVoltageV': maxVoltageV,
        'minVoltageV': minVoltageV,
      };

  factory RangePredictionState.fromJson(Map<String, dynamic> json) {
    final rawHistory = json['consumptionHistoryWhPerKm'] as List?;
    return RangePredictionState(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      controllerId: json['controllerId'] as String? ?? '',
      learnedCapacityWh: (json['learnedCapacityWh'] as num?)?.toDouble(),
      consumptionHistoryWhPerKm: rawHistory != null
          ? rawHistory.map((e) => (e as num).toDouble()).toList()
          : const [],
      socConfidence: (json['socConfidence'] as num?)?.toDouble() ?? 0.0,
      maxVoltageV: (json['maxVoltageV'] as num?)?.toDouble(),
      minVoltageV: (json['minVoltageV'] as num?)?.toDouble(),
    );
  }
}

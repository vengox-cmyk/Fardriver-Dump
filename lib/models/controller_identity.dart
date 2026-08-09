enum ControllerCompatibility {
  same,
  compatible,
  incompatible,
  unknown,
}

class ControllerIdentity {
  final String? model;
  final String? hardwareVersion;
  final String? firmwareVersion;
  final String? functionCode;
  final String? extensionCode;
  final String? bindingId;

  const ControllerIdentity({
    this.model,
    this.hardwareVersion,
    this.firmwareVersion,
    this.functionCode,
    this.extensionCode,
    this.bindingId,
  });

  bool get isComplete => [
        model,
        hardwareVersion,
        firmwareVersion,
        functionCode,
        extensionCode,
        bindingId,
      ].every(_present);

  ControllerCompatibility compare(ControllerIdentity other) {
    if (!isComplete || !other.isComplete) {
      return ControllerCompatibility.unknown;
    }
    if (model != other.model ||
        hardwareVersion != other.hardwareVersion ||
        functionCode != other.functionCode ||
        extensionCode != other.extensionCode ||
        bindingId != other.bindingId) {
      return ControllerCompatibility.incompatible;
    }
    if (firmwareVersion == other.firmwareVersion) {
      return ControllerCompatibility.same;
    }
    return _majorVersion(firmwareVersion!) ==
            _majorVersion(other.firmwareVersion!)
        ? ControllerCompatibility.compatible
        : ControllerCompatibility.incompatible;
  }

  Map<String, Object?> toJson() => {
        'model': model,
        'hardwareVersion': hardwareVersion,
        'firmwareVersion': firmwareVersion,
        'functionCode': functionCode,
        'extensionCode': extensionCode,
        'bindingId': bindingId,
      };

  factory ControllerIdentity.fromJson(Map<String, dynamic> json) =>
      ControllerIdentity(
        model: _stringOrNull(json['model']),
        hardwareVersion: _stringOrNull(json['hardwareVersion']),
        firmwareVersion: _stringOrNull(json['firmwareVersion']),
        functionCode: _stringOrNull(json['functionCode']),
        extensionCode: _stringOrNull(json['extensionCode']),
        bindingId: _stringOrNull(json['bindingId']),
      );

  static bool _present(Object? value) =>
      value is String && value.trim().isNotEmpty;

  static String? _stringOrNull(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;

  static String _majorVersion(String version) =>
      version.trim().split(RegExp(r'[.-]')).first;
}

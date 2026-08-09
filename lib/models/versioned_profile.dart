import 'dart:convert';

enum ProfileSource { integrated, user, imported, migrated }

const profileParameterNames = {
  'maxSpeedKph',
  'maxLineCurrA',
  'maxPhaseCurrA',
  'regenStrength',
  'throttleResponse',
};

class VersionedProfile {
  static const currentSchemaVersion = 1;

  final String id;
  final String name;
  final String description;
  final int schemaVersion;
  final String? controllerFamily;
  final Map<String, Object?> parameters;
  final ProfileSource source;
  final DateTime createdAt;
  final bool immutable;

  VersionedProfile({
    required this.id,
    required this.name,
    required this.description,
    this.schemaVersion = currentSchemaVersion,
    this.controllerFamily,
    required Map<String, Object?> parameters,
    required this.source,
    required this.createdAt,
    this.immutable = false,
  }) : parameters = Map.unmodifiable(_validateParameters(parameters)) {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id');
    if (name.trim().isEmpty) throw ArgumentError.value(name, 'name');
    if (schemaVersion != currentSchemaVersion) {
      throw ArgumentError.value(schemaVersion, 'schemaVersion');
    }
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'schemaVersion': schemaVersion,
        'controllerFamily': controllerFamily,
        'parameters': parameters,
        'source': source.name,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'immutable': immutable,
      };

  String encode() => jsonEncode(toJson());

  factory VersionedProfile.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != currentSchemaVersion) {
      throw const FormatException('unsupported profile schema');
    }
    final parameters = json['parameters'];
    final source =
        ProfileSource.values.where((value) => value.name == json['source']);
    if (parameters is! Map || source.length != 1) {
      throw const FormatException('invalid profile metadata');
    }
    return VersionedProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      schemaVersion: json['schemaVersion'] as int,
      controllerFamily: json['controllerFamily'] as String?,
      parameters: Map<String, Object?>.from(parameters),
      source: source.single,
      createdAt: DateTime.parse(json['createdAt'] as String),
      immutable: json['immutable'] as bool? ?? false,
    );
  }

  factory VersionedProfile.migrateLegacy(Map<String, dynamic> legacy) {
    final name = legacy['name'];
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('legacy profile name is required');
    }
    final parameters = <String, Object?>{};
    for (final key in profileParameterNames) {
      if (legacy.containsKey(key)) parameters[key] = legacy[key];
    }
    if (parameters.length != profileParameterNames.length) {
      throw const FormatException('legacy profile is incomplete');
    }
    return VersionedProfile(
      id: 'migrated-${name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}',
      name: name,
      description: legacy['description'] as String? ?? 'Migrated profile',
      parameters: parameters,
      source: ProfileSource.migrated,
      createdAt: DateTime.tryParse(legacy['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  static Map<String, Object?> _validateParameters(Map<String, Object?> input) {
    final unknown = input.keys.toSet().difference(profileParameterNames);
    if (unknown.isNotEmpty) {
      throw FormatException('unknown profile parameters: ${unknown.join(',')}');
    }
    final result = <String, Object?>{};
    for (final entry in input.entries) {
      if (entry.value is! num || (entry.value as num).isNaN) {
        throw FormatException('invalid profile value: ${entry.key}');
      }
      result[entry.key] = entry.value;
    }
    return result;
  }
}

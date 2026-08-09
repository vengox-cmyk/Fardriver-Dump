import 'dart:convert';

enum FixtureDirection {
  controllerToApp,
  appToController,
}

class FixtureControllerMetadata {
  final String model;
  final String firmware;

  const FixtureControllerMetadata({
    required this.model,
    required this.firmware,
  });

  factory FixtureControllerMetadata.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('controller metadata is required');
    }
    final model = value['model'];
    final firmware = value['firmware'];
    if (model is! String || model.trim().isEmpty) {
      throw const FormatException('controller.model is required');
    }
    if (firmware is! String || firmware.trim().isEmpty) {
      throw const FormatException('controller.firmware is required');
    }
    return FixtureControllerMetadata(
      model: model,
      firmware: firmware,
    );
  }
}

class ProtocolFixture {
  final String id;
  final FixtureDirection direction;
  final DateTime timestamp;
  final FixtureControllerMetadata controller;
  final List<int> bytes;
  final Map<String, dynamic> expected;

  const ProtocolFixture({
    required this.id,
    required this.direction,
    required this.timestamp,
    required this.controller,
    required this.bytes,
    required this.expected,
  });

  factory ProtocolFixture.fromJson(Map<String, dynamic> value) {
    final id = value['id'];
    final timestamp = value['timestamp'];
    final direction = value['direction'];
    final bytes = value['bytes'];
    final expected = value['expected'];

    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('id is required');
    }
    if (timestamp is! String) {
      throw const FormatException('timestamp is required');
    }
    final parsedTimestamp = DateTime.tryParse(timestamp);
    if (parsedTimestamp == null) {
      throw FormatException('invalid timestamp: $timestamp');
    }
    final parsedDirection = switch (direction) {
      'rx' => FixtureDirection.controllerToApp,
      'tx' => FixtureDirection.appToController,
      _ => throw FormatException('invalid direction: $direction'),
    };
    if (bytes is! String) {
      throw const FormatException('bytes must be a hex string');
    }
    final parsedBytes = _parseHex(bytes);
    if (parsedBytes.length != 8 && parsedBytes.length != 16) {
      throw FormatException(
        'packet must contain 8 or 16 bytes, got ${parsedBytes.length}',
      );
    }
    if (expected is! Map<String, dynamic>) {
      throw const FormatException('expected decode is required');
    }

    return ProtocolFixture(
      id: id,
      direction: parsedDirection,
      timestamp: parsedTimestamp.toUtc(),
      controller: FixtureControllerMetadata.fromJson(value['controller']),
      bytes: List.unmodifiable(parsedBytes),
      expected: Map.unmodifiable(expected),
    );
  }

  static List<int> _parseHex(String value) {
    final tokens = value.trim().isEmpty
        ? const <String>[]
        : value.trim().split(RegExp(r'\s+'));
    try {
      return tokens.map((token) {
        if (!RegExp(r'^[0-9A-Fa-f]{2}$').hasMatch(token)) {
          throw const FormatException(
              'bytes must contain two-digit hex values');
        }
        return int.parse(token, radix: 16);
      }).toList();
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('invalid hex bytes');
    }
  }
}

class ProtocolFixtureLoader {
  static List<ProtocolFixture> parseJsonLines(String content) {
    final fixtures = <ProtocolFixture>[];
    final lines = content.split('\n');
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index].trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('fixture line must be a JSON object');
        }
        fixtures.add(ProtocolFixture.fromJson(decoded));
      } on FormatException catch (error) {
        throw FormatException('line ${index + 1}: ${error.message}');
      } on Object catch (error) {
        throw FormatException('line ${index + 1}: invalid JSON ($error)');
      }
    }
    return List.unmodifiable(fixtures);
  }
}

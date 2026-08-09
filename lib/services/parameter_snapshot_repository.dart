import 'dart:convert';

import 'package:arcdash/models/controller_identity.dart';
import 'package:arcdash/services/versioned_json_repository.dart';

class PersistedParameterSnapshot {
  final ControllerIdentity controller;
  final Set<int> requiredAddresses;
  final Map<int, List<int>> rawBlocks;
  final Map<String, Object?> metadata;
  final String source;
  final DateTime capturedAt;
  final bool complete;
  final String integrityChecksum;

  PersistedParameterSnapshot({
    required this.controller,
    required this.requiredAddresses,
    required Map<int, List<int>> rawBlocks,
    required this.metadata,
    required this.source,
    required this.capturedAt,
    required this.complete,
    String? integrityChecksum,
  })  : rawBlocks = rawBlocks.map(
          (address, bytes) => MapEntry(address, List.unmodifiable(bytes)),
        ),
        integrityChecksum =
            integrityChecksum ?? _checksum(rawBlocks, requiredAddresses),
        assert(source != '');

  bool get isUsable =>
      complete &&
      controller.isComplete &&
      requiredAddresses.every(rawBlocks.containsKey) &&
      integrityChecksum == _checksum(rawBlocks, requiredAddresses);

  Map<String, Object?> toPayload() => {
        'controller': controller.toJson(),
        'requiredAddresses': requiredAddresses.toList()..sort(),
        'rawBlocks': {
          for (final entry in rawBlocks.entries)
            entry.key.toString(): entry.value,
        },
        'metadata': metadata,
        'source': source,
        'capturedAt': capturedAt.toUtc().toIso8601String(),
        'complete': complete,
        'integrityChecksum': integrityChecksum,
      };

  factory PersistedParameterSnapshot.fromPayload(Map<String, Object?> payload) {
    final raw = payload['rawBlocks'];
    final required = payload['requiredAddresses'];
    final controller = payload['controller'];
    if (raw is! Map || required is! List || controller is! Map) {
      throw const FormatException('invalid parameter snapshot payload');
    }
    final blocks = <int, List<int>>{};
    for (final entry in raw.entries) {
      final address = int.tryParse(entry.key.toString());
      final bytes = entry.value;
      if (address == null ||
          bytes is! List ||
          bytes.any((byte) => byte is! int || byte < 0 || byte > 255)) {
        throw const FormatException('invalid raw snapshot block');
      }
      blocks[address] = List<int>.from(bytes);
    }
    final addresses =
        required.whereType<num>().map((address) => address.toInt()).toSet();
    final checksum = payload['integrityChecksum'];
    final source = payload['source'];
    final capturedAt = payload['capturedAt'];
    if (checksum is! String || source is! String || capturedAt is! String) {
      throw const FormatException('snapshot metadata is incomplete');
    }
    return PersistedParameterSnapshot(
      controller:
          ControllerIdentity.fromJson(Map<String, dynamic>.from(controller)),
      requiredAddresses: addresses,
      rawBlocks: blocks,
      metadata: payload['metadata'] is Map
          ? Map<String, Object?>.from(payload['metadata'] as Map)
          : const {},
      source: source,
      capturedAt: DateTime.parse(capturedAt),
      complete: payload['complete'] == true,
      integrityChecksum: checksum,
    );
  }

  static String _checksum(
      Map<int, List<int>> blocks, Set<int> requiredAddresses) {
    final canonical = jsonEncode({
      'requiredAddresses': requiredAddresses.toList()..sort(),
      'rawBlocks': {
        for (final address in blocks.keys.toList()..sort())
          address.toString(): blocks[address],
      },
    });
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(canonical)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}

class ParameterSnapshotRepository {
  final VersionedJsonRepository _complete;
  final VersionedJsonRepository _pending;

  const ParameterSnapshotRepository({
    required VersionedJsonRepository complete,
    required VersionedJsonRepository pending,
  })  : _complete = complete,
        _pending = pending;

  Future<void> save(PersistedParameterSnapshot snapshot) {
    final repository = snapshot.complete ? _complete : _pending;
    return repository.save(snapshot.toPayload());
  }

  Future<PersistedParameterSnapshot?> loadComplete() async {
    final payload = await _complete.load();
    if (payload == null) return null;
    final snapshot = PersistedParameterSnapshot.fromPayload(payload);
    if (!snapshot.isUsable) {
      throw const FormatException('snapshot is incomplete or corrupted');
    }
    return snapshot;
  }
}

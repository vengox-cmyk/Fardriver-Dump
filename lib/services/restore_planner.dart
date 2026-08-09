import 'package:arcdash/models/controller_identity.dart';
import 'package:arcdash/services/parameter_snapshot_repository.dart';

enum RestoreRejection {
  incompleteSnapshot,
  incompatibleController,
  unknownController,
}

class RestorePlanException implements Exception {
  final RestoreRejection reason;

  const RestorePlanException(this.reason);
}

class RestoreDiff {
  final int address;
  final List<int> current;
  final List<int> target;
  final bool critical;

  const RestoreDiff({
    required this.address,
    required this.current,
    required this.target,
    required this.critical,
  });
}

class RestorePlan {
  final List<RestoreDiff> changes;
  final bool requiresConfirmation;

  const RestorePlan({
    required this.changes,
    required this.requiresConfirmation,
  });

  bool get isEmpty => changes.isEmpty;

  // T029 deliberately produces no executable write path.
  bool get canExecute => false;
}

class RestorePlanner {
  static const _criticalAddresses = {0x15, 0x19, 0x1A, 0xA0};

  const RestorePlanner();

  RestorePlan build({
    required PersistedParameterSnapshot backup,
    required PersistedParameterSnapshot current,
  }) {
    if (!backup.isUsable || !current.isUsable) {
      throw const RestorePlanException(RestoreRejection.incompleteSnapshot);
    }
    final compatibility = backup.controller.compare(current.controller);
    if (compatibility == ControllerCompatibility.unknown) {
      throw const RestorePlanException(RestoreRejection.unknownController);
    }
    if (compatibility == ControllerCompatibility.incompatible) {
      throw const RestorePlanException(RestoreRejection.incompatibleController);
    }

    final addresses = {
      ...backup.rawBlocks.keys,
      ...current.rawBlocks.keys,
    }.toList()
      ..sort();
    final changes = <RestoreDiff>[];
    for (final address in addresses) {
      final before = current.rawBlocks[address];
      final after = backup.rawBlocks[address];
      if (before == null || after == null) continue;
      if (!_sameBytes(before, after)) {
        changes.add(RestoreDiff(
          address: address,
          current: before,
          target: after,
          critical: _criticalAddresses.contains(address),
        ));
      }
    }
    return RestorePlan(
      changes: List.unmodifiable(changes),
      requiresConfirmation: changes.any((change) => change.critical),
    );
  }

  static bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

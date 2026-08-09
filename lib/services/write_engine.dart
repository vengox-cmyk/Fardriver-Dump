import 'dart:async';

import 'package:arcdash/services/write_safety.dart';

class WritePolicy {
  final bool enabled;
  final bool hardwareApproved;
  final Set<String> rolloutSafeParameters;

  const WritePolicy({
    this.enabled = false,
    this.hardwareApproved = false,
    this.rolloutSafeParameters = const {},
  });

  bool allows(
          String name, SafetyDecision safety, ParameterDefinition definition) =>
      enabled &&
      hardwareApproved &&
      rolloutSafeParameters.contains(name) &&
      definition.writable &&
      safety.allowed;
}

class RawParameterDiff {
  final String name;
  final int address;
  final int before;
  final int after;

  const RawParameterDiff({
    required this.name,
    required this.address,
    required this.before,
    required this.after,
  });
}

class ReadModifyWritePlanner {
  final ParameterCatalog catalog;

  const ReadModifyWritePlanner({this.catalog = const ParameterCatalog()});

  List<RawParameterDiff> plan({
    required Map<String, int> currentWords,
    required Map<String, int> targets,
  }) {
    final names = targets.keys.toList()..sort();
    final result = <RawParameterDiff>[];
    for (final name in names) {
      final definition = catalog[name];
      final current = currentWords[name];
      if (current == null) throw StateError('missing current raw value: $name');
      final next = definition.applyToWord(current, targets[name]!);
      if (next != current) {
        result.add(RawParameterDiff(
          name: name,
          address: definition.address,
          before: current,
          after: next,
        ));
      }
    }
    return List.unmodifiable(result);
  }
}

enum TransactionResult {
  success,
  safetyChanged,
  writeFailed,
  ackFailed,
  readBackFailed
}

class ParameterTransactionResult {
  final String name;
  final TransactionResult result;

  const ParameterTransactionResult(this.name, this.result);
}

typedef WriteStep = Future<bool> Function(RawParameterDiff diff);
typedef VerifyStep = Future<bool> Function(RawParameterDiff diff);
typedef SafetyCheck = bool Function();

class WriteTransaction {
  const WriteTransaction();

  Future<List<ParameterTransactionResult>> execute({
    required List<RawParameterDiff> diffs,
    required SafetyCheck safety,
    required WriteStep write,
    required VerifyStep verifyAck,
    required VerifyStep readBack,
  }) async {
    final results = <ParameterTransactionResult>[];
    for (final diff in diffs) {
      if (!safety()) {
        results.add(ParameterTransactionResult(
            diff.name, TransactionResult.safetyChanged));
        break;
      }
      if (!await write(diff)) {
        results.add(ParameterTransactionResult(
            diff.name, TransactionResult.writeFailed));
        break;
      }
      if (!await verifyAck(diff)) {
        results.add(
            ParameterTransactionResult(diff.name, TransactionResult.ackFailed));
        break;
      }
      if (!await readBack(diff)) {
        results.add(ParameterTransactionResult(
            diff.name, TransactionResult.readBackFailed));
        break;
      }
      results.add(
          ParameterTransactionResult(diff.name, TransactionResult.success));
    }
    return List.unmodifiable(results);
  }
}

class RollbackPlan {
  final List<RawParameterDiff> confirmed;
  final bool safe;

  const RollbackPlan({required this.confirmed, required this.safe});

  List<RawParameterDiff> reverse() => confirmed.reversed
      .map((diff) => RawParameterDiff(
            name: diff.name,
            address: diff.address,
            before: diff.after,
            after: diff.before,
          ))
      .toList(growable: false);
}

class WriteLock {
  bool _busy = false;
  final Map<String, Future<Object?>> _inFlight = {};

  bool get busy => _busy;

  Future<T> run<T>(String idempotencyKey, Future<T> Function() action) {
    final existing = _inFlight[idempotencyKey];
    if (existing != null) return existing as Future<T>;
    if (_busy) return Future<T>.error(StateError('write engine busy'));
    _busy = true;
    final task = action().whenComplete(() {
      _busy = false;
      _inFlight.remove(idempotencyKey);
    });
    _inFlight[idempotencyKey] = task;
    return task;
  }
}

class WriteAuditLog {
  final int maxEntries;
  final List<Map<String, Object?>> _entries = [];

  WriteAuditLog({this.maxEntries = 100});

  List<Map<String, Object?>> get entries => List.unmodifiable(_entries);

  void add(Map<String, Object?> entry) {
    _entries.add(Map.unmodifiable(entry));
    if (_entries.length > maxEntries) _entries.removeAt(0);
  }
}

import 'package:arcdash/services/parameter_snapshot_repository.dart';
import 'package:arcdash/services/versioned_json_repository.dart';

class StockBackupInfo {
  final PersistedParameterSnapshot snapshot;
  final bool integrityValid;

  const StockBackupInfo({
    required this.snapshot,
    required this.integrityValid,
  });

  String get integrityStatus => integrityValid ? 'valid' : 'invalid';
}

class StockBackupRepository {
  final VersionedJsonRepository _stock;
  final VersionedJsonRepository _history;

  const StockBackupRepository({
    required VersionedJsonRepository stock,
    required VersionedJsonRepository history,
  })  : _stock = stock,
        _history = history;

  /// Saves exactly once. Partial, default-only, or corrupted reads are refused.
  Future<bool> saveInitial(PersistedParameterSnapshot snapshot) async {
    if (!snapshot.isUsable || await _stock.load() != null) return false;
    await _stock.save(snapshot.toPayload());
    return true;
  }

  Future<StockBackupInfo?> load() async {
    final payload = await _stock.load();
    if (payload == null) return null;
    final snapshot = PersistedParameterSnapshot.fromPayload(payload);
    return StockBackupInfo(
      snapshot: snapshot,
      integrityValid: snapshot.isUsable,
    );
  }

  /// Replacing a stock backup requires explicit confirmation and keeps history.
  Future<bool> replaceConfirmed(
    PersistedParameterSnapshot snapshot, {
    required bool confirmed,
  }) async {
    if (!confirmed || !snapshot.isUsable) return false;
    final current = await load();
    if (current == null) return saveInitial(snapshot);

    final history = await _history.load() ?? <String, Object?>{'entries': []};
    final entries = history['entries'] is List
        ? List<Object?>.from(history['entries'] as List)
        : <Object?>[];
    entries.add(current.snapshot.toPayload());
    await _history.save({'entries': entries});
    await _stock.save(snapshot.toPayload());
    return true;
  }
}

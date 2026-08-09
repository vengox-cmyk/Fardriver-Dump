import 'dart:convert';
import 'package:arcdash/models/fault_catalog.dart';
import 'package:arcdash/services/range_prediction_repository.dart';

class FaultEventRecord {
  final String id;
  final DateTime occurredAt;
  DateTime? resolvedAt;
  final int rawBitMask;
  final List<FaultDefinition> activeFaults;

  FaultEventRecord({
    required this.id,
    required this.occurredAt,
    this.resolvedAt,
    required this.rawBitMask,
    required this.activeFaults,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'occurredAt': occurredAt.toIso8601String(),
        'resolvedAt': resolvedAt?.toIso8601String(),
        'rawBitMask': rawBitMask,
      };

  factory FaultEventRecord.fromJson(
    Map<String, dynamic> json,
    FaultCatalog catalog,
  ) {
    final mask = json['rawBitMask'] as int;
    return FaultEventRecord(
      id: json['id'] as String,
      occurredAt: DateTime.parse(json['occurredAt'] as String),
      resolvedAt: json['resolvedAt'] != null
          ? DateTime.parse(json['resolvedAt'] as String)
          : null,
      rawBitMask: mask,
      activeFaults: catalog.parseMask(mask),
    );
  }
}

class FaultHistoryRepository {
  static const String _storageKey = 'fault_history_records';
  final KeyValueStorage _storage;
  final FaultCatalog _catalog;
  final int maxHistoryCount;

  FaultHistoryRepository({
    required KeyValueStorage storage,
    FaultCatalog catalog = const FaultCatalog(),
    this.maxHistoryCount = 50,
  })  : _storage = storage,
        _catalog = catalog;

  void recordFaultEvent({
    required int rawBitMask,
    required DateTime timestamp,
  }) {
    final history = loadHistory();

    if (rawBitMask == 0) {
      // Resolve any currently open fault
      for (final event in history) {
        if (event.resolvedAt == null) {
          event.resolvedAt = timestamp;
        }
      }
    } else {
      // New active fault event
      final newRecord = FaultEventRecord(
        id: 'fault_${timestamp.millisecondsSinceEpoch}',
        occurredAt: timestamp,
        rawBitMask: rawBitMask,
        activeFaults: _catalog.parseMask(rawBitMask),
      );
      history.insert(0, newRecord);

      if (history.length > maxHistoryCount) {
        history.removeRange(maxHistoryCount, history.length);
      }
    }

    final rawJson = jsonEncode(history.map((e) => e.toJson()).toList());
    _storage.write(_storageKey, rawJson);
  }

  List<FaultEventRecord> loadHistory() {
    try {
      final raw = _storage.read(_storageKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];

      return decoded
          .map((e) => FaultEventRecord.fromJson(
                e as Map<String, dynamic>,
                _catalog,
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void clearAll() {
    _storage.delete(_storageKey);
  }
}

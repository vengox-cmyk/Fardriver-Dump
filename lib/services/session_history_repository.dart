import 'dart:convert';
import 'package:arcdash/models/session_metrics.dart';
import 'package:arcdash/services/range_prediction_repository.dart';

class SessionRecord {
  final String id;
  final DateTime startTime;
  final DateTime? endTime;
  final SessionMetrics metrics;

  const SessionRecord({
    required this.id,
    required this.startTime,
    this.endTime,
    required this.metrics,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime?.toIso8601String(),
        'metrics': {
          'durationMs': metrics.duration.inMilliseconds,
          'distanceKm': metrics.distanceKm,
          'avgSpeedKph': metrics.avgSpeedKph,
          'maxSpeedKph': metrics.maxSpeedKph,
          'consumedWh': metrics.consumedWh,
          'recoveredWh': metrics.recoveredWh,
          'netWh': metrics.netWh,
          'whPerKm': metrics.whPerKm,
          'maxPowerKw': metrics.maxPowerKw,
          'maxMotorTempC': metrics.maxMotorTempC,
          'maxMosTempC': metrics.maxMosTempC,
          'isIncomplete': metrics.isIncomplete,
        },
      };

  factory SessionRecord.fromJson(Map<String, dynamic> json) {
    final m = json['metrics'] as Map<String, dynamic>;
    return SessionRecord(
      id: json['id'] as String,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] != null
          ? DateTime.parse(json['endTime'] as String)
          : null,
      metrics: SessionMetrics(
        duration: Duration(milliseconds: m['durationMs'] as int? ?? 0),
        distanceKm: (m['distanceKm'] as num).toDouble(),
        avgSpeedKph: (m['avgSpeedKph'] as num).toDouble(),
        maxSpeedKph: (m['maxSpeedKph'] as num).toDouble(),
        consumedWh: (m['consumedWh'] as num).toDouble(),
        recoveredWh: (m['recoveredWh'] as num).toDouble(),
        netWh: (m['netWh'] as num).toDouble(),
        whPerKm: (m['whPerKm'] as num).toDouble(),
        maxPowerKw: (m['maxPowerKw'] as num).toDouble(),
        maxMotorTempC: (m['maxMotorTempC'] as num?)?.toDouble(),
        maxMosTempC: (m['maxMosTempC'] as num?)?.toDouble(),
        isIncomplete: m['isIncomplete'] as bool? ?? false,
      ),
    );
  }
}

class SessionHistoryRepository {
  static const String _storageKey = 'session_history_records';
  final KeyValueStorage _storage;
  final int maxHistoryCount;

  SessionHistoryRepository({
    required KeyValueStorage storage,
    this.maxHistoryCount = 50,
  }) : _storage = storage;

  void saveSession(SessionRecord record) {
    final history = loadHistory();
    history.removeWhere((item) => item.id == record.id);
    history.insert(0, record);

    if (history.length > maxHistoryCount) {
      history.removeRange(maxHistoryCount, history.length);
    }

    final rawJson = jsonEncode(history.map((e) => e.toJson()).toList());
    _storage.write(_storageKey, rawJson);
  }

  List<SessionRecord> loadHistory() {
    try {
      final raw = _storage.read(_storageKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];

      return decoded
          .map((e) => SessionRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void deleteSession(String id) {
    final history = loadHistory();
    history.removeWhere((item) => item.id == id);
    final rawJson = jsonEncode(history.map((e) => e.toJson()).toList());
    _storage.write(_storageKey, rawJson);
  }

  void clearAll() {
    _storage.delete(_storageKey);
  }
}

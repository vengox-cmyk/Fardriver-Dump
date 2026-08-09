import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/models/session_metrics.dart';
import 'package:arcdash/services/range_prediction_repository.dart';
import 'package:arcdash/services/session_history_repository.dart';

void main() {
  group('T072 - Sessionhistorie persistieren', () {
    late SessionHistoryRepository repository;
    late MemoryStorage memoryStorage;

    setUp(() {
      memoryStorage = MemoryStorage();
      repository = SessionHistoryRepository(
        storage: memoryStorage,
        maxHistoryCount: 3,
      );
    });

    test('saves and loads session record with metrics correctly', () {
      final record = SessionRecord(
        id: 'sess-1',
        startTime: DateTime(2026, 8, 3, 10, 0),
        endTime: DateTime(2026, 8, 3, 10, 30),
        metrics: const SessionMetrics(
          duration: Duration(minutes: 30),
          distanceKm: 15.0,
          avgSpeedKph: 30.0,
          maxSpeedKph: 55.0,
          consumedWh: 300.0,
          recoveredWh: 20.0,
          netWh: 280.0,
          whPerKm: 18.66,
          maxPowerKw: 4.5,
          maxMotorTempC: 50.0,
          maxMosTempC: 38.0,
          isIncomplete: false,
        ),
      );

      repository.saveSession(record);
      final history = repository.loadHistory();

      expect(history.length, 1);
      expect(history.first.id, 'sess-1');
      expect(history.first.metrics.distanceKm, 15.0);
    });

    test('enforces retention limit by discarding oldest sessions', () {
      for (int i = 1; i <= 5; i++) {
        repository.saveSession(SessionRecord(
          id: 'sess-$i',
          startTime: DateTime(2026, 8, 3, 10, i),
          metrics: const SessionMetrics(
            duration: Duration(minutes: 10),
            distanceKm: 5.0,
            avgSpeedKph: 30.0,
            maxSpeedKph: 40.0,
            consumedWh: 100.0,
            recoveredWh: 0.0,
            netWh: 100.0,
            whPerKm: 20.0,
            maxPowerKw: 3.0,
            isIncomplete: false,
          ),
        ));
      }

      final history = repository.loadHistory();
      // Should hold max 3 items
      expect(history.length, 3);
      expect(history.map((s) => s.id), ['sess-5', 'sess-4', 'sess-3']);
    });

    test('deletes individual session cleanly', () {
      repository.saveSession(SessionRecord(
        id: 'sess-del',
        startTime: DateTime.now(),
        metrics: const SessionMetrics(
          duration: Duration(minutes: 5),
          distanceKm: 2.0,
          avgSpeedKph: 24.0,
          maxSpeedKph: 30.0,
          consumedWh: 40.0,
          recoveredWh: 0.0,
          netWh: 40.0,
          whPerKm: 20.0,
          maxPowerKw: 2.0,
          isIncomplete: false,
        ),
      ));

      expect(repository.loadHistory().length, 1);
      repository.deleteSession('sess-del');
      expect(repository.loadHistory(), isEmpty);
    });

    test('handles corrupt JSON storage gracefully without breaking', () {
      memoryStorage.write('session_history_records', 'corrupted-data{[');
      expect(repository.loadHistory(), isEmpty);
    });
  });
}

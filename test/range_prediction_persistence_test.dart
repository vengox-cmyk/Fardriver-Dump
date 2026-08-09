import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/models/range_prediction_state.dart';
import 'package:arcdash/services/range_prediction_repository.dart';

void main() {
  group('T068 Range Prediction Persistence (Learned State)', () {
    test('serialization round-trip preserves capacity and consumption history',
        () {
      const state = RangePredictionState(
        schemaVersion: 1,
        controllerId: 'FD-72600-A1',
        learnedCapacityWh: 2450.5,
        consumptionHistoryWhPerKm: [22.5, 24.0, 21.8],
        socConfidence: 0.85,
      );

      final jsonMap = state.toJson();
      final restored = RangePredictionState.fromJson(jsonMap);

      expect(restored.schemaVersion, 1);
      expect(restored.controllerId, 'FD-72600-A1');
      expect(restored.learnedCapacityWh, 2450.5);
      expect(restored.consumptionHistoryWhPerKm, [22.5, 24.0, 21.8]);
      expect(restored.socConfidence, 0.85);
    });

    test('voltage calibration range survives serialization round-trip', () {
      const state = RangePredictionState(
        schemaVersion: 1,
        controllerId: 'FD-72600-A1',
        maxVoltageV: 82.4,
        minVoltageV: 58.2,
      );

      final restored = RangePredictionState.fromJson(state.toJson());

      expect(restored.maxVoltageV, 82.4);
      expect(restored.minVoltageV, 58.2);
    });

    test('corrupted or mismatching controller ID resets to safe initial state',
        () {
      final repository = RangePredictionRepository(storage: MemoryStorage());

      // Save state for controller A
      const stateA = RangePredictionState(
        schemaVersion: 1,
        controllerId: 'CONTROLLER-A',
        learnedCapacityWh: 3000.0,
        consumptionHistoryWhPerKm: [25.0],
      );
      repository.saveState(stateA);

      // Loading for controller B must return null / safe default
      final loadedB = repository.loadState(controllerId: 'CONTROLLER-B');
      expect(loadedB, isNull);

      // Loading for controller A returns stored state
      final loadedA = repository.loadState(controllerId: 'CONTROLLER-A');
      expect(loadedA, isNotNull);
      expect(loadedA!.learnedCapacityWh, 3000.0);
    });

    test('corrupt JSON or legacy schema triggers controlled reset', () {
      final storage = MemoryStorage();
      storage.write('range_prediction_state', 'invalid-json-content{');

      final repository = RangePredictionRepository(storage: storage);
      final loaded = repository.loadState(controllerId: 'ANY');
      expect(loaded, isNull);
    });
  });

  group('T068 Voltage Calibration Learning', () {
    test('learnVoltage expands min and max on first observations', () {
      final repository = RangePredictionRepository(storage: MemoryStorage());

      repository.learnVoltage(controllerId: 'FD-1', voltageV: 72.5);
      repository.learnVoltage(controllerId: 'FD-1', voltageV: 84.2);
      repository.learnVoltage(controllerId: 'FD-1', voltageV: 60.1);

      final state = repository.loadState(controllerId: 'FD-1');

      expect(state, isNotNull);
      expect(state!.maxVoltageV, 84.2);
      expect(state.minVoltageV, 60.1);
    });

    test('learnVoltage ignores invalid readings and does not shrink range', () {
      final repository = RangePredictionRepository(storage: MemoryStorage());

      repository.learnVoltage(controllerId: 'FD-1', voltageV: 72.0);
      repository.learnVoltage(controllerId: 'FD-1', voltageV: 80.0);
      repository.learnVoltage(controllerId: 'FD-1', voltageV: 70.0);
      repository.learnVoltage(controllerId: 'FD-1', voltageV: -1.0);
      repository.learnVoltage(controllerId: 'FD-1', voltageV: 82.0);

      final state = repository.loadState(controllerId: 'FD-1');

      expect(state, isNotNull);
      expect(state!.maxVoltageV, 82.0);
      expect(state.minVoltageV, 70.0);
    });
    test('single-slot calibration stays bound to the active controller', () {
      final repository = RangePredictionRepository(storage: MemoryStorage());

      repository.learnVoltage(controllerId: 'CONTROLLER-A', voltageV: 84.0);

      // Stored state is only readable for the controller it was learned for.
      final stateB = repository.loadState(controllerId: 'CONTROLLER-B');
      expect(stateB, isNull);

      final stateA = repository.loadState(controllerId: 'CONTROLLER-A');
      expect(stateA, isNotNull);
      expect(stateA!.maxVoltageV, 84.0);
    });

    test('resetVoltageCalibration clears only the calibration range', () {
      final repository = RangePredictionRepository(storage: MemoryStorage());

      repository.learnVoltage(controllerId: 'FD-1', voltageV: 84.0);
      repository.resetVoltageCalibration(controllerId: 'FD-1');

      final state = repository.loadState(controllerId: 'FD-1');

      expect(state, isNotNull);
      expect(state!.maxVoltageV, isNull);
      expect(state.minVoltageV, isNull);

      repository.learnVoltage(controllerId: 'FD-1', voltageV: 60.0);
      final relearned = repository.loadState(controllerId: 'FD-1');
      expect(relearned!.minVoltageV, 60.0);
    });
  });
}

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:arcdash/models/range_prediction_state.dart';

abstract class KeyValueStorage {
  String? read(String key);
  void write(String key, String value);
  void delete(String key);
}

class MemoryStorage implements KeyValueStorage {
  final Map<String, String> _data = {};

  @override
  String? read(String key) => _data[key];

  @override
  void write(String key, String value) => _data[key] = value;

  @override
  void delete(String key) => _data.remove(key);
}

/// Adapter for [SharedPreferences]. A null [SharedPreferences] (e.g. before
/// storage initialization) degrades gracefully to a read-only/no-op store.
class SharedPreferencesKeyValueStorage implements KeyValueStorage {
  final SharedPreferences? _prefs;

  SharedPreferencesKeyValueStorage([this._prefs]);

  @override
  String? read(String key) => _prefs?.getString(key);

  @override
  void write(String key, String value) => _prefs?.setString(key, value);

  @override
  void delete(String key) => _prefs?.remove(key);
}

class RangePredictionRepository {
  static const String _storageKey = 'range_prediction_state';
  final KeyValueStorage _storage;

  RangePredictionRepository({required KeyValueStorage storage})
      : _storage = storage;

  void saveState(RangePredictionState state) {
    final rawJson = jsonEncode(state.toJson());
    _storage.write(_storageKey, rawJson);
    _storage.write('${_storageKey}_last_saved', rawJson);
    if (state.controllerId.isNotEmpty) {
      _storage.write('${_storageKey}_${state.controllerId}', rawJson);
    }
  }

  RangePredictionState? loadState({required String controllerId}) {
    try {
      final raw = (controllerId.isNotEmpty
              ? _storage.read('${_storageKey}_$controllerId')
              : null) ??
          _storage.read(_storageKey) ??
          _storage.read('${_storageKey}_last_saved');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final state = RangePredictionState.fromJson(decoded);
      if (controllerId.isNotEmpty &&
          state.controllerId.isNotEmpty &&
          state.controllerId != controllerId) {
        return null;
      }
      return state;
    } catch (_) {
      return null;
    }
  }

  /// Automatically folds a live voltage reading into the learned calibration
  /// range and persists it. No-op when [voltageV] is invalid or already inside
  /// the learned range.
  void learnVoltage({required String controllerId, required double voltageV}) {
    if (!voltageV.isFinite || voltageV <= 0) return;
    final state = loadState(controllerId: controllerId) ??
        RangePredictionState(controllerId: controllerId);
    final updated = state.learnVoltage(voltageV);
    if (!identical(updated, state)) {
      saveState(updated);
    }
  }

  /// Clears the learned voltage calibration range for the given controller.
  void resetVoltageCalibration({required String controllerId}) {
    final state = loadState(controllerId: controllerId);
    if (state == null) return;
    saveState(state.clearVoltageCalibration());
  }

  void resetState() {
    _storage.delete(_storageKey);
  }
}

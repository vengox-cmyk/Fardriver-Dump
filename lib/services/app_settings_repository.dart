import 'dart:convert';
import 'package:arcdash/models/app_settings.dart';
import 'package:arcdash/services/range_prediction_repository.dart';

enum ResetDomain {
  dashboardLayouts,
  learnedData,
  sessionHistory,
  tuningProfiles,
  appSettings,
}

class AppSettingsRepository {
  static const String _settingsKey = 'app_settings';
  final KeyValueStorage _storage;

  AppSettingsRepository({required KeyValueStorage storage})
      : _storage = storage;

  AppSettings loadSettings() {
    try {
      final raw = _storage.read(_settingsKey);
      if (raw == null || raw.isEmpty) return const AppSettings();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const AppSettings();
      return AppSettings.fromJson(decoded);
    } catch (_) {
      return const AppSettings();
    }
  }

  void saveSettings(AppSettings settings) {
    final rawJson = jsonEncode(settings.toJson());
    _storage.write(_settingsKey, rawJson);
  }

  void resetDomain(ResetDomain domain) {
    final key = switch (domain) {
      ResetDomain.dashboardLayouts => 'dashboard_layouts',
      ResetDomain.learnedData => 'range_prediction_state',
      ResetDomain.sessionHistory => 'session_history_records',
      ResetDomain.tuningProfiles => 'tuning_profiles_data',
      ResetDomain.appSettings => _settingsKey,
    };
    _storage.delete(key);
  }

  void resetAllAppData({bool preserveStockBackup = true}) {
    for (final domain in ResetDomain.values) {
      resetDomain(domain);
    }
    if (!preserveStockBackup) {
      _storage.delete('stock_backup_data');
    }
  }
}

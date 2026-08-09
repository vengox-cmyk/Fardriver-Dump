import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/models/app_settings.dart';
import 'package:arcdash/services/app_settings_repository.dart';
import 'package:arcdash/services/range_prediction_repository.dart';

void main() {
  group('T075 - Einstellungen und Datenverwaltung', () {
    late AppSettingsRepository settingsRepo;
    late MemoryStorage memoryStorage;

    setUp(() {
      memoryStorage = MemoryStorage();
      settingsRepo = AppSettingsRepository(storage: memoryStorage);
    });

    test('loads default settings when no data is stored', () {
      final settings = settingsRepo.loadSettings();
      expect(settings.languageCode, 'de');
      expect(settings.autoReconnect, isTrue);
      expect(settings.hapticFeedbackEnabled, isTrue);
    });

    test('saves and persists settings updates', () {
      const updated = AppSettings(
        languageCode: 'en',
        autoReconnect: false,
        hapticFeedbackEnabled: false,
      );

      settingsRepo.saveSettings(updated);
      final loaded = settingsRepo.loadSettings();

      expect(loaded.languageCode, 'en');
      expect(loaded.autoReconnect, isFalse);
      expect(loaded.hapticFeedbackEnabled, isFalse);
    });

    test(
        'selective reset clears specific storage domains without deleting stock backups',
        () {
      // Seed data in multiple domains
      memoryStorage.write('app_settings', '{"languageCode":"en"}');
      memoryStorage.write('dashboard_layouts', '{"custom":"layout"}');
      memoryStorage.write('range_prediction_state', '{"learned":123}');
      memoryStorage.write('session_history_records', '[{"id":"1"}]');
      memoryStorage.write('stock_backup_data', '{"CRITICAL_STOCK_DATA":true}');

      // Reset dashboard layouts and range learned state only
      settingsRepo.resetDomain(ResetDomain.dashboardLayouts);
      settingsRepo.resetDomain(ResetDomain.learnedData);

      expect(memoryStorage.read('dashboard_layouts'), isNull);
      expect(memoryStorage.read('range_prediction_state'), isNull);

      // Stock backup, settings and session history must remain untouched!
      expect(memoryStorage.read('app_settings'), isNotNull);
      expect(memoryStorage.read('session_history_records'), isNotNull);
      expect(memoryStorage.read('stock_backup_data'), isNotNull);
    });

    test('full data reset preserves stock backups safely', () {
      memoryStorage.write('app_settings', '{"languageCode":"en"}');
      memoryStorage.write('dashboard_layouts', '{"custom":"layout"}');
      memoryStorage.write('range_prediction_state', '{"learned":123}');
      memoryStorage.write('session_history_records', '[{"id":"1"}]');
      memoryStorage.write('stock_backup_data', '{"CRITICAL_STOCK_DATA":true}');

      settingsRepo.resetAllAppData(preserveStockBackup: true);

      expect(memoryStorage.read('app_settings'), isNull);
      expect(memoryStorage.read('dashboard_layouts'), isNull);
      expect(memoryStorage.read('range_prediction_state'), isNull);
      expect(memoryStorage.read('session_history_records'), isNull);

      // Stock backup MUST NOT be wiped!
      expect(memoryStorage.read('stock_backup_data'), isNotNull);
    });
  });
}

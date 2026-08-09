import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/models/fault_catalog.dart';
import 'package:arcdash/services/range_prediction_repository.dart';
import 'package:arcdash/services/fault_history_repository.dart';

void main() {
  group('T074 - Fehlerkatalog und Fehlerhistorie', () {
    late FaultCatalog catalog;
    late FaultHistoryRepository historyRepo;
    late MemoryStorage memoryStorage;

    setUp(() {
      catalog = const FaultCatalog();
      memoryStorage = MemoryStorage();
      historyRepo = FaultHistoryRepository(
        storage: memoryStorage,
        maxHistoryCount: 5,
      );
    });

    test(
        'maps known error bits to clear German titles, severity, and safe behavior guidelines',
        () {
      final hallFault = catalog.lookupBit(bitIndex: 0); // Hall sensor
      expect(hallFault.titleGerman, contains('Hall-Sensor'));
      expect(hallFault.severity, FaultSeverity.error);
      expect(hallFault.safetyGuidelineGerman, contains('Motor anhalten'));

      final tempProtect = catalog.lookupBit(bitIndex: 6); // Motor Temp Protect
      expect(tempProtect.titleGerman, contains('Übertemperatur'));
      expect(tempProtect.severity, FaultSeverity.warning);
    });

    test(
        'handles unknown bit flags gracefully as diagnostic raw code without crashing or giving dangerous advice',
        () {
      final unknownFault = catalog.lookupBit(bitIndex: 31);
      expect(unknownFault.titleGerman, contains('Unbekannter Fehlercode'));
      expect(unknownFault.rawCode, '0x80000000');
      expect(unknownFault.severity, FaultSeverity.unknown);
      expect(unknownFault.safetyGuidelineGerman, contains('Diagnosecode'));
    });

    test(
        'records fault occurrences and resolution events in history repository',
        () {
      final now = DateTime(2026, 8, 3, 15, 0);

      // Record occurrence
      historyRepo.recordFaultEvent(
        rawBitMask: 0x01, // Bit 0 (Hall sensor)
        timestamp: now,
      );

      var history = historyRepo.loadHistory();
      expect(history.length, 1);
      expect(history.first.activeFaults.first.bitIndex, 0);
      expect(history.first.resolvedAt, isNull);

      // Resolve fault
      historyRepo.recordFaultEvent(
        rawBitMask: 0x00, // All clear
        timestamp: now.add(const Duration(minutes: 2)),
      );

      history = historyRepo.loadHistory();
      expect(history.first.resolvedAt, isNotNull);
    });

    test('enforces max history limit for fault events', () {
      for (int i = 0; i < 10; i++) {
        historyRepo.recordFaultEvent(
          rawBitMask: 1 << (i % 4),
          timestamp: DateTime.now().add(Duration(seconds: i)),
        );
      }

      final history = historyRepo.loadHistory();
      expect(history.length, 5); // Bounded to max 5
    });
  });
}

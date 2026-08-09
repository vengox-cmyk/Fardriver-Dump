import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/models/session_metrics.dart';
import 'package:arcdash/services/session_history_repository.dart';
import 'package:arcdash/services/session_export_service.dart';

class MockFileSharer implements FileSharer {
  String? lastSharedPath;
  String? lastMimeType;

  @override
  Future<bool> shareFile(
      {required String filePath, required String mimeType}) async {
    lastSharedPath = filePath;
    lastMimeType = mimeType;
    return true;
  }
}

void main() {
  group('T073 - Sessionexport und Sharing', () {
    late SessionExportService exportService;
    late MockFileSharer mockSharer;
    late SessionRecord sampleRecord;

    setUp(() {
      mockSharer = MockFileSharer();
      exportService = SessionExportService(fileSharer: mockSharer);

      sampleRecord = SessionRecord(
        id: 'session-2026-08-03-01',
        startTime: DateTime(2026, 8, 3, 14, 0),
        endTime: DateTime(2026, 8, 3, 14, 30),
        metrics: const SessionMetrics(
          duration: Duration(minutes: 30),
          distanceKm: 12.5,
          avgSpeedKph: 25.0,
          maxSpeedKph: 45.0,
          consumedWh: 250.0,
          recoveredWh: 15.0,
          netWh: 235.0,
          whPerKm: 18.8,
          maxPowerKw: 3.8,
          maxMotorTempC: 52.0,
          maxMosTempC: 40.0,
          isIncomplete: false,
        ),
      );
    });

    test('exports JSON with SI units and schema version correctly', () {
      final jsonStr = exportService.generateJsonExport(sampleRecord);
      expect(jsonStr, contains('"schemaVersion": 1'));
      expect(jsonStr, contains('"session-2026-08-03-01"'));
      expect(jsonStr, contains('"distanceKm": 12.5'));
      expect(jsonStr, contains('"netWh": 235.0'));
    });

    test('exports CSV with standardized headers and German locale option', () {
      final csvStr =
          exportService.generateCsvExport(sampleRecord, useGermanLocale: true);
      expect(
          csvStr,
          contains(
              'ID;Startzeit;Dauer (Min);Distanz (km);Durchschnitt (km/h);Maximal (km/h);Netto Energie (Wh)'));
      expect(
          csvStr,
          contains(
              'session-2026-08-03-01;2026-08-03T14:00:00.000;30;12,5;25,0;45,0;235,0'));
    });

    test('generates valid ArcDash safe filenames', () {
      final jsonName = exportService.generateFileName(sampleRecord, 'json');
      final csvName = exportService.generateFileName(sampleRecord, 'csv');

      expect(jsonName,
          matches(r'^arcdash_session_session-2026-08-03-01_\d+\.json$'));
      expect(csvName,
          matches(r'^arcdash_session_session-2026-08-03-01_\d+\.csv$'));
    });

    test('invokes file sharer with safe path and correct mime type', () async {
      final success = await exportService.shareSession(
        record: sampleRecord,
        format: ExportFormat.json,
        targetPath: '/tmp/test_export.json',
      );

      expect(success, isTrue);
      expect(mockSharer.lastSharedPath, '/tmp/test_export.json');
      expect(mockSharer.lastMimeType, 'application/json');
    });
  });
}

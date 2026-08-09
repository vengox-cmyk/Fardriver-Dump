import 'dart:convert';
import 'package:arcdash/services/session_history_repository.dart';

enum ExportFormat { json, csv }

abstract class FileSharer {
  Future<bool> shareFile({required String filePath, required String mimeType});
}

class SessionExportService {
  final FileSharer fileSharer;
  final int schemaVersion;

  SessionExportService({
    required this.fileSharer,
    this.schemaVersion = 1,
  });

  String generateJsonExport(SessionRecord record) {
    final payload = {
      'schemaVersion': schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'record': record.toJson(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  String generateCsvExport(SessionRecord record,
      {bool useGermanLocale = false}) {
    final sep = useGermanLocale ? ';' : ',';
    final fmtNum = (double val) => useGermanLocale
        ? val.toStringAsFixed(1).replaceAll('.', ',')
        : val.toStringAsFixed(1);

    final headers = [
      'ID',
      'Startzeit',
      'Dauer (Min)',
      'Distanz (km)',
      'Durchschnitt (km/h)',
      'Maximal (km/h)',
      'Netto Energie (Wh)',
    ].join(sep);

    final values = [
      record.id,
      record.startTime.toIso8601String(),
      record.metrics.duration.inMinutes.toString(),
      fmtNum(record.metrics.distanceKm),
      fmtNum(record.metrics.avgSpeedKph),
      fmtNum(record.metrics.maxSpeedKph),
      fmtNum(record.metrics.netWh),
    ].join(sep);

    return '$headers\n$values';
  }

  String generateFileName(SessionRecord record, String extension) {
    final cleanId = record.id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final ts = DateTime.now().millisecondsSinceEpoch;
    return 'arcdash_session_${cleanId}_$ts.$extension';
  }

  Future<bool> shareSession({
    required SessionRecord record,
    required ExportFormat format,
    required String targetPath,
  }) async {
    final mimeType =
        format == ExportFormat.json ? 'application/json' : 'text/csv';
    return await fileSharer.shareFile(
      filePath: targetPath,
      mimeType: mimeType,
    );
  }
}

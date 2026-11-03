import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';

import 'package:arcdash/models/ride_record.dart';
import 'package:arcdash/models/ride_stats.dart';
import 'package:arcdash/services/parameter_dump.dart';
import 'package:arcdash/services/parameter_dump_io.dart';
import 'package:arcdash/services/ride_analysis.dart';
import 'package:arcdash/services/saved_files.dart';

/// Saves rides permanently and reads them back for the Rides tab.
///
/// A ride writes the per-second CSV (`farsure/rides/`) and a small ride
/// record (`farsure/ride_records/`) that points at the parameter dump in
/// force at the start. It never writes a parameter dump itself (the live
/// archiver already saves each distinct configuration once), so nothing is
/// duplicated. Every ride the rider starts is saved, however short.
class RideArchive {
  RideArchive(this.store,
      {Future<String> Function()? appVersion, this.controllerName})
      : _appVersion = appVersion ?? ParameterDumpIo.appVersion;

  final SavedFilesStore store;

  /// Name of the connected controller (BLE name, e.g. CONTROLDM309); used
  /// as the ride's controller id ahead of the snapshot's id, which may be
  /// a MAC in older dumps.
  final String? Function()? controllerName;
  final Future<String> Function() _appVersion;

  static String recordFileName(DateTime start) =>
      'ride_${SavedFilesStore.stamp(start)}.json';

  static String csvFileName(DateTime start) =>
      'arcdash_ride_${start.millisecondsSinceEpoch}.csv';

  /// The ~10 Hz companion of [csvFileName].
  static String telemetryFileName(DateTime start) =>
      'arcdash_ride_${start.millisecondsSinceEpoch}_telemetry.csv';

  static bool isTelemetryFile(String name) => name.endsWith('_telemetry.csv');

  /// Writes the whole CSV (from the samples in memory) and a finished
  /// record in one go. Returns the record, or null when the write failed
  /// (never throws). Live rides use [RideRecorder], which streams instead.
  Future<RideRecord?> save(RideSession session) async {
    try {
      final csvName = csvFileName(session.startTime);
      await store.write(SavedFileKind.rideCsv, csvName,
          const ListToCsvConverter().convert(session.toCsvRows()));
      final snapshot = await pickSnapshot(session.startTime);
      return await writeRecord(session,
          csvName: csvName, snapshot: snapshot, finished: true);
    } catch (e) {
      debugPrint('Saving ride record failed: $e');
      return null;
    }
  }

  /// Settings snapshot for a ride: the newest saved dump before the start,
  /// or one saved within the grace window after it (file name + controller
  /// id; both empty/null when there is none).
  Future<({String? name, String controllerId})> pickSnapshot(
      DateTime start) async {
    final dumps = await store.list(kind: SavedFileKind.dump);
    final snapshot = RideAnalysis.pickSnapshot([
      for (final d in dumps)
        (time: d.time, source: d.info['source'] ?? '', name: d.name)
    ], start);
    var controllerId = '';
    for (final d in dumps) {
      if (d.name == snapshot) controllerId = d.info['controller_id'] ?? '';
    }
    return (name: snapshot, controllerId: controllerId);
  }

  /// Writes (atomically replaces) the ride record of [session].
  Future<RideRecord> writeRecord(
    RideSession session, {
    required String csvName,
    required ({String? name, String controllerId}) snapshot,
    required bool finished,
  }) async {
    final record = RideRecord.fromSession(session,
        settingsDump: snapshot.name,
        csvFile: csvName,
        controllerId: controllerNameOf(controllerName?.call() ?? '') ??
            snapshot.controllerId,
        appVersion: await _appVersion(),
        finished: finished);
    await store.write(SavedFileKind.rideRecord,
        recordFileName(session.startTime), record.encode());
    return record;
  }

  /// Ride record entries, newest first (heads only; cheap).
  Future<List<SavedFileEntry>> listRecords() =>
      store.list(kind: SavedFileKind.rideRecord);

  static Future<RideRecord> load(File file) async =>
      RideRecord.decode(await file.readAsString());

  /// The saved ride before [ride] from the same controller, or null.
  ///
  /// v1.4: matched by controller NAME (e.g. CONTROLDM309), because BLE MAC
  /// addresses change. Older files only have a MAC (or nothing); those are
  /// used as a fallback when no ride with the same name exists, but a ride
  /// with a different name is never used. See [pickPrevious].
  Future<RideRecord?> previousOf(RideRecord ride) async {
    final entries = await listRecords();
    final older = <RideRecord>[];
    for (final e in entries) {
      if (!e.time.isBefore(ride.start)) continue;
      try {
        final r = await load(e.file);
        if (r.id != ride.id) older.add(r);
      } on Object {
        continue;
      }
    }
    return pickPrevious(ride, older);
  }

  /// MAC-looking ids (AA:BB:CC:DD:EE:FF) are not stable names.
  static final _mac = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$');

  /// The controller name in [id], or null for a MAC / empty id.
  static String? controllerNameOf(String id) {
    final t = id.trim();
    if (t.isEmpty || _mac.hasMatch(t)) return null;
    return t.toUpperCase();
  }

  /// Newest ride in [older] (any order) for the same controller as [ride]:
  /// 1. same name; 2. else the newest one without a name (MAC-only/old
  /// file). A ride whose name differs is never picked. When [ride] itself
  /// has no name, the newest older ride is used (old behaviour).
  static RideRecord? pickPrevious(RideRecord ride, List<RideRecord> older) {
    final sorted = [
      for (final r in older)
        if (r.start.isBefore(ride.start) && r.id != ride.id) r
    ]..sort((a, b) => b.start.compareTo(a.start));
    final name = controllerNameOf(ride.controllerId);
    if (name == null) return sorted.isEmpty ? null : sorted.first;
    for (final r in sorted) {
      if (controllerNameOf(r.controllerId) == name) return r;
    }
    for (final r in sorted) {
      if (controllerNameOf(r.controllerId) == null) return r;
    }
    return null;
  }

  /// The parameter dump file a record points at, parsed; null when gone.
  Future<ParameterDump?> loadDump(String? fileName) async {
    if (fileName == null || fileName.isEmpty) return null;
    try {
      final dir = await store.directoryFor(SavedFileKind.dump);
      final file = File('${dir.path}/${SavedFilesStore.safeName(fileName)}');
      if (!await file.exists()) return null;
      return ParameterDumpIo.parseFile(await file.readAsBytes(), fileName);
    } on Object catch (e) {
      debugPrint('Ride settings snapshot unreadable: $e');
      return null;
    }
  }
}

/// Streams one running ride to disk so nothing is lost and memory stays
/// flat however long the ride is.
///
/// * [begin] creates the ride CSV (header) and an unfinished record.
/// * [add] buffers one CSV row in memory (a few bytes).
/// * [checkpoint] appends the buffered rows to the CSV and rewrites the
///   record (atomic), still marked unfinished, with the end time = now.
///   The stats notifier calls it every few seconds, so a crash or a killed
///   app loses at most that much and leaves a ride marked unfinished.
/// * [finish] flushes the rest and writes the record as finished.
///
/// All disk work runs one after another on a private queue and never throws.
class RideRecorder {
  RideRecorder(this.archive, this.session);

  final RideArchive archive;
  final RideSession session;

  final StringBuffer _pending = StringBuffer();
  File? _csv;
  ({String? name, String controllerId}) _snapshot =
      (name: null, controllerId: '');
  Future<void> _queue = Future<void>.value();
  int _rowsWritten = 0;

  String get csvName => RideArchive.csvFileName(session.startTime);

  /// ~10 Hz telemetry next to the 1 Hz ride CSV.
  String get telemetryName => RideArchive.telemetryFileName(session.startTime);

  final StringBuffer _telemetry = StringBuffer();
  int _telemetryLines = 0;
  File? _telemetryCsv;

  /// Telemetry rows dropped because the buffer was full (disk failing).
  int telemetryDropped = 0;

  /// Most rows held in memory between flushes (5 s at 10 Hz is ~50; the cap
  /// only matters when writing keeps failing), so memory stays bounded.
  static const telemetryBufferCap = 3000;

  static const telemetryHeader = [
    'Time', 'ms', 'Speed (km/h)', 'RPM', 'Voltage (V)', 'Line current (A)',
    'Phase A (A)', 'Phase C (A)', 'Motor (°C)', 'Controller (°C)',
    'Throttle depth', 'Modulation', 'Field weakening', 'Gear', 'Boost',
  ];

  /// Adds one telemetry row (strings, [telemetryHeader] order).
  void addTelemetry(List<String> row) {
    if (_telemetryLines >= telemetryBufferCap) {
      telemetryDropped++;
      return;
    }
    _telemetry.write(_line(row));
    _telemetryLines++;
  }

  /// CSV rows on disk so far (header excluded).
  int get rowsWritten => _rowsWritten;

  static const _codec = ListToCsvConverter();
  static String _line(List<String> row) => '${_codec.convert([row])}\r\n';

  Future<void> _enqueue(Future<void> Function() job) {
    return _queue = _queue.then((_) => job()).catchError((Object e) {
      debugPrint('Ride recorder: $e');
    });
  }

  Future<void> begin() => _enqueue(() async {
        final dir = await archive.store.directoryFor(SavedFileKind.rideCsv);
        final file = File('${dir.path}/$csvName');
        await file.writeAsString(_line(RideSession.csvHeader), flush: true);
        _csv = file;
        final tFile = File('${dir.path}/$telemetryName');
        await tFile.writeAsString(_line(telemetryHeader), flush: true);
        _telemetryCsv = tFile;
        await _refreshSnapshot();
        await _writeRecord(finished: false);
      });

  void add(SpeedSample sample) {
    _pending.write(_line(RideSession.csvRow(sample)));
  }

  Future<void> checkpoint() => _enqueue(() async {
        await _flushRows();
        // The snapshot may still change until the grace window after the
        // start has passed (a dump read right after starting counts).
        if (DateTime.now().difference(session.startTime) <=
            RideAnalysis.snapshotGrace + const Duration(seconds: 10)) {
          await _refreshSnapshot();
        }
        await _writeRecord(finished: false);
      });

  /// Flushes everything and writes the finished record (null on failure).
  Future<RideRecord?> finish() async {
    RideRecord? record;
    await _enqueue(() async {
      await _flushRows();
      await _refreshSnapshot();
      record = await _writeRecord(finished: true);
      // Public Documents/FarSure/rides copies (best effort).
      for (final f in [_csv, _telemetryCsv]) {
        if (f == null) continue;
        try {
          final hook = SavedFilesStore.onWritten;
          if (hook != null) {
            await hook(SavedFileKind.rideCsv, f);
          }
        } catch (e) {
          debugPrint('Ride CSV mirror skipped: $e');
        }
      }
    });
    return record;
  }

  Future<void> _flushTelemetry() async {
    final file = _telemetryCsv;
    if (file == null || _telemetry.isEmpty) return;
    final text = _telemetry.toString();
    _telemetry.clear();
    final lines = _telemetryLines;
    _telemetryLines = 0;
    try {
      await file.writeAsString(text, mode: FileMode.append, flush: true);
    } catch (e) {
      // Keep (bounded) for the next checkpoint.
      final later = _telemetry.toString();
      _telemetry
        ..clear()
        ..write(text)
        ..write(later);
      _telemetryLines += lines;
      debugPrint('Telemetry flush failed: $e');
    }
  }

  Future<void> _flushRows() async {
    await _flushTelemetry();
    final file = _csv;
    if (file == null || _pending.isEmpty) return;
    final text = _pending.toString();
    _pending.clear();
    try {
      await file.writeAsString(text, mode: FileMode.append, flush: true);
    } catch (_) {
      // Keep the rows for the next checkpoint.
      final later = _pending.toString();
      _pending
        ..clear()
        ..write(text)
        ..write(later);
      rethrow;
    }
    _rowsWritten += '\n'.allMatches(text).length;
  }

  Future<void> _refreshSnapshot() async {
    try {
      _snapshot = await archive.pickSnapshot(session.startTime);
    } catch (e) {
      debugPrint('Ride snapshot lookup failed: $e');
    }
  }

  Future<RideRecord> _writeRecord({required bool finished}) =>
      archive.writeRecord(session,
          csvName: csvName, snapshot: _snapshot, finished: finished);
}

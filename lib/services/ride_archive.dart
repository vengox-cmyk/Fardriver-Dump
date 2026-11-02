import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';

import 'package:arcdash/models/ride_record.dart';
import 'package:arcdash/models/ride_stats.dart';
import 'package:arcdash/services/parameter_dump.dart';
import 'package:arcdash/services/parameter_dump_io.dart';
import 'package:arcdash/services/ride_analysis.dart';
import 'package:arcdash/services/saved_files.dart';

/// Saves finished rides permanently and reads them back for the Rides tab.
///
/// On ride end it writes the per-second CSV (`farsure/rides/`) and a small
/// ride record (`farsure/ride_records/`) that points at the parameter dump
/// in force at the start. It never writes a parameter dump itself (the live
/// archiver already saves each distinct configuration once), so nothing is
/// duplicated.
class RideArchive {
  RideArchive(this.store, {Future<String> Function()? appVersion})
      : _appVersion = appVersion ?? ParameterDumpIo.appVersion;

  final SavedFilesStore store;
  final Future<String> Function() _appVersion;

  /// Rides shorter than this (and under [minDistanceKm]) are not saved as
  /// records: a push across the garage is not a ride.
  static const minDuration = Duration(seconds: 60);
  static const minDistanceKm = 0.1;

  static bool worthSaving(RideSession s) =>
      s.duration >= minDuration || s.distanceKm >= minDistanceKm;

  static String recordFileName(DateTime start) =>
      'ride_${SavedFilesStore.stamp(start)}.json';

  /// Writes the CSV and the record. Returns the record, or null when the
  /// ride is too short or the write failed (never throws).
  Future<RideRecord?> save(RideSession session) async {
    if (!worthSaving(session)) return null;
    try {
      final csvName =
          'arcdash_ride_${session.startTime.millisecondsSinceEpoch}.csv';
      await store.write(SavedFileKind.rideCsv, csvName,
          const ListToCsvConverter().convert(session.toCsvRows()));

      final dumps = await store.list(kind: SavedFileKind.dump);
      final snapshot = RideAnalysis.pickSnapshot([
        for (final d in dumps)
          (time: d.time, source: d.info['source'] ?? '', name: d.name)
      ], session.startTime);
      String controllerId = '';
      for (final d in dumps) {
        if (d.name == snapshot) controllerId = d.info['controller_id'] ?? '';
      }
      final record = RideRecord.fromSession(session,
          settingsDump: snapshot,
          csvFile: csvName,
          controllerId: controllerId,
          appVersion: await _appVersion());
      await store.write(SavedFileKind.rideRecord,
          recordFileName(session.startTime), record.encode());
      return record;
    } catch (e) {
      debugPrint('Saving ride record failed: $e');
      return null;
    }
  }

  /// Ride record entries, newest first (heads only; cheap).
  Future<List<SavedFileEntry>> listRecords() =>
      store.list(kind: SavedFileKind.rideRecord);

  static Future<RideRecord> load(File file) async =>
      RideRecord.decode(await file.readAsString());

  /// The saved ride directly before [ride] (by start time), or null.
  Future<RideRecord?> previousOf(RideRecord ride) async {
    final entries = await listRecords();
    for (final e in entries) {
      // newest first: the first one older than this ride
      if (!e.time.isBefore(ride.start)) continue;
      try {
        final r = await load(e.file);
        if (r.id != ride.id) return r;
      } on Object {
        continue;
      }
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

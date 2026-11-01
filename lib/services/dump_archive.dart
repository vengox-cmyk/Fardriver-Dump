import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:arcdash/models/fardriver_param_catalog.dart';
import 'package:arcdash/services/parameter_capture.dart';
import 'package:arcdash/services/parameter_csv.dart';
import 'package:arcdash/services/parameter_dump.dart';
import 'package:arcdash/services/parameter_dump_io.dart';
import 'package:arcdash/services/parameter_snapshot_repository.dart';
import 'package:arcdash/services/saved_files.dart';

/// Writes live parameter snapshots permanently to `farsure/dumps/` — but
/// only when the parameter *values* differ from the latest saved dump.
///
/// Why v1.2.2 wrote hundreds of files: the controller streams a real-time
/// clock (`TimeHour`/`TimeMin`/`TimeSecond`, blocks 0x1E/0x24) and riding
/// counters inside its config blocks, so every streaming cycle looked like a
/// "changed configuration" and was saved as a new file. On top of that the
/// "already saved" memory was per BLE address (which changes between
/// connections), lived only in RAM, and unchanged settings were re-saved
/// every 30 minutes.
///
/// Now the comparison masks the clock, counters, BLE id and timestamps, is
/// made against the newest dump *on disk* (so it survives restarts and
/// address changes), and there is no periodic re-save. Nothing is ever
/// deleted automatically.
class LiveDumpArchiver {
  LiveDumpArchiver({
    required SavedFilesStore store,
    required Future<String> Function() appVersion,
    DateTime Function()? clock,
  })  : _store = store,
        _appVersion = appVersion,
        _clock = clock ?? DateTime.now;

  final SavedFilesStore _store;
  final Future<String> Function() _appVersion;
  final DateTime Function() _clock;

  Future<File?> _queue = Future.value();

  /// Fields that are not configuration: riding counters, the controller's
  /// clock and its save counter.
  static const _volatile = [
    ('SaveNum', 0x00),
    ('ModelYear', 0x1E),
    ('ModelMonth', 0x1E),
    ('ModelDay', 0x1E),
    ('TimeHour', 0x1E),
    ('TimeMin', 0x24),
    ('TimeSecond', 0x24),
    ('DistanceLSB', 0x69),
    ('TotalTime', 0x7C),
    ('DistanceMSB', 0x7C),
    ('AVGPower', 0xD0),
    ('AVGSpeed', 0xD0),
  ];

  /// Snapshot signature of the parameter values only (clock, counters and
  /// save counter masked; BLE id and timestamps are not part of it).
  static String configSignature(Map<int, List<int>> blocks) {
    final masked = {
      for (final e in blocks.entries) e.key: [...e.value]
    };
    for (final (name, block) in _volatile) {
      final data = masked[block];
      if (data == null) continue;
      final def = FardriverParamCatalog.byName(name, block: block);
      final bytes = (def.bitOffset + def.bitWidth + 7) ~/ 8;
      for (var i = def.byteOffset;
          i < def.byteOffset + bytes && i < data.length;
          i++) {
        data[i] = 0;
      }
    }
    final keys = masked.keys.toList()..sort();
    return keys.map((k) => '$k:${masked[k]!.join(',')}').join(';');
  }

  /// Newest saved dump and its values signature, or null when none can be
  /// read.
  static Future<(File, String)?> latestSaved(SavedFilesStore store) async {
    final entries = await store.list(kind: SavedFileKind.dump);
    for (final e in entries) {
      try {
        final dump =
            ParameterCsvCodec.decode(await e.file.readAsString());
        return (e.file, configSignature(dump.blocks));
      } on Object {
        continue; // unreadable file: try the next newest
      }
    }
    return null;
  }

  /// Saves [dump] unless its values equal the newest saved dump; returns
  /// the new file, or the existing identical file when skipped.
  static Future<({File file, bool duplicate})> saveUnlessDuplicate(
      SavedFilesStore store, ParameterDump dump,
      {required String appVersion, DateTime? now}) async {
    final latest = await latestSaved(store);
    if (latest != null && latest.$2 == configSignature(dump.blocks)) {
      return (file: latest.$1, duplicate: true);
    }
    final file = await ParameterDumpIo.saveDump(store, dump,
        appVersion: appVersion, now: now);
    return (file: file, duplicate: false);
  }

  String? _latestSignature;
  bool _loaded = false;

  /// Called for every new complete live snapshot. Returns the written file,
  /// or null when the values match the newest saved dump.
  Future<File?> onSnapshot(PersistedParameterSnapshot snapshot) {
    final next = _queue.then((_) => _save(snapshot));
    _queue = next.catchError((Object _) => null);
    return next;
  }

  Future<File?> _save(PersistedParameterSnapshot snapshot) async {
    try {
      if (!_loaded) {
        _latestSignature = (await latestSaved(_store))?.$2;
        _loaded = true;
      }
      final signature = configSignature(snapshot.rawBlocks);
      if (signature == _latestSignature) return null;
      final dump = ParameterCaptureService.toDump(snapshot);
      final file = await ParameterDumpIo.saveDump(_store, dump,
          appVersion: await _appVersion(), now: _clock());
      _latestSignature = signature;
      return file;
    } catch (e) {
      debugPrint('Saving live parameter dump failed: $e');
      return null;
    }
  }
}

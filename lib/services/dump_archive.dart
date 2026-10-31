import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:arcdash/models/fardriver_param_catalog.dart';
import 'package:arcdash/services/parameter_capture.dart';
import 'package:arcdash/services/parameter_dump_io.dart';
import 'package:arcdash/services/parameter_snapshot_repository.dart';
import 'package:arcdash/services/saved_files.dart';

/// Writes every live parameter snapshot permanently to `farsure/dumps/`.
///
/// The controller keeps a few counters inside the config blocks (odometer,
/// total time, rolling AVGPower/AVGSpeed) that change while riding, so the
/// raw snapshot changes every ~100 m. A new file is written when the
/// *configuration* changes (counters masked), and otherwise at most once per
/// [minInterval] — so a new connection or changed parameters are always
/// kept without filling the phone with near-identical files.
class LiveDumpArchiver {
  LiveDumpArchiver({
    required SavedFilesStore store,
    required Future<String> Function() appVersion,
    DateTime Function()? clock,
    this.minInterval = const Duration(minutes: 30),
  })  : _store = store,
        _appVersion = appVersion,
        _clock = clock ?? DateTime.now;

  final SavedFilesStore _store;
  final Future<String> Function() _appVersion;
  final DateTime Function() _clock;
  final Duration minInterval;

  final Map<String, String> _lastSignature = {};
  final Map<String, DateTime> _lastSavedAt = {};
  Future<File?> _queue = Future.value();

  /// Fields that count up while riding (not configuration).
  static const _counters = [
    ('DistanceLSB', 0x69),
    ('TotalTime', 0x7C),
    ('DistanceMSB', 0x7C),
    ('AVGPower', 0xD0),
    ('AVGSpeed', 0xD0),
  ];

  /// Snapshot signature with the riding counters masked out.
  static String configSignature(Map<int, List<int>> blocks) {
    final masked = {
      for (final e in blocks.entries) e.key: [...e.value]
    };
    for (final (name, block) in _counters) {
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

  /// Called for every new complete live snapshot. Returns the written file,
  /// or null when skipped (unchanged configuration, recently saved).
  Future<File?> onSnapshot(PersistedParameterSnapshot snapshot) {
    final next = _queue.then((_) => _save(snapshot));
    _queue = next.catchError((Object _) => null);
    return next;
  }

  Future<File?> _save(PersistedParameterSnapshot snapshot) async {
    final dump = ParameterCaptureService.toDump(snapshot);
    final id = dump.controllerId;
    final signature = configSignature(snapshot.rawBlocks);
    final now = _clock();
    final last = _lastSavedAt[id];
    if (_lastSignature[id] == signature &&
        last != null &&
        now.difference(last) < minInterval) {
      return null;
    }
    try {
      final file = await ParameterDumpIo.saveDump(_store, dump,
          appVersion: await _appVersion(), now: now);
      _lastSignature[id] = signature;
      _lastSavedAt[id] = now;
      return file;
    } catch (e) {
      debugPrint('Saving live parameter dump failed: $e');
      return null;
    }
  }
}

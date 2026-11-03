import 'dart:async';
import 'dart:io';

import 'package:arcdash/models/fardriver_param_catalog.dart';
import 'package:arcdash/services/parameter_csv.dart';
import 'package:arcdash/services/parameter_dump.dart';
import 'package:arcdash/services/saved_files.dart';
import 'package:arcdash/services/write/fardriver_write_protocol.dart';
import 'package:arcdash/services/write/write_allowlist.dart';
import 'package:arcdash/services/write/write_log.dart';

/// What the write service needs from the live connection. The app wires
/// it to the BLE dongle + controller notifier; tests use a fake.
abstract class ControllerWriteLink {
  bool get connected;

  /// Time since the current connection was established.
  Duration get connectedFor;

  /// Time since the last valid frame from the controller.
  Duration get sinceLastFrame;

  int get rpm;
  double get speedKph;

  /// Controller name (BLE MAC addresses change, so never the MAC).
  String get controllerName;

  /// Newest bytes of every configuration block seen on this connection.
  Map<int, List<int>> get latestBlocks;

  /// Address of each configuration block as it arrives.
  Stream<int> get blockArrivals;

  Future<void> send(List<int> frame);
}

/// Why a write was refused (nothing was sent).
class WriteRefused implements Exception {
  final String message;
  const WriteRefused(this.message);
  @override
  String toString() => message;
}

class PlannedChange {
  final WritableField field;
  final int oldRaw;
  final int newRaw;
  const PlannedChange(this.field, this.oldRaw, this.newRaw);

  String get oldText => field.format(oldRaw);
  String get newText => field.format(newRaw);
}

enum ChangeSetKind { write, restore, undo }

/// Everything one confirmation covers.
class ChangeSet {
  final String title;
  final List<PlannedChange> changes;
  final ChangeSetKind kind;

  /// Extra lines for the review screen (e.g. the speed impact).
  final List<String> notes;

  const ChangeSet({
    required this.title,
    required this.changes,
    this.kind = ChangeSetKind.write,
    this.notes = const [],
  });
}

enum VerifyResult {
  ok,
  mismatch,

  /// The block did not come back in time.
  noReadback,

  /// Not sent (the write stopped before this field).
  notSent;

  String get label => switch (this) {
        ok => 'verified',
        mismatch => 'MISMATCH',
        noReadback => 'not read back',
        notSent => 'not sent',
      };
}

class FieldResult {
  final PlannedChange change;
  final VerifyResult verify;
  final int? readBackRaw;
  const FieldResult(this.change, this.verify, this.readBackRaw);
}

class WriteResult {
  final String writeId;
  final ChangeSet set;
  final List<FieldResult> fields;
  final File backup;
  final File log;

  /// Set when the write stopped early (e.g. the wheel started turning).
  final String? error;

  const WriteResult({
    required this.writeId,
    required this.set,
    required this.fields,
    required this.backup,
    required this.log,
    this.error,
  });

  bool get success =>
      error == null && fields.every((f) => f.verify == VerifyResult.ok);

  /// Fields worth restoring (anything that was sent but not verified, or
  /// everything when the write failed part way).
  bool get needsRestore => !success;
}

/// The only path that changes controller settings. Every write:
/// 1. refuses unless connected, stable and standing still (rpm 0, speed 0);
/// 2. saves a full pre-write backup dump permanently (`farsure/backups/`);
/// 3. sends only allowlisted words (read-modify-write, other bits kept);
/// 4. saves to flash, then waits for the blocks to stream back and checks
///    every value;
/// 5. logs time, controller, field, old, new and the result permanently
///    (`farsure/write_log/`).
class ControllerWriteService {
  ControllerWriteService({
    required this.link,
    required this.store,
    required this.experimentalEnabled,
    this.appVersion = '',
    DateTime Function()? clock,
    this.frameGap = const Duration(milliseconds: 60),
    this.readbackTimeout = const Duration(seconds: 12),
  }) : _clock = clock ?? DateTime.now;

  final ControllerWriteLink link;
  final SavedFilesStore store;
  final bool Function() experimentalEnabled;
  final String appVersion;
  final DateTime Function() _clock;
  final Duration frameGap;
  final Duration readbackTimeout;

  /// Connection must have been up this long with frames still arriving.
  static const minConnected = Duration(seconds: 3);
  static const maxFrameGap = Duration(milliseconds: 1500);

  bool _busy = false;

  /// Null when writing is allowed right now, else a plain reason.
  String? refusalReason() {
    if (!link.connected) return 'Not connected to the controller.';
    if (link.connectedFor < minConnected ||
        link.sinceLastFrame > maxFrameGap) {
      return 'Connection is not stable yet. Stay close to the bike and '
          'try again in a few seconds.';
    }
    if (link.rpm != 0 || link.speedKph > 0) {
      return 'The wheel is turning. Stop the bike (0 rpm, 0 speed) first.';
    }
    return null;
  }

  /// Builds a change set from new raw values; drops unchanged values.
  /// Throws [WriteRefused] for anything not allowed.
  ChangeSet plan(Map<String, int> newRaw,
      {required String title,
      ChangeSetKind kind = ChangeSetKind.write,
      List<String> notes = const []}) {
    final blocks = link.latestBlocks;
    final changes = <PlannedChange>[];
    for (final e in newRaw.entries) {
      final field = WriteAllowlist.byKey(e.key);
      if (field == null || WriteAllowlist.isForbiddenName(e.key)) {
        throw WriteRefused('${e.key} is not a setting FarSure writes.');
      }
      if (field.experimental && !experimentalEnabled()) {
        throw WriteRefused('${field.label} is experimental. Turn on '
            '"Experimental writes" in Settings to change it.');
      }
      if (e.value < field.rawMin || e.value > field.rawMax) {
        throw WriteRefused('${field.label}: ${field.format(e.value)} is '
            'outside the allowed range ${field.format(field.rawMin)} – '
            '${field.format(field.rawMax)}.');
      }
      final block = blocks[field.def.block];
      if (block == null) {
        throw WriteRefused('${field.label} has not been read from the '
            'controller yet. Wait until the settings are read.');
      }
      final old = field.readRaw(block);
      if (old != e.value) changes.add(PlannedChange(field, old, e.value));
    }
    return ChangeSet(title: title, changes: changes, kind: kind, notes: notes);
  }

  /// Runs [set] (after the rider confirmed the review screen).
  Future<WriteResult> apply(ChangeSet set) async {
    if (_busy) throw const WriteRefused('Another write is still running.');
    if (set.changes.isEmpty) {
      throw const WriteRefused('Nothing to change: the controller already '
          'has these values.');
    }
    final reason = refusalReason();
    if (reason != null) throw WriteRefused(reason);
    for (final c in set.changes) {
      if (c.field.experimental && !experimentalEnabled()) {
        throw WriteRefused('${c.field.label} is experimental and the '
            'Experimental toggle is off.');
      }
    }
    _busy = true;
    try {
      return await _run(set);
    } finally {
      _busy = false;
    }
  }

  Future<WriteResult> _run(ChangeSet set) async {
    final started = _clock();
    final writeId = SavedFilesStore.stamp(started);
    final name = link.controllerName;
    // 1. Full backup first; no backup, no write.
    final backup = await saveBackup(started);

    // 2. Group by word, read-modify-write from the freshest block.
    final byWord = <int, List<PlannedChange>>{};
    for (final c in set.changes) {
      (byWord[c.field.wordAddress] ??= []).add(c);
    }
    final sentWords = <int>{};
    String? error;
    for (final entry in byWord.entries) {
      final reason = refusalReason();
      if (reason != null) {
        error = 'Stopped: $reason';
        break;
      }
      final first = entry.value.first.field;
      final block = link.latestBlocks[first.def.block]!;
      final o = first.wordByteOffset;
      var word = block[o] | (block[o + 1] << 8);
      for (final c in entry.value) {
        word = c.field.applyTo(word, c.newRaw);
      }
      if (!WriteAllowlist.isWritableWord(entry.key)) {
        error = 'Internal check refused word ${entry.key}';
        break;
      }
      await link.send(FardriverWriteProtocol.writeWord(entry.key, word));
      sentWords.add(entry.key);
      await Future<void>.delayed(frameGap);
    }

    // 3. Save to flash (even after a partial write, so the controller's
    //    flash matches what it runs and the restore offer is honest).
    final needBlocks = {
      for (final c in set.changes)
        if (sentWords.contains(c.field.wordAddress)) c.field.def.block
    };
    final arrived = <int>{};
    final sub = link.blockArrivals.listen((b) {
      if (needBlocks.contains(b)) arrived.add(b);
    });
    try {
      if (sentWords.isNotEmpty) {
        await link.send(FardriverWriteProtocol.saveStampFrame(_clock()));
        await Future<void>.delayed(FardriverWriteProtocol.saveGap);
        await link.send(FardriverWriteProtocol.saveFrame());
        arrived.clear();
        // 4. Wait for every touched block to stream back.
        final deadline = _clock().add(readbackTimeout);
        while (!arrived.containsAll(needBlocks) &&
            _clock().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
    } finally {
      await sub.cancel();
    }

    final results = <FieldResult>[];
    for (final c in set.changes) {
      if (!sentWords.contains(c.field.wordAddress)) {
        results.add(FieldResult(c, VerifyResult.notSent, null));
        continue;
      }
      if (!arrived.contains(c.field.def.block)) {
        results.add(FieldResult(c, VerifyResult.noReadback, null));
        continue;
      }
      final back = c.field.readRaw(link.latestBlocks[c.field.def.block]!);
      results.add(FieldResult(
          c, back == c.newRaw ? VerifyResult.ok : VerifyResult.mismatch, back));
    }
    final log = await WriteLogStore(store).write(WriteLogSession(
      writeId: writeId,
      time: started,
      controllerName: name,
      kind: set.kind,
      title: set.title,
      backupFile: backup.uri.pathSegments.last,
      error: error,
      rows: [
        for (final r in results)
          WriteLogRow(
            field: r.change.field.key,
            label: r.change.field.label,
            oldRaw: r.change.oldRaw,
            newRaw: r.change.newRaw,
            oldText: r.change.oldText,
            newText: r.change.newText,
            verify: r.verify,
            readBackRaw: r.readBackRaw,
          )
      ],
    ));
    return WriteResult(
        writeId: writeId,
        set: set,
        fields: results,
        backup: backup,
        log: log,
        error: error);
  }

  /// Saves the full pre-write backup (permanent). Throws [WriteRefused]
  /// when not every configuration block has been read yet.
  Future<File> saveBackup(DateTime at) async {
    final blocks = link.latestBlocks;
    final required = [
      for (final b in FardriverParamCatalog.mandatoryBlocks)
        if (!FardriverParamCatalog.optionalBlocks.contains(b)) b
    ];
    final missing = required.where((b) => !blocks.containsKey(b)).toList();
    if (missing.isNotEmpty) {
      throw const WriteRefused('Not all settings have been read from the '
          'controller yet, so no backup can be made. Wait a few seconds.');
    }
    final dump = ParameterDump(
      source: ParameterDumpSource.live,
      sourceLabel: 'pre-write-backup',
      blocks: {
        for (final e in blocks.entries)
          if (e.value.length == FardriverParamCatalog.blockLength)
            e.key: List<int>.of(e.value)
      },
      requiredBlocks: required,
      optionalBlocks: FardriverParamCatalog.optionalBlocks,
      controllerId: link.controllerName,
      capturedAt: at,
      appVersion: appVersion,
    );
    final csv = ParameterCsvCodec.encode(dump,
        allowIncomplete: true, appVersion: appVersion);
    return store.write(
        SavedFileKind.backup,
        'prewrite_backup_${SavedFilesStore.safeName(link.controllerName)}_'
        '${SavedFilesStore.stamp(at)}.csv',
        csv);
  }

  /// Puts back the old values of a write that failed or did not verify.
  ChangeSet planRestore(WriteResult result) => plan({
        for (final f in result.fields)
          if (f.verify != VerifyResult.notSent)
            f.change.field.key: f.change.oldRaw
      },
          title: 'Restore old values',
          kind: ChangeSetKind.restore);

  /// "Undo to backup": restores only the fields [session] touched, with
  /// the values from its pre-write backup.
  Future<ChangeSet> planUndo(WriteLogSession session) async {
    final dir = await store.directoryFor(SavedFileKind.backup);
    final file = File('${dir.path}/${session.backupFile}');
    if (!await file.exists()) {
      throw WriteRefused('The backup ${session.backupFile} is missing.');
    }
    final dump = ParameterCsvCodec.decode(await file.readAsString(),
        fileName: session.backupFile);
    final values = <String, int>{};
    for (final row in session.rows) {
      final field = WriteAllowlist.byKey(row.field);
      if (field == null) continue;
      final block = dump.blocks[field.def.block];
      if (block == null) continue;
      values[field.key] = field.readRaw(block);
    }
    return plan(values,
        title: 'Undo to backup from ${session.timeLabel}',
        kind: ChangeSetKind.undo);
  }
}

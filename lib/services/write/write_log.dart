import 'dart:io';

import 'package:arcdash/services/parameter_csv.dart';
import 'package:arcdash/services/saved_files.dart';
import 'package:arcdash/services/write/write_service.dart';

class WriteLogRow {
  final String field;
  final String label;
  final int oldRaw;
  final int newRaw;
  final String oldText;
  final String newText;
  final VerifyResult verify;
  final int? readBackRaw;

  const WriteLogRow({
    required this.field,
    required this.label,
    required this.oldRaw,
    required this.newRaw,
    required this.oldText,
    required this.newText,
    required this.verify,
    this.readBackRaw,
  });

  FieldOutcome get outcome =>
      fieldOutcome(verify: verify, oldRaw: oldRaw, readBackRaw: readBackRaw);
}

/// One write (one confirmation) as saved in `farsure/write_log/`.
class WriteLogSession {
  final String writeId;
  final DateTime time;
  final String controllerName;
  final ChangeSetKind kind;
  final String title;
  final String backupFile;
  final String? error;
  final List<WriteLogRow> rows;

  const WriteLogSession({
    required this.writeId,
    required this.time,
    required this.controllerName,
    required this.kind,
    required this.title,
    required this.backupFile,
    required this.rows,
    this.error,
  });

  /// Derived from the rows (also for v1 logs, which only said
  /// ok/failed: a v1 "failed" with a verified row decodes as partial).
  WriteOutcome get outcome => WriteSummary.outcomeOf(
      rows.map((r) => r.outcome),
      stoppedEarly: error != null);

  bool get success => outcome == WriteOutcome.ok;

  String get message =>
      WriteSummary.message([for (final r in rows) (r.label, r.outcome)]);

  String get timeLabel {
    final l = time.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} '
        '${two(l.hour)}:${two(l.minute)}';
  }

  /// v2 (v1.4): result is ok/partial/failed, a plain summary line and a
  /// per-field outcome column. v1 files still decode.
  static const format = 'farsure-write-log-v2';
  static const header = [
    'time',
    'controller',
    'field',
    'old',
    'new',
    'old_raw',
    'new_raw',
    'verify',
    'readback_raw',
    'key',
    'outcome',
  ];

  String encode() {
    final out = <List<String>>[
      ['# FarSure write log', format],
      ['# write_id', writeId],
      ['# time', time.toUtc().toIso8601String()],
      ['# controller', controllerName],
      ['# kind', kind.name],
      ['# title', title],
      ['# backup', backupFile],
      ['# result', outcome.label],
      ['# summary', message],
      if (error != null) ['# error', error!],
      header,
      for (final r in rows)
        [
          time.toUtc().toIso8601String(),
          controllerName,
          r.label,
          r.oldText,
          r.newText,
          '${r.oldRaw}',
          '${r.newRaw}',
          r.verify.label,
          r.readBackRaw?.toString() ?? '',
          r.field, // catalog key keeps undo exact even if labels change
          r.outcome.text,
        ],
    ];
    return FlatCsv.encode(out);
  }

  static WriteLogSession decode(String text) {
    final rows = FlatCsv.decode(text);
    final meta = <String, String>{};
    final data = <WriteLogRow>[];
    var inData = false;
    for (final r in rows) {
      if (r.isEmpty) continue;
      if (r.first.startsWith('#')) {
        if (r.length > 1) meta[r.first.substring(1).trim()] = r[1];
        continue;
      }
      if (!inData) {
        inData = true; // header row
        continue;
      }
      if (r.length < 10) continue;
      data.add(WriteLogRow(
        field: r[9],
        label: r[2],
        oldText: r[3],
        newText: r[4],
        oldRaw: int.parse(r[5]),
        newRaw: int.parse(r[6]),
        verify: VerifyResult.values.firstWhere((v) => v.label == r[7],
            orElse: () => VerifyResult.noReadback),
        readBackRaw: int.tryParse(r[8]),
      ));
    }
    return WriteLogSession(
      writeId: meta['write_id'] ?? '',
      time: DateTime.tryParse(meta['time'] ?? '') ?? DateTime(2000),
      controllerName: meta['controller'] ?? '',
      kind: ChangeSetKind.values.firstWhere((k) => k.name == meta['kind'],
          orElse: () => ChangeSetKind.write),
      title: meta['title'] ?? '',
      backupFile: meta['backup'] ?? '',
      error: meta['error'],
      rows: data,
    );
  }
}

/// Permanent write log: one CSV per write in `farsure/write_log/`.
class WriteLogStore {
  WriteLogStore(this.store);
  final SavedFilesStore store;

  Future<File> write(WriteLogSession s) => store.write(SavedFileKind.writeLog,
      'write_${s.writeId}_${s.kind.name}.csv', s.encode());

  /// Newest first; unreadable files are skipped.
  Future<List<(File, WriteLogSession)>> list() async {
    final out = <(File, WriteLogSession)>[];
    for (final e in await store.list(kind: SavedFileKind.writeLog)) {
      try {
        out.add((e.file, WriteLogSession.decode(await e.file.readAsString())));
      } on Object {
        continue;
      }
    }
    return out;
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:arcdash/services/parameter_csv.dart';

/// What a permanently saved file holds. [folder] is the sub-folder under
/// `<app documents>/farsure/`.
enum SavedFileKind {
  calibration('calibrations'),
  dump('dumps'),
  diagnosticLog('logs'),
  rideCsv('rides');

  const SavedFileKind(this.folder);
  final String folder;
}

/// One file in the permanent store, with the key facts read from its header
/// so the list works without a controller (and without parsing everything).
class SavedFileEntry {
  final File file;
  final SavedFileKind kind;

  /// When the data was recorded (from the file header), falling back to the
  /// file's modification time.
  final DateTime time;
  final int sizeBytes;

  /// Header facts, e.g. `confidence`, `suggested_GearRatio`,
  /// `controller_id`, `source`, `status`.
  final Map<String, String> info;

  const SavedFileEntry({
    required this.file,
    required this.kind,
    required this.time,
    required this.sizeBytes,
    this.info = const {},
  });

  String get name => file.uri.pathSegments.last;
  String get path => file.path;
}

/// Permanent, offline file store: `<app documents>/farsure/<kind>/`.
///
/// Everything FarSure captures (calibration rides, parameter dumps,
/// diagnostic logs, ride CSVs) is written here so it can be reopened,
/// shared and deleted later without a controller connection. Writes are
/// atomic (temp file + rename) so a crash never leaves half a file.
class SavedFilesStore {
  SavedFilesStore({required Future<Directory> Function() documentsDir})
      : _documentsDir = documentsDir;

  final Future<Directory> Function() _documentsDir;

  static const rootFolder = 'farsure';

  /// Bytes read from the start of each file to build the list entry.
  static const _headBytes = 16 * 1024;

  Future<Directory> root() async {
    final docs = await _documentsDir();
    return Directory('${docs.path}/$rootFolder');
  }

  Future<Directory> directoryFor(SavedFileKind kind) async {
    final dir = Directory('${(await root()).path}/${kind.folder}');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Writes (or overwrites) [fileName] in the folder for [kind].
  Future<File> write(
      SavedFileKind kind, String fileName, String contents) async {
    final dir = await directoryFor(kind);
    return writeAtomically(File('${dir.path}/${safeName(fileName)}'), contents);
  }

  /// Replaces [target] via a temp file + rename (never half-written).
  static Future<File> writeAtomically(File target, String contents) async {
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(contents, flush: true);
    return temp.rename(target.path);
  }

  /// All saved files, newest first. Ride CSVs written by older versions to
  /// the documents root (`arcdash_ride_*.csv`) are listed too.
  Future<List<SavedFileEntry>> list({SavedFileKind? kind}) async {
    final entries = <SavedFileEntry>[];
    for (final k in SavedFileKind.values) {
      if (kind != null && k != kind) continue;
      final dir = Directory('${(await root()).path}/${k.folder}');
      final files = <File>[];
      if (await dir.exists()) {
        await for (final e in dir.list(followLinks: false)) {
          if (e is File && !e.path.endsWith('.tmp')) files.add(e);
        }
      }
      if (k == SavedFileKind.rideCsv) files.addAll(await _legacyRideCsvs());
      for (final f in files) {
        final entry = await _entryFor(f, k);
        if (entry != null) entries.add(entry);
      }
    }
    entries.sort((a, b) => b.time.compareTo(a.time));
    return entries;
  }

  Future<List<File>> _legacyRideCsvs() async {
    try {
      final docs = await _documentsDir();
      if (!await docs.exists()) return const [];
      return [
        await for (final e in docs.list(followLinks: false))
          if (e is File && RegExp(r'arcdash_ride_\d+\.csv$').hasMatch(e.path))
            e,
      ];
    } on FileSystemException {
      return const [];
    }
  }

  Future<SavedFileEntry?> _entryFor(File file, SavedFileKind kind) async {
    try {
      final stat = await file.stat();
      final head = await _readHead(file);
      final info = switch (kind) {
        SavedFileKind.calibration => calibrationInfo(head),
        SavedFileKind.dump => dumpInfo(head),
        _ => const <String, String>{},
      };
      final recorded = DateTime.tryParse(info['time'] ?? '');
      return SavedFileEntry(
        file: file,
        kind: kind,
        time: (recorded ?? stat.modified).toLocal(),
        sizeBytes: stat.size,
        info: info,
      );
    } on FileSystemException {
      return null;
    }
  }

  Future<String> _readHead(File file) async {
    final raf = await file.open();
    try {
      final bytes = await raf.read(_headBytes);
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      await raf.close();
    }
  }

  Future<void> delete(SavedFileEntry entry) async {
    if (await entry.file.exists()) await entry.file.delete();
  }

  /// Deletes every saved file (all kinds, including legacy ride CSVs).
  /// Returns how many files were removed.
  Future<int> deleteAll() async {
    final all = await list();
    for (final e in all) {
      await delete(e);
    }
    return all.length;
  }

  /// Key facts of a saved calibration ride (see `CalibrationCsv`): rows
  /// `section,key,value` near the top of the file.
  static Map<String, String> calibrationInfo(String head) {
    final info = <String, String>{};
    for (final row in FlatCsv.decode(_completeLines(head))) {
      if (row.length < 3) continue;
      final value = row[2];
      switch ('${row[0]}.${row[1]}') {
        case 'summary.started_at':
          info['time'] = value;
        case 'summary.controller_id':
          info['controller_id'] = value;
        case 'summary.status':
          info['status'] = value;
        case 'summary.duration_s':
          info['duration_s'] = value;
        case 'summary.seconds_recorded':
          info['samples'] = value;
        case 'summary.clean_seconds':
          info['clean_seconds'] = value;
        case 'fit.confidence':
          info['confidence'] = value;
        case 'ble.suggested_GearRatio':
          info['suggested_GearRatio'] = value;
        case 'settings.GearRatio':
          info['GearRatio'] = value;
      }
    }
    return info;
  }

  /// Key facts of a saved parameter dump (`# key,value` header rows).
  static Map<String, String> dumpInfo(String head) {
    final info = <String, String>{};
    for (final row in FlatCsv.decode(_completeLines(head))) {
      if (row.isEmpty || !row.first.startsWith('#')) continue;
      final key = row.first.substring(1).trim();
      final value = row.length > 1 ? row[1] : '';
      switch (key) {
        case 'capture_time':
          info['time'] = value;
        case 'controller_id':
          info['controller_id'] = value;
        case 'source':
          info['source'] = value;
      }
    }
    return info;
  }

  /// Drops a trailing partial line from a truncated head read.
  static String _completeLines(String head) {
    if (head.length < _headBytes ~/ 2) return head;
    final cut = head.lastIndexOf('\n');
    return cut < 0 ? head : head.substring(0, cut + 1);
  }

  /// File-system safe name (keeps letters, digits, `._-`).
  static String safeName(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  /// Local-time stamp for file names, e.g. `20261031_154502`.
  static String stamp(DateTime t) {
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}${two(l.month)}${two(l.day)}_'
        '${two(l.hour)}${two(l.minute)}${two(l.second)}';
  }
}

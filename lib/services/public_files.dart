import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import 'package:arcdash/models/tire_rack.dart';
import 'package:arcdash/services/parameter_dump_io.dart';
import 'package:arcdash/services/saved_files.dart';
import 'package:arcdash/services/tire_rack_store.dart';

/// Mirrors the permanent store to public `Documents/FarSure/...` through
/// MediaStore (Android 10+, no storage permission), so files survive an
/// uninstall and can be opened by any file manager / PC over USB.
///
/// The app's private copy stays the source of truth; the mirror is
/// best-effort and never blocks or fails a save.
class PublicFiles {
  PublicFiles._();

  static const displayPath = 'Documents/FarSure';
  static const _channel = MethodChannel('com.arcdash.arcdash/public_files');
  static const _migrationMarker = '.public_mirror_v1';

  /// Replaceable in tests.
  static Future<bool> Function(
          String folder, String name, String mime, List<int> bytes) saver =
      _platformSave;

  static Future<bool> _platformSave(
      String folder, String name, String mime, List<int> bytes) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('save', {
            'folder': folder,
            'name': name,
            'mime': mime,
            'bytes': Uint8List.fromList(bytes),
          }) ??
          false;
    } on Object {
      return false;
    }
  }

  /// Public sub-folder for each kind.
  static String folderFor(SavedFileKind kind) => switch (kind) {
        SavedFileKind.calibration => 'calibration',
        SavedFileKind.dump => 'dumps',
        SavedFileKind.diagnosticLog => 'logs',
        SavedFileKind.rideCsv || SavedFileKind.rideRecord => 'rides',
        SavedFileKind.dashCheck => 'dash_checks',
        SavedFileKind.writeLog => 'write_log',
        SavedFileKind.backup => 'backups',
        SavedFileKind.tires => 'tires',
      };

  static String pathFor(SavedFileKind kind) =>
      '$displayPath/${folderFor(kind)}';

  static String _mime(String name) => name.endsWith('.json')
      ? 'application/json'
      : name.endsWith('.csv')
          ? 'text/csv'
          : 'text/plain';

  static Future<bool> mirror(SavedFileKind kind, File file) async {
    final name = file.uri.pathSegments.last;
    return saver(folderFor(kind), name, _mime(name), await file.readAsBytes());
  }

  /// Wires [SavedFilesStore.write] to the mirror and runs the one-time
  /// migration of files saved by older versions.
  static Future<void> install(SavedFilesStore store) async {
    SavedFilesStore.onWritten = (kind, file) async {
      await mirror(kind, file);
    };
    try {
      final marker = File('${(await store.root()).path}/$_migrationMarker');
      if (await marker.exists()) return;
      final n = await mirrorAll(store);
      if (n >= 0) {
        await marker.create(recursive: true);
      }
    } on Object {
      // Try again next start.
    }
  }

  /// Copies every saved file. Returns the count, or -1 when public
  /// storage is unavailable (Android 9 or older).
  static Future<int> mirrorAll(SavedFilesStore store,
      {bool force = false}) async {
    var count = 0;
    var anyFailed = false;
    for (final e in await store.list()) {
      if (await mirror(e.kind, e.file)) {
        count++;
      } else {
        anyFailed = true;
      }
    }
    if (count == 0 && anyFailed) return -1;
    return count;
  }

  /// System picker (opens anywhere, including Documents/FarSure). Imports
  /// a parameter dump (FarSure CSV / official export) or a tire rack JSON.
  /// Returns a message for the user, or null when cancelled.
  static Future<String?> importWithPicker(SavedFilesStore store) async {
    final file = await FilePicker.pickFile(type: FileType.any);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return importBytes(store, file.name, bytes);
  }

  static Future<String> importBytes(
      SavedFilesStore store, String name, List<int> bytes) async {
    final text = utf8.decode(bytes, allowMalformed: true);
    if (TireRack.looksLikeRack(text)) {
      try {
        final n = await TireRackStore(store).importText(text);
        return 'Imported $n tire size${n == 1 ? '' : 's'}';
      } on FormatException catch (e) {
        return 'Not imported: ${e.message}';
      }
    }
    try {
      final dump = ParameterDumpIo.parseFile(bytes, name,
          appVersion: await ParameterDumpIo.appVersion());
      final saved = await ParameterDumpIo.keepCopy(store, dump);
      return saved == null ? 'Not imported: could not save' : 'Imported dump $name';
    } on Object {
      return 'Not imported: not a dump or tire rack file';
    }
  }
}

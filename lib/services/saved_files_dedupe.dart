import 'package:flutter/foundation.dart';

import 'package:arcdash/services/dump_archive.dart';
import 'package:arcdash/services/parameter_dump_io.dart';
import 'package:arcdash/services/saved_files.dart';

/// Finds saved files that are duplicates of another saved file (v1.2.3).
///
/// Never deletes anything itself; the Saved files screen lists the result
/// and asks before removing. Parameter dumps are duplicates when their
/// configuration VALUES match ([LiveDumpArchiver.configSignature], which
/// ignores the controller's clock and live counters); every other kind only
/// when the file content is byte-for-byte identical. In each group the
/// OLDEST file is kept (the original capture).
class SavedFilesDedupe {
  const SavedFilesDedupe._();

  /// Returns the entries that can be removed, newest first.
  static Future<List<SavedFileEntry>> findDuplicates(
      List<SavedFileEntry> entries) async {
    final sorted = [...entries]..sort((a, b) {
        final t = a.time.compareTo(b.time);
        return t != 0 ? t : a.name.compareTo(b.name);
      });
    final seen = <String>{};
    final dupes = <SavedFileEntry>[];
    for (final e in sorted) {
      final key = await _keyFor(e);
      if (key == null) continue; // unreadable: never offered for removal
      if (!seen.add('${e.kind.name}|$key')) dupes.add(e);
    }
    return dupes.reversed.toList();
  }

  static Future<String?> _keyFor(SavedFileEntry e) async {
    try {
      final bytes = await e.file.readAsBytes();
      if (e.kind == SavedFileKind.dump) {
        try {
          final dump = ParameterDumpIo.parseFile(bytes, e.name);
          if (dump.blocks.isNotEmpty) {
            return 'sig:${LiveDumpArchiver.configSignature(dump.blocks)}';
          }
        } on Object {
          // fall through to exact content
        }
      }
      return 'bytes:${bytes.length}:${_hash(bytes)}';
    } on Object catch (err) {
      debugPrint('Dedupe could not read ${e.name}: $err');
      return null;
    }
  }

  /// FNV-1a 64 bit over the content (plus length in the key).
  static String _hash(List<int> bytes) {
    var h = 0xcbf29ce484222325;
    for (final b in bytes) {
      h ^= b;
      h = h * 0x100000001b3; // wraps at 64 bit
    }
    return h.toRadixString(16);
  }
}

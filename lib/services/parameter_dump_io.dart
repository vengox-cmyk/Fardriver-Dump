import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:arcdash/services/dump_archive.dart';
import 'package:arcdash/services/heb_file_parser.dart';
import 'package:arcdash/services/parameter_capture.dart';
import 'package:arcdash/services/parameter_csv.dart';
import 'package:arcdash/services/parameter_dump.dart';
import 'package:arcdash/services/parameter_snapshot_repository.dart';
import 'package:arcdash/services/saved_files.dart';

/// Loading and sharing of parameter dumps. Everything here is read-only with
/// respect to the controller: files are only read from disk and written to the
/// share sheet / clipboard. A `.heb` is never sent to the controller.
class ParameterDumpIo {
  ParameterDumpIo._();

  /// Parses picked file bytes: `.heb` (696 bytes) or an ArcDash parameter CSV.
  static ParameterDump parseFile(List<int> bytes, String fileName,
      {String appVersion = ''}) {
    final lower = fileName.toLowerCase();
    final looksLikeCsv = bytes.isNotEmpty &&
        (bytes.first == 0x23 || bytes.first == 0x22 || bytes.first == 0xEF);
    if (lower.endsWith('.heb') ||
        (!lower.endsWith('.csv') &&
            bytes.length == HebFile.expectedLength &&
            !looksLikeCsv)) {
      return ParameterDump.fromHeb(HebFile.parse(bytes),
          fileName: fileName, appVersion: appVersion);
    }
    final text = String.fromCharCodes(bytes);
    return ParameterCsvCodec.decode(_utf8(bytes, text), fileName: fileName);
  }

  static String _utf8(List<int> bytes, String fallback) {
    try {
      return const Utf8Decoder().convert(bytes);
    } on FormatException {
      return fallback;
    }
  }

  /// Opens the system file picker. Returns null if the user cancelled.
  static Future<ParameterDump?> pickAndParse() async {
    final file = await FilePicker.pickFile(type: FileType.any);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return parseFile(bytes, file.name, appVersion: await appVersion());
  }

  static Future<ParameterDump?> loadLive(
      ParameterSnapshotRepository? repository) async {
    if (repository == null) return null;
    final snapshot = await repository.loadComplete();
    return snapshot == null ? null : ParameterCaptureService.toDump(snapshot);
  }

  static Future<String> appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return 'FarSure ${info.version}+${info.buildNumber}';
    } on Object {
      return 'FarSure';
    }
  }

  static String safeFileName(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');

  /// Permanent file name of a dump in `farsure/dumps/`.
  static String dumpFileName(ParameterDump dump, {DateTime? now}) {
    final id = dump.controllerId.isEmpty ? 'unknown' : dump.controllerId;
    final at = dump.capturedAt ?? now ?? DateTime.now();
    return SavedFilesStore.safeName(
        'dump_${id}_${dump.source.name}_${SavedFilesStore.stamp(at)}.csv');
  }

  /// Writes [dump] permanently (same CSV as the export) to
  /// `farsure/dumps/`. Incomplete dumps are saved too (marked
  /// `# complete,no`), so nothing captured is lost.
  static Future<File> saveDump(SavedFilesStore store, ParameterDump dump,
      {required String appVersion, DateTime? now}) {
    final csv = ParameterCsvCodec.encode(dump,
        allowIncomplete: true, appVersion: appVersion);
    return store.write(SavedFileKind.dump, dumpFileName(dump, now: now), csv);
  }

  /// Best-effort permanent copy (e.g. of a dump opened from a file); never
  /// throws, returns null when saving was impossible. When the values equal
  /// the newest saved dump that file is returned instead of a duplicate.
  static Future<File?> keepCopy(
      SavedFilesStore store, ParameterDump dump) async {
    try {
      return (await LiveDumpArchiver.saveUnlessDuplicate(store, dump,
              appVersion: await appVersion()))
          .file;
    } catch (e) {
      debugPrint('Keeping a copy of the dump failed: $e');
      return null;
    }
  }

  /// Shares an already saved [file] (falls back to copying its text).
  static Future<void> shareSavedFile(
    BuildContext context,
    File file, {
    required String subject,
    required String copiedMessage,
  }) async {
    final text = await file.readAsString();
    if (!context.mounted) return;
    await shareOrCopy(context,
        text: text,
        fileName: file.uri.pathSegments.last,
        subject: subject,
        copiedMessage: copiedMessage,
        file: file);
  }

  /// Shares [text] as a CSV file through the Android share sheet and falls
  /// back to the clipboard if sharing fails or is dismissed. With [file]
  /// (a permanently saved copy of [text]) that file is shared directly.
  static Future<void> shareOrCopy(
    BuildContext context, {
    required String text,
    required String fileName,
    required String subject,
    required String copiedMessage,
    File? file,
  }) async {
    var shared = false;
    try {
      var shareFile = file;
      if (shareFile == null) {
        final dir = await getTemporaryDirectory();
        shareFile = File('${dir.path}/$fileName');
        await shareFile.writeAsString(text);
      }
      final mime = fileName.endsWith('.txt') ? 'text/plain' : 'text/csv';
      final result = await SharePlus.instance.share(ShareParams(
        files: [XFile(shareFile.path, mimeType: mime, name: fileName)],
        subject: subject,
        text: subject,
      ));
      shared = result.status == ShareResultStatus.success;
    } catch (e) {
      debugPrint('Share failed, falling back to clipboard: $e');
    }
    if (shared) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(copiedMessage),
        duration: const Duration(seconds: 3),
      ));
    }
  }
}

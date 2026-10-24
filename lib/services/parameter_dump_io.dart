import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:arcdash/services/heb_file_parser.dart';
import 'package:arcdash/services/parameter_capture.dart';
import 'package:arcdash/services/parameter_csv.dart';
import 'package:arcdash/services/parameter_dump.dart';
import 'package:arcdash/services/parameter_snapshot_repository.dart';

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
      return 'ArcDash ${info.version}+${info.buildNumber}';
    } on Object {
      return 'ArcDash';
    }
  }

  static String safeFileName(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');

  /// Shares [text] as a CSV file through the Android share sheet and falls
  /// back to the clipboard if sharing fails or is dismissed.
  static Future<void> shareOrCopy(
    BuildContext context, {
    required String text,
    required String fileName,
    required String subject,
    required String copiedMessage,
  }) async {
    var shared = false;
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(text);
      final result = await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv', name: fileName)],
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

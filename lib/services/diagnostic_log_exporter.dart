import 'dart:io';
import 'package:flutter/material.dart';
import 'package:arcdash/l10n/app_strings.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:arcdash/services/diagnostic_log.dart';
import 'package:arcdash/services/saved_files.dart';

class DiagnosticLogExporter {
  static Future<void> shareOrCopy(
    BuildContext context,
    DiagnosticLog diagnostics, {
    SavedFilesStore? store,
    DateTime? now,
  }) async {
    final text = diagnostics.exportAsText(redact: false);
    bool shared = false;

    // Permanent copy in farsure/logs/ (Settings → Data management →
    // Saved files), so the log survives without a connection.
    File? saved;
    if (store != null) {
      try {
        saved = await store.write(
            SavedFileKind.diagnosticLog,
            'diagnostic_${SavedFilesStore.stamp(now ?? DateTime.now())}.txt',
            text);
      } catch (e) {
        debugPrint('Saving diagnostic log failed: $e');
      }
    }

    try {
      var file = saved;
      if (file == null) {
        final tempDir = await getTemporaryDirectory();
        file = File('${tempDir.path}/arcdash_diagnostic_log.txt');
        await file.writeAsString(text);
      }

      final result = await SharePlus.instance.share(ShareParams(
        files: [
          XFile(file.path,
              mimeType: 'text/plain', name: 'arcdash_diagnostic_log.txt')
        ],
        subject: 'FarSure BLE diagnostic log',
        text: 'FarSure BLE diagnostic log',
      ));
      if (result.status == ShareResultStatus.success) {
        shared = true;
      }
    } catch (e) {
      debugPrint('Share failed, falling back to clipboard: $e');
    }

    if (!shared) {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppStrings.of(context).text(AppText.diagnosticLogCopied)),
            duration: const Duration(seconds: 3),
            backgroundColor: const Color(0xFF00E5FF),
          ),
        );
      }
    }
  }
}

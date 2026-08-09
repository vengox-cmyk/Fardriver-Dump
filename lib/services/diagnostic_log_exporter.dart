import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:arcdash/services/diagnostic_log.dart';

class DiagnosticLogExporter {
  static Future<void> shareOrCopy(
    BuildContext context,
    DiagnosticLog diagnostics,
  ) async {
    final text = diagnostics.exportAsText(redact: false);
    bool shared = false;

    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/arcdash_diagnostic_log.txt');
      await file.writeAsString(text);

      final result = await Share.shareXFiles(
        [
          XFile(file.path,
              mimeType: 'text/plain', name: 'arcdash_diagnostic_log.txt')
        ],
        subject: 'ArcDash BLE Diagnose-Log',
        text: 'ArcDash BLE Diagnose-Log',
      );
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
          const SnackBar(
            content: Text('Diagnose-Log in Zwischenablage kopiert!'),
            duration: Duration(seconds: 3),
            backgroundColor: Color(0xFF00E5FF),
          ),
        );
      }
    }
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:arcdash/models/range_prediction_state.dart';

class ProfileExporter {
  static Future<void> exportProfile(
      BuildContext context, RangePredictionState? profile) async {
    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Kein gelerntes Profil vorhanden zum Exportieren.')),
      );
      return;
    }

    final jsonStr =
        const JsonEncoder.withIndent('  ').convert(profile.toJson());
    await Clipboard.setData(ClipboardData(text: jsonStr));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Profil in die Zwischenablage kopiert! Du kannst es jetzt direkt teilen.'),
          backgroundColor: Color(0xFF123328),
        ),
      );
    }
  }

  static Future<RangePredictionState?> importProfileDialog(
      BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Profil importieren'),
        content: TextField(
          controller: controller,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: 'Füge hier das JSON des gelernten Profils ein...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Importieren'),
          ),
        ],
      ),
    );

    if (result == null || result.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(result.trim());
      if (decoded is! Map<String, dynamic>)
        throw const FormatException('Invalid JSON object');
      return RangePredictionState.fromJson(decoded);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler beim Importieren: $e'),
            backgroundColor: const Color(0xFFFF5470),
          ),
        );
      }
      return null;
    }
  }
}

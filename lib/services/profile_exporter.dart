import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:arcdash/l10n/app_strings.dart';
import 'package:arcdash/models/range_prediction_state.dart';

class ProfileExporter {
  static Future<void> exportProfile(
      BuildContext context, RangePredictionState? profile) async {
    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(AppStrings.of(context).text(AppText.noLearnedProfile))),
      );
      return;
    }

    final jsonStr =
        const JsonEncoder.withIndent('  ').convert(profile.toJson());
    await Clipboard.setData(ClipboardData(text: jsonStr));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.of(context).text(AppText.profileCopied)),
          backgroundColor: const Color(0xFF123328),
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
        title: Text(AppStrings.of(context).text(AppText.importProfile)),
        content: TextField(
          controller: controller,
          maxLines: 8,
          decoration: InputDecoration(
            hintText: AppStrings.of(context).text(AppText.profilePasteHint),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(AppStrings.of(context).text(AppText.cancel)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(AppStrings.of(context).text(AppText.importAction)),
          ),
        ],
      ),
    );

    if (result == null || result.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(result.trim());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid JSON object');
      }
      return RangePredictionState.fromJson(decoded);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${AppStrings.of(context).text(AppText.importFailed)}: $e'),
            backgroundColor: const Color(0xFFFF5470),
          ),
        );
      }
      return null;
    }
  }
}

import 'package:shared_preferences/shared_preferences.dart';

/// Use-at-your-own-risk notice (issue #2). Shown in full on first launch and
/// again after each major version change, and always under Settings → About.
class Disclaimer {
  Disclaimer._();

  /// Full text, verbatim from issue #2 (the `**…**` marks the bold lead-in).
  static const lead = 'Use at your own risk.';
  static const body =
      'FarSure reads and explains FarDriver controller settings. It is an '
      'independent hobby project, not made by, affiliated with, or endorsed by '
      'FarDriver. Parameter names, values, decodes, health-check flags and any '
      'suggestions (including from AI) may be incomplete or wrong. They are '
      'information only, not professional advice. Changing controller '
      'settings can damage your controller, motor or battery, cause fire, loss '
      'of control, injury or death, void warranties, or make your vehicle '
      'illegal on public roads. Always verify settings against your '
      "hardware's specifications and the official FarDriver software, keep a "
      'backup dump before making any change, and only make changes you '
      "understand. You are solely responsible for your vehicle's configuration "
      'and how you ride it. The software is provided "as is", without warranty '
      'of any kind, and the authors are not liable for any damage, injury or '
      'loss arising from its use.';
  static const fullText = '$lead $body';

  /// Short line for the dump and compare screens.
  static const shortLine =
      'Informational only, verify before use. Not affiliated with FarDriver.';

  static const credit = 'Based on ArcDash / Biketunes by caydenchapple';

  /// SharedPreferences key holding the major version whose notice was accepted.
  static const prefKey = 'disclaimer_accepted_major';

  /// Major version of `1.1.205` → 1. Unparsable or missing → [fallbackMajor].
  static const fallbackMajor = 1;
  static int majorOf(String? version) {
    final head = (version ?? '').trim().split('.').first;
    return int.tryParse(head) ?? fallbackMajor;
  }

  static bool isAccepted(int? acceptedMajor, String? version) =>
      acceptedMajor != null && acceptedMajor >= majorOf(version);

  /// True when the notice must be shown. If preferences cannot be read the
  /// notice is shown (safe default).
  static Future<bool> needsAcceptance(String? version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return !isAccepted(prefs.getInt(prefKey), version);
    } on Object {
      return true;
    }
  }

  static Future<void> accept(String? version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(prefKey, majorOf(version));
    } on Object {
      // Not persisted; it will be shown again next launch.
    }
  }
}

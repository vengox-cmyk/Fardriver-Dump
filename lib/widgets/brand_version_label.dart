import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Small "FarSure by Vengox · v1.1.N" line. The version is read at runtime from the
/// installed package (CI sets it via `flutter build --build-name=1.1.<commits>`),
/// so it always matches the APK release version.
class BrandVersionLabel extends StatefulWidget {
  const BrandVersionLabel({super.key, this.style});

  final TextStyle? style;

  static const brand = 'FarSure by Vengox';

  static Future<String?>? _cached;

  /// Runtime app version (e.g. `1.1.188`), or null if unavailable.
  static Future<String?> version() => _cached ??= _load();

  static Future<String?> _load() async {
    try {
      final version = (await PackageInfo.fromPlatform()).version.trim();
      return version.isEmpty ? null : version;
    } on Object {
      return null;
    }
  }

  @visibleForTesting
  static void resetCache() => _cached = null;

  static String format(String? version) =>
      version == null ? brand : '$brand · v$version';

  @override
  State<BrandVersionLabel> createState() => _BrandVersionLabelState();
}

class _BrandVersionLabelState extends State<BrandVersionLabel> {
  late final Future<String?> _version = BrandVersionLabel.version();

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
        future: _version,
        builder: (context, snapshot) => Text(
          BrandVersionLabel.format(snapshot.data),
          key: const ValueKey('brand-version-label'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: widget.style,
        ),
      );
}

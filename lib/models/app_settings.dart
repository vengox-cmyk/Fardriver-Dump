import 'package:arcdash/utils/speed_units.dart';

class AppSettings {
  final String languageCode;
  final bool autoReconnect;
  final bool hapticFeedbackEnabled;

  /// True once the user explicitly picked a language in Settings. Older
  /// installs stored the former default 'de' without a choice; those (and
  /// any settings without this flag) fall back to English.
  final bool languageChosen;

  /// Display unit for speed/distance (data and exports stay metric).
  final SpeedUnit speedUnit;

  /// Allows writing settings whose protocol is not yet confirmed on a real
  /// controller (see docs/write_protocol.md). Off by default.
  ///
  /// v1.4: stored under [experimentalKey]. The v1.3 key
  /// ('experimentalWrites') is ignored on purpose: once switched on in
  /// v1.3 (the Battery screen pointed riders to it) it stayed on forever,
  /// and nothing ever reset it. Every install starts off again.
  final bool experimentalWrites;

  static const experimentalKey = 'experimentalWritesV14';
  static const defaultLanguageCode = 'en';
  static const supportedLanguageCodes = ['en', 'de'];

  const AppSettings({
    this.languageCode = defaultLanguageCode,
    this.autoReconnect = true,
    this.hapticFeedbackEnabled = true,
    this.languageChosen = false,
    this.speedUnit = SpeedUnit.kmh,
    this.experimentalWrites = false,
  });

  AppSettings copyWith({
    String? languageCode,
    bool? autoReconnect,
    bool? hapticFeedbackEnabled,
    bool? languageChosen,
    SpeedUnit? speedUnit,
    bool? experimentalWrites,
  }) =>
      AppSettings(
        languageCode: languageCode ?? this.languageCode,
        autoReconnect: autoReconnect ?? this.autoReconnect,
        hapticFeedbackEnabled:
            hapticFeedbackEnabled ?? this.hapticFeedbackEnabled,
        languageChosen: languageChosen ?? this.languageChosen,
        speedUnit: speedUnit ?? this.speedUnit,
        experimentalWrites: experimentalWrites ?? this.experimentalWrites,
      );

  Map<String, dynamic> toJson() => {
        'languageCode': languageCode,
        'autoReconnect': autoReconnect,
        'hapticFeedbackEnabled': hapticFeedbackEnabled,
        'languageChosen': languageChosen,
        'speedUnit': speedUnit.key,
        experimentalKey: experimentalWrites,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final chosen = json['languageChosen'] == true;
    final stored = json['languageCode'];
    return AppSettings(
      languageCode:
          chosen && stored is String && supportedLanguageCodes.contains(stored)
              ? stored
              : defaultLanguageCode,
      languageChosen: chosen,
      autoReconnect: json['autoReconnect'] as bool? ?? true,
      hapticFeedbackEnabled: json['hapticFeedbackEnabled'] as bool? ?? true,
      speedUnit: SpeedUnit.fromKey(json['speedUnit']),
      experimentalWrites: json[experimentalKey] == true,
    );
  }
}

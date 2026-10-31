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

  static const defaultLanguageCode = 'en';
  static const supportedLanguageCodes = ['en', 'de'];

  const AppSettings({
    this.languageCode = defaultLanguageCode,
    this.autoReconnect = true,
    this.hapticFeedbackEnabled = true,
    this.languageChosen = false,
    this.speedUnit = SpeedUnit.kmh,
  });

  AppSettings copyWith({
    String? languageCode,
    bool? autoReconnect,
    bool? hapticFeedbackEnabled,
    bool? languageChosen,
    SpeedUnit? speedUnit,
  }) =>
      AppSettings(
        languageCode: languageCode ?? this.languageCode,
        autoReconnect: autoReconnect ?? this.autoReconnect,
        hapticFeedbackEnabled:
            hapticFeedbackEnabled ?? this.hapticFeedbackEnabled,
        languageChosen: languageChosen ?? this.languageChosen,
        speedUnit: speedUnit ?? this.speedUnit,
      );

  Map<String, dynamic> toJson() => {
        'languageCode': languageCode,
        'autoReconnect': autoReconnect,
        'hapticFeedbackEnabled': hapticFeedbackEnabled,
        'languageChosen': languageChosen,
        'speedUnit': speedUnit.key,
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
    );
  }
}

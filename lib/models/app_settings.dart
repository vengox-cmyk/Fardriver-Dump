class AppSettings {
  final String languageCode;
  final bool autoReconnect;
  final bool hapticFeedbackEnabled;

  const AppSettings({
    this.languageCode = 'de',
    this.autoReconnect = true,
    this.hapticFeedbackEnabled = true,
  });

  Map<String, dynamic> toJson() => {
        'languageCode': languageCode,
        'autoReconnect': autoReconnect,
        'hapticFeedbackEnabled': hapticFeedbackEnabled,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        languageCode: json['languageCode'] as String? ?? 'de',
        autoReconnect: json['autoReconnect'] as bool? ?? true,
        hapticFeedbackEnabled: json['hapticFeedbackEnabled'] as bool? ?? true,
      );
}

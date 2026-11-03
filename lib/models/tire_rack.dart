import 'dart:convert';
import 'dart:math' as math;

/// One tire size as the controller stores it: width (mm), aspect ratio (%)
/// and rim (inch) → `WheelWidth` / `WheelRatio` / `WheelRadius`.
///
/// The controller keeps whole-inch rims, so half-inch and scooter sizes are
/// mapped to the size with the same outer diameter. Speed formula (same as
/// `BleSpeedSettings`): km/h per rpm = 0.00376991136 × (Radius×1270 +
/// Width×Ratio) / RateRatio, i.e. diameter mm = (Radius×1270+Width×Ratio)/50.
class TireSize {
  final String name;
  final int widthMm;
  final int ratioPct;
  final int rimInch;
  final bool preset;

  const TireSize({
    required this.name,
    required this.widthMm,
    required this.ratioPct,
    required this.rimInch,
    this.preset = false,
  });

  /// Outer diameter the controller computes from these three values (mm).
  double get diameterMm => (rimInch * 1270.0 + widthMm * ratioPct) / 50.0;

  double get circumferenceM => diameterMm * math.pi / 1000.0;

  String get code => '$widthMm/$ratioPct-$rimInch';

  TireSize copyWith(
          {String? name, int? widthMm, int? ratioPct, int? rimInch}) =>
      TireSize(
          name: name ?? this.name,
          widthMm: widthMm ?? this.widthMm,
          ratioPct: ratioPct ?? this.ratioPct,
          rimInch: rimInch ?? this.rimInch);

  Map<String, dynamic> toJson() => {
        'name': name,
        'widthMm': widthMm,
        'ratioPct': ratioPct,
        'rimInch': rimInch,
      };

  static TireSize? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final w = json['widthMm'];
    final r = json['ratioPct'];
    final rim = json['rimInch'];
    if (name is! String || w is! int || r is! int || rim is! int) return null;
    if (!valid(w, r, rim)) return null;
    return TireSize(name: name, widthMm: w, ratioPct: r, rimInch: rim);
  }

  /// Same limits as the write allowlist.
  static bool valid(int width, int ratio, int rim) =>
      width >= 40 && width <= 255 && ratio >= 20 && ratio <= 120 &&
      rim >= 4 && rim <= 24;
}

class TireRack {
  TireRack._();

  static const format = 'farsure-tires-v1';

  /// Built-in sizes. Half-inch rims are rounded down (the controller
  /// stores whole inches) and the aspect ratio raised to keep the real
  /// outer diameter; the name keeps the size printed on the tire.
  static const presets = <TireSize>[
    // Half-inch rims: ratio raised so the outer diameter matches.
    // 8.5x2 ≈ 216 mm outer → 50/64-6 (216.4 mm)
    TireSize(name: '8.5x2', widthMm: 50, ratioPct: 64, rimInch: 6, preset: true),
    // 10x2.5 ≈ 254 mm → 65/78-6 (253.8 mm)
    TireSize(name: '10x2.5', widthMm: 65, ratioPct: 78, rimInch: 6, preset: true),
    // 10x3 = 80/65-6.5 (269.1 mm) → 80/73-6 (269.2 mm)
    TireSize(name: '10x3 (80/65-6.5)', widthMm: 80, ratioPct: 73, rimInch: 6, preset: true),
    // 90/65-6.5 (282.1 mm) → 90/72-6 (282.0 mm)
    TireSize(name: '90/65-6.5', widthMm: 90, ratioPct: 72, rimInch: 6, preset: true),
    // 100/65-6.5 (295.1 mm) → 100/71-6 (294.4 mm)
    TireSize(name: '100/65-6.5', widthMm: 100, ratioPct: 71, rimInch: 6, preset: true),
    TireSize(name: '110/70-12', widthMm: 110, ratioPct: 70, rimInch: 12, preset: true),
    TireSize(name: '120/70-12', widthMm: 120, ratioPct: 70, rimInch: 12, preset: true),
    TireSize(name: '130/70-12', widthMm: 130, ratioPct: 70, rimInch: 12, preset: true),
    TireSize(name: '110/70-13', widthMm: 110, ratioPct: 70, rimInch: 13, preset: true),
    TireSize(name: '120/70-13', widthMm: 120, ratioPct: 70, rimInch: 13, preset: true),
    TireSize(name: '60/100-14', widthMm: 60, ratioPct: 100, rimInch: 14, preset: true),
    TireSize(name: '70/100-14', widthMm: 70, ratioPct: 100, rimInch: 14, preset: true),
    TireSize(name: '80/100-14', widthMm: 80, ratioPct: 100, rimInch: 14, preset: true),
    TireSize(name: '90/100-14', widthMm: 90, ratioPct: 100, rimInch: 14, preset: true),
  ];

  static String encode(List<TireSize> custom) =>
      const JsonEncoder.withIndent('  ').convert({
        'format': format,
        'tires': [for (final t in custom) t.toJson()],
      });

  /// Custom sizes from an export; throws [FormatException] when the file
  /// is not a FarSure tire rack.
  static List<TireSize> decode(String text) {
    final json = jsonDecode(text);
    if (json is! Map || json['format'] != format) {
      throw const FormatException('Not a FarSure tire rack file');
    }
    final list = json['tires'];
    if (list is! List) return const [];
    return [
      for (final t in list)
        if (TireSize.fromJson(t) case final TireSize s) s
    ];
  }

  static bool looksLikeRack(String text) => text.contains('"$format"');

  /// Speed at [rpm] motor rpm with [gearRatio] (km/h).
  static double kphAt(TireSize t, double rpm, double gearRatio) =>
      gearRatio <= 0 ? 0 : rpm / gearRatio * t.circumferenceM * 60 / 1000;
}

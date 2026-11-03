import 'package:arcdash/models/fardriver_param_catalog.dart';
import 'package:arcdash/services/parameter_dump.dart';

/// How well a writable field's address and encoding are established.
enum WriteConfidence {
  /// The official app writes this exact word with this encoding.
  confirmed,

  /// Address decoded and shown by the official app, but it never writes
  /// it. Only offered with the Experimental toggle on.
  experimental,
}

/// One setting FarSure may write. Everything else is refused.
class WritableField {
  /// Stable key (the catalog name).
  final String key;

  /// Plain label for the review screen and the write log.
  final String label;

  final WriteConfidence confidence;

  /// Allowed raw range (inclusive), checked before anything is sent.
  final int rawMin;
  final int rawMax;

  /// Where the address/encoding comes from (shown in docs and the log).
  final String source;

  const WritableField({
    required this.key,
    required this.label,
    required this.confidence,
    required this.rawMin,
    required this.rawMax,
    required this.source,
  });

  bool get experimental => confidence == WriteConfidence.experimental;

  FardriverParamDef get def => FardriverParamCatalog.byName(key);

  /// Word address on the controller (block + byte offset / 2).
  int get wordAddress => def.block + def.byteOffset ~/ 2;

  /// Bit position of the field inside its 16-bit word.
  int get shift => (def.byteOffset % 2) * 8 + def.bitOffset;

  int get mask => ((1 << def.bitWidth) - 1) << shift;

  /// Byte offset of the word inside the 12-byte block.
  int get wordByteOffset => (def.byteOffset ~/ 2) * 2;

  int readRaw(List<int> block) => FardriverDecoder.rawInt(def, block);

  /// [word] with this field replaced by [raw] (other bits kept).
  int applyTo(int word, int raw) => (word & ~mask & 0xFFFF) | ((raw << shift) & mask);

  /// Human value, e.g. "GearRatio 4.106 (RateRatio 4106)" or "63.0 V".
  String format(int raw) {
    if (key == 'RateRatio') return WriteAllowlist.gearRatioLabel(raw);
    final d = def;
    if (d.factor == 1.0) return '$raw${d.unit.isEmpty ? '' : ' ${d.unit}'}';
    final digits = d.factor >= 0.1 ? 1 : (d.factor >= 0.01 ? 2 : 3);
    return '${(raw * d.factor).toStringAsFixed(digits)}'
        '${d.unit.isEmpty ? '' : ' ${d.unit}'}';
  }
}

/// Hard-coded list of the only settings FarSure writes.
///
/// Never on this list (and refused by [isForbiddenName] even if someone
/// adds them): current limits, phase / hall / motor-angle settings, PID
/// gains, field weakening, auto-learn and system commands.
class WriteAllowlist {
  WriteAllowlist._();

  static const fields = <WritableField>[
    WritableField(
      key: 'RateRatio',
      label: 'GearRatio (RateRatio)',
      confidence: WriteConfidence.confirmed,
      rawMin: 500,
      rawMax: 30000,
      source: 'MotorNet6 ParaPage: word 212 = GearRatio × 1000',
    ),
    WritableField(
      key: 'SpdPulseNum',
      label: 'SpdPulseNum (dash pulse rate)',
      confidence: WriteConfidence.confirmed,
      rawMin: 1,
      rawMax: 65535,
      source: 'MotorNet6 ParaPage: word 53, u16',
    ),
    WritableField(
      key: 'SpeedPulse',
      label: 'Speed Pulses',
      confidence: WriteConfidence.confirmed,
      rawMin: 1,
      rawMax: 31,
      source: 'MotorNet6 ParaPage: word 26 high byte bits 0-4 (RMW)',
    ),
    WritableField(
      key: 'WheelWidth',
      label: 'Tire width (mm)',
      confidence: WriteConfidence.confirmed,
      rawMin: 40,
      rawMax: 255,
      source: 'MotorNet6 ParaPage: word 211 high byte',
    ),
    WritableField(
      key: 'WheelRatio',
      label: 'Tire aspect ratio (%)',
      confidence: WriteConfidence.confirmed,
      rawMin: 20,
      rawMax: 120,
      source: 'MotorNet6 ParaPage: word 210 low byte',
    ),
    WritableField(
      key: 'WheelRadius',
      label: 'Rim size (inch)',
      confidence: WriteConfidence.confirmed,
      rawMin: 4,
      rawMax: 24,
      source: 'MotorNet6 ParaPage: word 210 high byte',
    ),
    WritableField(
      key: 'LowVolProtect',
      label: 'Low voltage protect',
      confidence: WriteConfidence.confirmed,
      rawMin: 100,
      rawMax: 2000,
      source: 'MotorNet6 ParaPage: word 31 = V × 10',
    ),
    WritableField(
      key: 'BattRatedCap',
      label: 'Battery rated capacity (Ah)',
      confidence: WriteConfidence.confirmed,
      rawMin: 20,
      rawMax: 250,
      source: 'MotorNet6 ParaPage: word 28, 20-250 Ah',
    ),
    WritableField(
      key: 'HighVolProtect',
      label: 'Over voltage protect',
      confidence: WriteConfidence.experimental,
      rawMin: 100,
      rawMax: 2000,
      source: 'fardriver.hpp word 37 = V × 10; shown, never written by '
          'the official app',
    ),
    WritableField(
      key: 'HighVolRestore',
      label: 'Over voltage restore',
      confidence: WriteConfidence.experimental,
      rawMin: 100,
      rawMax: 2000,
      source: 'fardriver.hpp word 0x83 = V × 10; shown, never written by '
          'the official app',
    ),
  ];

  static final _forbidden = RegExp(
      r'(Curr|Phase|Hall|Angle|Kp|Ki|Kd|PID|Weak|Learn|Zero|Modulation|'
      r'SysCmd|Factory|Reset|Mos|Pole)',
      caseSensitive: false);

  /// True for anything FarSure must never write.
  static bool isForbiddenName(String name) => _forbidden.hasMatch(name);

  static WritableField? byKey(String key) {
    for (final f in fields) {
      if (f.key == key) return f;
    }
    return null;
  }

  /// Fields usable now ([experimental] = the Settings toggle).
  static List<WritableField> available({required bool experimental}) =>
      [for (final f in fields) if (experimental || !f.experimental) f];

  static bool isWritableWord(int word) =>
      fields.any((f) => f.wordAddress == word);

  static String gearRatioLabel(int rateRatio) =>
      'GearRatio ${(rateRatio / 1000).toStringAsFixed(3)} '
      '(RateRatio $rateRatio)';

  /// RateRatio for a gear ratio such as 4.106 → 4106.
  static int rateRatioFor(double gearRatio) =>
      (gearRatio * 1000).round();
}

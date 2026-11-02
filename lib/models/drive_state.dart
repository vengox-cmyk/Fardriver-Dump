/// Gear (drive direction + speed level) and boost, decoded from the
/// controller's status frames.
///
/// Confirmed against the official FarDriver app on a BT HCI capture
/// (ND961000, Nov 2026; see `test/fixtures/bt_frames/`):
///
/// * 0xE2 data byte 0 (`arg[2]`):
///   * bits 0-1 direction: 0 = N, 1 = D, 2 = R (3 is not used),
///   * bits 2-3 speed level: 0 = low, 1 = mid, 2 = high (3 is shown as high),
///   * bit 5 (0x20): wheel turning.
///   e.g. 0x81 D/low, 0x85 D/mid, 0x89 D/high, 0xA9 D/high + moving.
/// * 0xD6 `Global_state3` = `arg[9] * 256 + arg[8]` (data bytes 7/6):
///   bit 2 (0x04) set while boost is active. 0xD6 arrives about every 1.5 s,
///   so the last value is held until the next one.
library;

enum DriveDirection {
  neutral('N'),
  drive('D'),
  reverse('R'),
  unknown('?');

  final String letter;
  const DriveDirection(this.letter);

  static DriveDirection fromBits(int bits) => switch (bits & 0x03) {
        0 => DriveDirection.neutral,
        1 => DriveDirection.drive,
        2 => DriveDirection.reverse,
        _ => DriveDirection.unknown,
      };

  /// Stable code for CSV and JSON.
  String get code => letter == '?' ? '' : letter;

  static DriveDirection fromCode(String? code) => switch (code) {
        'N' => DriveDirection.neutral,
        'D' => DriveDirection.drive,
        'R' => DriveDirection.reverse,
        _ => DriveDirection.unknown,
      };
}

enum SpeedLevel {
  low('LOW', 'DL'),
  mid('MID', 'DM'),
  high('HIGH', 'D');

  /// Word shown on the FarSure chip ("D · LOW").
  final String word;

  /// What the official FarDriver app shows (DL / DM / D).
  final String official;

  const SpeedLevel(this.word, this.official);

  /// Level 3 is not a real setting; the official app shows it as high.
  static SpeedLevel fromBits(int bits) => switch (bits & 0x03) {
        0 => SpeedLevel.low,
        1 => SpeedLevel.mid,
        _ => SpeedLevel.high,
      };

  /// Stable code for CSV and JSON.
  String get code => name;

  static SpeedLevel? fromCode(String? code) {
    for (final level in SpeedLevel.values) {
      if (level.name == code) return level;
    }
    return null;
  }
}

/// Snapshot of gear + boost, as shown on the status chip.
class GearStatus {
  final DriveDirection direction;
  final SpeedLevel level;
  final bool wheelMoving;

  /// Last 0xD6 boost bit; false until the first 0xD6 frame.
  final bool boost;

  const GearStatus({
    required this.direction,
    required this.level,
    this.wheelMoving = false,
    this.boost = false,
  });

  /// 0xE2 data byte 0.
  factory GearStatus.fromE2Byte(int b, {bool boost = false}) => GearStatus(
        direction: DriveDirection.fromBits(b),
        level: SpeedLevel.fromBits(b >> 2),
        wheelMoving: (b & 0x20) != 0,
        boost: boost,
      );

  /// `Global_state3` from the 12 data bytes of a 0xD6 frame.
  static int globalState3(List<int> d6Data) => (d6Data[7] << 8) | d6Data[6];

  /// True when the 0xD6 boost bit (Global_state3 & 0x04) is set.
  static bool boostFromD6(List<int> d6Data) =>
      (globalState3(d6Data) & 0x04) != 0;

  /// Boost only replaces the level while driving forward (official app shows
  /// "Bst" in place of the gear label in D).
  bool get showsBoost => boost && direction == DriveDirection.drive;

  /// Chip text: "N", "R", "D · LOW", "D · MID", "D · HIGH", "D · BST".
  String get label => switch (direction) {
        DriveDirection.drive => 'D · ${showsBoost ? 'BST' : level.word}',
        DriveDirection.neutral => 'N',
        DriveDirection.reverse => 'R',
        DriveDirection.unknown => '?',
      };

  /// Official-app style: N, R, DL, DM, D, Bst.
  String get officialLabel => switch (direction) {
        DriveDirection.drive => showsBoost ? 'Bst' : level.official,
        _ => direction.letter,
      };

  GearStatus withBoost(bool value) => GearStatus(
      direction: direction,
      level: level,
      wheelMoving: wheelMoving,
      boost: value);

  @override
  bool operator ==(Object other) =>
      other is GearStatus &&
      other.direction == direction &&
      other.level == level &&
      other.wheelMoving == wheelMoving &&
      other.boost == boost;

  @override
  int get hashCode => Object.hash(direction, level, wheelMoving, boost);

  @override
  String toString() => 'GearStatus($label)';
}

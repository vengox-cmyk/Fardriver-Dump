/// Complete FarDriver configuration parameter catalog.
///
/// The field list is generated from
/// `reference/upstream/fardriver-controllers/fardriver.hpp` by
/// `tool/gen_param_catalog.py` (see `fardriver_param_catalog.g.dart`). It is a
/// reverse-engineered memory map: every named field is flagged
/// [FardriverParamDef.unverified] and every `unk*` field is flagged
/// [FardriverParamDef.unknown]. Exports always carry the raw value and the raw
/// 12-byte block next to any scaled value, so a wrong decode never loses data.
///
/// This catalog is read-only: nothing here encodes or writes values.
library;

part 'fardriver_param_catalog.g.dart';

enum FardriverParamKind { int, enumeration, text }

class FardriverParamDef {
  /// Block start address (word address of the first word in the 12-byte block).
  final int block;
  final String name;

  /// Byte offset inside the 12-byte block data (0..11).
  final int byteOffset;

  /// Bit offset (LSB first) relative to [byteOffset].
  final int bitOffset;
  final int bitWidth;
  final bool signed;
  final FardriverParamKind kind;

  /// scaled = raw * factor + offset
  final double factor;
  final double offset;
  final String unit;
  final Map<int, String> labels;

  /// Trailing comment from fardriver.hpp (raw provenance).
  final String note;

  /// Decoded from the reverse-engineered header, not confirmed on hardware.
  final bool unverified;

  /// Field name is a placeholder (`unk*`, reserved) in the header.
  final bool unknown;

  const FardriverParamDef({
    required this.block,
    required this.name,
    required this.byteOffset,
    required this.bitOffset,
    required this.bitWidth,
    required this.signed,
    required this.kind,
    required this.factor,
    required this.offset,
    required this.unit,
    required this.note,
    required this.unverified,
    required this.unknown,
    this.labels = const {},
  });

  /// 16-bit word address that contains the first bit of this field.
  int get wordAddress => block + byteOffset ~/ 2;

  /// Human readable bit range relative to [byteOffset], e.g. `0-15` or `2-3`.
  String get bitsLabel => '$bitOffset-${bitOffset + bitWidth - 1}';

  String get status => unknown ? 'unknown' : 'unverified';

  /// Stable key used to match parameters across dumps.
  String get key => '${block.toRadixString(16)}:$byteOffset:$bitOffset:$name';
}

class FardriverParamCatalog {
  FardriverParamCatalog._();

  /// All configuration blocks present in the live BLE stream (0x00-0xD0 and
  /// 0x5D), in address order.
  static const List<int> configBlocks = [
    0x00, 0x06, 0x0C, 0x12, 0x18, 0x1E, 0x24, 0x2A, 0x30, 0x5D, 0x63, 0x69, //
    0x7C, 0x82, 0x88, 0x8E, 0x94, 0x9A, 0xA0, 0xA6, 0xAC, 0xB2, 0xB8, 0xBE,
    0xC4, 0xCA, 0xD0,
  ];

  /// Blocks that may never be streamed by some controllers. A live snapshot
  /// without them is still exported (listed as missing optional blocks).
  static const List<int> optionalBlocks = [0x5D];

  /// Config blocks every complete snapshot must contain (0x00-0xD0 without
  /// the optional ones). Same set as a `.heb` file.
  static const List<int> mandatoryBlocks = [
    0x00, 0x06, 0x0C, 0x12, 0x18, 0x1E, 0x24, 0x2A, 0x30, 0x63, 0x69, 0x7C, //
    0x82, 0x88, 0x8E, 0x94, 0x9A, 0xA0, 0xA6, 0xAC, 0xB2, 0xB8, 0xBE, 0xC4,
    0xCA, 0xD0,
  ];

  static const int blockLength = 12;

  static List<FardriverParamDef> get all => _generatedParams;

  static List<FardriverParamDef> forBlock(int block) =>
      _generatedParams.where((p) => p.block == block).toList();

  static FardriverParamDef byName(String name, {int? block}) => _generatedParams
      .firstWhere((p) => p.name == name && (block == null || p.block == block));
}

import 'package:arcdash/models/fardriver_param_catalog.dart';
import 'package:arcdash/services/heb_file_parser.dart';

/// Where a parameter dump came from.
enum ParameterDumpSource { live, heb, csv }

/// One decoded configuration value. Purely informational: nothing in this
/// file can encode or write a value back to the controller.
class DecodedParameter {
  final FardriverParamDef def;

  /// Raw integer (as text) or, for text fields, the raw bytes as hex.
  final String raw;

  /// Scaled value (or ASCII text for text fields).
  final String value;

  /// Enum label, `?` for an unknown enum value, empty for non-enum fields.
  final String label;

  const DecodedParameter({
    required this.def,
    required this.raw,
    required this.value,
    required this.label,
  });

  String get display {
    final unit = def.unit.isEmpty ? '' : ' ${def.unit}';
    return label.isEmpty ? '$value$unit' : '$label ($value)';
  }
}

/// A set of raw 12-byte configuration blocks plus provenance metadata.
class ParameterDump {
  final ParameterDumpSource source;

  /// Source description written to CSV, e.g. `live`, `heb:backup.heb`.
  final String sourceLabel;
  final String controllerId;
  final DateTime? capturedAt;
  final String appVersion;
  final Map<int, List<int>> blocks;
  final List<int> requiredBlocks;

  /// Blocks exported when present but not required for completeness.
  final List<int> optionalBlocks;

  ParameterDump({
    required this.source,
    required this.sourceLabel,
    required Map<int, List<int>> blocks,
    required this.requiredBlocks,
    this.optionalBlocks = const [],
    this.controllerId = '',
    this.capturedAt,
    this.appVersion = '',
  }) : blocks = Map.unmodifiable(blocks.map((address, bytes) {
          if (bytes.length != FardriverParamCatalog.blockLength) {
            throw FormatException(
                'block 0x${address.toRadixString(16)} must have 12 bytes');
          }
          return MapEntry(address, List<int>.unmodifiable(bytes));
        }));

  /// Builds a dump from a parsed `.heb` file (26 blocks, no 0x5D).
  factory ParameterDump.fromHeb(HebFile heb,
          {required String fileName, String appVersion = ''}) =>
      ParameterDump(
        source: ParameterDumpSource.heb,
        sourceLabel: 'heb:$fileName',
        blocks: heb.blocks,
        requiredBlocks: HebFile.blockAddresses,
        appVersion: appVersion,
      );

  List<int> get missingBlocks =>
      requiredBlocks.where((b) => !blocks.containsKey(b)).toList();

  /// Optional blocks (0x5D) that were not received. Never blocks export.
  List<int> get missingOptionalBlocks =>
      optionalBlocks.where((b) => !blocks.containsKey(b)).toList();

  bool get isComplete => missingBlocks.isEmpty;

  List<DecodedParameter> decode() => [
        for (final def in FardriverParamCatalog.all)
          if (blocks[def.block] != null)
            FardriverDecoder.decode(def, blocks[def.block]!),
      ];
}

class FardriverDecoder {
  FardriverDecoder._();

  static int rawInt(FardriverParamDef def, List<int> block) {
    final nbytes = (def.bitOffset + def.bitWidth + 7) ~/ 8;
    var value = 0;
    for (var i = 0; i < nbytes; i++) {
      value |= block[def.byteOffset + i] << (8 * i);
    }
    value = (value >> def.bitOffset) & ((1 << def.bitWidth) - 1);
    if (def.signed && (value & (1 << (def.bitWidth - 1))) != 0) {
      value -= 1 << def.bitWidth;
    }
    return value;
  }

  static double? scaled(FardriverParamDef def, List<int> block) {
    if (def.kind == FardriverParamKind.text) return null;
    return rawInt(def, block) * def.factor + def.offset;
  }

  static DecodedParameter decode(FardriverParamDef def, List<int> block) {
    if (def.kind == FardriverParamKind.text) {
      final chunk =
          block.sublist(def.byteOffset, def.byteOffset + def.bitWidth ~/ 8);
      return DecodedParameter(
        def: def,
        raw: chunk.map(_hex2).join(),
        value: ascii(chunk),
        label: '',
      );
    }
    final raw = rawInt(def, block);
    if (def.kind == FardriverParamKind.enumeration) {
      return DecodedParameter(
          def: def, raw: '$raw', value: '$raw', label: def.labels[raw] ?? '?');
    }
    return DecodedParameter(
      def: def,
      raw: '$raw',
      value: formatScaled(raw, def.factor, def.offset),
      label: '',
    );
  }

  /// Formatting shared byte-for-byte with tool/fardriver_dump.py.
  static String formatScaled(int raw, double factor, double offset) {
    if (factor == 1.0 && offset == offset.truncateToDouble()) {
      return '${raw + offset.toInt()}';
    }
    var text = (raw * factor + offset).toStringAsFixed(4);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      text = text.replaceFirst(RegExp(r'\.$'), '');
    }
    return text == '-0' || text.isEmpty ? '0' : text;
  }

  static String ascii(List<int> bytes) {
    var end = bytes.length;
    while (end > 0 && bytes[end - 1] == 0) {
      end--;
    }
    return String.fromCharCodes(
        bytes.sublist(0, end).map((c) => c >= 0x20 && c < 0x7F ? c : 0x2E));
  }

  static String blockHex(List<int> bytes) => bytes.map(_hex2).join(' ');

  static String _hex2(int b) =>
      b.toRadixString(16).padLeft(2, '0').toUpperCase();
}

import 'package:arcdash/models/fardriver_param_catalog.dart';
import 'package:arcdash/services/heb_file_parser.dart';
import 'package:arcdash/services/parameter_dump.dart';

/// Minimal RFC 4180 CSV helpers matching Python's `csv` module
/// (QUOTE_MINIMAL, `\n` line terminator) so the app and
/// tool/fardriver_dump.py produce byte-identical files.
class FlatCsv {
  FlatCsv._();

  static String encodeRow(List<String> cells) => cells.map(_cell).join(',');

  static String encode(List<List<String>> rows) =>
      rows.map((r) => '${encodeRow(r)}\n').join();

  static String _cell(String value) {
    if (value.contains(RegExp('[,"\r\n]'))) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  static List<List<String>> decode(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var quoted = false;
    var i = 0;
    if (text.startsWith('\uFEFF')) i = 1;
    var rowHasContent = false;
    void endCell() {
      row.add(cell.toString());
      cell.clear();
    }

    void endRow() {
      endCell();
      if (rowHasContent || row.length > 1 || row.first.isNotEmpty) {
        rows.add(row);
      }
      row = <String>[];
      rowHasContent = false;
    }

    while (i < text.length) {
      final c = text[i];
      if (quoted) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          cell.write(c);
        }
      } else if (c == '"') {
        quoted = true;
        rowHasContent = true;
      } else if (c == ',') {
        endCell();
        rowHasContent = true;
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        endRow();
      } else {
        cell.write(c);
      }
      i++;
    }
    if (cell.isNotEmpty || row.isNotEmpty || rowHasContent) endRow();
    return rows;
  }
}

class IncompleteSnapshotException implements Exception {
  final List<int> missingBlocks;
  const IncompleteSnapshotException(this.missingBlocks);

  @override
  String toString() => 'Parameter snapshot incomplete, missing blocks: '
      '${missingBlocks.map(hexByte).join(' ')}';
}

String hexByte(int value) =>
    '0x${value.toRadixString(16).padLeft(2, '0').toUpperCase()}';

/// Flat CSV export/import of a full parameter dump ("arcdash-param-csv-v1").
class ParameterCsvCodec {
  ParameterCsvCodec._();

  static const format = 'arcdash-param-csv-v1';
  static const title = '# ArcDash FarDriver parameter dump';

  /// Disclaimer line written into every exported CSV (ignored on import).
  static const notice =
      'Informational only - verify before use. Not affiliated with FarDriver.';

  /// Marker row that starts the trailing section of unidentified (`unk*`)
  /// rows. Older files have no marker and interleave those rows; both parse.
  static const unidentifiedMarker = '# unidentified';
  static const columns = [
    'block',
    'word_address',
    'byte_offset',
    'bits',
    'name',
    'raw_value',
    'scaled_value',
    'unit',
    'enum_label',
    'raw_block_hex',
    'status',
    'note',
  ];

  static List<String> commonCells(FardriverParamDef def) => [
        hexByte(def.block),
        hexByte(def.wordAddress),
        '${def.byteOffset}',
        def.bitsLabel,
        def.displayName,
      ];

  /// Encodes [dump] as CSV. Live snapshots must be complete unless
  /// [allowIncomplete] is set; incomplete dumps throw
  /// [IncompleteSnapshotException].
  static String encode(ParameterDump dump,
      {bool allowIncomplete = false, String? appVersion}) {
    final missing = dump.missingBlocks;
    if (missing.isNotEmpty && !allowIncomplete) {
      throw IncompleteSnapshotException(missing);
    }
    final rows = <List<String>>[
      [title, format],
      ['# notice', notice],
      ['# controller_id', dump.controllerId],
      ['# capture_time', dump.capturedAt?.toUtc().toIso8601String() ?? ''],
      ['# app_version', appVersion ?? dump.appVersion],
      ['# source', dump.sourceLabel],
      ['# complete', missing.isEmpty ? 'yes' : 'no'],
      ['# missing_blocks', missing.map(hexByte).join(' ')],
      [
        '# missing_optional_blocks',
        dump.missingOptionalBlocks.map(hexByte).join(' ')
      ],
      columns,
    ];
    final unidentified = <List<String>>[];
    for (final p in dump.decode()) {
      (p.def.unidentified ? unidentified : rows).add([
        ...commonCells(p.def),
        p.raw,
        p.value,
        p.def.unit,
        p.label,
        FardriverDecoder.blockHex(dump.blocks[p.def.block]!),
        p.def.status,
        p.def.note,
      ]);
    }
    rows
      ..add([unidentifiedMarker])
      ..addAll(unidentified);
    return FlatCsv.encode(rows);
  }

  /// Parses a CSV written by [encode] or tool/fardriver_dump.py. The raw
  /// blocks are rebuilt from `raw_block_hex` and re-decoded with the current
  /// catalog, so stale decoded columns never matter.
  static ParameterDump decode(String text, {String fileName = 'csv'}) {
    final meta = <String, String>{};
    final blocks = <int, List<int>>{};
    List<String>? header;
    for (final row in FlatCsv.decode(text)) {
      if (row.isEmpty) continue;
      if (row.first.startsWith('#')) {
        final key = row.first.replaceFirst(RegExp(r'^#+'), '').trim();
        meta[key] = row.length > 1 ? row[1] : '';
        continue;
      }
      if (header == null) {
        header = row;
        if (!row.contains('block') || !row.contains('raw_block_hex')) {
          throw const FormatException('not an ArcDash parameter CSV');
        }
        continue;
      }
      if (row.length != header.length) {
        throw const FormatException('CSV row has wrong number of cells');
      }
      final rec = Map.fromIterables(header, row);
      final block = int.parse(rec['block']!.replaceFirst('0x', ''), radix: 16);
      final hex = rec['raw_block_hex']!.replaceAll(' ', '');
      if (hex.length != 24) {
        throw FormatException('block ${hexByte(block)} hex must be 12 bytes');
      }
      final bytes = [
        for (var i = 0; i < 24; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16)
      ];
      final previous = blocks[block];
      if (previous != null && previous.join(',') != bytes.join(',')) {
        throw FormatException('inconsistent hex for block ${hexByte(block)}');
      }
      blocks[block] = bytes;
    }
    if (meta['ArcDash FarDriver parameter dump'] != format) {
      throw const FormatException('missing arcdash-param-csv-v1 header');
    }
    if (blocks.isEmpty) throw const FormatException('CSV has no blocks');
    final source =
        (meta['source'] ?? '').isEmpty ? 'csv:$fileName' : meta['source']!;
    return ParameterDump(
      source: ParameterDumpSource.csv,
      sourceLabel: source,
      blocks: blocks,
      requiredBlocks: source.startsWith('heb:')
          ? HebFile.blockAddresses
          : FardriverParamCatalog.mandatoryBlocks,
      optionalBlocks: source.startsWith('heb:')
          ? const []
          : FardriverParamCatalog.optionalBlocks,
      controllerId: meta['controller_id'] ?? '',
      capturedAt: DateTime.tryParse(meta['capture_time'] ?? ''),
      appVersion: meta['app_version'] ?? '',
    );
  }
}

enum ParameterChange { changed, same, onlyA, onlyB }

class ParameterDiffEntry {
  final FardriverParamDef def;
  final DecodedParameter? a;
  final DecodedParameter? b;
  final ParameterChange change;

  const ParameterDiffEntry(this.def, this.a, this.b, this.change);

  String get changeLabel => switch (change) {
        ParameterChange.changed => 'changed',
        ParameterChange.same => 'same',
        ParameterChange.onlyA => 'only_a',
        ParameterChange.onlyB => 'only_b',
      };
}

/// Compares two dumps by raw value, in catalog order. Read-only.
class ParameterDiff {
  ParameterDiff._();

  static const format = 'arcdash-param-diff-v1';
  static const columns = [
    'change',
    'block',
    'word_address',
    'byte_offset',
    'bits',
    'name',
    'unit',
    'a_raw',
    'a_value',
    'a_label',
    'b_raw',
    'b_value',
    'b_label',
    'status',
  ];

  static List<ParameterDiffEntry> compare(ParameterDump a, ParameterDump b,
      {bool showAll = false}) {
    final out = <ParameterDiffEntry>[];
    for (final def in FardriverParamCatalog.all) {
      final ba = a.blocks[def.block];
      final bb = b.blocks[def.block];
      if (ba == null && bb == null) continue;
      final da = ba == null ? null : FardriverDecoder.decode(def, ba);
      final db = bb == null ? null : FardriverDecoder.decode(def, bb);
      final change = da == null
          ? ParameterChange.onlyB
          : db == null
              ? ParameterChange.onlyA
              : da.raw == db.raw
                  ? ParameterChange.same
                  : ParameterChange.changed;
      if (change == ParameterChange.same && !showAll) continue;
      out.add(ParameterDiffEntry(def, da, db, change));
    }
    return out;
  }

  static String toCsv(ParameterDump a, ParameterDump b,
      {bool showAll = false, String appVersion = ''}) {
    String time(ParameterDump d) =>
        d.capturedAt?.toUtc().toIso8601String() ?? '';
    final rows = <List<String>>[
      ['# ArcDash FarDriver parameter diff', format],
      ['# notice', ParameterCsvCodec.notice],
      ['# a_source', a.sourceLabel],
      ['# a_controller_id', a.controllerId],
      ['# a_capture_time', time(a)],
      ['# b_source', b.sourceLabel],
      ['# b_controller_id', b.controllerId],
      ['# b_capture_time', time(b)],
      ['# app_version', appVersion],
      ['# show_all', showAll ? 'yes' : 'no'],
      columns,
    ];
    final unidentified = <List<String>>[];
    for (final e in compare(a, b, showAll: showAll)) {
      (e.def.unidentified ? unidentified : rows).add([
        e.changeLabel,
        ...ParameterCsvCodec.commonCells(e.def),
        e.def.unit,
        e.a?.raw ?? '',
        e.a?.value ?? '',
        e.a?.label ?? '',
        e.b?.raw ?? '',
        e.b?.value ?? '',
        e.b?.label ?? '',
        e.def.status,
      ]);
    }
    rows
      ..add([ParameterCsvCodec.unidentifiedMarker])
      ..addAll(unidentified);
    return FlatCsv.encode(rows);
  }
}

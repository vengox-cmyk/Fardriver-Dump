import 'dart:convert';
import 'dart:io';

import 'package:arcdash/models/fardriver_param_catalog.dart';
import 'package:arcdash/services/diagnostic_log.dart';
import 'package:arcdash/services/heb_file_parser.dart';
import 'package:arcdash/services/parameter_capture.dart';
import 'package:arcdash/services/parameter_csv.dart';
import 'package:arcdash/services/parameter_dump.dart';
import 'package:arcdash/services/parameter_dump_io.dart';
import 'package:arcdash/services/parameter_snapshot_repository.dart';
import 'package:arcdash/services/versioned_json_repository.dart';
import 'package:arcdash/utils/packet_parser.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixtureDir = 'test/fixtures/param_dump';

class _MemoryStore implements AtomicJsonStore {
  String? contents;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> replace(String value) async => contents = value;
}

ParameterSnapshotRepository _repository() => ParameterSnapshotRepository(
      complete: VersionedJsonRepository(
          store: _MemoryStore(), type: 'p', schemaVersion: 1),
      pending: VersionedJsonRepository(
          store: _MemoryStore(), type: 'pp', schemaVersion: 1),
    );

List<int> _syntheticHeb() =>
    List<int>.generate(HebFile.expectedLength, (i) => (i * 37 + 11) & 0xFF);

ParameterDump _hebDump([List<int>? bytes]) => ParameterDump.fromHeb(
      HebFile.parse(bytes ?? _syntheticHeb()),
      fileName: 'synthetic_696.heb',
      appVersion: 'fardriver_dump.py/1',
    );

DecodedParameter _decode(String name, List<int> block, {int? at}) =>
    FardriverDecoder.decode(
        FardriverParamCatalog.byName(name, block: at), block);

List<int> _hex(String text) =>
    [for (final b in text.split(' ')) int.parse(b, radix: 16)];

List<int> _block(Map<int, int> bytes) =>
    List<int>.generate(12, (i) => bytes[i] ?? 0);

ParameterDump _liveDump(Map<int, List<int>> blocks) => ParameterDump(
      source: ParameterDumpSource.live,
      sourceLabel: 'live',
      blocks: blocks,
      requiredBlocks: FardriverParamCatalog.mandatoryBlocks,
      optionalBlocks: FardriverParamCatalog.optionalBlocks,
    );

void main() {
  group('catalog', () {
    test('covers 0x00-0xD0 plus 0x5D, every block fully mapped', () {
      const blocks = FardriverParamCatalog.configBlocks;
      expect(blocks, hasLength(27));
      expect(blocks, containsAll(HebFile.blockAddresses));
      expect(blocks, contains(0x5D));
      for (final block in blocks) {
        final bits = FardriverParamCatalog.forBlock(block)
            .where((p) => !p.overlay)
            .fold<int>(0, (sum, p) => sum + p.bitWidth);
        expect(bits, 96, reason: 'block 0x${block.toRadixString(16)}');
      }
      expect(FardriverParamCatalog.all.where((p) => p.unknown), isNotEmpty);
      expect(FardriverParamCatalog.all.every((p) => p.unverified || p.unknown),
          isTrue,
          reason: 'nothing is hardware-verified yet');
    });
  });

  group('decode & scaling', () {
    test('MaxSpeed 0x12 byte 6 is a plain LE word', () {
      final def = FardriverParamCatalog.byName('MaxSpeed', block: 0x12);
      expect(def.byteOffset, 6);
      expect(def.wordAddress, 0x15);
      final p = _decode('MaxSpeed', _block({6: 0x70, 7: 0x17}), at: 0x12);
      expect(p.raw, '6000');
      expect(p.value, '6000');
      expect(def.unit, 'rpm');
    });

    test('MaxLineCurr 0x18 byte 2 is divided by 4', () {
      final p = _decode('MaxLineCurr', _block({2: 0x2D, 3: 0x01}), at: 0x18);
      expect(p.raw, '301');
      expect(p.value, '75.25');
      expect(p.def.unit, 'A');
    });

    test('RatedVoltage is divided by 10', () {
      final p = _decode('RatedVoltage', _block({10: 0xC8, 11: 0x02}), at: 0x12);
      expect(p.raw, '712');
      expect(p.value, '71.2');
      expect(p.def.unit, 'V');
    });

    test('ThrottleResponse is the 2-bit field at bits 2-3 of byte 4', () {
      final def = FardriverParamCatalog.byName('ThrottleResponse', block: 0x18);
      expect(def.bitsLabel, '2-3');
      final p = FardriverDecoder.decode(def, _block({4: 0x08}));
      expect(p.raw, '2');
    });

    test('100/128 percent fields round half-up to 4 decimals', () {
      expect(FardriverDecoder.formatScaled(1, 100 / 128, 0), '0.7813');
      expect(FardriverDecoder.formatScaled(3, 100 / 128, 0), '2.3438');
      expect(FardriverDecoder.formatScaled(128, 100 / 128, 0), '100');
      expect(FardriverDecoder.formatScaled(0, 0.1, 0), '0');
    });

    test('ModelYear adds 2000', () {
      final def = FardriverParamCatalog.byName('ModelYear');
      final p = FardriverDecoder.decode(def, _block({def.byteOffset: 24}));
      expect(p.value, '2024');
    });

    test('signed fields are two-complement', () {
      final p = _decode('PhaseACoeff', _block({4: 0xFF, 5: 0xFF}), at: 0x00);
      expect(p.raw, '-1');
    });

    test('enum values carry their label, unknown values get ?', () {
      final def = FardriverParamCatalog.all.firstWhere((p) =>
          p.kind == FardriverParamKind.enumeration && p.labels.isNotEmpty);
      final key = def.labels.keys.first;
      final block = List<int>.filled(12, 0);
      // write key into the field (LSB-first)
      var bits = key << def.bitOffset;
      for (var i = 0; bits != 0; i++, bits >>= 8) {
        block[def.byteOffset + i] |= bits & 0xFF;
      }
      final p = FardriverDecoder.decode(def, block);
      expect(p.label, def.labels[key]);
    });

    test('text fields become hex raw + printable ASCII', () {
      final def = FardriverParamCatalog.byName('ModelName', block: 0xA0);
      final block = List<int>.filled(12, 0);
      final text = 'FD72'.codeUnits;
      for (var i = 0; i < text.length; i++) {
        block[def.byteOffset + i] = text[i];
      }
      final p = FardriverDecoder.decode(def, block);
      expect(p.value, startsWith('FD72'));
      expect(p.raw, startsWith('46443732'));
    });
  });

  group('heb', () {
    test('synthetic 696-byte heb parses into 26 blocks without 0x5D', () {
      final bytes = File('$_fixtureDir/synthetic_696.heb').readAsBytesSync();
      expect(bytes, hasLength(696));
      final dump = ParameterDumpIo.parseFile(bytes, 'synthetic_696.heb');
      expect(dump.source, ParameterDumpSource.heb);
      expect(dump.blocks, hasLength(26));
      expect(dump.blocks.containsKey(0x5D), isFalse);
      expect(dump.isComplete, isTrue);
      expect(dump.blocks[0x12], _syntheticHeb().sublist(36, 48));
    });

    test('wrong-size heb is rejected', () {
      expect(() => ParameterDumpIo.parseFile(List.filled(695, 0), 'x.heb'),
          throwsFormatException);
    });
  });

  group('csv', () {
    test('matches the golden file shared with tool/fardriver_dump.py', () {
      final golden = File('$_fixtureDir/synthetic_696.csv').readAsStringSync();
      expect(ParameterCsvCodec.encode(_hebDump()), golden);
    });

    test('round-trips through the CSV decoder', () {
      final dump = _hebDump();
      final text = ParameterCsvCodec.encode(dump);
      final back = ParameterDumpIo.parseFile(utf8.encode(text), 'export.csv');
      expect(back.blocks, dump.blocks);
      expect(back.sourceLabel, dump.sourceLabel);
      expect(ParameterCsvCodec.encode(back), text);
    });

    test('quotes cells with commas and quotes', () {
      expect(FlatCsv.encodeRow(['a,b', 'c"d', 'e']), '"a,b","c""d",e');
      expect(FlatCsv.decode('"a,b","c""d",e\n'), [
        ['a,b', 'c"d', 'e']
      ]);
    });

    test('snapshots missing a mandatory block are refused', () {
      final blocks = Map.of(_hebDump().blocks)..remove(0x12);
      blocks[0x5D] = List<int>.filled(12, 1);
      final dump = _liveDump(blocks);
      expect(dump.isComplete, isFalse);
      expect(
          () => ParameterCsvCodec.encode(dump),
          throwsA(isA<IncompleteSnapshotException>()
              .having((e) => e.missingBlocks, 'missing', [0x12])));
      expect(ParameterCsvCodec.encode(dump, allowIncomplete: true),
          contains('# complete,no'));
    });

    test('a live snapshot without optional 0x5D exports and lists it', () {
      final dump = _liveDump(Map.of(_hebDump().blocks)); // no 0x5D
      expect(dump.isComplete, isTrue);
      expect(dump.missingOptionalBlocks, [0x5D]);
      final csv = ParameterCsvCodec.encode(dump);
      expect(csv, contains('# complete,yes\n'));
      expect(csv, contains('# missing_blocks,\n'));
      expect(csv, contains('# missing_optional_blocks,0x5D\n'));
      final back = ParameterCsvCodec.decode(csv);
      expect(back.isComplete, isTrue);
      expect(back.missingOptionalBlocks, [0x5D]);
    });

    test('rejects CSVs that are not ArcDash dumps', () {
      expect(() => ParameterCsvCodec.decode('a,b,c\n1,2,3\n'),
          throwsFormatException);
    });
  });

  group('diff', () {
    test('identical dumps have no differences', () {
      expect(ParameterDiff.compare(_hebDump(), _hebDump()), isEmpty);
      expect(
          ParameterDiff.compare(_hebDump(), _hebDump(), showAll: true),
          hasLength(FardriverParamCatalog.all.length -
              FardriverParamCatalog.forBlock(0x5D).length));
    });

    test('a changed byte shows the one parameter with old/new values', () {
      final changed = _syntheticHeb();
      changed[3 * 12 + 6] ^= 0xFF; // 0x12 MaxSpeed low byte
      final entries = ParameterDiff.compare(_hebDump(), _hebDump(changed));
      expect(entries, hasLength(1));
      expect(entries.single.def.name, 'MaxSpeed');
      expect(entries.single.change, ParameterChange.changed);
      expect(entries.single.a!.raw, isNot(entries.single.b!.raw));

      final csv = ParameterDiff.toCsv(_hebDump(), _hebDump(changed));
      final rows = FlatCsv.decode(csv);
      final header = rows.indexWhere((r) => r.first == 'change');
      final marker = rows
          .indexWhere((r) => r.first == ParameterCsvCodec.unidentifiedMarker);
      expect(rows[header], ParameterDiff.columns);
      expect(rows.sublist(header + 1, marker), hasLength(1));
      expect(rows[header + 1].first, 'changed');
      expect(marker, rows.length - 1, reason: 'no unidentified changes');
    });

    test('blocks present on one side only are listed as only_a / only_b', () {
      final heb = _hebDump();
      final live = _liveDump({
        ...heb.blocks,
        0x5D: List<int>.filled(12, 1),
      });
      final entries = ParameterDiff.compare(heb, live);
      expect(entries, isNotEmpty);
      expect(entries.every((e) => e.change == ParameterChange.onlyB), isTrue);
      expect(entries.every((e) => e.def.block == 0x5D), isTrue);
    });
  });

  group('v1.1 corrections (real controller frames, issue #2)', () {
    // Raw blocks from a real ND96 controller dump (owner's scooter, app
    // v1.0.191), values checked against the official FarDriver app.
    final real = <int, List<int>>{
      0x06: _hex('00 00 09 0A 16 49 80 00 31 00 E0 C1'),
      0x1E: _hex('40 00 76 02 4E 44 00 50 1A 0A 16 14'),
      0x24: _hex('2C 23 BF 04 B0 04 B8 0B AC 0D FA 00'),
      0x9A: _hex('00 00 00 00 10 16 F8 00 35 00 6A 00'),
      0xB8: _hex('01 80 DD 02 00 00 40 00 52 A8 19 40'),
      0xC4: _hex('00 48 00 5F 00 02 00 02 00 01 00 80'),
      0xCA: _hex('55 00 4B 0B 18 00 00 1A 80 3A 40 00'),
      0xD0: _hex('08 61 00 AB 46 0C 1E 78 A0 0F 29 15'),
    };
    String v(String name, int block) =>
        _decode(name, real[block]!, at: block).value;

    test('LowSpeed is byte 8 (3500 rpm), BackSpeed byte 10 (250 rpm)', () {
      expect(v('LowSpeed', 0x24), '3500');
      expect(v('BackSpeed', 0x24), '250');
      expect(FardriverParamCatalog.byName('LowSpeed').byteOffset, 8);
      expect(FardriverParamCatalog.byName('BackSpeed').byteOffset, 10);
    });

    test('LearnVolLow / LearnVolHigh are u16 (18432 / 24320)', () {
      expect(v('LearnVolLow', 0xC4), '18432');
      expect(v('LearnVolHigh', 0xC4), '24320');
      final overlays =
          FardriverParamCatalog.forBlock(0xC4).where((p) => p.overlay).toList();
      expect(overlays, hasLength(16), reason: 'H72 flag bits kept as overlay');
    });

    test('AN is 5 bits (16) and AlarmRecord_1 is gone', () {
      expect(v('AN', 0x9A), '16');
      expect(FardriverParamCatalog.all.where((p) => p.name == 'AlarmRecord_1'),
          isEmpty);
    });

    test('wheel geometry and GearRatio match the official app', () {
      expect(v('WheelRadius', 0xD0), '12');
      expect(v('WheelRatio', 0xD0), '70');
      expect(v('WheelWidth', 0xD0), '120');
      expect(v('RateRatio', 0xD0), '4000');
      expect(v('GearRatio', 0xD0), '4');
    });

    test('ParkConfig 2 = Disabled, NoCanCnt x2 ms, BackPTime index', () {
      final park = _decode('ParkConfig', real[0x06]!, at: 0x06);
      expect(park.raw, '2');
      expect(park.label, 'Disabled');
      expect(v('NoCanCnt', 0xCA), '150');
      expect(FardriverParamCatalog.byName('NoCanCnt').unit, 'ms');
      final bp = _decode('BackPTime', real[0xB8]!, at: 0xB8);
      expect(bp.raw, '18');
      expect(bp.value, '18');
      expect(bp.label, '240s');
    });

    test('RelayDelay is the u16 at word 0x21 (20480 ms)', () {
      final def = FardriverParamCatalog.byName('RelayDelay');
      expect(def.wordAddress, 0x21);
      expect(def.overlay, isTrue);
      expect(v('RelayDelay', 0x1E), '20480');
    });

    test('official names are display names, internal keys stay stable', () {
      const renames = {
        'CustomMaxLineCurr': 'BoostLineCurr',
        'HighVolProtect': 'OverVolProtect',
        'MosTempProtect': 'ControllerTempProtect',
        'StartKP': 'StartKC',
        'ModelName': 'ProductCode',
        'SppedKP': 'SpeedKP',
        'Data0': 'DATA0',
      };
      renames.forEach((key, display) {
        final def = FardriverParamCatalog.byName(key);
        expect(def.displayName, display);
        expect(def.note, contains('fardriver.hpp name: $key'));
      });
      expect(FardriverParamCatalog.byName('Data0').unknown, isFalse);
    });
  });

  group('csv formats (v1.1 notice + unidentified section)', () {
    test('export has the notice line and a trailing unidentified section', () {
      final csv = ParameterCsvCodec.encode(_hebDump());
      final lines = csv.split('\n');
      expect(lines[1],
          '# notice,Informational only - verify before use. Not affiliated with FarDriver.');
      final marker = lines.indexOf(ParameterCsvCodec.unidentifiedMarker);
      expect(marker, greaterThan(0));
      final main = lines.sublist(0, marker);
      final tail = lines.sublist(marker + 1).where((l) => l.isNotEmpty);
      expect(main.where((l) => l.contains(',unknown,')), isEmpty);
      expect(tail, isNotEmpty);
      expect(tail.every((l) => l.contains(',unknown,')), isTrue);
      expect(
          tail.length,
          FardriverParamCatalog.all
              .where((p) => p.unidentified && p.block != 0x5D)
              .length);
    });

    test('new-format CSV round-trips', () {
      final dump = _hebDump();
      final back = ParameterCsvCodec.decode(ParameterCsvCodec.encode(dump));
      expect(back.blocks, dump.blocks);
    });

    test('old v1.0 CSV (no notice, unknowns interleaved) still parses', () {
      final old =
          File('$_fixtureDir/synthetic_696_v1_0.csv').readAsStringSync();
      expect(old, isNot(contains('# notice')));
      expect(old, isNot(contains('# unidentified')));
      final dump = ParameterDumpIo.parseFile(utf8.encode(old), 'old.csv');
      expect(dump.blocks, _hebDump().blocks);
      expect(ParameterDiff.compare(dump, _hebDump()), isEmpty);
    });

    test('compare old CSV vs new CSV vs HEB shows no differences', () {
      final heb = _hebDump();
      final newer = ParameterCsvCodec.decode(ParameterCsvCodec.encode(heb));
      final old = ParameterCsvCodec.decode(
          File('$_fixtureDir/synthetic_696_v1_0.csv').readAsStringSync());
      expect(ParameterDiff.compare(old, newer), isEmpty);
      expect(ParameterDiff.compare(heb, old), isEmpty);
    });

    test('changed unidentified rows stay in the diff, in their own section',
        () {
      final changed = _syntheticHeb();
      final def = FardriverParamCatalog.all.firstWhere(
          (p) => p.unidentified && p.block != 0x5D && p.bitWidth >= 8);
      final index = HebFile.blockAddresses.indexOf(def.block);
      changed[index * 12 + def.byteOffset] ^= 0xFF;
      final entries = ParameterDiff.compare(_hebDump(), _hebDump(changed));
      expect(entries.any((e) => e.def.unidentified), isTrue);
      final rows =
          FlatCsv.decode(ParameterDiff.toCsv(_hebDump(), _hebDump(changed)));
      final marker = rows
          .indexWhere((r) => r.first == ParameterCsvCodec.unidentifiedMarker);
      expect(rows.sublist(marker + 1).map((r) => r.last), contains('unknown'));
    });
  });

  group('live capture', () {
    test('persists only once every config block was seen', () async {
      final repo = _repository();
      var now = DateTime.utc(2026, 10, 23, 12);
      final capture = ParameterCaptureService(
        repository: repo,
        controllerId: () => 'AA:BB',
        clock: () => now,
        appVersion: 'test',
      );
      final heb = _hebDump();
      final blocks = {...heb.blocks, 0x5D: List<int>.filled(12, 7)};
      const order = FardriverParamCatalog.configBlocks;
      for (final address in order.take(order.length - 1)) {
        capture.addBlock(address, blocks[address]!);
      }
      capture.addBlock(0xE2, List<int>.filled(12, 0)); // telemetry ignored
      await capture.pendingSave;
      expect(capture.latest, isNull);
      expect(await repo.loadComplete(), isNull);

      now = now.add(const Duration(seconds: 1));
      capture.addBlock(order.last, blocks[order.last]!);
      await capture.pendingSave;
      final saved = await repo.loadComplete();
      expect(saved, isNotNull);
      expect(saved!.rawBlocks, blocks);
      final dump = ParameterCaptureService.toDump(saved);
      expect(dump.isComplete, isTrue);
      expect(dump.controllerId, 'AA:BB');
      expect(ParameterCsvCodec.encode(dump), contains('# source,live'));
    });

    test('saves without 0x5D once the capture timeout has passed', () async {
      final repo = _repository();
      final start = DateTime.utc(2026, 10, 23, 12);
      var now = start;
      final capture = ParameterCaptureService(
        repository: repo,
        controllerId: () => 'AA:BB',
        clock: () => now,
        timeout: const Duration(seconds: 5),
      );
      final heb = _hebDump();
      for (final address in FardriverParamCatalog.mandatoryBlocks) {
        capture.addBlock(address, heb.blocks[address]!);
      }
      await capture.pendingSave;
      expect(capture.latest, isNull, reason: 'still waiting for 0x5D');

      now = start.add(const Duration(seconds: 3));
      capture.addBlock(0x00, heb.blocks[0x00]!); // stream keeps rotating
      capture.addBlock(0xE2, List<int>.filled(12, 0));
      await capture.pendingSave;
      expect(capture.latest, isNull);

      now = start.add(const Duration(seconds: 6));
      capture.addBlock(0xE8, List<int>.filled(12, 0)); // telemetry only
      await capture.pendingSave;
      final saved = await repo.loadComplete();
      expect(saved, isNotNull);
      expect(saved!.rawBlocks.containsKey(0x5D), isFalse);
      expect(saved.metadata['missingOptionalBlocks'], [0x5D]);
      final dump = ParameterCaptureService.toDump(saved);
      expect(dump.isComplete, isTrue);
      expect(dump.missingOptionalBlocks, [0x5D]);
      expect(ParameterCsvCodec.encode(dump),
          contains('# missing_optional_blocks,0x5D\n'));

      // 0x5D arriving later replaces the snapshot with the full one.
      now = start.add(const Duration(seconds: 7));
      capture.addBlock(0x5D, List<int>.filled(12, 9));
      await capture.pendingSave;
      final full = await repo.loadComplete();
      expect(full!.rawBlocks[0x5D], List<int>.filled(12, 9));
      expect(
          ParameterCaptureService.toDump(full).missingOptionalBlocks, isEmpty);
    });

    test('never saves while a mandatory block is missing', () async {
      final repo = _repository();
      final start = DateTime.utc(2026, 10, 23, 12);
      var now = start;
      final capture = ParameterCaptureService(
        repository: repo,
        controllerId: () => 'x',
        clock: () => now,
        timeout: const Duration(seconds: 5),
      );
      for (var t = 0; t < 30; t += 2) {
        now = start.add(Duration(seconds: t));
        for (final address in FardriverParamCatalog.configBlocks) {
          if (address == 0xD0) continue;
          capture.addBlock(address, List<int>.filled(12, 1));
        }
        capture.addBlock(0xE2, List<int>.filled(12, 0));
      }
      await capture.pendingSave;
      expect(capture.latest, isNull);
      expect(await repo.loadComplete(), isNull);
    });

    test('reset discards a partial capture', () async {
      final repo = _repository();
      var now = DateTime.utc(2026, 10, 23, 12);
      final capture = ParameterCaptureService(
          repository: repo, controllerId: () => 'x', clock: () => now);
      const order = FardriverParamCatalog.configBlocks;
      for (final address in order.take(10)) {
        capture.addBlock(address, List<int>.filled(12, 1));
      }
      capture.reset();
      now = now.add(const Duration(seconds: 1));
      for (final address in order.skip(10)) {
        capture.addBlock(address, List<int>.filled(12, 1));
      }
      await capture.pendingSave;
      expect(capture.latest, isNull);
      expect(await repo.loadComplete(), isNull);
    });
  });

  group('python tool parity', () {
    final python = Process.runSync('which', ['python3']).exitCode == 0;

    test('fardriver_dump.py selftest passes', () {
      final r =
          Process.runSync('python3', ['tool/fardriver_dump.py', 'selftest']);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    }, skip: python ? false : 'python3 not available');

    test('generated catalog is up to date', () {
      final r =
          Process.runSync('python3', ['tool/gen_param_catalog.py', '--check']);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    }, skip: python ? false : 'python3 not available');

    test('python heb2csv output equals the golden', () {
      final r = Process.runSync('python3', [
        'tool/fardriver_dump.py',
        'heb2csv',
        '$_fixtureDir/synthetic_696.heb',
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(
          r.stdout, File('$_fixtureDir/synthetic_696.csv').readAsStringSync());
    }, skip: python ? false : 'python3 not available');

    test('python log2csv reads the app diagnostic log text export', () {
      final heb = _hebDump();
      final blocks = {...heb.blocks, 0x5D: List<int>.filled(12, 0x5D)};
      final log = DiagnosticLog(
          maxEvents: 200, clock: () => DateTime.utc(2026, 10, 23, 12));
      log.add(DiagnosticEventType.connect, details: {'deviceId': 'x'});
      for (var index = 0; index < flashReadAddr.length; index++) {
        final address = flashReadAddr[index];
        final payload = blocks[address] ?? List<int>.filled(12, 0);
        final packet = [0xAA, 0x80 | index, ...payload, 0, 0];
        log.add(DiagnosticEventType.frame, details: {
          'address': address,
          'length': 16,
          'hex': PacketParser.toHexString(packet),
        });
      }
      final dir = Directory.systemTemp.createTempSync('arcdash_log');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/diag.txt';
      File(path).writeAsStringSync(log.exportAsText());
      final r = Process.runSync('python3', [
        'tool/fardriver_dump.py',
        'log2csv',
        path,
        '--controller-id',
        'AA:BB',
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final dump = ParameterCsvCodec.decode(r.stdout as String);
      expect(dump.blocks, blocks);
      expect(dump.isComplete, isTrue);
      expect(dump.controllerId, 'AA:BB');
    }, skip: python ? false : 'python3 not available');
  });
}

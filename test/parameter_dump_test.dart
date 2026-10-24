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

List<int> _block(Map<int, int> bytes) =>
    List<int>.generate(12, (i) => bytes[i] ?? 0);

ParameterDump _liveDump(Map<int, List<int>> blocks) => ParameterDump(
      source: ParameterDumpSource.live,
      sourceLabel: 'live',
      blocks: blocks,
      requiredBlocks: FardriverParamCatalog.configBlocks,
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

    test('incomplete snapshots are refused', () {
      final blocks = Map.of(_hebDump().blocks);
      final dump = _liveDump(blocks); // no 0x5D
      expect(dump.isComplete, isFalse);
      expect(
          () => ParameterCsvCodec.encode(dump),
          throwsA(isA<IncompleteSnapshotException>()
              .having((e) => e.missingBlocks, 'missing', [0x5D])));
      expect(ParameterCsvCodec.encode(dump, allowIncomplete: true),
          contains('# complete,no'));
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
      expect(rows[header], ParameterDiff.columns);
      expect(rows.sublist(header + 1), hasLength(1));
      expect(rows.last.first, 'changed');
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

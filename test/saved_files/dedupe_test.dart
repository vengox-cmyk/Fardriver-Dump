import 'dart:io';

import 'package:arcdash/services/parameter_csv.dart';
import 'package:arcdash/services/parameter_dump.dart';
import 'package:arcdash/services/saved_files.dart';
import 'package:arcdash/services/saved_files_dedupe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory docs;
  late SavedFilesStore store;

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('farsure_dedupe');
    store = SavedFilesStore(documentsDir: () async => docs);
  });
  tearDown(() => docs.delete(recursive: true));

  final real = ParameterCsvCodec.decode(
      File('test/fixtures/param_dump/farsure_live_20261101.csv')
          .readAsStringSync());

  String dumpCsv(void Function(Map<int, List<int>>) edit, DateTime at) {
    final blocks = {
      for (final e in real.blocks.entries) e.key: [...e.value]
    };
    edit(blocks);
    return ParameterCsvCodec.encode(
        ParameterDump(
          source: real.source,
          sourceLabel: real.sourceLabel,
          blocks: blocks,
          requiredBlocks: real.requiredBlocks,
          optionalBlocks: real.optionalBlocks,
          controllerId: real.controllerId,
          capturedAt: at,
        ),
        allowIncomplete: true);
  }

  Future<void> touch(File f, DateTime t) => f.setLastModified(t);

  test('dumps: same values with another clock are duplicates; oldest kept',
      () async {
    final t0 = DateTime(2026, 11, 1, 10);
    final a =
        await store.write(SavedFileKind.dump, 'a.csv', dumpCsv((_) {}, t0));
    final b = await store.write(SavedFileKind.dump, 'b.csv',
        dumpCsv((m) => m[0x24]![1] = 42, t0.add(const Duration(hours: 1))));
    final c = await store.write(SavedFileKind.dump, 'c.csv',
        dumpCsv((m) => m[0x30]![10] ^= 0x01, t0.add(const Duration(hours: 2))));
    await touch(a, t0);
    await touch(b, t0.add(const Duration(hours: 1)));
    await touch(c, t0.add(const Duration(hours: 2)));

    final entries = await store.list();
    final dupes = await SavedFilesDedupe.findDuplicates(entries);
    expect(dupes.map((e) => e.name), ['b.csv']);
    // Finding never deletes.
    expect(await store.list(), hasLength(3));
  });

  test('other kinds: only identical content counts; kinds never mix', () async {
    await store.write(SavedFileKind.diagnosticLog, 'l1.txt', 'same');
    await store.write(SavedFileKind.diagnosticLog, 'l2.txt', 'same');
    await store.write(SavedFileKind.diagnosticLog, 'l3.txt', 'different');
    await store.write(SavedFileKind.rideCsv, 'r1.csv', 'same');
    final dupes = await SavedFilesDedupe.findDuplicates(await store.list());
    expect(dupes, hasLength(1));
    expect(dupes.single.kind, SavedFileKind.diagnosticLog);
  });
}

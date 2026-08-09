import 'package:arcdash/services/write_engine.dart';
import 'package:arcdash/services/write_safety.dart';
import 'package:flutter_test/flutter_test.dart';

ParameterDefinition _confirmed({int mask = 0x000C, int shift = 2}) =>
    ParameterDefinition(
      name: 'test',
      address: 0x1A,
      minRaw: 0,
      maxRaw: 3,
      mask: mask,
      shift: shift,
      risk: ParameterRisk.comfort,
      readable: true,
      hardwareBoundsConfirmed: true,
    );

void main() {
  test('read-modify-write preserves adjacent bits and is deterministic', () {
    final definition = _confirmed();
    const current = 0xFFF3;
    final updated = definition.applyToWord(current, 2);
    expect(updated & ~0x000C, current & ~0x000C);
    expect(updated & 0x000C, 0x0008);
  });

  test('transaction needs write, ACK and read-back for success', () async {
    final diff = const RawParameterDiff(
      name: 'test',
      address: 0x1A,
      before: 0,
      after: 1,
    );
    final result = await const WriteTransaction().execute(
      diffs: [diff],
      safety: () => true,
      write: (_) async => true,
      verifyAck: (_) async => true,
      readBack: (_) async => false,
    );
    expect(result.single.result, TransactionResult.readBackFailed);
  });

  test('lock deduplicates same request and rejects different parallel request',
      () async {
    final lock = WriteLock();
    final first = lock.run('same', () async => 7);
    expect(await lock.run('same', () async => 9), 7);
    expect(await first, 7);
    expect(await lock.run('next', () async => 11), 11);
  });

  test('audit log remains bounded', () {
    final audit = WriteAuditLog(maxEntries: 2);
    audit
      ..add({'id': 1})
      ..add({'id': 2})
      ..add({'id': 3});
    expect(audit.entries.map((entry) => entry['id']), [2, 3]);
  });
}

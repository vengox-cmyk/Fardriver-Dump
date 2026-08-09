import 'package:arcdash/models/controller_identity.dart';
import 'package:arcdash/services/parameter_snapshot_repository.dart';
import 'package:arcdash/services/stock_backup_repository.dart';
import 'package:arcdash/services/versioned_json_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements AtomicJsonStore {
  String? contents;
  @override
  Future<String?> read() async => contents;
  @override
  Future<void> replace(String value) async => contents = value;
}

PersistedParameterSnapshot _snapshot({
  bool complete = true,
  String binding = 'binding-a',
}) =>
    PersistedParameterSnapshot(
      controller: ControllerIdentity(
        model: 'FD72680',
        hardwareVersion: 'HW1',
        firmwareVersion: '1.2.0',
        functionCode: 'F0',
        extensionCode: 'E1',
        bindingId: binding,
      ),
      requiredAddresses: const {0x12},
      rawBlocks: const {
        0x12: [1, 2, 3]
      },
      metadata: const {},
      source: 'controller-read',
      capturedAt: DateTime.utc(2026, 1, 1),
      complete: complete,
    );

StockBackupRepository _repository(_MemoryStore stock, _MemoryStore history) =>
    StockBackupRepository(
      stock: VersionedJsonRepository(
        store: stock,
        type: 'stock-backup',
        schemaVersion: 1,
      ),
      history: VersionedJsonRepository(
        store: history,
        type: 'stock-backup-history',
        schemaVersion: 1,
      ),
    );

void main() {
  test('saves only the first complete snapshot and reports integrity',
      () async {
    final stock = _MemoryStore();
    final repository = _repository(stock, _MemoryStore());
    expect(await repository.saveInitial(_snapshot(complete: false)), isFalse);
    expect(await repository.saveInitial(_snapshot()), isTrue);
    expect(
        await repository.saveInitial(_snapshot(binding: 'binding-b')), isFalse);
    expect((await repository.load())!.integrityStatus, 'valid');
  });

  test('replacement requires confirmation and preserves history', () async {
    final history = _MemoryStore();
    final repository = _repository(_MemoryStore(), history);
    await repository.saveInitial(_snapshot());
    expect(
      await repository.replaceConfirmed(_snapshot(binding: 'binding-b'),
          confirmed: false),
      isFalse,
    );
    expect(
      await repository.replaceConfirmed(_snapshot(binding: 'binding-b'),
          confirmed: true),
      isTrue,
    );
    final historyPayload = await VersionedJsonRepository(
      store: history,
      type: 'stock-backup-history',
      schemaVersion: 1,
    ).load();
    expect((historyPayload!['entries'] as List), hasLength(1));
  });
}

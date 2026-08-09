import 'package:arcdash/models/controller_identity.dart';
import 'package:arcdash/services/parameter_snapshot_repository.dart';
import 'package:arcdash/services/versioned_json_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements AtomicJsonStore {
  String? contents;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> replace(String value) async => contents = value;
}

ControllerIdentity _controller() => const ControllerIdentity(
      model: 'FD72680',
      hardwareVersion: 'HW1',
      firmwareVersion: '1.2.0',
      functionCode: 'F0',
      extensionCode: 'E1',
      bindingId: 'binding-a',
    );

ParameterSnapshotRepository _repository(
    _MemoryStore complete, _MemoryStore pending) {
  return ParameterSnapshotRepository(
    complete: VersionedJsonRepository(
      store: complete,
      type: 'parameter-snapshot',
      schemaVersion: 1,
    ),
    pending: VersionedJsonRepository(
      store: pending,
      type: 'parameter-snapshot-pending',
      schemaVersion: 1,
    ),
  );
}

PersistedParameterSnapshot _snapshot({bool complete = true}) =>
    PersistedParameterSnapshot(
      controller: _controller(),
      requiredAddresses: const {0x12, 0x18},
      rawBlocks: const {
        0x12: [1, 2, 3],
        0x18: [4, 5, 6],
      },
      metadata: const {'packetCount': 2},
      source: 'controller-read',
      capturedAt: DateTime.utc(2026, 1, 1),
      complete: complete,
    );

void main() {
  test('stores complete snapshots separately and preserves raw bytes',
      () async {
    final complete = _MemoryStore();
    final pending = _MemoryStore();
    final repository = _repository(complete, pending);
    await repository.save(_snapshot());

    final loaded = await repository.loadComplete();
    expect(loaded!.rawBlocks[0x12], [1, 2, 3]);
    expect(loaded.isUsable, isTrue);
    expect(pending.contents, isNull);
  });

  test('never exposes incomplete or tampered data as usable', () async {
    final complete = _MemoryStore();
    final pending = _MemoryStore();
    final repository = _repository(complete, pending);
    await repository.save(_snapshot(complete: false));
    expect(await repository.loadComplete(), isNull);

    await repository.save(_snapshot());
    complete.contents = complete.contents!.replaceFirst('1,2,3', '9,2,3');
    await expectLater(repository.loadComplete(), throwsFormatException);
  });
}

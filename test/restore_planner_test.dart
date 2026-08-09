import 'package:arcdash/models/controller_identity.dart';
import 'package:arcdash/services/parameter_snapshot_repository.dart';
import 'package:arcdash/services/restore_planner.dart';
import 'package:flutter_test/flutter_test.dart';

const identity = ControllerIdentity(
  model: 'FD72680',
  hardwareVersion: 'HW1',
  firmwareVersion: '1.2.0',
  functionCode: 'F0',
  extensionCode: 'E1',
  bindingId: 'binding-a',
);

PersistedParameterSnapshot _snapshot({
  required Map<int, List<int>> blocks,
  ControllerIdentity controller = identity,
}) =>
    PersistedParameterSnapshot(
      controller: controller,
      requiredAddresses: blocks.keys.toSet(),
      rawBlocks: blocks,
      metadata: const {},
      source: 'read',
      capturedAt: DateTime.utc(2026, 1, 1),
      complete: true,
    );

void main() {
  test('identical snapshots produce an empty non-executable plan', () {
    final snapshot = _snapshot(blocks: const {
      0x12: [1, 2, 3]
    });
    final plan = const RestorePlanner().build(
      backup: snapshot,
      current: snapshot,
    );
    expect(plan.isEmpty, isTrue);
    expect(plan.canExecute, isFalse);
  });

  test('creates diffs and flags critical parameter changes', () {
    final plan = const RestorePlanner().build(
      backup: _snapshot(blocks: const {
        0x19: [1, 2, 3]
      }),
      current: _snapshot(blocks: const {
        0x19: [4, 5, 6]
      }),
    );
    expect(plan.changes.single.address, 0x19);
    expect(plan.changes.single.critical, isTrue);
    expect(plan.requiresConfirmation, isTrue);
  });

  test('rejects foreign and incomplete snapshots', () {
    expect(
      () => const RestorePlanner().build(
        backup: _snapshot(blocks: const {
          0x12: [1]
        }),
        current: _snapshot(
          blocks: const {
            0x12: [1]
          },
          controller: const ControllerIdentity(
            model: 'other',
            hardwareVersion: 'HW1',
            firmwareVersion: '1.2.0',
            functionCode: 'F0',
            extensionCode: 'E1',
            bindingId: 'binding-a',
          ),
        ),
      ),
      throwsA(isA<RestorePlanException>().having(
        (error) => error.reason,
        'reason',
        RestoreRejection.incompatibleController,
      )),
    );
  });
}

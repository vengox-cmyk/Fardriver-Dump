import 'package:arcdash/services/snapshot_builder.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _block(int value) => List<int>.filled(12, value);

void main() {
  final start = DateTime.utc(2026, 8, 2, 12);

  test('completes only after every required block is fresh', () {
    final builder =
        ParameterSnapshotBuilder(timeout: const Duration(seconds: 5));
    builder.begin(
      controllerId: 'fixture-a',
      requiredAddresses: {0x12, 0x18, 0xD0},
      at: start,
    );

    builder.addBlock(
        address: 0xD0,
        bytes: _block(1),
        at: start.add(const Duration(seconds: 1)));
    builder.addBlock(
        address: 0x12,
        bytes: _block(2),
        at: start.add(const Duration(seconds: 2)));
    expect(
        builder.snapshot(at: start.add(const Duration(seconds: 2))).isComplete,
        isFalse);
    expect(
        builder
            .snapshot(at: start.add(const Duration(seconds: 2)))
            .missingAddresses,
        {0x18});

    builder.addBlock(
        address: 0x18,
        bytes: _block(3),
        at: start.add(const Duration(seconds: 3)));
    final snapshot =
        builder.snapshot(at: start.add(const Duration(seconds: 3)));
    expect(snapshot.isComplete, isTrue);
    expect(snapshot.progress, 1.0);
    expect(snapshot.blocks[0x12], _block(2));
  });

  test('duplicates replace a block without inflating progress', () {
    final builder = ParameterSnapshotBuilder();
    builder.begin(
        controllerId: 'fixture-a', requiredAddresses: {0x12, 0x18}, at: start);
    builder.addBlock(address: 0x12, bytes: _block(1), at: start);
    builder.addBlock(
        address: 0x12,
        bytes: _block(2),
        at: start.add(const Duration(seconds: 1)));

    final snapshot =
        builder.snapshot(at: start.add(const Duration(seconds: 1)));
    expect(snapshot.progress, 0.5);
    expect(snapshot.blocks[0x12], _block(2));
  });

  test('timeout and controller changes discard old blocks', () {
    final builder =
        ParameterSnapshotBuilder(timeout: const Duration(seconds: 5));
    builder.begin(
        controllerId: 'fixture-a', requiredAddresses: {0x12, 0x18}, at: start);
    builder.addBlock(address: 0x12, bytes: _block(1), at: start);
    expect(
        builder.snapshot(at: start.add(const Duration(seconds: 6))).isTimedOut,
        isTrue);

    builder.begin(
        controllerId: 'fixture-b',
        requiredAddresses: {0x12, 0x18},
        at: start.add(const Duration(seconds: 7)));
    final snapshot =
        builder.snapshot(at: start.add(const Duration(seconds: 7)));
    expect(snapshot.controllerId, 'fixture-b');
    expect(snapshot.blocks, isEmpty);
    expect(snapshot.missingAddresses, {0x12, 0x18});
  });
}

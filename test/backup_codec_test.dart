import 'dart:io';

import 'package:arcdash/models/controller_identity.dart';
import 'package:arcdash/services/backup_codec.dart';
import 'package:arcdash/services/parameter_snapshot_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const controller = ControllerIdentity(
  model: 'FD72680',
  hardwareVersion: 'HW1',
  firmwareVersion: '1.2.0',
  functionCode: 'F0',
  extensionCode: 'E1',
  bindingId: 'binding-a',
);

PersistedParameterSnapshot snapshot() => PersistedParameterSnapshot(
      controller: controller,
      requiredAddresses: const {0x12},
      rawBlocks: const {
        0x12: [1, 2, 3]
      },
      metadata: const {'source': 'read'},
      source: 'controller-read',
      capturedAt: DateTime.utc(2026, 1, 1),
      complete: true,
    );

void main() {
  test('JSON export/import is byte-exact and controller-bound', () {
    final contents = BackupCodec.encode(snapshot());
    final restored =
        BackupCodec.decode(contents, expectedController: controller);
    expect(restored.rawBlocks[0x12], [1, 2, 3]);
    expect(BackupCodec.encode(restored), contents);
  });

  test('rejects malformed, tampered, unknown, and foreign backups', () {
    expect(() => BackupCodec.decode('{'), throwsFormatException);
    expect(
        () => BackupCodec.decode('{"format":"other"}'), throwsFormatException);
    final tampered =
        BackupCodec.encode(snapshot()).replaceFirst('1,2,3', '9,2,3');
    expect(() => BackupCodec.decode(tampered), throwsFormatException);
    expect(
      () => BackupCodec.decode(
        BackupCodec.encode(snapshot()),
        expectedController: controller.copyWithBinding('binding-b'),
      ),
      throwsFormatException,
    );
  });

  test('does not import HEB files', () async {
    final directory = await Directory.systemTemp.createTemp('arcdash-backup-');
    final file = File('${directory.path}/controller.heb')
      ..writeAsStringSync('x');
    expect(const BackupFileService().importFile(file), throwsFormatException);
    await directory.delete(recursive: true);
  });
}

extension on ControllerIdentity {
  ControllerIdentity copyWithBinding(String value) => ControllerIdentity(
        model: model,
        hardwareVersion: hardwareVersion,
        firmwareVersion: firmwareVersion,
        functionCode: functionCode,
        extensionCode: extensionCode,
        bindingId: value,
      );
}

import 'dart:io';

import 'package:arcdash/services/versioned_json_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('writes a versioned document atomically and round-trips payload',
      () async {
    final directory = await Directory.systemTemp.createTemp('arcdash-repo-');
    final file = File('${directory.path}/snapshot.json');
    final repository = VersionedJsonRepository(
      store: AtomicJsonFileStore(file),
      type: 'parameter-snapshot',
      schemaVersion: 1,
    );

    await repository.save({
      'bytes': [1, 2, 3],
      'complete': true
    });
    expect(await repository.load(), {
      'bytes': [1, 2, 3],
      'complete': true,
    });
    expect(await File('${file.path}.tmp').exists(), isFalse);
    await directory.delete(recursive: true);
  });

  test('rejects unknown schema and never silently migrates it', () async {
    final directory = await Directory.systemTemp.createTemp('arcdash-repo-');
    final file = File('${directory.path}/snapshot.json');
    await file.writeAsString(
        '{"type":"parameter-snapshot","schemaVersion":2,"payload":{}}');
    final repository = VersionedJsonRepository(
      store: AtomicJsonFileStore(file),
      type: 'parameter-snapshot',
      schemaVersion: 1,
    );

    await expectLater(repository.load(), throwsFormatException);
    await directory.delete(recursive: true);
  });
}

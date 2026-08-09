import 'dart:convert';
import 'dart:io';

import 'package:arcdash/models/controller_identity.dart';
import 'package:arcdash/services/parameter_snapshot_repository.dart';

class BackupCodec {
  static const format = 'arcdash-backup-v1';

  static String encode(PersistedParameterSnapshot snapshot) {
    if (!snapshot.isUsable) {
      throw const FormatException('only complete snapshots can be exported');
    }
    return jsonEncode({
      'format': format,
      'schemaVersion': 1,
      'snapshot': snapshot.toPayload(),
    });
  }

  static PersistedParameterSnapshot decode(
    String contents, {
    ControllerIdentity? expectedController,
  }) {
    final decoded = jsonDecode(contents);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != format ||
        decoded['schemaVersion'] != 1 ||
        decoded['snapshot'] is! Map) {
      throw const FormatException('unsupported ArcDash backup format');
    }
    final snapshot = PersistedParameterSnapshot.fromPayload(
      Map<String, Object?>.from(decoded['snapshot'] as Map),
    );
    if (!snapshot.isUsable) {
      throw const FormatException('backup is incomplete or corrupted');
    }
    if (expectedController != null &&
        snapshot.controller.compare(expectedController) ==
            ControllerCompatibility.incompatible) {
      throw const FormatException('backup belongs to another controller');
    }
    return snapshot;
  }
}

class BackupFileService {
  const BackupFileService();

  Future<void> exportFile(
      File file, PersistedParameterSnapshot snapshot) async {
    final temporary = File('${file.path}.tmp');
    await file.parent.create(recursive: true);
    await temporary.writeAsString(BackupCodec.encode(snapshot), flush: true);
    await temporary.rename(file.path);
  }

  Future<PersistedParameterSnapshot> importFile(
    File file, {
    ControllerIdentity? expectedController,
  }) async {
    if (file.path.toLowerCase().endsWith('.heb')) {
      throw const FormatException(
          'HEB import is disabled until T016 is proven');
    }
    return BackupCodec.decode(
      await file.readAsString(),
      expectedController: expectedController,
    );
  }
}

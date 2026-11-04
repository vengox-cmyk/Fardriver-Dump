import 'dart:async';
import 'dart:io';

import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/saved_files_provider.dart';
import 'package:arcdash/providers/stats_provider.dart';
import 'package:arcdash/services/bluetooth_service.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/services/saved_files.dart';
import 'package:arcdash/services/storage_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('connecting a controller never starts a ride recording', () async {
    SharedPreferences.setMockInitialValues({});
    final docs = await Directory.systemTemp.createTemp('farsure_noauto_');
    final conn = StreamController<DongleConnectionState>.broadcast();
    final c = ProviderContainer(overrides: [
      savedFilesStoreProvider
          .overrideWithValue(SavedFilesStore(documentsDir: () async => docs)),
      storageServiceProvider.overrideWithValue(StorageService()),
      connectionStateProvider.overrideWith((ref) => conn.stream),
    ]);
    c.listen(connectionStateProvider, (_, __) {});
    c.listen(statsProvider, (_, __) {});
    for (final s in [
      DongleConnectionState.connecting,
      DongleConnectionState.connected,
      DongleConnectionState.disconnected,
      DongleConnectionState.connected,
    ]) {
      conn.add(s);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.read(statsProvider.notifier).isRecording, isFalse,
          reason: 'after $s');
      expect(c.read(statsProvider).currentSession, isNull);
    }
    c.dispose();
    await conn.close();
    await docs.delete(recursive: true);
  });
}

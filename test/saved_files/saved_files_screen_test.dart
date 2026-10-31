import 'dart:io';

import 'package:arcdash/l10n/app_strings.dart';
import 'package:arcdash/models/gps_calibration.dart';
import 'package:arcdash/models/speed_suggestions.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/saved_files_provider.dart';
import 'package:arcdash/screens/saved_files_screen.dart';
import 'package:arcdash/services/calibration_csv.dart';
import 'package:arcdash/services/calibration_settings.dart';
import 'package:arcdash/services/saved_files.dart';
import 'package:arcdash/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../calibration/ride_fixtures.dart';

Widget _app(SavedFilesStore store) => ProviderScope(
      overrides: [
        savedFilesStoreProvider.overrideWithValue(store),
        storageServiceProvider.overrideWithValue(StorageService()),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: [
          AppStrings.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: SavedFilesScreen(),
      ),
    );

String _calibrationCsv() {
  final samples = ride([
    ...steadyLegs(8, [30, 50, 70])
  ]);
  final analysis = const CalibrationAnalyzer().analyze(samples);
  return CalibrationCsv.build(
    samples: samples,
    analysis: analysis,
    fit: CalibrationFit.fromAnalysis(analysis),
    dkdSnapshots: const [],
    settings: const CalibrationSettings(
      ble: BleSpeedSettings(
          wheelRadius: 12, wheelWidth: 120, wheelRatio: 70, rateRatio: 4000),
      speedPulses: 11,
      spdPulseNum: null,
      source: 'test',
    ),
    appVersion: '1.2.1',
    exportedAt: t0,
    startedAt: samples.first.at,
    stoppedAt: samples.last.at,
    controllerId: 'AA:BB',
    status: CalibrationCsv.statusStopped,
  );
}

void main() {
  late Directory docs;
  late SavedFilesStore store;

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('farsure_screen_');
    store = SavedFilesStore(documentsDir: () async => docs);
  });

  tearDown(() async {
    if (await docs.exists()) await docs.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    // Real file I/O completes outside the fake clock: alternate real waits
    // and pumps until the list (or the reopened screen) has loaded.
    for (var i = 0; i < 300; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
      if (i > 40 && find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }
  }

  testWidgets('empty state', (tester) async {
    await tester.pumpWidget(_app(store));
    await settle(tester);
    expect(find.byKey(const ValueKey('saved-files-empty')), findsOneWidget);
  });

  testWidgets('lists by type, reopens a calibration, deletes with confirm',
      (tester) async {
    await tester.runAsync(() async {
      await store.write(SavedFileKind.calibration,
          'calibration_20261024_120000.csv', _calibrationCsv());
      await store.write(
          SavedFileKind.diagnosticLog, 'diagnostic_1.txt', 'hello log');
    });
    await tester.pumpWidget(_app(store));
    await settle(tester);

    expect(find.byKey(const ValueKey('saved-section-calibration')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('saved-section-diagnosticLog')),
        findsOneWidget);
    const row = ValueKey('saved-file-calibration_20261024_120000.csv');
    expect(find.byKey(row), findsOneWidget);

    // Reopen the calibration results, read-only, without a controller.
    await tester.tap(find.byKey(row));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('saved-calibration-banner')), findsOneWidget);
    await tester.pageBack();
    await settle(tester);
    await tester.pumpAndSettle();

    // Delete → cancel keeps it; confirm removes it.
    const del = ValueKey('saved-delete-diagnostic_1.txt');
    await tester.ensureVisible(find.byKey(del));
    await tester.tap(find.byKey(del));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('saved-delete-cancel')));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => store.list()), hasLength(2));

    await tester.tap(find.byKey(del));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('saved-delete-confirm')));
    await settle(tester);
    expect(await tester.runAsync(() => store.list()), hasLength(1));
    expect(find.byKey(const ValueKey('saved-file-diagnostic_1.txt')),
        findsNothing);

    // Delete all sits behind its own confirmation.
    await tester.tap(find.byKey(const ValueKey('saved-delete-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('saved-delete-confirm')));
    await settle(tester);
    expect(await tester.runAsync(() => store.list()), isEmpty);
    expect(find.byKey(const ValueKey('saved-files-empty')), findsOneWidget);
  });
}

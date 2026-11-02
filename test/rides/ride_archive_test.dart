import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arcdash/l10n/app_strings.dart';
import 'package:arcdash/models/ride_stats.dart';
import 'package:arcdash/providers/rides_provider.dart';
import 'package:arcdash/providers/saved_files_provider.dart';
import 'package:arcdash/screens/ride_detail_screen.dart';
import 'package:arcdash/services/parameter_dump_io.dart';
import 'package:arcdash/services/ride_archive.dart';
import 'package:arcdash/services/saved_files.dart';
import 'package:arcdash/utils/speed_units.dart';

import 'ride_test_helpers.dart';

RideSession _session(DateTime start, {double km = 4, int samples = 3}) {
  final s =
      RideSession(id: '${start.millisecondsSinceEpoch}', startTime: start);
  for (var i = 0; i < samples; i++) {
    s.addSample(
        speedKph: 40,
        voltageV: 80,
        currentA: 30,
        deltaTimeSeconds: 1,
        motorTempC: 60);
  }
  s.distanceKm = km;
  s.endTime = start.add(const Duration(minutes: 12));
  return s;
}

void main() {
  late Directory docs;
  late SavedFilesStore store;
  late RideArchive archive;
  final day1 = DateTime(2026, 10, 31, 9, 0);
  final day2 = DateTime(2026, 11, 1, 9, 0);

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('farsure_rides_');
    store = SavedFilesStore(documentsDir: () async => docs);
    archive = RideArchive(store, appVersion: () async => '1.2.4');
  });

  tearDown(() async {
    if (await docs.exists()) await docs.delete(recursive: true);
  });

  Future<void> seedTwoRides() async {
    await ParameterDumpIo.saveDump(store,
        testDump(maxLineA: 200, at: day1.subtract(const Duration(hours: 1))),
        appVersion: '1.2.4', now: day1.subtract(const Duration(hours: 1)));
    expect(await archive.save(_session(day1)), isNotNull);
    await ParameterDumpIo.saveDump(store,
        testDump(maxLineA: 240, at: day2.subtract(const Duration(hours: 1))),
        appVersion: '1.2.4', now: day2.subtract(const Duration(hours: 1)));
    expect(await archive.save(_session(day2)), isNotNull);
  }

  test('saves record + CSV, links the settings snapshot, finds previous',
      () async {
    await seedTwoRides();
    final records = await archive.listRecords();
    expect(records, hasLength(2));
    final newest = await RideArchive.load(records.first.file);
    expect(newest.start, day2);
    expect(newest.appVersion, '1.2.4');
    expect(newest.csvFile, 'arcdash_ride_${day2.millisecondsSinceEpoch}.csv');
    final dump = await archive.loadDump(newest.settingsDump);
    expect(dump, isNotNull);

    final prev = await archive.previousOf(newest);
    expect(prev!.start, day1);
    expect(prev.settingsDump, isNot(newest.settingsDump));
    expect(await archive.previousOf(prev), isNull);

    // the linked ride CSVs are folded into their records in the Rides list
    final all = [
      for (final k in RidesListing.kinds) ...await store.list(kind: k)
    ];
    final listing = RidesListing.from(all);
    expect(listing.entries.map((e) => e.kind),
        everyElement(SavedFileKind.rideRecord));
    expect(listing.recordIds,
        {'${day1.millisecondsSinceEpoch}', '${day2.millisecondsSinceEpoch}'});
  });

  test('skips very short rides and never throws', () async {
    final short = RideSession(id: 'x', startTime: day1)
      ..endTime = day1.add(const Duration(seconds: 20));
    expect(await archive.save(short), isNull);
    final broken = RideArchive(
        SavedFilesStore(
            documentsDir: () async => throw const FileSystemException('no')),
        appVersion: () async => '1');
    expect(await broken.save(_session(day1)), isNull);
  });

  test('detail data diffs settings against the previous ride', () async {
    await seedTwoRides();
    final records = await archive.listRecords();
    final data =
        await RideDetailData.load(store, records.first.file, SpeedUnit.kmh);
    expect(data.previous, isNotNull);
    expect(data.diff!.changes.map((c) => c.def.name), ['MaxLineCurr']);
    expect(data.suggestions.first, startsWith('Settings changed'));
    expect(data.aiText, contains('200 A -> 240 A'));
  });

  testWidgets('ride detail shows sections, disclaimer and copies for AI',
      (tester) async {
    late File file;
    await tester.runAsync(() async {
      await seedTwoRides();
      file = (await archive.listRecords()).first.file;
    });
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(ProviderScope(
      overrides: [savedFilesStoreProvider.overrideWithValue(store)],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: RideDetailScreen(file: file, unit: SpeedUnit.mph),
      ),
    ));
    for (var i = 0; i < 300; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
      if (find.byKey(const ValueKey('ride-copy-ai')).evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.byKey(const ValueKey('ride-view-settings')), findsOneWidget);
    expect(find.textContaining('Max line (battery) current'), findsWidgets);
    expect(find.byKey(const ValueKey('ride-disclaimer')), findsOneWidget);
    final copy = find.byKey(const ValueKey('ride-copy-ai'));
    await tester.ensureVisible(copy);
    await tester.pump();
    await tester.tap(copy);
    await tester.pump();
    expect(copied, contains('Suggestions only'));
    expect(copied, contains('mph'));
  });
}

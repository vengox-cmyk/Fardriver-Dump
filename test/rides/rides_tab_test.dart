import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arcdash/l10n/app_strings.dart';
import 'package:arcdash/models/ride_stats.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/saved_files_provider.dart';
import 'package:arcdash/screens/ride_detail_screen.dart';
import 'package:arcdash/screens/stats_screen.dart';
import 'package:arcdash/services/ride_archive.dart';
import 'package:arcdash/services/saved_files.dart';
import 'package:arcdash/services/storage_service.dart';

import 'ride_test_helpers.dart';

void main() {
  late Directory docs;
  late SavedFilesStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    docs = await Directory.systemTemp.createTemp('farsure_tab_');
    store = SavedFilesStore(documentsDir: () async => docs);
  });

  tearDown(() async {
    if (await docs.exists()) await docs.delete(recursive: true);
  });

  Widget app() => ProviderScope(
        overrides: [
          savedFilesStoreProvider.overrideWithValue(store),
          storageServiceProvider.overrideWithValue(StorageService()),
          connectionStateProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: [
            AppStrings.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Scaffold(body: StatsScreen()),
        ),
      );

  Future<void> settle(WidgetTester tester, Finder until) async {
    for (var i = 0; i < 300; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
      if (until.evaluate().isNotEmpty) break;
    }
  }

  testWidgets('empty Rides tab says nothing is saved yet', (tester) async {
    await tester.pumpWidget(app());
    final none = find.byKey(const ValueKey('rides-none-saved'));
    await settle(tester, none);
    expect(none, findsOneWidget);
  });

  testWidgets('lists saved rides offline and opens one', (tester) async {
    final start = DateTime(2026, 11, 1, 9, 0);
    await tester.runAsync(() async {
      final s = RideSession(id: 'r1', startTime: start, distanceKm: 6)
        ..endTime = start.add(const Duration(minutes: 15));
      await RideArchive(store, appVersion: () async => 't').save(s);
    });
    await tester.pumpWidget(app());
    final tile =
        find.byKey(ValueKey('ride-entry-${RideArchive.recordFileName(start)}'));
    await settle(tester, tile);
    expect(tile, findsOneWidget);
    // its CSV is folded into the record, not listed separately
    expect(
        find.byKey(ValueKey(
            'ride-entry-arcdash_ride_${start.millisecondsSinceEpoch}.csv')),
        findsNothing);

    await tester.ensureVisible(tile);
    await tester.pump();
    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(RideDetailScreen), findsOneWidget);
  });

  testWidgets('long histories load in pages', (tester) async {
    final base = DateTime(2026, 9, 1, 8, 0);
    await tester.runAsync(() async {
      for (var i = 0; i < 25; i++) {
        final start = base.add(Duration(days: i));
        await store.write(SavedFileKind.rideRecord,
            RideArchive.recordFileName(start), testRide(start: start).encode());
      }
    });
    await tester.pumpWidget(app());
    final more = find.byKey(const ValueKey('rides-show-more'));
    final newest = find.byKey(ValueKey(
        'ride-entry-${RideArchive.recordFileName(base.add(const Duration(days: 24)))}'));
    await settle(tester, newest);
    expect(newest, findsOneWidget);
    // only the first page is in the list: scroll to its end
    await tester.scrollUntilVisible(more, 300,
        scrollable: find.descendant(
            of: find.byKey(const ValueKey('rides-scroll')),
            matching: find.byType(Scrollable)));
    expect(more, findsOneWidget);
    await tester.tap(more);
    await tester.pump();
    expect(more, findsNothing);
  });
}

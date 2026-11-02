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
import 'package:arcdash/providers/stats_provider.dart';
import 'package:arcdash/screens/stats_screen.dart';
import 'package:arcdash/services/parameter_dump_io.dart';
import 'package:arcdash/services/ride_archive.dart';
import 'package:arcdash/services/saved_files.dart';
import 'package:arcdash/services/storage_service.dart';

import 'ride_test_helpers.dart';

class _FakeKeepAlive extends RideKeepAlive {
  int starts = 0;
  int stops = 0;
  @override
  Future<void> start() async => starts++;
  @override
  Future<void> stop() async => stops++;
}

void main() {
  late Directory docs;
  late SavedFilesStore store;
  late RideArchive archive;
  late _FakeKeepAlive keepAlive;
  LiveRideSample? live;

  setUpAll(() => StatsNotifier.sampleEvery = const Duration(hours: 1));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    docs = await Directory.systemTemp.createTemp('farsure_manual_');
    store = SavedFilesStore(documentsDir: () async => docs);
    archive = RideArchive(store, appVersion: () async => 't');
    keepAlive = _FakeKeepAlive();
    live = const LiveRideSample(speedKph: 36, voltageV: 84, currentA: 0);
  });

  tearDown(() async {
    if (await docs.exists()) await docs.delete(recursive: true);
  });

  List<Override> overrides() => [
        savedFilesStoreProvider.overrideWithValue(store),
        storageServiceProvider.overrideWithValue(StorageService()),
        connectionStateProvider.overrideWith((ref) => const Stream.empty()),
        rideKeepAliveProvider.overrideWithValue(keepAlive),
        liveRideSampleProvider.overrideWithValue((_) => live),
      ];

  Future<List<String>> csvLines() async {
    final dir = await store.directoryFor(SavedFileKind.rideCsv);
    final files = dir.listSync().whereType<File>().toList();
    expect(files, hasLength(1));
    return (await files.single.readAsString())
        .split('\r\n')
        .where((l) => l.isNotEmpty)
        .toList();
  }

  Future<Map<String, String>> recordInfo() async {
    final records = await archive.listRecords();
    expect(records, hasLength(1));
    return records.single.info;
  }

  test('nothing records until Start; Stop saves even a tiny ride', () async {
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    final n = c.read(statsProvider.notifier);
    n.sampleNow();
    expect(c.read(statsProvider).currentSession, isNull);
    expect(await archive.listRecords(), isEmpty);

    await n.startRide();
    expect(c.read(statsProvider).isTracking, isTrue);
    expect(keepAlive.starts, 1);
    await n.stopRide();
    expect(c.read(statsProvider).currentSession, isNull);
    expect(keepAlive.stops, 1);
    final info = await recordInfo();
    expect(info['finished'], 'true');
    expect(await csvLines(), [RideSession.csvHeader.join(',')]);
  });

  test('streams samples past 500, checkpoints unfinished, Stop finishes',
      () async {
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    final n = c.read(statsProvider.notifier);
    await n.startRide();
    final session = c.read(statsProvider).currentSession!;
    expect((await recordInfo())['finished'], 'false');

    for (var i = 0; i < 650; i++) {
      n.sampleNow(session.startTime.add(Duration(seconds: i + 1)));
    }
    await n.checkpointNow();
    expect(await csvLines(), hasLength(651));
    expect((await recordInfo())['finished'], 'false');
    expect(session.sampleCount, 650);
    expect(session.speedHistory, hasLength(RideSession.chartSamples));

    n.sampleNow(session.startTime.add(const Duration(seconds: 651)));
    await n.stopRide();
    expect(await csvLines(), hasLength(652));
    final info = await recordInfo();
    expect(info['finished'], 'true');
    // 650 s at 36 km/h = 6.5 km (first sample has no delta).
    expect(double.parse(info['distanceKm']!), closeTo(6.5, 0.01));
  });

  test('a Bluetooth drop keeps the ride and invents no distance', () async {
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    final n = c.read(statsProvider.notifier);
    await n.startRide();
    final session = c.read(statsProvider).currentSession!;
    DateTime t(int s) => session.startTime.add(Duration(seconds: s));

    for (var i = 1; i <= 11; i++) {
      n.sampleNow(t(i));
    }
    final before = session.distanceKm;
    expect(before, closeTo(0.1, 1e-6));

    live = null; // disconnected for 60 s
    for (var i = 12; i < 72; i++) {
      n.sampleNow(t(i));
    }
    expect(c.read(statsProvider).currentSession, same(session));
    expect(c.read(statsProvider).waitingForController, isTrue);
    expect(session.distanceKm, before);

    live = const LiveRideSample(speedKph: 36, voltageV: 84, currentA: 0);
    n.sampleNow(t(72)); // reconnect: no delta across the gap
    expect(session.distanceKm, before);
    expect(c.read(statsProvider).waitingForController, isFalse);
    n.sampleNow(t(73));
    expect(session.distanceKm, closeTo(before + 0.01, 1e-6));

    await n.stopRide();
    expect(await csvLines(), hasLength(1 + 13));
  });

  test('a crash leaves a saved, unfinished ride', () async {
    final c = ProviderContainer(overrides: overrides());
    final n = c.read(statsProvider.notifier);
    await n.startRide();
    final session = c.read(statsProvider).currentSession!;
    for (var i = 1; i <= 20; i++) {
      n.sampleNow(session.startTime.add(Duration(seconds: i)));
    }
    await n.checkpointNow();
    c.dispose(); // app killed: no Stop
    final records = await archive.listRecords();
    final ride = await RideArchive.load(records.single.file);
    expect(ride.finished, isFalse);
    expect(await csvLines(), hasLength(21));
  });

  test('snapshot: a dump read within 2 minutes after Start is used', () async {
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    final n = c.read(statsProvider.notifier);
    await n.startRide();
    final start = c.read(statsProvider).currentSession!.startTime;
    final at = start.add(const Duration(seconds: 30));
    await ParameterDumpIo.saveDump(store, testDump(at: at),
        appVersion: 't', now: at);
    await n.stopRide();
    final ride =
        await RideArchive.load((await archive.listRecords()).single.file);
    expect(ride.settingsDump, isNotNull);
  });

  group('Rides tab', () {
    Widget app() => ProviderScope(
          overrides: overrides(),
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

    testWidgets('Start shows recording + elapsed; Stop asks, then saves',
        (tester) async {
      await tester.pumpWidget(app());
      expect(find.byIcon(Icons.refresh_outlined), findsNothing);
      await tester.tap(find.byKey(const ValueKey('ride-start')));
      final rec = find.byKey(const ValueKey('ride-recording'));
      await settle(tester, rec);
      expect(rec, findsOneWidget);
      expect(find.byKey(const ValueKey('ride-elapsed')), findsOneWidget);
      expect(find.text('0:00:00'), findsOneWidget);

      // The in-progress record is listed and marked as recording.
      final recBadge = find.textContaining('recording');
      for (var i = 0; i < 100 && recBadge.evaluate().isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.drag(
            find.byKey(const ValueKey('rides-scroll')), const Offset(0, -200));
        await tester.pump();
      }
      expect(recBadge, findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('ride-stop')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('ride-stop')));
      await tester.pumpAndSettle();
      expect(find.text('Stop and save this ride?'), findsOneWidget);
      await tester.tap(find.text('Keep recording'));
      await tester.pumpAndSettle();
      expect(rec, findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('ride-stop')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ride-stop-confirm')));
      final start = find.byKey(const ValueKey('ride-start'));
      await settle(tester, start);
      expect(start, findsOneWidget);
      String? finished;
      for (var i = 0; i < 200 && finished != 'true'; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          finished = (await archive.listRecords()).single.info['finished'];
        });
        await tester.pump();
      }
      expect(finished, 'true');
    });

    testWidgets('shows the controller-lost note while recording',
        (tester) async {
      live = null;
      await tester.pumpWidget(app());
      await tester.tap(find.byKey(const ValueKey('ride-start')));
      final note = find.byKey(const ValueKey('ride-waiting-controller'));
      await settle(tester, note);
      expect(note, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ride-stop')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ride-stop-confirm')));
      await settle(tester, find.byKey(const ValueKey('ride-start')));
    });

    testWidgets('an unfinished saved ride carries a badge', (tester) async {
      final start = DateTime(2026, 11, 1, 9, 0);
      await tester.runAsync(() async {
        final s = RideSession(id: 'u1', startTime: start, distanceKm: 2)
          ..endTime = start.add(const Duration(minutes: 5));
        await archive.writeRecord(s,
            csvName: RideArchive.csvFileName(start),
            snapshot: (name: null, controllerId: ''),
            finished: false);
      });
      await tester.pumpWidget(app());
      final badge = find
          .byKey(ValueKey('ride-badge-${RideArchive.recordFileName(start)}'));
      await settle(tester, badge);
      expect(badge, findsOneWidget);
      expect(find.textContaining('unfinished'), findsOneWidget);
    });
  });
}

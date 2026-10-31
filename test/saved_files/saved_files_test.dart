import 'dart:async';
import 'dart:io';

import 'package:arcdash/models/app_settings.dart';
import 'package:arcdash/models/controller_state.dart';
import 'package:arcdash/models/gps_calibration.dart';
import 'package:arcdash/models/speed_suggestions.dart';
import 'package:arcdash/services/calibration_archive.dart';
import 'package:arcdash/services/calibration_csv.dart';
import 'package:arcdash/services/calibration_settings.dart';
import 'package:arcdash/services/dump_archive.dart';
import 'package:arcdash/services/gps_calibration_session.dart';
import 'package:arcdash/services/heb_file_parser.dart';
import 'package:arcdash/services/parameter_capture.dart';
import 'package:arcdash/services/parameter_csv.dart';
import 'package:arcdash/services/parameter_dump.dart';
import 'package:arcdash/services/parameter_dump_io.dart';
import 'package:arcdash/services/parameter_snapshot_repository.dart';
import 'package:arcdash/services/saved_files.dart';
import 'package:arcdash/utils/speed_units.dart';
import 'package:flutter_test/flutter_test.dart';

import '../calibration/calibration_session_test.dart' show FakeGps, fix;
import '../calibration/ride_fixtures.dart';

const _settings = CalibrationSettings(
  ble: BleSpeedSettings(
      wheelRadius: 12, wheelWidth: 120, wheelRatio: 70, rateRatio: 4000),
  speedPulses: 11,
  spdPulseNum: 38050,
  source: 'snapshot 2026-10-24',
);

ParameterDump _hebDump() => ParameterDump.fromHeb(
      HebFile.parse(List<int>.generate(
          HebFile.expectedLength, (i) => (i * 37 + 11) & 0xFF)),
      fileName: 'synthetic_696.heb',
      appVersion: 'test',
    );

CalibrationSessionState _stoppedRide({List<DkdSnapshot>? dkd}) {
  final samples = ride([
    ...steadyLegs(8, [30, 50, 70]),
    const Leg(3, 15)
  ]);
  final analysis = const CalibrationAnalyzer().analyze(samples);
  return CalibrationSessionState(
    status: CalibrationStatus.stopped,
    startedAt: samples.first.at,
    stoppedAt: samples.last.at.add(const Duration(seconds: 1)),
    samples: samples,
    analysis: analysis,
    fit: CalibrationFit.fromAnalysis(analysis),
    dkdSnapshots: dkd ??
        [
          DkdSnapshot(
              at: t0.add(const Duration(seconds: 5)),
              rpm: 2244.25,
              gpsKph: 50.125,
              controllerKph: 51,
              dkdKph: 51.5),
        ],
  );
}

void main() {
  late Directory docs;
  late SavedFilesStore store;

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('farsure_saved_');
    store = SavedFilesStore(documentsDir: () async => docs);
  });

  tearDown(() async {
    if (await docs.exists()) await docs.delete(recursive: true);
  });

  group('SavedFilesStore', () {
    test('writes into farsure/<kind>/ and lists newest first by type',
        () async {
      final a = await store.write(
          SavedFileKind.diagnosticLog, 'diagnostic_20261030_100000.txt', 'old');
      await a.setLastModified(DateTime(2026, 10, 30, 10));
      final b = await store.write(
          SavedFileKind.diagnosticLog, 'diagnostic_20261031_100000.txt', 'new');
      await b.setLastModified(DateTime(2026, 10, 31, 10));
      await store.write(SavedFileKind.dump, 'x.csv', '');
      // A leftover temp file of an interrupted write is never listed.
      await File('${docs.path}/farsure/logs/broken.txt.tmp')
          .writeAsString('half');
      // Ride CSVs from older versions in the documents root are found too.
      await File('${docs.path}/arcdash_ride_1730000000000.csv')
          .writeAsString('t,v');

      expect(
          a.path, '${docs.path}/farsure/logs/diagnostic_20261030_100000.txt');
      final logs = await store.list(kind: SavedFileKind.diagnosticLog);
      expect(logs.map((e) => e.name), [
        'diagnostic_20261031_100000.txt',
        'diagnostic_20261030_100000.txt',
      ]);
      expect(logs.first.sizeBytes, 3);
      final all = await store.list();
      expect(all.map((e) => e.kind).toSet(), {
        SavedFileKind.diagnosticLog,
        SavedFileKind.dump,
        SavedFileKind.rideCsv,
      });
      expect(all, hasLength(4));
    });

    test('overwrite keeps one file; delete and delete all', () async {
      await store.write(SavedFileKind.calibration, 'c.csv', 'one');
      await store.write(SavedFileKind.calibration, 'c.csv', 'two');
      var all = await store.list();
      expect(all, hasLength(1));
      expect(await all.single.file.readAsString(), 'two');

      await store.write(SavedFileKind.dump, 'd.csv', 'd');
      all = await store.list();
      await store.delete(all.firstWhere((e) => e.name == 'c.csv'));
      expect((await store.list()).map((e) => e.name), ['d.csv']);

      await store.write(SavedFileKind.diagnosticLog, 'l.txt', 'l');
      expect(await store.deleteAll(), 2);
      expect(await store.list(), isEmpty);
    });

    test('unsafe names are sanitised', () async {
      final f = await store.write(SavedFileKind.dump, '../evil:name.csv', 'x');
      expect(f.parent.path, '${docs.path}/farsure/dumps');
    });

    test('stamp is local time', () {
      expect(SavedFilesStore.stamp(DateTime(2026, 10, 31, 15, 4, 5)),
          '20261031_150405');
    });
  });

  group('calibration files', () {
    test('build → parse round trip reproduces the fit and suggestions', () {
      final session = _stoppedRide();
      final csv = CalibrationCsv.build(
        samples: session.samples,
        analysis: session.analysis,
        fit: session.fit,
        dkdSnapshots: session.dkdSnapshots,
        settings: _settings,
        appVersion: '1.2.1',
        exportedAt: t0,
        startedAt: session.startedAt,
        stoppedAt: session.stoppedAt,
        controllerId: 'AA:BB:CC',
        status: CalibrationCsv.statusStopped,
      );
      final saved = CalibrationCsv.parse(csv);
      expect(saved.samples, hasLength(session.samples.length));
      expect(saved.controllerId, 'AA:BB:CC');
      expect(saved.status, CalibrationCsv.statusStopped);
      expect(saved.startedAt, session.startedAt);
      expect(saved.stoppedAt, session.stoppedAt);
      expect(saved.settings.ble!.rateRatio, 4000);
      expect(saved.settings.speedPulses, 11);
      expect(saved.settings.spdPulseNum, 38050);
      expect(saved.dkdSnapshots.single.dkdKph, 51.5);
      expect(saved.dkdSnapshots.single.rpm, 2244.25);

      final reopened = saved.toSessionState();
      expect(reopened.status, CalibrationStatus.stopped);
      expect(reopened.analysis.cleanSeconds, session.analysis.cleanSeconds);
      expect(reopened.fit!.kGps, session.fit!.kGps);
      expect(reopened.fit!.confidence, session.fit!.confidence);
      final before =
          RateRatioSuggestion.compute(_settings.ble!, session.fit!.kGps);
      final after =
          RateRatioSuggestion.compute(saved.settings.ble!, reopened.fit!.kGps);
      expect(after.suggested, before.suggested);
    });

    test('CSV stays metric and adds mph columns', () {
      final session = _stoppedRide();
      final csv = CalibrationCsv.build(
        samples: session.samples,
        analysis: session.analysis,
        fit: session.fit,
        dkdSnapshots: const [],
        settings: _settings,
        appVersion: '1.2.1',
        exportedAt: t0,
        startedAt: session.startedAt,
      );
      final rows = FlatCsv.decode(csv);
      final header = rows.firstWhere((r) => r.first == 'time');
      final row = rows[rows.indexOf(header) + 1];
      final kph = double.parse(row[header.indexOf('gps_kmh')]);
      final mph = double.parse(row[header.indexOf('gps_mph')]);
      expect(mph, closeTo(kph / SpeedUnit.kmPerMile, 0.01));
    });

    test('CalibrationArchive saves one file per ride with list info', () async {
      var controllerId = 'AA:BB:CC';
      final archive = CalibrationArchive(
        store: store,
        settings: () async => _settings,
        controllerId: () => controllerId,
        appVersion: () async => '1.2.1',
        clock: () => t0,
      );
      final session = _stoppedRide();
      final recording = session.copyWith(status: CalibrationStatus.recording);
      final path = await archive.save(recording);
      controllerId = ''; // disconnected after the ride: id is kept
      final path2 = await archive.save(session);
      expect(path2, path);
      expect(path, endsWith(CalibrationArchive.fileNameFor(t0)));

      final entry = (await store.list(kind: SavedFileKind.calibration)).single;
      expect(entry.time, t0.toLocal());
      expect(entry.info['status'], 'stopped');
      expect(entry.info['controller_id'], 'AA:BB:CC');
      expect(entry.info['confidence'], session.fit!.confidence.name);
      expect(entry.info['suggested_GearRatio'], isNotEmpty);
      expect(entry.info['samples'], '${session.samples.length}');
    });

    test('rewrite stores DKD readings entered later in the same file',
        () async {
      final archive = CalibrationArchive(
        store: store,
        settings: () async => _settings,
        controllerId: () => 'id1',
        appVersion: () async => '1.2.1',
      );
      final session = _stoppedRide(dkd: [
        DkdSnapshot(at: t0, rpm: 2244, gpsKph: 50, controllerKph: 51),
      ]);
      final path = (await archive.save(session))!;
      final file = File(path);
      final saved = CalibrationCsv.parse(await file.readAsString());
      expect(saved.dkdSnapshots.single.dkdKph, isNull);
      await CalibrationArchive.rewrite(file, saved,
          dkdSnapshots: [saved.dkdSnapshots.single.withReading(52)],
          appVersion: '1.2.1');
      final again = CalibrationCsv.parse(await file.readAsString());
      expect(again.dkdSnapshots.single.dkdKph, 52);
      expect(again.controllerId, 'id1');
      expect(again.samples, hasLength(session.samples.length));
      expect(await store.list(), hasLength(1));
    });
  });

  group('incremental save', () {
    late FakeGps gps;
    late StreamController<RpmReading> rpm;
    late List<CalibrationSessionState> saves;
    late GpsCalibrationNotifier notifier;

    setUp(() {
      gps = FakeGps();
      rpm = StreamController<RpmReading>.broadcast();
      saves = [];
      notifier = GpsCalibrationNotifier(
        gps: gps,
        rpm: rpm.stream,
        controller: () => const ControllerReadout(speedKph: 51, braking: false),
        saver: (s) async {
          saves.add(s);
          return '/saved/${s.samples.length}';
        },
        autoSaveInterval: const Duration(milliseconds: 40),
      );
    });

    tearDown(() async {
      notifier.dispose();
      await rpm.close();
      await gps.controller.close();
    });

    test('saves while recording, on stop and after DKD edits', () async {
      await notifier.start();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(saves, isEmpty, reason: 'nothing recorded yet');

      final now = DateTime.now();
      rpm.add(RpmReading(rpm: 2244, at: now));
      await Future<void>.delayed(Duration.zero);
      notifier.onFix(fix(now, 50));
      expect(notifier.tapDkd(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(saves, isNotEmpty);
      expect(saves.last.isRecording, isTrue);
      expect(notifier.state.savedPath, '/saved/1');

      await notifier.stop();
      expect(saves.last.status, CalibrationStatus.stopped);
      final afterStop = saves.length;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(saves.length, afterStop, reason: 'timer stops with the ride');

      notifier.setDkdReading(0, 52);
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(saves.length, afterStop + 1);
      expect(saves.last.dkdSnapshots.single.dkdKph, 52);
    });

    test('a failing saver never breaks the ride', () async {
      final failing = GpsCalibrationNotifier(
        gps: gps,
        rpm: rpm.stream,
        controller: () => const ControllerReadout(speedKph: 51, braking: false),
        saver: (_) async => throw const FileSystemException('disk full'),
      );
      await failing.start();
      failing.onFix(fix(DateTime.now(), 50));
      expect(await failing.saveNow(), isNull);
      await failing.stop();
      expect(failing.state.status, CalibrationStatus.stopped);
      failing.dispose();
    });
  });

  group('parameter dumps', () {
    test('saveDump writes the export CSV and reloads identically', () async {
      final dump = _hebDump();
      final file = await ParameterDumpIo.saveDump(store, dump,
          appVersion: '1.2.1', now: DateTime(2026, 10, 31, 9, 30));
      expect(file.path, contains('/farsure/dumps/dump_'));
      expect(file.path, endsWith('_20261031_093000.csv'));
      expect(await file.readAsString(),
          ParameterCsvCodec.encode(dump, appVersion: '1.2.1'));
      final reloaded =
          ParameterDumpIo.parseFile(await file.readAsBytes(), 'x.csv');
      expect(reloaded.blocks, dump.blocks);
      final entry = (await store.list(kind: SavedFileKind.dump)).single;
      expect(entry.info['source'], isNotEmpty);
    });

    test('live archiver: first snapshot, config changes, not counters',
        () async {
      var now = DateTime(2026, 10, 31, 9);
      final archiver = LiveDumpArchiver(
          store: store, appVersion: () async => '1.2.1', clock: () => now);
      PersistedParameterSnapshot snap(Map<int, List<int>> blocks) =>
          PersistedParameterSnapshot(
            controller:
                ParameterCaptureService.identityFromBlocks(blocks, 'AA:BB'),
            requiredAddresses: blocks.keys.toSet(),
            rawBlocks: blocks,
            metadata: const {'controllerId': 'AA:BB', 'appVersion': '1.2.1'},
            source: 'live',
            capturedAt: now,
            complete: true,
          );
      final blocks = {
        for (final e in _hebDump().blocks.entries) e.key: [...e.value]
      };

      expect(await archiver.onSnapshot(snap(blocks)), isNotNull);
      // Odometer and rolling AVGPower moved while riding → same config.
      now = now.add(const Duration(minutes: 1));
      blocks[0x69]![8] = (blocks[0x69]![8] + 2) & 0xFF;
      blocks[0xD0]![3] = (blocks[0xD0]![3] + 7) & 0xFF;
      expect(await archiver.onSnapshot(snap(blocks)), isNull);
      // A real parameter change is always kept.
      now = now.add(const Duration(seconds: 2));
      blocks[0x30]![10] = (blocks[0x30]![10] + 1) & 0xFF;
      expect(await archiver.onSnapshot(snap(blocks)), isNotNull);
      // Unchanged config is still refreshed every 30 minutes.
      now = now.add(const Duration(minutes: 31));
      expect(await archiver.onSnapshot(snap(blocks)), isNotNull);
      expect(await store.list(kind: SavedFileKind.dump), hasLength(3));
    });
  });

  group('units', () {
    test('km/h ↔ mph conversions', () {
      expect(SpeedUnit.mph.fromKph(100), closeTo(62.137, 0.001));
      expect(SpeedUnit.mph.toKph(62.137119), closeTo(100, 1e-4));
      expect(SpeedUnit.mph.fromKm(SpeedUnit.kmPerMile), closeTo(1, 1e-12));
      expect(SpeedUnit.kmh.fromKph(42), 42);
      expect(SpeedUnit.mph.speed(80.4672), '50 mph');
      expect(SpeedUnit.kmh.distance(12.34), '12.3 km');
      expect(SpeedUnit.mph.distance(16.09344), '10.0 mi');
      expect(SpeedUnit.mph.whPerDistanceFromWhPerKm(40), closeTo(64.37, 0.01));
      expect(SpeedUnit.mph.energyPerDistanceLabel, 'Wh/mi');
    });

    test('setting persists in AppSettings JSON; defaults to km/h', () {
      const settings = AppSettings();
      expect(settings.speedUnit, SpeedUnit.kmh);
      final json = settings.copyWith(speedUnit: SpeedUnit.mph).toJson();
      expect(json['speedUnit'], 'mph');
      expect(AppSettings.fromJson(json).speedUnit, SpeedUnit.mph);
      expect(AppSettings.fromJson(const {}).speedUnit, SpeedUnit.kmh);
      expect(SpeedUnit.fromKey('bogus'), SpeedUnit.kmh);
    });
  });

  test('controller state type is unchanged (metric)', () {
    expect(ControllerState(lastUpdate: t0).speedKph, isA<double>());
  });
}

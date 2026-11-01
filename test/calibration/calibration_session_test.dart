import 'dart:async';

import 'package:arcdash/models/controller_state.dart';
import 'package:arcdash/models/gps_calibration.dart';
import 'package:arcdash/models/speed_source.dart';
import 'package:arcdash/models/speed_suggestions.dart';
import 'package:arcdash/services/calibration_csv.dart';
import 'package:arcdash/services/calibration_settings.dart';
import 'package:arcdash/services/gps_calibration_session.dart';
import 'package:arcdash/services/gps_location_service.dart';
import 'package:arcdash/services/parameter_csv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ride_fixtures.dart';

class FakeGps implements GpsSource {
  FakeGps([this.availability = GpsAvailability.ready]);

  final GpsAvailability availability;
  final controller = StreamController<GpsSpeedSample>.broadcast();

  @override
  Future<GpsAvailability> ensureReady() async => availability;

  @override
  Stream<GpsSpeedSample> fixes() => controller.stream;

  @override
  Future<void> openSettings(GpsAvailability availability) async {}
}

GpsSpeedSample fix(DateTime at, double kph) => GpsSpeedSample(
    speedKph: kph,
    accuracyMeters: 4,
    speedAccuracyMps: 0.3,
    headingDeg: 90,
    capturedAt: at);

void main() {
  group('CalibrationPairer', () {
    test('averages rpm per second and reuses a fresh last value', () {
      final p = CalibrationPairer();
      p.addRpm(RpmReading(rpm: 2000, at: t0));
      p.addRpm(
          RpmReading(rpm: 2100, at: t0.add(const Duration(milliseconds: 500))));
      expect(p.takeSecond(t0.add(const Duration(seconds: 1))), 2050);
      // Nothing new: last reading is 1.0 s old → reused.
      expect(p.takeSecond(t0.add(const Duration(milliseconds: 1500))), 2100);
      // Too old.
      expect(p.takeSecond(t0.add(const Duration(seconds: 3))), isNull);
    });
  });

  group('GpsCalibrationNotifier', () {
    late FakeGps gps;
    late StreamController<RpmReading> rpm;
    late DateTime now;
    late GpsCalibrationNotifier notifier;

    setUp(() {
      gps = FakeGps();
      rpm = StreamController<RpmReading>.broadcast();
      now = t0;
      notifier = GpsCalibrationNotifier(
        gps: gps,
        rpm: rpm.stream,
        controller: () => const ControllerReadout(speedKph: 51, braking: false),
        clock: () => now,
      );
    });

    tearDown(() async {
      notifier.dispose();
      await rpm.close();
      await gps.controller.close();
    });

    test('pairs GPS fixes with rpm and builds a fit', () async {
      expect(await notifier.start(), GpsAvailability.ready);
      expect(notifier.state.status, CalibrationStatus.recording);
      for (var i = 0; i < 12; i++) {
        now = t0.add(Duration(seconds: i));
        rpm.add(RpmReading(rpm: 50 / kTrue, at: now));
        await Future<void>.delayed(Duration.zero);
        notifier.onFix(fix(now, 50));
      }
      final s = notifier.state;
      expect(s.samples, hasLength(12));
      expect(s.samples.first.controllerKph, 51);
      expect(s.cleanSeconds, 10);
      expect(s.fit!.kGps, closeTo(kTrue, 1e-9));
    });

    test('no in-ride DKD tap: DKD edits without readings are no-ops', () async {
      await notifier.start();
      rpm.add(RpmReading(rpm: 2244, at: now));
      await Future<void>.delayed(Duration.zero);
      notifier.onFix(fix(now, 50));
      await notifier.stop();
      expect(notifier.state.dkdSnapshots, isEmpty);
      notifier.setDkdReading(0, 52);
      notifier.removeDkdSnapshot(0);
      expect(notifier.state.dkdSnapshots, isEmpty);
    });

    test('lost GPS records noGps seconds', () async {
      await notifier.start();
      now = t0.add(const Duration(seconds: 3));
      notifier.onTick();
      expect(notifier.state.samples.single.gps, isNull);
      expect(notifier.state.analysis.verdicts.single, SampleVerdict.noGps);
    });

    test('denied permission → unavailable, nothing recorded', () async {
      final denied = GpsCalibrationNotifier(
        gps: FakeGps(GpsAvailability.denied),
        rpm: rpm.stream,
        controller: () => const ControllerReadout(speedKph: 0, braking: false),
      );
      expect(await denied.start(), GpsAvailability.denied);
      expect(denied.state.status, CalibrationStatus.unavailable);
      expect(denied.state.gpsProblem, GpsAvailability.denied);
      denied.dispose();
    });
  });

  group('CalibrationSettings', () {
    Map<int, List<int>> blocks() {
      final d0 = List<int>.filled(12, 0);
      d0[4] = 70; // WheelRatio
      d0[5] = 12; // WheelRadius
      d0[7] = 120; // WheelWidth
      d0[8] = 4000 & 0xFF; // RateRatio LE
      d0[9] = 4000 >> 8;
      final b18 = List<int>.filled(12, 0)
        ..[5] = 0xE0 | 11; // SpeedPulse bits 0-4
      final b30 = List<int>.filled(12, 0)
        ..[10] = 38050 & 0xFF
        ..[11] = 38050 >> 8;
      return {0xD0: d0, 0x18: b18, 0x30: b30};
    }

    test('decodes wheel, RateRatio, Speed Pulses and SpdPulseNum', () {
      final s = CalibrationSettings.fromBlocks(blocks(), source: 'test');
      expect(s.ble!.rateRatio, 4000);
      expect(s.ble!.kBle, closeTo(kTrue, 1e-6));
      expect(s.speedPulses, 11);
      expect(s.spdPulseNum, 38050);
    });

    test('missing blocks → null values', () {
      final s = CalibrationSettings.fromBlocks({}, source: 'test');
      expect(s.ble, isNull);
      expect(s.speedPulses, isNull);
    });

    test('falls back to live 0xD0 geometry without a snapshot', () {
      final live = ControllerState(
          lastUpdate: t0,
          wheelRadius: 12,
          wheelWidth: 120,
          wheelRatio: 70,
          rateRatio: 4000);
      final s =
          CalibrationSettings.resolve(live: live, liveGeometryReceived: true);
      expect(s.ble!.rateRatio, 4000);
      expect(s.spdPulseNum, isNull);
      expect(s.source, contains('live'));
      expect(
          CalibrationSettings.resolve(live: live, liveGeometryReceived: false)
              .ble,
          isNull);
    });
  });

  test('CSV export has summary, settings, fit, DKD and per-second rows', () {
    final samples = ride([
      ...steadyLegs(6, [30, 50]),
      const Leg(3, 15),
    ]);
    const analyzer = CalibrationAnalyzer();
    final analysis = analyzer.analyze(samples);
    final fit = CalibrationFit.fromAnalysis(analysis);
    final csv = CalibrationCsv.build(
      samples: samples,
      analysis: analysis,
      fit: fit,
      dkdSnapshots: [
        DkdSnapshot(
            at: t0, rpm: 2244, gpsKph: 50, controllerKph: 51, dkdKph: 51.5),
      ],
      settings: const CalibrationSettings(
        ble: BleSpeedSettings(
            wheelRadius: 12, wheelWidth: 120, wheelRatio: 70, rateRatio: 4000),
        speedPulses: 11,
        spdPulseNum: 38050,
        source: 'test',
      ),
      appVersion: '1.2.0',
      exportedAt: t0,
    );
    final rows = FlatCsv.decode(csv);
    expect(
        rows.any((r) => r.length == 3 && r[1] == 'k_gps_kmh_per_rpm'), isTrue);
    expect(rows.any((r) => r[1] == 'suggested_RateRatio'), isTrue);
    expect(rows.any((r) => r[1] == 'suggested_SpdPulseNum'), isTrue);
    expect(rows.any((r) => r[0] == 'dkd_snapshot'), isTrue);
    final header = rows.indexWhere((r) => r.first == 'time');
    expect(rows.length - header - 1, samples.length);
    expect(rows.last[9], 'too_slow');
    expect(rows.last[8], '0');
    expect(rows[header + 2][8], '1');
  });
}

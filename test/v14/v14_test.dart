import 'dart:io';

import 'package:arcdash/models/app_settings.dart';
import 'package:arcdash/models/gps_calibration.dart';
import 'package:arcdash/models/ride_record.dart';
import 'package:arcdash/models/speed_source.dart';
import 'package:arcdash/models/speed_suggestions.dart';
import 'package:arcdash/services/calibration_csv.dart';
import 'package:arcdash/services/calibration_settings.dart';
import 'package:arcdash/services/ride_archive.dart';
import 'package:arcdash/services/write/write_allowlist.dart';
import 'package:arcdash/services/write/write_log.dart';
import 'package:arcdash/services/write/write_outcome.dart';
import 'package:flutter_test/flutter_test.dart';

import '../rides/ride_test_helpers.dart';

SavedCalibration _fixture(String f) => CalibrationCsv.parse(
    File('test/fixtures/calibration/$f.csv').readAsStringSync());

void main() {
  group('item 6: GPS filter on real rides', () {
    test('defaults are the v1.4 tuning', () {
      const c = CalibrationFilterConfig();
      expect(c.maxLagError, 0.04);
      expect(c.maxRatioJump, 0.06);
      expect(c.maxTrailError, 0.05);
      expect(c.trailSeconds, 2);
    });
    for (final (f, minClean, maxCi, lo, hi) in [
      ('blu_view2_ride', 55, 0.008, 4106, 4121),
      ('ride_20261102_green', 115, 0.005, 4106, 4121),
      ('ride_20261103_calibG', 200, 0.007, 4100, 4121),
    ]) {
      test(f, () {
        final s = _fixture(f).toSessionState();
        expect(s.analysis.cleanSeconds, greaterThanOrEqualTo(minClean));
        expect(s.fit!.ciRelative!, lessThan(maxCi));
        final saved = _fixture(f);
        final sug =
            RateRatioSuggestion.compute(saved.settings.ble!, s.fit!.kGps);
        expect(sug.suggested, inInclusiveRange(lo, hi));
      });
    }
  });

  group('item 6b: GPS trailing rpm', () {
    final t0 = DateTime.utc(2026, 11, 3, 12);
    CalibrationSample sec(int i, double v, double rpm) => CalibrationSample(
          at: t0.add(Duration(seconds: i)),
          gps: GpsSpeedSample(
              speedKph: v,
              accuracyMeters: 3,
              speedAccuracyMps: 0.5,
              capturedAt: t0.add(Duration(seconds: i))),
          rpm: rpm,
          controllerKph: v,
        );
    test('rpm steps, GPS follows a second later → gpsLag', () {
      final samples = [
        for (var i = 0; i < 20; i++)
          sec(i, i <= 10 ? 50 : 53.5, i < 10 ? 2300 : 2300 * 1.07),
      ];
      final a = const CalibrationAnalyzer().analyze(samples);
      expect(a.verdicts[10], SampleVerdict.gpsLag);
      expect(a.verdicts[11], SampleVerdict.gpsLag);
      expect(a.verdicts[5], SampleVerdict.kept);
      expect(a.verdicts[16], SampleVerdict.kept);
    });
    test('hill / throttle wobble moving both together is kept', () {
      final samples = [
        for (var i = 0; i < 20; i++)
          sec(i, 50 * (1 + 0.01 * (i % 3)), 2300 * (1 + 0.01 * (i % 3))),
      ];
      final a = const CalibrationAnalyzer().analyze(samples);
      expect(a.verdicts.sublist(1, 19), everyElement(SampleVerdict.kept));
    });
  });

  group('item 7: CSV keeps both ride-start and current settings', () {
    test('settings_now section written and different from start', () {
      const start = CalibrationSettings(
          ble: BleSpeedSettings(
              wheelRadius: 12, wheelWidth: 130, wheelRatio: 70, rateRatio: 4000),
          speedPulses: 4,
          spdPulseNum: 102,
          source: 'ride start');
      const now = CalibrationSettings(
          ble: BleSpeedSettings(
              wheelRadius: 12, wheelWidth: 130, wheelRatio: 70, rateRatio: 4106),
          speedPulses: 4,
          spdPulseNum: 102,
          source: 'now');
      final csv = CalibrationCsv.build(
        samples: const [],
        analysis: const CalibrationAnalyzer().analyze(const []),
        fit: null,
        dkdSnapshots: const [],
        settings: start,
        currentSettings: now,
        appVersion: '1.4.0',
        exportedAt: DateTime(2026, 11, 3),
      );
      expect(csv, contains('settings_now,RateRatio,4106'));
      expect(CalibrationCsv.parse(csv).settings.ble!.rateRatio, 4000);
    });
  });

  group('item 8/9: over voltage read-only, partial outcome', () {
    test('HighVol fields are read-only', () {
      for (final k in ['HighVolProtect', 'HighVolRestore']) {
        expect(WriteAllowlist.byKey(k)!.readOnly, isTrue);
      }
    });
    test('v1 log with HighVol mismatch decodes as partial', () {
      final log = WriteLogSession.decode(
          File('test/fixtures/write_logs/v1_highvol_mismatch.csv')
              .readAsStringSync());
      expect(log.outcome, WriteOutcome.partial);
      expect(log.message, contains('saved'));
      expect(log.message, contains('rejected'));
    });
    test('v1 RateRatio log decodes as ok', () {
      final log = WriteLogSession.decode(
          File('test/fixtures/write_logs/v1_rateratio_ok.csv')
              .readAsStringSync());
      expect(log.outcome, WriteOutcome.ok);
    });
    test('WriteSummary', () {
      expect(
          WriteSummary.outcomeOf(
              [FieldOutcome.saved, FieldOutcome.rejectedUnchanged]),
          WriteOutcome.partial);
      expect(WriteSummary.outcomeOf([FieldOutcome.notConfirmed]),
          WriteOutcome.failed);
      expect(WriteSummary.outcomeOf([FieldOutcome.saved]), WriteOutcome.ok);
    });
  });

  group('item 10: experimental toggle', () {
    test('old v1.3 key is ignored', () {
      expect(AppSettings.fromJson({'experimentalWrites': true})
          .experimentalWrites, isFalse);
      expect(AppSettings.fromJson({AppSettings.experimentalKey: true})
          .experimentalWrites, isTrue);
      expect(WriteAllowlist.hasExperimental, isFalse);
    });
  });

  group('item 11: previous ride by controller name', () {
    final t0 = DateTime.utc(2026, 11, 1);
    RideRecord r(int h, String id) =>
        testRide(start: t0.add(Duration(hours: h)), controllerId: id);
    test('same name wins, different name never used', () {
      final ride = r(10, 'ND72530');
      final older = [r(1, 'ND72530'), r(5, 'OTHER'), r(3, 'AA:BB:CC:DD:EE:FF')];
      expect(RideArchive.pickPrevious(ride, older)!.start.toUtc().hour, 1);
    });
    test('falls back to MAC/unnamed ride', () {
      final ride = r(10, 'nd72530');
      final older = [r(5, 'OTHER'), r(3, 'AA:BB:CC:DD:EE:FF'), r(2, '')];
      expect(RideArchive.pickPrevious(ride, older)!.start.toUtc().hour, 3);
      expect(RideArchive.pickPrevious(ride, [r(5, 'OTHER')]), isNull);
    });
    test('names', () {
      expect(RideArchive.controllerNameOf('AA:BB:CC:DD:EE:FF'), isNull);
      expect(RideArchive.controllerNameOf(' nd1 '), 'ND1');
    });
  });
}

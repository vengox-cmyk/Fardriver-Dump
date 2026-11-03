import 'dart:io';

import 'package:arcdash/models/app_settings.dart';
import 'package:arcdash/models/gps_calibration.dart';
import 'package:arcdash/models/ride_record.dart';
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
    });
    for (final (f, minClean, maxCi) in [
      ('blu_view2_ride', 80, 0.007),
      ('ride_20261102_green', 140, 0.004),
      ('ride_20261103_calibG', 220, 0.007),
    ]) {
      test(f, () {
        final s = _fixture(f).toSessionState();
        expect(s.analysis.cleanSeconds, greaterThanOrEqualTo(minClean));
        expect(s.fit!.ciRelative!, lessThan(maxCi));
      });
    }
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

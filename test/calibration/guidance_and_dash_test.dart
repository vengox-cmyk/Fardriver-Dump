import 'dart:async';
import 'dart:io';

import 'package:arcdash/models/calibration_guidance.dart';
import 'package:arcdash/models/dash_speed.dart';
import 'package:arcdash/models/gps_calibration.dart';
import 'package:arcdash/models/speed_suggestions.dart';
import 'package:arcdash/services/calibration_csv.dart';
import 'package:arcdash/services/dash_check.dart';
import 'package:arcdash/services/gps_calibration_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calibration_session_test.dart' show FakeGps, fix;

DkdSnapshot pt(double rpm, double dash, {double app = 0}) => DkdSnapshot(
    at: DateTime(2026, 11, 1, 12),
    rpm: rpm,
    gpsKph: 0,
    controllerKph: app,
    dkdKph: dash);

void main() {
  final saved = CalibrationCsv.parse(
      File('test/fixtures/calibration/blu_view2_ride.csv').readAsStringSync());
  final session = saved.toSessionState();
  final analysis = session.analysis;
  final fit = session.fit!;
  final ble = saved.settings.ble!;

  group('plain-language results (fixture ride)', () {
    test('rejection breakdown is sorted, sums to the rejected seconds', () {
      final lines = rejectionBreakdown(analysis);
      expect(lines.first.advice.verdict, SampleVerdict.tooSlow);
      expect(lines.first.seconds, 197);
      for (var i = 1; i < lines.length; i++) {
        expect(lines[i].seconds, lessThanOrEqualTo(lines[i - 1].seconds));
      }
      final rejected = analysis.verdicts.where((v) => v != SampleVerdict.kept);
      expect(lines.fold<int>(0, (s, l) => s + l.seconds), rejected.length);
      expect(lines.every((l) => l.advice.fix.isNotEmpty), isTrue);
    });

    test('every verdict has advice text', () {
      for (final v in SampleVerdict.values) {
        expect(adviceFor(v).what, isNotEmpty);
      }
    });

    test('fit summary names RateRatio, error and clean seconds', () {
      final s = fitSummary(fit, ble: ble);
      final suggested = RateRatioSuggestion.compute(ble, fit.kGps).suggested;
      expect(s, contains('RateRatio: $suggested'));
      expect(s, contains('(now 4000)'));
      expect(s, contains('${fit.cleanSeconds} clean seconds'));
      expect(s, contains('% high'));
    });

    test('no-fit summary on an empty ride', () {
      expect(noFitSummary(const CalibrationAnalyzer().analyze(const [])),
          isNotEmpty);
    });

    test('capture checklist reflects the real fit requirements', () {
      final p = CaptureProgress.of(analysis, fit);
      expect(p.requirements, hasLength(4));
      // 74 clean s of 90 → not done yet, with a hint.
      expect(p.requirements[0].done, isFalse);
      expect(p.requirements[0].progress, closeTo(74 / 90, 0.02));
      expect(p.requirements[0].hint, contains('more steady seconds'));
      for (final r in p.requirements) {
        expect(r.progress, inInclusiveRange(0, 1));
      }
      final empty = CaptureProgress.of(
          const CalibrationAnalyzer().analyze(const []), null);
      expect(empty.allDone, isFalse);
      expect(empty.requirements.every((r) => r.progress == 0), isTrue);
    });
  });

  group('dash speed column', () {
    const anchor = DashAnchor(
        kDash: 0.02,
        speedPulses: 11,
        spdPulseNum: 38050,
        points: 3,
        source: 't');

    test('exact at the anchor; rises with SpeedPulse and SpdPulseNum', () {
      expect(anchor.kFor(sp: 11, spn: 38050), 0.02);
      expect(anchor.kFor(sp: 22, spn: 38050), closeTo(0.04, 1e-12));
      expect(anchor.kFor(sp: 11, spn: 76100), closeTo(0.04, 1e-12));
      expect(anchor.kFor(sp: 11, spn: 19025), closeTo(0.01, 1e-12));
      expect(anchor.kFor(sp: null, spn: 38050), isNull);
      expect(anchor.estimateKph(1000, sp: 11, spn: 38050), closeTo(20, 1e-9));
      expect(anchor.estimateKph(0, sp: 11, spn: 38050), isNull);
    });

    test('calibration CSV carries dash_kmh_est, labelled and not in the fit',
        () {
      final csv = CalibrationCsv.build(
        samples: saved.samples,
        analysis: analysis,
        fit: fit,
        dkdSnapshots: const [],
        settings: saved.settings,
        appVersion: 'test',
        exportedAt: DateTime(2026, 11, 1),
        dashAnchor: anchor,
      );
      expect(csv, contains('dash_kmh_est'));
      expect(csv, contains('dash_est,status,$dashEstimateLabel\n'));
      expect(csv, isNot(contains(dashCalibratedLabel)));
      final back = CalibrationCsv.parse(csv);
      expect(back.samples, hasLength(saved.samples.length));
      // Same fit with or without the estimate column.
      expect(back.toSessionState().fit!.kGps, closeTo(fit.kGps, 1e-12));
    });
  });

  group('dash column after a dash check', () {
    test('shown as calibrated from the check', () {
      final rec = DashCheckRecord(
        startedAt: DateTime(2026, 11, 1, 12, 30),
        points: [pt(1000, 21), pt(2000, 42)],
        speedPulses: 11,
        spdPulseNum: 38050,
      );
      final anchor = rec.anchor!;
      expect(anchor.fromDashCheck, isTrue);
      expect(dashStatusLabel(anchor), startsWith(dashCalibratedLabel));
      expect(dashStatusLabel(null), dashEstimateLabel);
      final csv = CalibrationCsv.build(
        samples: saved.samples,
        analysis: analysis,
        fit: fit,
        dkdSnapshots: const [],
        settings: saved.settings,
        appVersion: 'test',
        exportedAt: DateTime(2026, 11, 1),
        dashAnchor: anchor,
      );
      expect(csv, contains('dash_est,status,$dashCalibratedLabel'));
      expect(csv, contains('same settings as anchor (measured)'));
    });
  });

  group('stationary dash check', () {
    test('needs two points; prefers the GPS reference', () {
      expect(
          DashCheckResult.compute(
              points: [pt(1000, 20)],
              kGps: 0.02,
              kApp: 0.021,
              speedPulses: 11,
              spdPulseNum: 38050),
          isNull);
      final r = DashCheckResult.compute(
          points: [pt(1000, 21), pt(2000, 42)],
          kGps: 0.02,
          kApp: 0.03,
          speedPulses: 11,
          spdPulseNum: 38050)!;
      expect(r.referenceSource, 'gps');
      expect(r.error, closeTo(0.05, 1e-9));
      // Dash 5 % high (> 4 %): Speed Pulses step first, then SpdPulseNum;
      // display ∝ SP × SPN (higher SpdPulseNum = higher dash, verified
      // hands-on by the owner) so the new settings slow the dash by 1/1.05.
      final s = r.suggestion!;
      expect(s.suggestedSpeedPulses, 10);
      final factor =
          (s.suggestedSpeedPulses / 11) * (s.suggestedSpdPulseNum / 38050);
      expect(factor, closeTo(1 / 1.05, 0.001));
      // 2 % high → SpdPulseNum only, lower (= slower display).
      final small = DashCheckResult.compute(
          points: [pt(1000, 20.4), pt(2000, 40.8)],
          kGps: 0.02,
          kApp: null,
          speedPulses: 11,
          spdPulseNum: 38050)!;
      expect(small.suggestion!.changesSpeedPulses, isFalse);
      expect(small.suggestion!.suggestedSpdPulseNum, 37304);
      final app = DashCheckResult.compute(
          points: [pt(1000, 21), pt(2000, 42)],
          kGps: null,
          kApp: 0.021,
          speedPulses: 11,
          spdPulseNum: 38050)!;
      expect(app.referenceSource, 'app');
      expect(app.error, closeTo(0, 1e-9));
    });

    test('dash check file round-trips', () {
      final rec = DashCheckRecord(
        startedAt: DateTime(2026, 11, 1, 12, 30),
        points: [pt(1000, 21, app: 20), pt(2000, 42, app: 40)],
        speedPulses: 11,
        spdPulseNum: 38050,
        ble: ble,
        controllerId: 'E0:07:D3:FD:00:5A',
        kGps: 0.02,
        kGpsSource: 'calibration_x.csv',
      );
      final csv = DashCheckCsv.build(rec,
          appVersion: 'test', exportedAt: DateTime(2026, 11, 1, 12, 31));
      final back = DashCheckCsv.parse(csv);
      expect(back.points, hasLength(2));
      expect(back.points.last.dkdKph, 42);
      expect(back.speedPulses, 11);
      expect(back.spdPulseNum, 38050);
      expect(back.kGps, closeTo(0.02, 1e-9));
      expect(back.result!.error, closeTo(0.05, 1e-6));
      expect(back.anchor!.kDash, closeTo(0.021, 1e-9));
    });

    test('capture only while standing still with rpm; each entry is saved',
        () async {
      var now = DateTime(2026, 11, 1, 12);
      final gps = FakeGps();
      final rpm = StreamController<RpmReading>.broadcast();
      final saves = <int>[];
      final n = DashCheckNotifier(
        gps: gps,
        rpm: rpm.stream,
        controller: () => const ControllerReadout(speedKph: 20, braking: false),
        newRecord: (at) async => DashCheckRecord(
            startedAt: at,
            points: const [],
            speedPulses: 11,
            spdPulseNum: 38050),
        saver: (r) async {
          saves.add(r.points.length);
          return '/x/dash.csv';
        },
        clock: () => now,
      );
      addTearDown(n.dispose);
      await n.begin();
      expect(n.state.ready, isTrue);

      // No GPS yet → refused.
      n.onRpm(RpmReading(rpm: 1000, at: now));
      expect(n.capture(), isFalse);

      // Moving → refused.
      n.onFix(fix(now, 25));
      expect(n.capture(), isFalse);

      // Standing still, wheel spinning → allowed.
      n.onFix(fix(now, 0.4));
      expect(n.capture(), isTrue);
      await n.enterDash(21);
      expect(n.state.points, hasLength(1));
      expect(saves, [1]);
      expect(n.state.savedPath, '/x/dash.csv');

      // Stale GPS (> 3 s) → refused.
      now = now.add(const Duration(seconds: 5));
      n.onRpm(RpmReading(rpm: 2000, at: now));
      expect(n.capture(), isFalse);

      // Discarded entry is not stored.
      n.onFix(fix(now, 0));
      expect(n.capture(), isTrue);
      await n.enterDash(null);
      expect(n.state.points, hasLength(1));

      await n.removePoint(0);
      expect(n.state.points, isEmpty);
      expect(saves, [1, 0]); // removal saved too; never deletes the file
      await rpm.close();
    });
  });
}

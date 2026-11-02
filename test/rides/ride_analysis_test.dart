import 'package:flutter_test/flutter_test.dart';

import 'package:arcdash/models/drive_state.dart';
import 'package:arcdash/models/ride_record.dart';
import 'package:arcdash/models/ride_stats.dart';
import 'package:arcdash/services/dump_archive.dart';
import 'package:arcdash/services/ride_analysis.dart';
import 'package:arcdash/services/saved_files.dart';
import 'package:arcdash/utils/speed_units.dart';

import 'ride_test_helpers.dart';

void main() {
  final t0 = DateTime(2026, 11, 1, 14, 0);
  GearStatus gear(int e2, {bool boost = false}) =>
      GearStatus.fromE2Byte(e2, boost: boost);

  group('ride telemetry accumulator', () {
    test('peaks, sag, gear time, boost and average power', () {
      final s = RideSession(id: '1', startTime: t0);
      // resting at 84 V, then 40 A pulls the pack to 78 V
      s.addSample(
          speedKph: 0,
          voltageV: 84,
          currentA: 1,
          deltaTimeSeconds: 1,
          gear: gear(0x01));
      s.addSample(
          speedKph: 30,
          voltageV: 78,
          currentA: 40,
          deltaTimeSeconds: 1,
          phaseACurrA: 120,
          phaseCCurrA: -150,
          motorTempC: 55,
          controllerTempC: 40,
          gear: gear(0x29, boost: true));
      s.addSample(
          speedKph: 40,
          voltageV: 80,
          currentA: 20,
          deltaTimeSeconds: 1,
          motorTempC: 61,
          controllerTempC: 38,
          gear: gear(0x25));
      final t = s.telemetry;
      expect(t.maxLineA, 40);
      expect(t.maxPhaseA, 150); // |phase C|
      expect(t.maxSagV, closeTo(6, 1e-9));
      expect(t.minV, 78);
      expect(t.maxV, 84);
      expect(t.maxMotorC, 61);
      expect(t.maxControllerC, 40);
      expect(t.boostSeconds, 1);
      expect(t.gearSeconds, {'D-LOW': 1, 'D-HIGH': 1, 'D-MID': 1});
      // moving samples only: (78*40 + 80*20) / 2
      expect(t.avgPowerW, closeTo(2360, 1e-9));
    });

    test('ride CSV has gear and boost columns', () {
      final s = RideSession(id: '1', startTime: t0);
      s.addSample(
          speedKph: 30,
          voltageV: 80,
          currentA: 10,
          deltaTimeSeconds: 1,
          gear: gear(0x29, boost: true),
          at: t0);
      s.addSample(
          speedKph: 31, voltageV: 80, currentA: 10, deltaTimeSeconds: 1);
      final rows = s.toCsvRows();
      expect(rows.first, ['Time', 'Speed (km/h)', 'Gear', 'Boost']);
      expect(rows[1].sublist(1), ['30.0', 'D-HIGH', '1']);
      expect(rows[2].sublist(1), ['31.0', '', '']);
    });
  });

  group('ride record', () {
    test('JSON round trip and list info', () {
      final s = RideSession(id: '42', startTime: t0, distanceKm: 3.2);
      s.addSample(
          speedKph: 30,
          voltageV: 80,
          currentA: 30,
          deltaTimeSeconds: 1,
          motorTempC: 50,
          gear: gear(0x05));
      s.endTime = t0.add(const Duration(minutes: 7));
      final r = RideRecord.fromSession(s,
          settingsDump: 'dump_a.csv', csvFile: 'arcdash_ride_1.csv');
      final text = r.encode();
      final back = RideRecord.decode(text);
      expect(back.id, '42');
      expect(back.start, t0);
      expect(back.duration, const Duration(minutes: 7));
      expect(back.maxLineA, 30);
      expect(back.maxMotorC, 50);
      expect(back.maxControllerC, isNull); // never received
      expect(back.gearSeconds, {'D-MID': 1});
      expect(back.settingsDump, 'dump_a.csv');

      final info = SavedFilesStore.rideRecordInfo(text);
      expect(DateTime.parse(info['time']!).toLocal(), t0);
      expect(info['id'], '42');
      expect(info['csvFile'], 'arcdash_ride_1.csv');
      expect(() => RideRecord.decode('{"format":"x"}'),
          throwsA(isA<FormatException>()));
    });
  });

  group('settings snapshot', () {
    test('newest dump not after start + grace, live preferred', () {
      final dumps = [
        (
          time: t0.subtract(const Duration(days: 1)),
          source: 'live',
          name: 'old'
        ),
        (
          time: t0.subtract(const Duration(hours: 1)),
          source: 'heb:x.heb',
          name: 'heb'
        ),
        (
          time: t0.subtract(const Duration(hours: 1)),
          source: 'live',
          name: 'live'
        ),
        (
          time: t0.add(const Duration(minutes: 1)),
          source: 'live',
          name: 'grace'
        ),
        (
          time: t0.add(const Duration(minutes: 30)),
          source: 'live',
          name: 'later'
        ),
      ];
      expect(RideAnalysis.pickSnapshot(dumps, t0), 'grace');
      expect(RideAnalysis.pickSnapshot(dumps.take(3), t0), 'live');
      expect(
          RideAnalysis.pickSnapshot(dumps.where((d) => d.name == 'later'), t0),
          isNull);
    });
  });

  group('config diff', () {
    test('ignores clock and counters, counts unidentified, plain names', () {
      final a = testDump(maxLineA: 200, timeHour: 9, unk2Cb: 1);
      final b = testDump(maxLineA: 240, timeHour: 17, unk2Cb: 2);
      final diff = RideAnalysis.configDiff(a, b);
      expect(diff.changes.map((c) => c.def.name), ['MaxLineCurr']);
      expect(diff.unidentifiedChanged, 1);
      final c = diff.changes.single;
      expect(c.name, 'Max line (battery) current');
      expect(c.before(SpeedUnit.kmh), '200 A');
      expect(c.after(SpeedUnit.kmh), '240 A');
      expect(LiveDumpArchiver.isVolatile(def('TimeHour')), isTrue);
      expect(LiveDumpArchiver.isVolatile(def('MaxLineCurr')), isFalse);
    });

    test('plain name fallback splits camel case', () {
      expect(RideAnalysis.plainName(def('RatedVoltage')), 'Rated voltage');
      expect(RideAnalysis.plainName(def('BlockTime')), 'Block time');
    });
  });

  group('callouts', () {
    test('thresholds decide what is notable', () {
      final prev = testRide(start: t0);
      final now = testRide(
          start: t0.add(const Duration(days: 1)),
          maxSpeedKph: 52.5, // +2.5 < 3
          maxLineA: 162, // +12 >= 10
          maxPhaseA: 320, // +20 < 25
          maxSagV: 6.5, // +2.5 >= 2
          maxMotorC: 64, // +4 < 5
          maxControllerC: 51, // +6 >= 5
          avgPowerW: 1120); // +12 % >= 10 %
      final byKind = {
        for (final c in RideAnalysis.callouts(now, prev)) c.kind: c.notable
      };
      expect(byKind, {
        CalloutKind.topSpeed: false,
        CalloutKind.peakLineCurrent: true,
        CalloutKind.peakPhaseCurrent: false,
        CalloutKind.voltageSag: true,
        CalloutKind.motorTemp: false,
        CalloutKind.controllerTemp: true,
        CalloutKind.avgPower: true,
      });
      final first = RideAnalysis.callouts(now, null);
      expect(first.every((c) => !c.notable && c.delta == null), isTrue);
    });

    test('speed callout follows the mph switch', () {
      final prev = testRide(start: t0, maxSpeedKph: 40);
      final now = testRide(start: t0, maxSpeedKph: 56.0934);
      final c = RideAnalysis.callouts(now, prev).first;
      expect(c.describe(SpeedUnit.mph), 'top speed +10.0 mph (34.9 mph)');
      expect(c.describe(SpeedUnit.kmh), 'top speed +16.1 km/h (56.1 km/h)');
    });
  });

  group('rule-based summary', () {
    test('limits, sag and temperatures against the ride settings', () {
      final ride = testRide(
          start: t0,
          maxLineA: 198, // of 200 A
          maxPhaseA: 300, // of 400 A: fine
          maxV: 84,
          maxSagV: 9, // 10.7 %
          maxMotorC: 112, // within 10 of 120
          maxControllerC: 50,
          boostSeconds: 30);
      final out = RideAnalysis.suggestions(ride, settings: testDump());
      expect(
          out.any((s) => s.startsWith('Line current reached 198 A')), isTrue);
      expect(out.any((s) => s.startsWith('Phase current')), isFalse);
      expect(
          out.any((s) => s.startsWith('Voltage sagged 9.0 V (11 %)')), isTrue);
      expect(out.any((s) => s.startsWith('Motor reached 112 °C')), isTrue);
      expect(out.any((s) => s.startsWith('Controller')), isFalse);
      expect(out.any((s) => s.startsWith('Boost was active for 30 s')), isTrue);
    });

    test('mentions changed settings and their effect; calm otherwise', () {
      final prev = testRide(start: t0, maxSpeedKph: 50);
      final now =
          testRide(start: t0.add(const Duration(days: 1)), maxSpeedKph: 56);
      final diff = RideAnalysis.configDiff(
          testDump(maxLineA: 200), testDump(maxLineA: 240));
      final out = RideAnalysis.suggestions(now, previous: prev, diff: diff);
      expect(
          out.first,
          contains(
              'Settings changed since the previous ride (Max line (battery) current)'));
      expect(out.first, contains('top speed +6.0 km/h'));

      expect(RideAnalysis.suggestions(testRide(start: t0)),
          ['First saved ride: nothing to compare with yet.']);
      expect(RideAnalysis.suggestions(testRide(start: t0), previous: prev),
          ['Nothing stood out compared with the previous ride.']);
    });

    test('Copy for AI text is compact, unit aware and makes no request', () {
      final prev = testRide(start: t0);
      final now = testRide(start: t0.add(const Duration(days: 1)));
      final diff = RideAnalysis.configDiff(
          testDump(maxLineA: 200), testDump(maxLineA: 240));
      final text = RideAnalysis.aiPrompt(now,
          previous: prev,
          diff: diff,
          suggestions: const ['note'],
          unit: SpeedUnit.mph);
      expect(text, contains('Suggestions only'));
      expect(text, contains('- Max line (battery) current: 200 A -> 240 A'));
      expect(text, contains('top 31.1 mph'));
      expect(text, contains('3.11 mi'));
      expect(text, contains('- note'));
      expect(text, isNot(contains('http')));
      expect(text.length, lessThan(1500));
    });
  });
}

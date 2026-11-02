import 'package:arcdash/models/drive_state.dart';
import 'package:arcdash/models/gps_calibration.dart';
import 'package:arcdash/models/speed_suggestions.dart';
import 'package:arcdash/services/calibration_csv.dart';
import 'package:arcdash/services/calibration_settings.dart';
import 'package:arcdash/widgets/gear_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../calibration/ride_fixtures.dart';

String _label(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('gear-chip-label'))).data!;

Color? _bg(WidgetTester tester) => (tester
        .widget<Container>(find.byKey(const ValueKey('gear-chip')))
        .decoration as BoxDecoration?)
    ?.color;

Future<void> _show(WidgetTester tester, GearStatus? s) =>
    tester.pumpWidget(MaterialApp(
        home: Scaffold(appBar: AppBar(actions: [GearChipView(status: s)]))));

void main() {
  testWidgets('chip shows D · level, N, R, BST and — when unknown',
      (tester) async {
    await _show(tester, GearStatus.fromE2Byte(0x25)); // D, mid, moving
    expect(_label(tester), 'D · MID');

    await _show(tester, GearStatus.fromE2Byte(0x00));
    expect(_label(tester), 'N');

    await _show(tester, GearStatus.fromE2Byte(0x02));
    expect(_label(tester), 'R');

    await _show(tester, GearStatus.fromE2Byte(0x09, boost: true));
    expect(_label(tester), 'D · BST');
    expect(_bg(tester), const Color(0xFFFFB020));

    await _show(tester, null);
    expect(_label(tester), '—');
  });

  test('calibration CSV keeps gear + boost per sample', () {
    final base = ride([
      ...steadyLegs(6, [30, 50])
    ]);
    final gears = [
      GearStatus.fromE2Byte(0x01),
      GearStatus.fromE2Byte(0x05),
      GearStatus.fromE2Byte(0x09, boost: true),
      null,
    ];
    final samples = [
      for (var i = 0; i < base.length; i++)
        CalibrationSample(
          at: base[i].at,
          gps: base[i].gps,
          rpm: base[i].rpm,
          controllerKph: base[i].controllerKph,
          braking: base[i].braking,
          gear: gears[i % gears.length],
        ),
    ];
    final analysis = const CalibrationAnalyzer().analyze(samples);
    final csv = CalibrationCsv.build(
      samples: samples,
      analysis: analysis,
      fit: CalibrationFit.fromAnalysis(analysis),
      dkdSnapshots: const [],
      settings: const CalibrationSettings(
        ble: BleSpeedSettings(
            wheelRadius: 12, wheelWidth: 120, wheelRatio: 70, rateRatio: 4000),
        speedPulses: 12,
        spdPulseNum: 36361,
        source: 'test',
      ),
      appVersion: 'test',
      exportedAt: t0,
    );
    expect(csv, contains('direction,speed_level,boost'));
    final back = CalibrationCsv.parse(csv).samples;
    expect(back.length, samples.length);
    for (var i = 0; i < samples.length; i++) {
      expect(back[i].gear, samples[i].gear, reason: 'row $i');
    }
  });
}

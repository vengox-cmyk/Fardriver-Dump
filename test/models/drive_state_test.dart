import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/models/controller_state.dart';
import 'package:arcdash/models/drive_state.dart';
import 'package:arcdash/models/telemetry_quality.dart';
import 'package:arcdash/utils/packet_parser.dart' show PacketParser;

List<int> _hex(String s) => [
      for (var i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16)
    ];

void main() {
  group('GearStatus.fromE2Byte', () {
    test('official examples', () {
      expect(GearStatus.fromE2Byte(0x89).label, 'D · HIGH');
      expect(GearStatus.fromE2Byte(0x85).label, 'D · MID');
      expect(GearStatus.fromE2Byte(0x81).label, 'D · LOW');
      final moving = GearStatus.fromE2Byte(0xA9);
      expect(moving.label, 'D · HIGH');
      expect(moving.wheelMoving, isTrue);
      expect(GearStatus.fromE2Byte(0x89).wheelMoving, isFalse);
    });

    test('N and R ignore the level; level 3 shows as high', () {
      expect(GearStatus.fromE2Byte(0x88).label, 'N');
      expect(GearStatus.fromE2Byte(0x8A).label, 'R');
      expect(GearStatus.fromE2Byte(0x0D).level, SpeedLevel.high);
      expect(GearStatus.fromE2Byte(0x03).direction, DriveDirection.unknown);
    });

    test('official-style labels', () {
      expect(GearStatus.fromE2Byte(0x81).officialLabel, 'DL');
      expect(GearStatus.fromE2Byte(0x85).officialLabel, 'DM');
      expect(GearStatus.fromE2Byte(0x89).officialLabel, 'D');
      expect(GearStatus.fromE2Byte(0x89, boost: true).officialLabel, 'Bst');
    });

    test('boost replaces the level only in D', () {
      expect(GearStatus.fromE2Byte(0x81, boost: true).label, 'D · BST');
      expect(GearStatus.fromE2Byte(0x80, boost: true).label, 'N');
      expect(GearStatus.fromE2Byte(0x82, boost: true).label, 'R');
    });
  });

  test('D6 Global_state3 bit 2 is boost', () {
    // Real frame: b8 = 0x00, b9 = 0x04 -> Global_state3 0x0400, no boost.
    final noBoost = PacketParser.parseStatusPacket(
        _hex('aab3f2bb82010030000481000b000a06'))!;
    expect(noBoost.address, 0xD6);
    final u = PacketParser.extractTelemetry(noBoost)!;
    expect(u.boost, isFalse);
    expect(u.mosTempC, 11);
    final data = List<int>.filled(12, 0)
      ..[6] = 0x04
      ..[7] = 0x04;
    expect(GearStatus.globalState3(data), 0x0404);
    expect(GearStatus.boostFromD6(data), isTrue);
    data[6] = 0x00;
    expect(GearStatus.boostFromD6(data), isFalse);
  });

  test('BT capture: gear levels and both boost episodes decode', () {
    final lines = File('test/fixtures/bt_frames/e2_d6_frames.csv')
        .readAsLinesSync()
        .where((l) => !l.startsWith('#') && !l.startsWith('time_local'));
    final labels = <String, int>{};
    final boostTimes = <String>[];
    var d6 = 0;
    for (final line in lines) {
      final cells = line.split(',');
      final parsed = PacketParser.parseStatusPacket(_hex(cells[2]));
      expect(parsed, isNotNull, reason: line);
      final update = PacketParser.extractTelemetry(parsed!)!;
      if (cells[1] == 'E2') {
        expect(parsed.address, 0xE2);
        final status = GearStatus.fromE2Byte(parsed.rawData[0]);
        labels[status.label] = (labels[status.label] ?? 0) + 1;
        expect(update.direction, status.direction);
      } else {
        expect(parsed.address, 0xD6);
        d6++;
        if (update.boost!) boostTimes.add(cells[0]);
      }
    }
    expect(labels, {'D · LOW': 123, 'D · MID': 33, 'D · HIGH': 356});
    expect(d6, 63);
    expect(boostTimes.first, '01:24:15.250');
    expect(boostTimes, contains('01:24:43.255'));
    expect(boostTimes.length, 9);
  });

  group('ControllerState.gearStatus', () {
    final now = DateTime(2026, 11, 2, 12);
    ControllerState state(
            {DateTime? gearAt, DateTime? boostAt, bool boost = false}) =>
        ControllerState(
          lastUpdate: now,
          gear: 1,
          driveDirection: DriveDirection.drive,
          boostActive: boost,
          boostAt: boostAt,
          telemetrySamples: {
            ControllerTelemetry.gear: TelemetrySample(
                value: 1,
                source: TelemetrySource.controller,
                capturedAt: gearAt ?? now),
          },
        );

    test('fresh gear and held boost', () {
      expect(state().gearStatus(now)!.label, 'D · MID');
      expect(
          state(boost: true, boostAt: now.subtract(const Duration(seconds: 2)))
              .gearStatus(now)!
              .label,
          'D · BST');
    });

    test('stale boost is dropped, stale gear is hidden', () {
      expect(
          state(boost: true, boostAt: now.subtract(const Duration(seconds: 9)))
              .gearStatus(now)!
              .label,
          'D · MID');
      expect(
          state(gearAt: now.subtract(const Duration(seconds: 9)))
              .gearStatus(now),
          isNull);
      expect(ControllerState(lastUpdate: now).gearStatus(now), isNull);
    });
  });
}

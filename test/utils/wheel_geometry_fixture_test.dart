import 'package:arcdash/utils/packet_parser.dart';
import 'package:arcdash/utils/unit_converter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real 0xD0 frame from a live diagnostic log (owner's ND96 controller,
/// 2026-10-24, seen 12x identical). The official FarDriver app shows
/// WheelRadius 12, WheelWidth 120, WheelRatio 70, GearRatio 4 (RateRatio 4000)
/// for this controller.
const _realD0Frame = [
  0xAA, 0xAF, 0x08, 0x61, 0x00, 0xAB, 0x46, 0x0C, //
  0x1E, 0x78, 0xA0, 0x0F, 0x29, 0x15, 0x1E, 0xE0,
];

void main() {
  group('0xD0 wheel geometry (real frame fixture)', () {
    test('frame passes CRC and maps to block 0xD0', () {
      final packet = PacketParser.parseStatusPacket(_realD0Frame);
      expect(packet, isNotNull);
      expect(packet!.address, 0xD0);
    });

    test('decodes radius 12, ratio 70, width 120, rateRatio 4000', () {
      final packet = PacketParser.parseStatusPacket(_realD0Frame)!;
      final update = PacketParser.extractTelemetry(packet)!;
      expect(update.wheelRadius, 12);
      expect(update.wheelRatio, 70);
      expect(update.wheelWidth, 120);
      expect(update.rateRatio, 4000);
    });

    test('gives ~0.0223 km/h per motor rpm (120/70-12 tyre, 4:1)', () {
      final u = PacketParser.extractTelemetry(
          PacketParser.parseStatusPacket(_realD0Frame)!)!;
      final kphPerRpm = UnitConverter.measureSpeedToKph(
        measureSpeed: 1,
        wheelRadius: u.wheelRadius!,
        wheelWidth: u.wheelWidth!,
        wheelRatio: u.wheelRatio!,
        rateRatio: u.rateRatio!,
      );
      expect(kphPerRpm, closeTo(0.02228, 0.0001));
      // 3500 rpm (LowSpeed) -> ~78 km/h: 875 wheel rpm x ~1.49 m tyre.
      expect(kphPerRpm * 3500, closeTo(78.0, 0.5));
    });
  });
}

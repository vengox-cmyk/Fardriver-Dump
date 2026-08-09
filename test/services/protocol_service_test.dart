import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/services/protocol_service.dart';
import 'package:arcdash/utils/crc_calculator.dart';

void main() {
  group('ProtocolService', () {
    test('buildWritePacket builds valid 8-byte packet with correct CRC', () {
      final packet = ProtocolService.buildWritePacket(0x15, 1000);
      expect(packet.length, 8);
      expect(packet[0], 0xAA);
      expect(packet[1], 0x46);
      expect(packet[2], 0x15);
      expect(packet[3], 0x15);
      expect(packet[4], 1000 & 0xFF);
      expect(packet[5], (1000 >> 8) & 0xFF);
      expect(CrcCalculator.verifyCRC(packet, 8), isTrue);
    });

    test('buildWritePacket16 and buildSysCmd construct expected payloads', () {
      final sysCmdPacket =
          ProtocolService.buildSysCmd(SysCmd.nonFollowingStatus);
      expect(sysCmdPacket.length, 8);
      expect(sysCmdPacket[2], FardriverAddr.sysCmd);
      expect(sysCmdPacket[4], 0x88);
      expect(sysCmdPacket[5], SysCmd.nonFollowingStatus);
      expect(CrcCalculator.verifyCRC(sysCmdPacket, 8), isTrue);
    });

    test('setMaxLineCurrPacket scales amps by 4 and clamps correctly', () {
      final packet = ProtocolService.setMaxLineCurrPacket(50.0);
      expect(packet[2], FardriverAddr.maxLineCurr);
      final rawVal = packet[4] | (packet[5] << 8);
      expect(rawVal, 200);

      // Clamp test
      final clampedPacket = ProtocolService.setMaxLineCurrPacket(20000.0);
      final clampedVal = clampedPacket[4] | (clampedPacket[5] << 8);
      expect(clampedVal, 0xFFFF);
    });

    test('setMaxSpeedPacket builds packet with clamped raw RPM', () {
      final packet = ProtocolService.setMaxSpeedPacket(3000);
      expect(packet[2], FardriverAddr.maxSpeed);
      final rawVal = packet[4] | (packet[5] << 8);
      expect(rawVal, 3000);
    });

    test('setThrottleResponsePacket shifts mode correctly', () {
      final packet = ProtocolService.setThrottleResponsePacket(1); // Sport
      expect(packet[2], FardriverAddr.throttleResponse);
      final rawVal = packet[4] | (packet[5] << 8);
      expect(rawVal, (1 & 0x03) << 2);
    });

    test('kphToMaxSpeedRaw calculates raw RPM and handles zero/negative factor',
        () {
      final rawRpm = ProtocolService.kphToMaxSpeedRaw(
        kph: 50.0,
        wheelRadius: 10,
        wheelWidth: 100,
        wheelRatio: 80,
        rateRatio: 10,
      );
      expect(rawRpm, greaterThan(0));

      final invalidRpm = ProtocolService.kphToMaxSpeedRaw(
        kph: 50.0,
        wheelRadius: 0,
        wheelWidth: 0,
        wheelRatio: 0,
        rateRatio: 0,
      );
      expect(invalidRpm, 0);
    });

    test('verifyWriteAck validates write acknowledgments', () {
      final packet = ProtocolService.buildWritePacket(0x15, 1000);
      expect(
          ProtocolService.verifyWriteAck(packet,
              expectedAddress: 0x15, expectedValue: 1000),
          isTrue);
      expect(ProtocolService.verifyWriteAck(packet, expectedAddress: 0x19),
          isFalse);
      expect(
          ProtocolService.verifyWriteAck(packet, expectedValue: 2000), isFalse);

      final invalidShort = [0xAA, 0x46];
      expect(ProtocolService.verifyWriteAck(invalidShort), isFalse);

      final invalidHeader = [0xBB, 0x46, 0x15, 0x15, 0x00, 0x00, 0x00, 0x00];
      expect(ProtocolService.verifyWriteAck(invalidHeader), isFalse);
    });
  });
}

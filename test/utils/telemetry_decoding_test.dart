import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/utils/packet_parser.dart';
import 'package:arcdash/utils/crc_calculator.dart';

ParsedPacket _createParsedPacket(int address, List<int> raw12Data) {
  final full = Uint8List(16);
  full[0] = 0xAA;
  // find id for address or use dummy 0
  int id = 0;
  for (int i = 0; i < flashReadAddr.length; i++) {
    if (flashReadAddr[i] == address) {
      id = i;
      break;
    }
  }
  full[1] = id;
  for (int i = 0; i < 12; i++) {
    full[2 + i] = raw12Data[i];
  }
  CrcCalculator.computeCRC(full, 16);
  return ParsedPacket(
    address: address,
    rawData: raw12Data,
    fullPacket: full,
  );
}

void main() {
  group('PacketParser - extractTelemetry', () {
    test('extracts telemetry for 0xE2 (AddrE2: speed, flags)', () {
      // rawData 12 bytes
      // d[0] = stateByte (0x01 = forward, 0x02 = reverse, 0x04 = gear 1, 0x08 = gear 2...)
      // d[2] = errByte1 (0x01 = hall, 0x02 = throttle, 0x40 = motorTempProtect, 0x80 = ctrlTempProtect)
      // d[3] = errByte2 (0x80 = brake)
      // d[6], d[7] = measureSpeed uint16LE
      final raw = List<int>.filled(12, 0);
      raw[0] = 0x01 | (0x02 << 2); // forward = true, gear = 2
      raw[2] = 0x01 |
          0x02 |
          0x40 |
          0x80; // hall, throttle, motorTempProtect, ctrlTempProtect
      raw[3] = 0x80; // brake = true
      raw[6] = 0xE8; // measureSpeed = 1000 (0x03E8)
      raw[7] = 0x03;

      final packet = _createParsedPacket(0xE2, raw);
      final update = PacketParser.extractTelemetry(packet);

      expect(update, isNotNull);
      expect(update!.measureSpeed, 1000);
      expect(update.forward, isTrue);
      expect(update.reverse, isFalse);
      expect(update.gear, 2);
      expect(update.brake, isTrue);
      expect(update.motorHallError, isTrue);
      expect(update.throttleError, isTrue);
      expect(update.motorTempProtect, isTrue);
      expect(update.controllerTempProtect, isTrue);
    });

    test('extracts telemetry for 0xE8 (AddrE8: voltage, current)', () {
      final raw = List<int>.filled(12, 0);
      // deciVolts at d[0..1] = 720 (72.0 V)
      raw[0] = 0xD0;
      raw[1] = 0x02;
      // lineCurrent at d[4..5] = 200 (50.0 A)
      raw[4] = 0xC8;
      raw[5] = 0x00;

      final packet = _createParsedPacket(0xE8, raw);
      final update = PacketParser.extractTelemetry(packet);

      expect(update, isNotNull);
      expect(update!.voltageV, closeTo(72.0, 0.01));
      expect(update.currentA, closeTo(50.0, 0.01));
    });

    test('extracts telemetry for 0xEE (AddrEE: phase currents)', () {
      final raw = List<int>.filled(12, 0);
      // phaseA at d[4..6] -> raw 100 -> 19.53125 A
      raw[4] = 0x00;
      raw[5] = 0x00;
      raw[6] = 0x64;
      // phaseC at d[7..9] -> raw 400 -> sqrt(400)=20 -> 39.0625 A
      raw[7] = 0x00;
      raw[8] = 0x01;
      raw[9] = 0x90;

      final packet = _createParsedPacket(0xEE, raw);
      final update = PacketParser.extractTelemetry(packet);

      expect(update, isNotNull);
      expect(update!.phaseACurrA, closeTo(19.53125, 0.01));
      expect(update.phaseCCurrA, closeTo(39.0625, 0.01));
    });

    test('extracts telemetry for 0xF4 (AddrF4: motor temp, battery SOC)', () {
      final raw = List<int>.filled(12, 0);
      // motorTemp at d[0..1] = 65
      raw[0] = 65;
      raw[1] = 0;
      // battCap at d[3] = 85%
      raw[3] = 85;

      final packet = _createParsedPacket(0xF4, raw);
      final update = PacketParser.extractTelemetry(packet);

      expect(update, isNotNull);
      expect(update!.motorTempC, 65.0);
      expect(update.battCapPercent, 85);
    });

    test('extracts telemetry for 0xD6 (AddrD6: MosFET temp)', () {
      final raw = List<int>.filled(12, 0);
      // mosTemp at d[10..11] = 42
      raw[10] = 42;
      raw[11] = 0;

      final packet = _createParsedPacket(0xD6, raw);
      final update = PacketParser.extractTelemetry(packet);

      expect(update, isNotNull);
      expect(update!.mosTempC, 42.0);
    });

    test('extracts telemetry for 0xD0 (AddrD0: wheel geometry)', () {
      final raw = List<int>.filled(12, 0);
      raw[4] = 12; // wheelRadius
      raw[5] = 80; // wheelRatio
      raw[6] = 120; // wheelWidth
      raw[8] = 10; // rateRatio uint16LE
      raw[9] = 0;

      final packet = _createParsedPacket(0xD0, raw);
      final update = PacketParser.extractTelemetry(packet);

      expect(update, isNotNull);
      expect(update!.wheelRadius, 12);
      expect(update.wheelRatio, 80);
      expect(update.wheelWidth, 120);
      expect(update.rateRatio, 10);
    });

    test('extracts telemetry for 0x12 (Addr12: MaxSpeed)', () {
      final raw = List<int>.filled(12, 0);
      raw[6] = 0xB8; // maxSpeed = 3000 (0x0BB8)
      raw[7] = 0x0B;

      final packet = _createParsedPacket(0x12, raw);
      final update = PacketParser.extractTelemetry(packet);

      expect(update, isNotNull);
      expect(update!.maxSpeed, 3000);
    });

    test('extracts telemetry for 0x18 (Addr18: MaxLineCurr)', () {
      final raw = List<int>.filled(12, 0);
      raw[2] = 200; // maxLineCurrRaw = 200
      raw[3] = 0;

      final packet = _createParsedPacket(0x18, raw);
      final update = PacketParser.extractTelemetry(packet);

      expect(update, isNotNull);
      expect(update!.maxLineCurrRaw, 200);
    });

    test('extracts telemetry for 0x0C (Addr0C: battery calibration)', () {
      final raw = List<int>.filled(12, 0);
      raw[2] = 0x58; // zeroBattCoeff = 600 (0x0258)
      raw[3] = 0x02;
      raw[4] = 0x48; // fullBattCoeff = 840 (0x0348)
      raw[5] = 0x03;

      final packet = _createParsedPacket(0x0C, raw);
      final update = PacketParser.extractTelemetry(packet);

      expect(update, isNotNull);
      expect(update!.zeroBattCoeff, 600);
      expect(update.fullBattCoeff, 840);
    });

    test(
        'returns null for unknown/unsupported address or invalid rawData length',
        () {
      final raw = List<int>.filled(12, 0);
      final packetUnknown = _createParsedPacket(0xFF, raw);
      expect(PacketParser.extractTelemetry(packetUnknown), isNull);

      const packetShort = ParsedPacket(
        address: 0xE2,
        rawData: [0x01, 0x02],
        fullPacket: [],
      );
      expect(PacketParser.extractTelemetry(packetShort), isNull);
    });
  });
}

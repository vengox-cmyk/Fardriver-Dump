import 'dart:math' as math;
import 'package:biketunes/utils/crc_calculator.dart';

/// Memory address lookup table for rotating status packet IDs (0–54).
/// id < 0x37 maps to flash_read_addr[id] from the FarDriver protocol repo.
const List<int> flashReadAddr = [
  0xE2, 0xE8, 0xEE, 0x00, 0x06, 0x0C, 0x12,
  0xE2, 0xE8, 0xEE, 0x18, 0x1E, 0x24, 0x2A,
  0xE2, 0xE8, 0xEE, 0x30, 0x5D, 0x63, 0x69,
  0xE2, 0xE8, 0xEE, 0x7C, 0x82, 0x88, 0x8E,
  0xE2, 0xE8, 0xEE, 0x94, 0x9A, 0xA0, 0xA6,
  0xE2, 0xE8, 0xEE, 0xAC, 0xB2, 0xB8, 0xBE,
  0xE2, 0xE8, 0xEE, 0xC4, 0xCA, 0xD0,
  0xE2, 0xE8, 0xEE, 0xD6, 0xDC, 0xF4, 0xFA,
];

/// Result of parsing a single 16-byte status packet.
class ParsedPacket {
  final int address;
  final List<int> rawData; // 12 data bytes (B2–B13)
  final List<int> fullPacket;

  const ParsedPacket({
    required this.address,
    required this.rawData,
    required this.fullPacket,
  });
}

/// Telemetry values extracted from address-specific structs.
class TelemetryUpdate {
  // From 0xE2 (AddrE2)
  final int? measureSpeed; // raw RPM ticks
  final bool? forward;
  final bool? reverse;
  final int? gear;
  final bool? brake;
  final bool? motorHallError;
  final bool? throttleError;
  final bool? motorTempProtect;
  final bool? controllerTempProtect;

  // From 0xE8 (AddrE8)
  final double? voltageV;    // deci_volts / 10.0
  final double? currentA;    // lineCurrent / 4.0

  // From 0xEE (AddrEE)
  final double? phaseACurrA; // 1.953125 * sqrt(raw)
  final double? phaseCCurrA;

  // From 0xF4 (AddrF4)
  final double? motorTempC;  // raw int16 (degrees C)
  final int? battCapPercent; // SOC 0–100

  // From 0xD6 (AddrD6)
  final double? mosTempC;    // MosTemp (controller temp, degrees C)

  // From 0xD0 (AddrD0) — wheel geometry for speed calculation
  final int? wheelRadius;
  final int? wheelWidth;
  final int? wheelRatio;
  final int? rateRatio;

  // From 0x12 (Addr12)
  final int? maxSpeed;

  // From 0x18 (Addr18)
  final int? maxLineCurrRaw; // / 4 = amps

  // From 0x0C (Addr0C) — battery calibration
  final int? zeroBattCoeff;
  final int? fullBattCoeff;

  const TelemetryUpdate({
    this.measureSpeed,
    this.forward,
    this.reverse,
    this.gear,
    this.brake,
    this.motorHallError,
    this.throttleError,
    this.motorTempProtect,
    this.controllerTempProtect,
    this.voltageV,
    this.currentA,
    this.phaseACurrA,
    this.phaseCCurrA,
    this.motorTempC,
    this.battCapPercent,
    this.mosTempC,
    this.wheelRadius,
    this.wheelWidth,
    this.wheelRatio,
    this.rateRatio,
    this.maxSpeed,
    this.maxLineCurrRaw,
    this.zeroBattCoeff,
    this.fullBattCoeff,
  });
}

class PacketParser {
  /// Extracts 16-byte packets from a raw byte stream buffer.
  /// Looks for 0xAA magic byte, validates CRC, and returns valid packets.
  static List<List<int>> extractPackets(List<int> buffer) {
    final packets = <List<int>>[];
    int i = 0;
    while (i < buffer.length - 15) {
      if (buffer[i] == 0xAA) {
        final candidate = buffer.sublist(i, i + 16);
        if (CrcCalculator.verifyCRC(candidate, 16)) {
          packets.add(candidate);
          i += 16;
          continue;
        }
      }
      // Also check for 8-byte write ack packets starting with 0xAA
      if (buffer[i] == 0xAA && i < buffer.length - 7) {
        final candidate8 = buffer.sublist(i, i + 8);
        if (CrcCalculator.verifyCRC(candidate8, 8)) {
          packets.add(candidate8);
          i += 8;
          continue;
        }
      }
      i++;
    }
    return packets;
  }

  /// Parses a 16-byte status packet.
  static ParsedPacket? parseStatusPacket(List<int> packet) {
    if (packet.length < 16) return null;
    if (packet[0] != 0xAA) return null;
    if (!CrcCalculator.verifyCRC(packet, 16)) return null;

    final idByte = packet[1];
    final id = idByte & 0x3F; // lower 6 bits
    if (id >= flashReadAddr.length) return null;

    final address = flashReadAddr[id];
    final rawData = packet.sublist(2, 14);

    return ParsedPacket(address: address, rawData: rawData, fullPacket: packet);
  }

  /// Reads a little-endian int16 from two bytes.
  static int readInt16LE(List<int> data, int offset) {
    final val = data[offset] | (data[offset + 1] << 8);
    return val > 0x7FFF ? val - 0x10000 : val;
  }

  /// Reads a little-endian uint16 from two bytes.
  static int readUint16LE(List<int> data, int offset) {
    return data[offset] | (data[offset + 1] << 8);
  }

  /// Reads 24-bit big-endian value used for phase currents.
  static double readPhaseCurrent(List<int> data, int offset) {
    final raw = (data[offset] << 16) | (data[offset + 1] << 8) | data[offset + 2];
    return 1.953125 * math.sqrt(raw.toDouble());
  }

  /// Extracts telemetry updates from a parsed packet by address.
  static TelemetryUpdate? extractTelemetry(ParsedPacket packet) {
    final d = packet.rawData;

    switch (packet.address) {
      case 0xE2: // AddrE2 — speed, status flags
        final stateByte = d[0];
        final errByte1 = d[2];
        final errByte2 = d[3];
        final measureSpeed = readUint16LE(d, 6); // bytes 8-9 relative to B0 = bytes 6-7 in rawData
        return TelemetryUpdate(
          measureSpeed: measureSpeed,
          forward: (stateByte & 0x01) != 0,
          reverse: (stateByte & 0x02) != 0,
          gear: (stateByte >> 2) & 0x03,
          brake: (errByte2 & 0x80) != 0,
          motorHallError: (errByte1 & 0x01) != 0,
          throttleError: (errByte1 & 0x02) != 0,
          motorTempProtect: (errByte1 & 0x40) != 0,
          controllerTempProtect: (errByte1 & 0x80) != 0,
        );

      case 0xE8: // AddrE8 — voltage, line current
        final deciVolts = readInt16LE(d, 0);
        final lineCurrent = readInt16LE(d, 4);
        return TelemetryUpdate(
          voltageV: deciVolts / 10.0,
          currentA: lineCurrent / 4.0,
        );

      case 0xEE: // AddrEE — phase currents
        // PhaseACurr at bytes 4-6 (0xF0), PhaseCCurr at bytes 7-9 (0xF1-ish)
        final phaseA = readPhaseCurrent(d, 4);
        final phaseC = readPhaseCurrent(d, 7);
        return TelemetryUpdate(
          phaseACurrA: phaseA,
          phaseCCurrA: phaseC,
        );

      case 0xF4: // AddrF4 — motor temp, battery SOC
        final motorTemp = readInt16LE(d, 0);
        final battCap = d[3].toSigned(8); // int8
        return TelemetryUpdate(
          motorTempC: motorTemp.toDouble(),
          battCapPercent: battCap.clamp(0, 100),
        );

      case 0xD6: // AddrD6 — MosFET temp (controller)
        // MosTemp is at bytes 10-11 (last int16 of the struct)
        final mosTemp = readInt16LE(d, 10);
        return TelemetryUpdate(mosTempC: mosTemp.toDouble());

      case 0xD0: // AddrD0 — wheel geometry
        final wheelRatio = d[5]; // WheelRatio at byte 5 of data
        final wheelRadius = d[4]; // WheelRadius at byte 4
        final rateRatio = readUint16LE(d, 8); // RateRatio
        final wheelWidth = d[6]; // WheelWidth
        return TelemetryUpdate(
          wheelRadius: wheelRadius,
          wheelWidth: wheelWidth,
          wheelRatio: wheelRatio,
          rateRatio: rateRatio,
        );

      case 0x12: // Addr12 — MaxSpeed
        final maxSpeed = readUint16LE(d, 6); // bytes 8-9 of packet = 6-7 in rawData
        return TelemetryUpdate(maxSpeed: maxSpeed);

      case 0x18: // Addr18 — MaxLineCurr
        final maxLineCurr = readUint16LE(d, 2); // bytes 4-5 of packet
        return TelemetryUpdate(maxLineCurrRaw: maxLineCurr);

      case 0x0C: // Addr0C — battery calibration
        final zeroBatt = readInt16LE(d, 2);
        final fullBatt = readInt16LE(d, 4);
        return TelemetryUpdate(zeroBattCoeff: zeroBatt, fullBattCoeff: fullBatt);

      default:
        return null;
    }
  }

  /// Formats a packet as hex string for debug display.
  static String toHexString(List<int> packet) {
    return packet.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
  }
}

extension SignedExtension on int {
  int toSigned(int bits) {
    final max = 1 << (bits - 1);
    if (this >= max) return this - (1 << bits);
    return this;
  }
}

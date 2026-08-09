import 'package:biketunes/utils/crc_calculator.dart';

/// Known memory addresses for FarDriver protocol.
class FardriverAddr {
  static const int maxSpeed = 0x15;
  static const int maxLineCurr = 0x19;
  static const int throttleResponse = 0x1A;
  static const int sysCmd = 0xA0;
  static const int ratedSpeed = 0x18;
  static const int polePairs = 0x14;
  static const int ratedPower = 0x16;
  static const int ratedVoltage = 0x17;
}

/// System command values written to address 0xA0 with prefix 0x88.
class SysCmd {
  static const int nonFollowingStatus = 0x01;
  static const int startSelfLearn = 0x02;
  static const int stopBalance = 0x03;
  static const int startDataGather = 0x06;
}

class ProtocolService {
  /// Builds the 8-byte write packet used to set a 16-bit value at [addr].
  ///
  /// Format: [0xAA][0x46][addr][addr][lo][hi][crc0][crc1]
  /// compute_length = 6 = (8 - 2), flags = 1 (bit 6 set → 0x40), so byte1 = 6 | 0x40 = 0x46
  static List<int> buildWritePacket(int addr, int value) {
    final packet = List<int>.filled(8, 0);
    packet[0] = 0xAA;
    packet[1] = 0x46; // compute_length=6, flags=1 (write)
    packet[2] = addr & 0xFF;
    packet[3] = addr & 0xFF; // addr_confirm = same addr
    packet[4] = value & 0xFF; // data low byte
    packet[5] = (value >> 8) & 0xFF; // data high byte
    CrcCalculator.computeCRC(packet, 8);
    return packet;
  }

  /// Builds the system command packet (writes [0x88, cmd] to address 0xA0).
  static List<int> buildSysCmd(int cmd) {
    return buildWritePacket16(FardriverAddr.sysCmd, 0x88, cmd);
  }

  /// Builds a write packet with two explicit data bytes (not a single uint16).
  static List<int> buildWritePacket16(int addr, int byte0, int byte1) {
    final packet = List<int>.filled(8, 0);
    packet[0] = 0xAA;
    packet[1] = 0x46;
    packet[2] = addr & 0xFF;
    packet[3] = addr & 0xFF;
    packet[4] = byte0 & 0xFF;
    packet[5] = byte1 & 0xFF;
    CrcCalculator.computeCRC(packet, 8);
    return packet;
  }

  /// Packet to start status streaming (non-following status mode).
  static List<int> startStatusStreamPacket() => buildSysCmd(SysCmd.nonFollowingStatus);

  /// Sets the max line current. [amps] is the desired value in A.
  /// Raw value = amps * 4.
  static List<int> setMaxLineCurrPacket(double amps) {
    final raw = (amps * 4).round().clamp(0, 0xFFFF);
    return buildWritePacket(FardriverAddr.maxLineCurr, raw);
  }

  /// Sets max speed. [maxSpeedRaw] is the raw uint16 RPM value.
  static List<int> setMaxSpeedPacket(int maxSpeedRaw) {
    return buildWritePacket(FardriverAddr.maxSpeed, maxSpeedRaw.clamp(0, 0xFFFF));
  }

  /// Sets throttle response mode: 0=Line, 1=Sport, 2=ECO.
  static List<int> setThrottleResponsePacket(int mode) {
    // ThrottleResponse occupies bits 2-3 of addr 0x1A (cfg26l byte)
    // Write mode in bits 2-3, preserve other bits as 0 for simplicity
    final val = (mode & 0x03) << 2;
    return buildWritePacket(FardriverAddr.throttleResponse, val);
  }

  /// Converts a desired speed in km/h to a raw MaxSpeed RPM value.
  /// Uses the inverse of the speed formula with default wheel geometry.
  /// speedKph = measureSpeed × (0.00376991136 × (radius×1270 + width×ratio) / rateRatio)
  static int kphToMaxSpeedRaw({
    required double kph,
    required int wheelRadius,
    required int wheelWidth,
    required int wheelRatio,
    required int rateRatio,
  }) {
    final factor =
        0.00376991136 * (wheelRadius * 1270.0 + wheelWidth * wheelRatio) / rateRatio;
    if (factor <= 0) return 0;
    return (kph / factor).round().clamp(0, 0xFFFF);
  }

  /// Verifies an 8-byte write ack packet from the controller.
  static bool verifyWriteAck(List<int> packet) {
    if (packet.length < 8) return false;
    if (packet[0] != 0xAA) return false;
    return CrcCalculator.verifyCRC(packet, 8);
  }
}

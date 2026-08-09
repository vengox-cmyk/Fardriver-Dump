import 'dart:typed_data';

/// Shared protocol reference vectors and helpers for tests.
class TestProtocolHelpers {
  /// Known-good CRC test vector input and expected bytes.
  static final Uint8List crcSampleInput =
      Uint8List.fromList([0xAA, 0x03, 0xE2]);

  /// Sample 16-byte telemetry frame for 0xE2
  static final Uint8List sampleE2Packet = Uint8List.fromList([
    0xAA,
    0x10,
    0xE2,
    0x00,
    0x00,
    0x10,
    0x27,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x3C,
    0x7F
  ]);

  /// Sample 8-byte write ACK frame
  static final Uint8List sampleAckPacket =
      Uint8List.fromList([0xAA, 0x08, 0x12, 0x00, 0x00, 0x00, 0x3C, 0x7F]);
}

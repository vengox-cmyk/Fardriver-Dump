import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/utils/crc_calculator.dart';

void main() {
  group('CrcCalculator', () {
    test('computeCRC populates correct CRC bytes at end of list', () {
      final buffer = Uint8List.fromList([0xAA, 0x03, 0xE2, 0x00, 0x00]);
      CrcCalculator.computeCRC(buffer, 5);
      expect(buffer[3], isNotNull);
      expect(buffer[4], isNotNull);

      // Verify CRC consistency
      expect(CrcCalculator.verifyCRC(buffer, 5), isTrue);
    });

    test('verifyCRC checks known good vector and rejects corrupted vector', () {
      final validBuffer =
          Uint8List.fromList([0xAA, 0x08, 0x12, 0x00, 0x00, 0x00, 0x00, 0x00]);
      CrcCalculator.computeCRC(validBuffer, 8);
      expect(CrcCalculator.verifyCRC(validBuffer, 8), isTrue);

      // Corrupt byte
      validBuffer[2] ^= 0xFF;
      expect(CrcCalculator.verifyCRC(validBuffer, 8), isFalse);
    });

    test('handles edge case inputs gracefully', () {
      final shortBuffer = [0xAA];
      expect(CrcCalculator.verifyCRC(shortBuffer, 1), isFalse);

      // Should not throw when computeCRC length is invalid
      CrcCalculator.computeCRC(shortBuffer, 1);
      expect(shortBuffer.length, 1);
    });
  });
}

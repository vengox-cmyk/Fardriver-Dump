import 'package:arcdash/utils/crc_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('16-byte upstream-shaped status vector has the documented CRC', () {
    final packet = <int>[
      0xAA,
      0x03,
      0x00,
      0x01,
      0x02,
      0x03,
      0x04,
      0x05,
      0x06,
      0x07,
      0x08,
      0x09,
      0x0A,
      0x0B,
      0x00,
      0x00,
    ];

    CrcCalculator.computeCRC(packet, 16);

    expect(packet.sublist(14), [0xFD, 0xFC]);
    expect(CrcCalculator.verifyCRC(packet, 16), isTrue);
  });

  test('8-byte write vector and every tested bit mutation are rejected', () {
    final packet = <int>[0xAA, 0x46, 0x18, 0x18, 0x20, 0x03, 0x00, 0x00];
    CrcCalculator.computeCRC(packet, 8);
    expect(CrcCalculator.verifyCRC(packet, 8), isTrue);

    for (var index = 0; index < 6; index++) {
      final mutated = [...packet]..[index] ^= 0x01;
      expect(CrcCalculator.verifyCRC(mutated, 8), isFalse);
    }
  });

  test('short and malformed inputs fail closed', () {
    expect(CrcCalculator.verifyCRC(const [0xAA], 8), isFalse);
    expect(CrcCalculator.verifyCRC(List<int>.filled(8, 0), 16), isFalse);
  });
}

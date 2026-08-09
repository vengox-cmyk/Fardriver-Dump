import 'package:arcdash/models/fardriver_memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Addr12 preserves unknown bytes and roundtrips raw storage', () {
    final raw = <int>[
      0x11,
      0x22,
      0x33,
      0x44,
      0x55,
      0x66,
      0x66,
      0x77,
      0x88,
      0x99,
      0xBB,
      0xCC,
    ];
    final block = Addr12Block.fromRaw(raw);

    expect(block.toRaw(), raw);
    expect(block.ld, 0x2211);
    expect(block.maxSpeed, 0x7766);
    expect(block.ratedVoltage, 0xCCBB);
  });

  test('Addr18 changes only throttle response bits', () {
    final raw = List<int>.filled(12, 0);
    raw[4] = 0xD1;
    final block = Addr18Block.fromRaw(raw);
    final changed = block.withThrottleResponse(2).toRaw();

    expect(changed[4] & 0x03, 0x01);
    expect((changed[4] >> 2) & 0x03, 0x02);
    expect((changed[4] >> 4) & 0x0F, (raw[4] >> 4) & 0x0F);
    expect(changed.sublist(5), raw.sublist(5));
  });

  test('signed and unsigned boundaries are decoded and validated', () {
    final raw = List<int>.filled(12, 0);
    raw[0] = 0xFF;
    raw[1] = 0x7F;
    final block = Addr12Block.fromRaw(raw);

    expect(block.ld, 32767);
    expect(() => Addr18Block.fromRaw(List<int>.filled(11, 0)),
        throwsFormatException);
    expect(() => block.withMaxSpeed(0x10000), throwsRangeError);
  });
}

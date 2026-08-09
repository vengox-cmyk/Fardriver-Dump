import 'package:arcdash/services/heb_file_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps the 26 FarDriver blocks and preserves CAN configuration bytes',
      () {
    final bytes =
        List<int>.generate(HebFile.expectedLength, (index) => index & 0xFF);
    final heb = HebFile.parse(bytes);

    expect(heb.blocks, hasLength(26));
    expect(heb.block(0x00), bytes.sublist(0, 12));
    expect(heb.block(0x12), bytes.sublist(36, 48));
    expect(heb.block(0xD0), bytes.sublist(300, 312));
    expect(heb.canConfiguration, bytes.sublist(312));
  });

  test('rejects truncated, extended, and unknown block access', () {
    expect(() => HebFile.parse(List.filled(695, 0)), throwsFormatException);
    expect(() => HebFile.parse(List.filled(697, 0)), throwsFormatException);
    expect(() => HebFile.parse(List.filled(696, 0)).block(0x01),
        throwsArgumentError);
  });
}

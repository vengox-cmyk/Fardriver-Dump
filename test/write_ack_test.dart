import 'package:arcdash/services/protocol_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fake ACK must correlate address and raw value', () {
    final ack = ProtocolService.buildWritePacket(0x18, 0x0320);

    expect(
      ProtocolService.verifyWriteAck(
        ack,
        expectedAddress: 0x18,
        expectedValue: 0x0320,
      ),
      isTrue,
    );
    expect(
      ProtocolService.verifyWriteAck(ack, expectedAddress: 0x19),
      isFalse,
    );
    expect(
      ProtocolService.verifyWriteAck(ack, expectedValue: 0x0321),
      isFalse,
    );
  });
}

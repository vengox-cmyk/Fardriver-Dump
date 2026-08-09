import 'package:arcdash/utils/crc_calculator.dart';
import 'package:arcdash/utils/packet_framer.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _statusPacket() {
  final packet = List<int>.filled(16, 0);
  packet[0] = 0xAA;
  packet[1] = 0x03;
  packet[2] = 0x42;
  CrcCalculator.computeCRC(packet, 16);
  return packet;
}

List<int> _ackPacket() {
  final packet = <int>[0xAA, 0x46, 0x18, 0x18, 0x20, 0x03, 0, 0];
  CrcCalculator.computeCRC(packet, 8);
  return packet;
}

void main() {
  test('emits every 16-byte packet for every split position', () {
    final packet = _statusPacket();
    for (var split = 0; split <= packet.length; split++) {
      final framer = PacketFramer();
      final first = framer.add(packet.sublist(0, split));
      if (split == packet.length) {
        expect(first, [packet], reason: '$split');
      } else {
        expect(first, isEmpty, reason: '$split');
        expect(framer.add(packet.sublist(split)), [packet], reason: '$split');
      }
    }
  });

  test('emits fragmented 8-byte ACKs and mixed packet sequences', () {
    final status = _statusPacket();
    final ack = _ackPacket();
    final framer = PacketFramer();

    expect(framer.add([0x01, 0x02, ...ack.sublist(0, 3)]), isEmpty);
    expect(framer.add([...ack.sublist(3), ...status]), [ack, status]);
  });

  test('drops bad CRC and resynchronizes after prefix noise', () {
    final broken = _statusPacket()..[4] ^= 0x01;
    final valid = _statusPacket();
    final framer = PacketFramer(maxBufferSize: 32);

    expect(framer.add([0x00, 0xFF, ...broken, 0x7F, ...valid]), [valid]);
    expect(framer.add(List<int>.filled(128, 0x11)), isEmpty);
    expect(framer.bufferedLength, lessThanOrEqualTo(32));
  });
}

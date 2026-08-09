import 'package:arcdash/utils/crc_calculator.dart';

class PacketFramer {
  final int maxBufferSize;
  final List<int> _buffer = [];

  PacketFramer({this.maxBufferSize = 512}) {
    if (maxBufferSize < 16) {
      throw ArgumentError.value(
          maxBufferSize, 'maxBufferSize', 'must be at least 16');
    }
  }

  int get bufferedLength => _buffer.length;

  void reset() => _buffer.clear();

  List<List<int>> add(Iterable<int> bytes) {
    _buffer.addAll(bytes);
    _trimBuffer();
    final packets = <List<int>>[];

    while (_buffer.isNotEmpty) {
      final start = _buffer.indexOf(0xAA);
      if (start < 0) {
        _buffer.clear();
        break;
      }
      if (start > 0) _buffer.removeRange(0, start);
      if (_buffer.length < 2) break;

      final isWriteResponse =
          (_buffer[1] & 0xC0) == 0x40 && (_buffer[1] & 0x3F) == 6;
      final packetLength = isWriteResponse ? 8 : 16;
      if (_buffer.length < packetLength) break;

      final candidate = _buffer.sublist(0, packetLength);
      if (CrcCalculator.verifyCRC(candidate, packetLength)) {
        packets.add(List.unmodifiable(candidate));
        _buffer.removeRange(0, packetLength);
      } else {
        // Discard only the current magic byte; a later magic byte may start a
        // valid packet after corrupted data.
        _buffer.removeAt(0);
      }
    }
    return packets;
  }

  void _trimBuffer() {
    if (_buffer.length <= maxBufferSize) return;
    _buffer.removeRange(0, _buffer.length - maxBufferSize);
  }
}

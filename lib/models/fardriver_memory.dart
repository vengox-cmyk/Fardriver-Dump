int _readUint16(List<int> raw, int offset) =>
    raw[offset] | (raw[offset + 1] << 8);

int _readInt16(List<int> raw, int offset) {
  final value = _readUint16(raw, offset);
  return value > 0x7FFF ? value - 0x10000 : value;
}

void _writeUint16(List<int> raw, int offset, int value) {
  raw[offset] = value & 0xFF;
  raw[offset + 1] = (value >> 8) & 0xFF;
}

List<int> _copyBlock(List<int> raw) {
  if (raw.length != 12) {
    throw const FormatException(
        'FarDriver memory blocks must contain 12 bytes');
  }
  return List<int>.from(raw);
}

class Addr12Block {
  final List<int> _raw;

  Addr12Block._(this._raw);

  factory Addr12Block.fromRaw(List<int> raw) => Addr12Block._(_copyBlock(raw));

  int get ld => _readInt16(_raw, 0);
  int get alarmDelay => _readUint16(_raw, 2);
  int get polePairs => _raw[4];
  int get maxSpeed => _readUint16(_raw, 6);
  int get ratedPower => _readUint16(_raw, 8);
  int get ratedVoltage => _readUint16(_raw, 10);

  List<int> toRaw() => List.unmodifiable(_raw);

  Addr12Block withMaxSpeed(int value) {
    if (value < 0 || value > 0xFFFF) throw RangeError.range(value, 0, 0xFFFF);
    final raw = List<int>.from(_raw);
    _writeUint16(raw, 6, value);
    return Addr12Block._(raw);
  }
}

class Addr18Block {
  final List<int> _raw;

  Addr18Block._(this._raw);

  factory Addr18Block.fromRaw(List<int> raw) => Addr18Block._(_copyBlock(raw));

  int get ratedSpeed => _readUint16(_raw, 0);
  int get maxLineCurrentRaw => _readUint16(_raw, 2);
  int get followConfig => _raw[4] & 0x03;
  int get throttleResponse => (_raw[4] >> 2) & 0x03;
  int get weakA => (_raw[4] >> 4) & 0x03;
  int get rxd => (_raw[4] >> 6) & 0x03;
  int get speedPulse => _raw[5] & 0x1F;
  int get gearConfig => (_raw[5] >> 5) & 0x07;
  int get lq => _readUint16(_raw, 6);
  int get batteryRatedCapacity => _readUint16(_raw, 8);

  List<int> toRaw() => List.unmodifiable(_raw);

  Addr18Block withThrottleResponse(int value) {
    if (value < 0 || value > 3) throw RangeError.range(value, 0, 3);
    final raw = List<int>.from(_raw);
    raw[4] = (raw[4] & 0xF3) | (value << 2);
    return Addr18Block._(raw);
  }
}

import 'package:flutter/foundation.dart';

import 'package:arcdash/utils/crc_calculator.dart';

/// Frames that change controller settings, byte-for-byte as the official
/// FarDriver app (MotorNet6) builds them. See `docs/write_protocol.md`.
///
/// Only this file builds write frames, and only for word addresses the
/// caller has already checked against the allowlist
/// (`WriteAllowlist.isWritableWord`). System commands other than "save to
/// flash" (auto-learn, reset, factory defaults) are deliberately not
/// expressible here.
class FardriverWriteProtocol {
  FardriverWriteProtocol._();

  /// Word address of the system command register (official `0xA0`).
  static const sysCmdAddress = 0xA0;

  /// Word address where "save" writes the date stamp first (ModelYear …
  /// TimeSecond, 6 bytes = 3 words).
  static const saveStampAddress = 0x22;

  /// Value written to [sysCmdAddress] to save parameters to flash
  /// (official ParaPage "Save": `WriteAddr({0x88, 0x04}, 0xA0, 2)`).
  static const saveCommand = [0x88, 0x04];

  /// Pause between the date stamp and the save command (official: 10 ms).
  static const saveGap = Duration(milliseconds: 10);

  /// Official `WriteAddr(data, addr, len)`: `AA`, `C0 + len + 4`, addr,
  /// addr, payload, CRC (init 3C/7F, same table as status frames).
  @visibleForTesting
  static List<int> frameForTest(int wordAddress, List<int> payload) =>
      _frame(wordAddress, payload);

  static List<int> _frame(int wordAddress, List<int> payload) {
    if (wordAddress < 0 || wordAddress > 0xFF) {
      throw ArgumentError.value(wordAddress, 'wordAddress');
    }
    if (payload.isEmpty || payload.length.isOdd || payload.length > 12) {
      throw ArgumentError.value(payload.length, 'payload length');
    }
    final total = payload.length + 6;
    final frame = List<int>.filled(total, 0);
    frame[0] = 0xAA;
    frame[1] = 0xC0 + payload.length + 4;
    frame[2] = wordAddress;
    frame[3] = wordAddress;
    for (var i = 0; i < payload.length; i++) {
      frame[4 + i] = payload[i] & 0xFF;
    }
    CrcCalculator.computeCRC(frame, total);
    return frame;
  }

  /// One 16-bit word, little endian (8-byte frame).
  static List<int> writeWord(int wordAddress, int value) {
    if (value < 0 || value > 0xFFFF) {
      throw ArgumentError.value(value, 'value');
    }
    if (wordAddress == sysCmdAddress) {
      throw ArgumentError('System commands cannot be written as a setting');
    }
    return _frame(wordAddress, [value & 0xFF, (value >> 8) & 0xFF]);
  }

  /// Date stamp frame written before the save command:
  /// `[year-2000, month, day, hour, minute, second]` at 0x22.
  static List<int> saveStampFrame(DateTime t) => _frame(saveStampAddress, [
        (t.year - 2000).clamp(0, 255),
        t.month,
        t.day,
        t.hour,
        t.minute,
        t.second,
      ]);

  /// The save-to-flash command frame (`AA C6 A0 A0 88 04 crc crc`).
  static List<int> saveFrame() => _frame(sysCmdAddress, saveCommand);

  static bool verifyCrc(List<int> frame) =>
      CrcCalculator.verifyCRC(frame, frame.length);
}

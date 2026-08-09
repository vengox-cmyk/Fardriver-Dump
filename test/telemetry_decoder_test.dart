import 'package:arcdash/utils/packet_parser.dart';
import 'package:flutter_test/flutter_test.dart';

ParsedPacket _packet(int address, List<int> data) => ParsedPacket(
      address: address,
      rawData: data,
      fullPacket: const [],
    );

void main() {
  test('decodes signed current and preserves its timestamp/source', () {
    final update = PacketParser.extractTelemetry(
      _packet(0xE8, [0xD0, 0x02, 0, 0, 0xF8, 0xFF, 0, 0, 0, 0, 0, 0]),
    );

    expect(update, isNotNull);
    expect(update!.voltageV, 72.0);
    expect(update.currentA, -2.0);
    expect(update.source, TelemetrySource.controllerStatus);
    expect(update.capturedAt, isA<DateTime>());
  });

  test('unknown addresses and short data fail closed', () {
    expect(
        PacketParser.extractTelemetry(_packet(0x55, List<int>.filled(12, 0))),
        isNull);
    expect(PacketParser.extractTelemetry(_packet(0xE8, [0, 0])), isNull);
  });

  test('error flags and unknown bit combinations remain representable', () {
    final update = PacketParser.extractTelemetry(
      _packet(0xE2, [0x0F, 0, 0xC3, 0x80, 0, 0, 0x34, 0x12, 0, 0, 0, 0]),
    );

    expect(update!.measureSpeed, 0x1234);
    expect(update.forward, isTrue);
    expect(update.reverse, isTrue);
    expect(update.gear, 3);
    expect(update.brake, isTrue);
    expect(update.motorHallError, isTrue);
    expect(update.throttleError, isTrue);
    expect(update.motorTempProtect, isTrue);
    expect(update.controllerTempProtect, isTrue);
  });
}

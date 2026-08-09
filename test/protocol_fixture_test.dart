import 'package:arcdash/models/protocol_fixture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const validLine = '''
{"id":"synthetic-stop","direction":"rx","timestamp":"2026-08-02T12:00:00Z","controller":{"model":"synthetic-fardriver","firmware":"fixture-1"},"bytes":"AA 03 00 00 00 00 00 00 00 00 00 00 00 00 00 00","expected":{"address":"0x00","state":"stop"}}
''';

  test('loads a fixture with metadata, bytes, direction and expected decode',
      () {
    final fixture = ProtocolFixtureLoader.parseJsonLines(validLine).single;

    expect(fixture.id, 'synthetic-stop');
    expect(fixture.direction, FixtureDirection.controllerToApp);
    expect(fixture.bytes, hasLength(16));
    expect(fixture.controller.model, 'synthetic-fardriver');
    expect(fixture.expected['state'], 'stop');
  });

  test('rejects invalid hex and unsupported packet lengths', () {
    expect(
      () => ProtocolFixtureLoader.parseJsonLines(
        validLine.replaceFirst('AA 03', 'AA ZZ'),
      ),
      throwsFormatException,
    );
    expect(
      () => ProtocolFixtureLoader.parseJsonLines(
        validLine.replaceFirst(
            'AA 03 00 00 00 00 00 00 00 00 00 00 00 00 00 00', 'AA 03'),
      ),
      throwsFormatException,
    );
  });

  test('rejects missing controller metadata and unknown direction', () {
    expect(
      () => ProtocolFixtureLoader.parseJsonLines(
        validLine.replaceFirst(
          '"controller":{"model":"synthetic-fardriver","firmware":"fixture-1"},',
          '',
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => ProtocolFixtureLoader.parseJsonLines(
        validLine.replaceFirst('"direction":"rx"', '"direction":"unknown"'),
      ),
      throwsFormatException,
    );
  });
}

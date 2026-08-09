import 'package:arcdash/services/foreground_service_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('versioned messages round-trip', () {
    const message = ServiceMessage(
      type: ServiceMessageType.result,
      code: 'safety_blocked',
      data: {'requestId': 'r1'},
    );
    final decoded = ServiceMessage.decode(message.encode());
    expect(decoded.type, ServiceMessageType.result);
    expect(decoded.code, 'safety_blocked');
  });

  test('unknown versions and message types fail closed', () {
    expect(
      () => ServiceMessage.decode({'version': 2, 'type': 'status', 'data': {}}),
      throwsFormatException,
    );
    expect(
      () => ServiceMessage.decode(
          {'version': 1, 'type': 'arbitrary', 'data': {}}),
      throwsFormatException,
    );
  });
}

import 'package:arcdash/models/controller_identity.dart';
import 'package:flutter_test/flutter_test.dart';

ControllerIdentity _identity({
  String firmware = '1.2.0',
  String model = 'FD72680',
  String binding = 'binding-a',
}) =>
    ControllerIdentity(
      model: model,
      hardwareVersion: 'HW1',
      firmwareVersion: firmware,
      functionCode: 'F0',
      extensionCode: 'E1',
      bindingId: binding,
    );

void main() {
  test('distinguishes same and tolerated same-major firmware', () {
    expect(_identity().compare(_identity()), ControllerCompatibility.same);
    expect(
      _identity().compare(_identity(firmware: '1.3.0')),
      ControllerCompatibility.compatible,
    );
  });

  test('rejects foreign model and different local binding', () {
    expect(
      _identity().compare(_identity(model: 'FD72530')),
      ControllerCompatibility.incompatible,
    );
    expect(
      _identity().compare(_identity(binding: 'binding-b')),
      ControllerCompatibility.incompatible,
    );
  });

  test('missing identity fields are unknown, never compatible', () {
    const incomplete = ControllerIdentity(model: 'FD72680');
    expect(incomplete.isComplete, isFalse);
    expect(incomplete.compare(_identity()), ControllerCompatibility.unknown);
    expect(
      ControllerIdentity.fromJson(incomplete.toJson()).isComplete,
      isFalse,
    );
  });
}

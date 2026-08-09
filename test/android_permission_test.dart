import 'package:arcdash/services/android_permission_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRequester implements PermissionRequester {
  final Set<RuntimePermission> denied;
  final requested = <RuntimePermission>[];

  _FakeRequester({this.denied = const {}});

  @override
  Future<bool> request(RuntimePermission permission) async {
    requested.add(permission);
    return !denied.contains(permission);
  }
}

void main() {
  test('Android 12+ requests Bluetooth scan and connect only', () {
    expect(
      AndroidPermissionPolicy.requiredForSdk(31),
      {RuntimePermission.bluetoothScan, RuntimePermission.bluetoothConnect},
    );
    expect(
      AndroidPermissionPolicy.requiredForSdk(30),
      {RuntimePermission.location},
    );
  });

  test('Android 13+ also requests notification permission', () {
    expect(
      AndroidPermissionPolicy.requiredForSdk(33),
      {
        RuntimePermission.bluetoothScan,
        RuntimePermission.bluetoothConnect,
        RuntimePermission.notifications,
      },
    );
  });

  test('permission denial returns a non-granted result without scanning',
      () async {
    final requester = _FakeRequester(
      denied: {RuntimePermission.bluetoothConnect},
    );
    final service = AndroidPermissionService(requester);

    final result = await service.requestForSdk(34);

    expect(result.granted, isFalse);
    expect(result.denied, contains(RuntimePermission.bluetoothConnect));
    expect(requester.requested, [
      RuntimePermission.bluetoothScan,
      RuntimePermission.bluetoothConnect,
      RuntimePermission.notifications,
    ]);
  });

  test('all required legacy permissions can be granted', () async {
    final requester = _FakeRequester();
    final result = await AndroidPermissionService(requester).requestForSdk(30);

    expect(result.granted, isTrue);
    expect(result.denied, isEmpty);
  });
}

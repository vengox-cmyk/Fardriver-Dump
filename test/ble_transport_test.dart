import 'dart:async';

import 'package:arcdash/services/ble_transport.dart';
import 'package:arcdash/services/bluetooth_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTransport implements BleTransport {
  final stateController = StreamController<DongleConnectionState>.broadcast();
  final dataController = StreamController<List<int>>.broadcast();
  final scanController = StreamController<List<DiscoveredDongle>>.broadcast();
  bool connectResult;
  bool writeResult;
  bool disposed = false;

  _FakeTransport({this.connectResult = true, this.writeResult = true});

  @override
  Stream<DongleConnectionState> get connectionStateStream =>
      stateController.stream;
  @override
  Stream<List<int>> get rawDataStream => dataController.stream;
  @override
  Stream<List<DiscoveredDongle>> get scanResultsStream => scanController.stream;
  @override
  DongleConnectionState state = DongleConnectionState.idle;
  @override
  Future<bool> isBluetoothOn() async => true;
  @override
  Future<void> startScan(
      {Duration timeout = const Duration(seconds: 10)}) async {
    state = DongleConnectionState.scanning;
    stateController.add(state);
  }

  @override
  Future<void> stopScan() async {}
  @override
  Future<bool> connect(DiscoveredDongle dongle) async => connectResult;
  @override
  Future<bool> write(List<int> data) async => writeResult;
  @override
  Future<void> disconnect() async {}
  @override
  void dispose() {
    disposed = true;
    stateController.close();
    dataController.close();
    scanController.close();
  }
}

void main() {
  test('fake transport controls state, connect/write failures and disposal',
      () async {
    final transport = _FakeTransport(connectResult: false, writeResult: false);
    final states = <DongleConnectionState>[];
    final subscription = transport.connectionStateStream.listen(states.add);

    await transport.startScan();
    expect(await transport.isBluetoothOn(), isTrue);
    expect(await transport.write(const [0xAA]), isFalse);
    expect(transport.state, DongleConnectionState.scanning);

    transport.dispose();
    await subscription.cancel();
    expect(transport.disposed, isTrue);
    expect(states, [DongleConnectionState.scanning]);
  });
}

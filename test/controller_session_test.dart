import 'dart:async';

import 'package:arcdash/services/ble_transport.dart';
import 'package:arcdash/services/bluetooth_service.dart';
import 'package:arcdash/services/controller_session.dart';
import 'package:arcdash/utils/crc_calculator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class _SessionTransport implements BleTransport {
  final states = StreamController<DongleConnectionState>.broadcast();
  final bytes = StreamController<List<int>>.broadcast();
  final scans = StreamController<List<DiscoveredDongle>>.broadcast();
  final connectResults = <bool>[];
  int connectCalls = 0;

  @override
  Stream<DongleConnectionState> get connectionStateStream => states.stream;
  @override
  Stream<List<int>> get rawDataStream => bytes.stream;
  @override
  Stream<List<DiscoveredDongle>> get scanResultsStream => scans.stream;
  @override
  DongleConnectionState state = DongleConnectionState.idle;
  @override
  Future<bool> isBluetoothOn() async => true;
  @override
  Future<void> startScan(
      {Duration timeout = const Duration(seconds: 10)}) async {}
  @override
  Future<void> stopScan() async {}
  @override
  Future<bool> connect(DiscoveredDongle dongle) async {
    connectCalls++;
    return connectResults.isEmpty ? true : connectResults.removeAt(0);
  }

  @override
  Future<bool> write(List<int> data) async => true;
  @override
  Future<void> disconnect() async {
    state = DongleConnectionState.disconnected;
    states.add(state);
  }

  @override
  void dispose() {
    states.close();
    bytes.close();
    scans.close();
  }
}

DiscoveredDongle _device() => DiscoveredDongle(
      device: BluetoothDevice.fromId('test-device'),
      name: 'CONTROLDMC88',
      rssi: -40,
    );

List<int> _statusPacket() {
  final packet = List<int>.filled(16, 0);
  packet[0] = 0xAA;
  packet[1] = 0x00;
  packet[2] = 0x01;
  packet[8] = 0x34;
  packet[9] = 0x12;
  CrcCalculator.computeCRC(packet, 16);
  return packet;
}

void main() {
  test('late consumers receive connected state and latest telemetry', () async {
    final transport = _SessionTransport();
    final session = ControllerSession(transport);
    transport.state = DongleConnectionState.connected;
    transport.states.add(DongleConnectionState.connected);
    final packet = _statusPacket();
    transport.bytes.add(packet.sublist(0, 5));
    transport.bytes.add(packet.sublist(5));
    await Future<void>.delayed(const Duration(milliseconds: 1));

    final current = await session
        .watch()
        .firstWhere((snapshot) => snapshot.telemetry != null);
    expect(current.state, ControllerSessionState.connected);
    expect(current.telemetry!.measureSpeed, 0x1234);
    await session.dispose();
    transport.dispose();
  });

  test('disconnect and dispose are idempotent', () async {
    final transport = _SessionTransport();
    final session = ControllerSession(transport);

    await session.disconnect();
    await session.disconnect();
    await session.dispose();
    await session.dispose();
    expect(session.current.state, ControllerSessionState.disconnected);
    transport.dispose();
  });

  test('reconnects the last confirmed device with bounded exponential backoff',
      () async {
    final transport = _SessionTransport()
      ..connectResults.addAll([true, false, true]);
    final waits = <Duration>[];
    final session = ControllerSession(
      transport,
      delay: (duration) async => waits.add(duration),
      baseReconnectDelay: const Duration(seconds: 1),
      maxReconnectDelay: const Duration(seconds: 3),
      jitter: (duration, _) => duration,
    );
    final device = _device();

    expect(await session.connect(device), isTrue);
    transport.states.add(DongleConnectionState.disconnected);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(transport.connectCalls, 3);
    expect(waits, [
      const Duration(seconds: 1),
      const Duration(seconds: 2),
    ]);
    expect(session.current.state, ControllerSessionState.connected);
    await session.dispose();
    transport.dispose();
  });

  test('multiple disconnects create one reconnect loop and cancel stops it',
      () async {
    final transport = _SessionTransport()..connectResults.add(true);
    var releaseDelay = Completer<void>();
    final session = ControllerSession(
      transport,
      delay: (_) => releaseDelay.future,
    );
    final device = _device();
    await session.connect(device);
    transport.states
      ..add(DongleConnectionState.disconnected)
      ..add(DongleConnectionState.disconnected);
    await Future<void>.delayed(Duration.zero);
    session.cancelReconnect();
    releaseDelay.complete();
    await Future<void>.delayed(Duration.zero);

    expect(transport.connectCalls, 1);
    expect(session.current.state, ControllerSessionState.disconnected);
    await session.dispose();
    transport.dispose();
  });
}

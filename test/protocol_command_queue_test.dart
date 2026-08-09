import 'dart:async';

import 'package:arcdash/services/ble_transport.dart';
import 'package:arcdash/services/bluetooth_service.dart';
import 'package:arcdash/services/protocol_command_queue.dart';
import 'package:arcdash/utils/crc_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

class _QueueTransport implements BleTransport {
  final states = StreamController<DongleConnectionState>.broadcast();
  final data = StreamController<List<int>>.broadcast();
  final writes = <List<int>>[];

  @override
  Stream<DongleConnectionState> get connectionStateStream => states.stream;
  @override
  Stream<List<int>> get rawDataStream => data.stream;
  @override
  Stream<List<DiscoveredDongle>> get scanResultsStream => const Stream.empty();
  @override
  DongleConnectionState state = DongleConnectionState.connected;
  @override
  Future<bool> isBluetoothOn() async => true;
  @override
  Future<void> startScan(
      {Duration timeout = const Duration(seconds: 10)}) async {}
  @override
  Future<void> stopScan() async {}
  @override
  Future<bool> connect(DiscoveredDongle dongle) async => true;
  @override
  Future<bool> write(List<int> packet) async {
    writes.add(packet);
    return true;
  }

  @override
  Future<void> disconnect() async {}
  @override
  void dispose() {
    states.close();
    data.close();
  }
}

List<int> _response(int marker) {
  final packet = [0xAA, 0x46, marker, marker, marker, 0, 0, 0];
  CrcCalculator.computeCRC(packet, 8);
  return packet;
}

void main() {
  test('serializes writes and routes only the active response', () async {
    final transport = _QueueTransport();
    final queue = ProtocolCommandQueue(transport);
    final first = queue.enqueue(
      packet: const [1],
      matches: (response) => response[2] == 1,
    );
    final second = queue.enqueue(
      packet: const [2],
      matches: (response) => response[2] == 2,
    );

    await Future<void>.delayed(Duration.zero);
    expect(transport.writes, [
      [1]
    ]);
    transport.data.add(_response(2));
    transport.data.add(_response(1));
    expect(await first.future, _response(1));
    await Future<void>.delayed(Duration.zero);
    expect(transport.writes, [
      [1],
      [2],
    ]);
    transport.data.add(_response(2));
    expect(await second.future, _response(2));

    await queue.dispose();
    transport.dispose();
  });

  test('timeout, cancellation and disconnect complete every ticket', () async {
    final transport = _QueueTransport();
    final queue = ProtocolCommandQueue(transport);
    final active = queue.enqueue(
      packet: const [1],
      matches: (_) => true,
      timeout: const Duration(milliseconds: 1),
    );
    final waiting = queue.enqueue(packet: const [2], matches: (_) => true);
    final waitingError = expectLater(
      waiting.future,
      throwsA(isA<CommandQueueException>().having(
        (error) => error.reason,
        'reason',
        CommandFailureReason.cancelled,
      )),
    );
    waiting.cancel();
    await waitingError;
    await expectLater(
      active.future,
      throwsA(isA<CommandQueueException>().having(
        (error) => error.reason,
        'reason',
        CommandFailureReason.timeout,
      )),
    );

    final disconnected = queue.enqueue(packet: const [3], matches: (_) => true);
    final disconnectedError = expectLater(
      disconnected.future,
      throwsA(isA<CommandQueueException>().having(
        (error) => error.reason,
        'reason',
        CommandFailureReason.disconnected,
      )),
    );
    transport.states.add(DongleConnectionState.disconnected);
    await disconnectedError;

    await queue.dispose();
    transport.dispose();
  });
}

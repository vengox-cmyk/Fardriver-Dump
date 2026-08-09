import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:arcdash/services/ble_transport.dart';
import 'package:arcdash/services/bluetooth_service.dart';
import 'package:arcdash/services/controller_session.dart';
import 'package:arcdash/services/session_lifecycle_service.dart';
import 'package:arcdash/services/session_history_repository.dart';
import 'package:arcdash/services/range_prediction_repository.dart';
import 'package:arcdash/models/session_metrics.dart';
import 'package:arcdash/utils/crc_calculator.dart';

class FakeBleTransport implements BleTransport {
  final _stateController =
      StreamController<DongleConnectionState>.broadcast(sync: true);
  final _rawDataController = StreamController<List<int>>.broadcast(sync: true);
  final _scanResultsController =
      StreamController<List<DiscoveredDongle>>.broadcast(sync: true);

  @override
  DongleConnectionState state = DongleConnectionState.idle;

  @override
  Stream<DongleConnectionState> get connectionStateStream =>
      _stateController.stream;

  @override
  Stream<List<int>> get rawDataStream => _rawDataController.stream;

  @override
  Stream<List<DiscoveredDongle>> get scanResultsStream =>
      _scanResultsController.stream;

  @override
  Future<void> startScan(
      {Duration timeout = const Duration(seconds: 10)}) async {
    state = DongleConnectionState.scanning;
    _stateController.add(state);
  }

  @override
  Future<void> stopScan() async {
    state = DongleConnectionState.idle;
    _stateController.add(state);
  }

  @override
  Future<bool> connect(DiscoveredDongle dongle) async {
    state = DongleConnectionState.connected;
    _stateController.add(state);
    return true;
  }

  @override
  Future<void> disconnect() async {
    state = DongleConnectionState.disconnected;
    _stateController.add(state);
  }

  @override
  Future<bool> isBluetoothOn() async => true;

  @override
  Future<bool> write(List<int> data) async => true;

  void emitRawPacket(List<int> packet) {
    _rawDataController.add(packet);
  }

  @override
  void dispose() {
    _stateController.close();
    _rawDataController.close();
    _scanResultsController.close();
  }
}

void main() {
  group('T078 - Integrationstest mit Fake-Transport', () {
    late FakeBleTransport fakeTransport;
    late ControllerSession session;
    late SessionLifecycleService lifecycleService;
    late SessionHistoryRepository historyRepo;
    late MemoryStorage memoryStorage;

    setUp(() {
      fakeTransport = FakeBleTransport();
      session = ControllerSession(fakeTransport);
      lifecycleService = SessionLifecycleService(
        sessionStream: session.watch(),
        disconnectGracePeriod: const Duration(milliseconds: 500),
      );
      memoryStorage = MemoryStorage();
      historyRepo = SessionHistoryRepository(storage: memoryStorage);
    });

    tearDown(() {
      lifecycleService.dispose();
      session.dispose();
      fakeTransport.dispose();
    });

    test(
        'full end-to-end flow: connect -> receive telemetry -> ride lifecycle -> end & persist session',
        () async {
      final dongle = DiscoveredDongle(
        device: BluetoothDevice.fromId('FD-1234'),
        name: 'FarDriver BLE',
        rssi: -60,
      );

      // 1. Connect
      final connected = await session.connect(dongle);
      expect(connected, isTrue);

      // 2. Emit 16-byte status packet (AddrE2 speed)
      final packetE2 = List<int>.filled(16, 0);
      packetE2[0] = 0xAA;
      packetE2[1] = 0x00; // ID 0 -> 0xE2
      packetE2[6] = 0xE8; // speed raw = 1000
      packetE2[7] = 0x03;
      CrcCalculator.computeCRC(packetE2, 16);

      fakeTransport.emitRawPacket(packetE2);

      // 3. Verify ride session started automatically
      expect(lifecycleService.isSessionActive, isTrue);
      final activeRide = lifecycleService.currentRideSession;
      expect(activeRide, isNotNull);

      // 4. Disconnect & let grace period expire to persist session
      await session.disconnect();
      await Future.delayed(const Duration(milliseconds: 700));

      expect(lifecycleService.isSessionActive, isFalse);

      // 5. Persist record to history
      final record = SessionRecord(
        id: 'sess-integration-1',
        startTime: activeRide!.startTime,
        endTime: activeRide.endTime,
        metrics: const SessionMetrics(
          duration: Duration(minutes: 5),
          distanceKm: 2.5,
          avgSpeedKph: 30.0,
          maxSpeedKph: 45.0,
          consumedWh: 50.0,
          recoveredWh: 0.0,
          netWh: 50.0,
          whPerKm: 20.0,
          maxPowerKw: 2.0,
          isIncomplete: false,
        ),
      );
      historyRepo.saveSession(record);

      final history = historyRepo.loadHistory();
      expect(history.length, 1);
      expect(history.first.id, 'sess-integration-1');
      expect(history.first.metrics.distanceKm, 2.5);
    });
  });
}

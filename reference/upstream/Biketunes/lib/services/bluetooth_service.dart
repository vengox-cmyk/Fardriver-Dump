import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' hide BluetoothService;

// BLE UART service/characteristic UUIDs for HM-10/HC-08 style dongles
const _uartServiceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';
const _uartCharUuid = '0000ffe1-0000-1000-8000-00805f9b34fb';

// Additional UUID variants some dongles use
const _altServiceUuid = '49535343-fe7d-4ae5-8fa9-9fafd205e455';
const _altCharWriteUuid = '49535343-8841-43f4-a8d4-ecbe34729bb3';
const _altCharNotifyUuid = '49535343-1e4d-4bd9-ba61-23c647249616';

enum DongleConnectionState {
  idle,
  scanning,
  connecting,
  connected,
  disconnected,
  error,
}

class DiscoveredDongle {
  final BluetoothDevice device;
  final String name;
  final int rssi;

  const DiscoveredDongle({
    required this.device,
    required this.name,
    required this.rssi,
  });
}

class DongleService {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;
  StreamSubscription? _notifySubscription;
  StreamSubscription? _deviceStateSubscription;

  final _connectionStateController =
      StreamController<DongleConnectionState>.broadcast();
  final _rawDataController = StreamController<List<int>>.broadcast();
  final _scanResultsController =
      StreamController<List<DiscoveredDongle>>.broadcast();

  Stream<DongleConnectionState> get connectionStateStream =>
      _connectionStateController.stream;
  Stream<List<int>> get rawDataStream => _rawDataController.stream;
  Stream<List<DiscoveredDongle>> get scanResultsStream =>
      _scanResultsController.stream;

  DongleConnectionState _state = DongleConnectionState.idle;
  DongleConnectionState get state => _state;

  BluetoothDevice? get connectedDevice => _connectedDevice;
  String? get connectedDeviceName => _connectedDevice?.platformName;

  void _setState(DongleConnectionState s) {
    _state = s;
    _connectionStateController.add(s);
  }

  /// Checks if Bluetooth adapter is on.
  Future<bool> isBluetoothOn() async {
    final adapterState = await FlutterBluePlus.adapterState.first;
    return adapterState == BluetoothAdapterState.on;
  }

  /// Starts scanning for FarDriver tuner dongles only.
  ///
  /// Layer 1: BLE-level service UUID filter — only devices advertising the
  /// known UART service UUIDs reach the callback (eliminates phones, headphones, etc.).
  /// Layer 2: Name-pattern filter — catches dongles advertising those services
  /// and validates against known FarDriver naming conventions.
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    _setState(DongleConnectionState.scanning);
    final results = <String, DiscoveredDongle>{};

    try {
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: true,
        withServices: [
          Guid(_uartServiceUuid),
          Guid(_altServiceUuid),
        ],
      );

      final sub = FlutterBluePlus.scanResults.listen((scanResults) {
        for (final r in scanResults) {
          final name = r.device.platformName.toLowerCase();
          // Accept all devices that passed the BLE service UUID filter,
          // plus name-pattern check as a secondary validation.
          final matchesName = name.isNotEmpty &&
              (name.contains('yuanq') ||
                  name.contains('foc') ||
                  name.contains('fardriver') ||
                  name.contains('ffe0') ||
                  name.contains('nd'));
          final matchesService = r.advertisementData.serviceUuids.any((u) {
            final s = u.toString().toLowerCase();
            return s.contains('ffe0') || s.contains('49535343');
          });
          if (matchesName || matchesService) {
            results[r.device.remoteId.str] = DiscoveredDongle(
              device: r.device,
              name: r.device.platformName.isNotEmpty
                  ? r.device.platformName
                  : 'FarDriver Dongle',
              rssi: r.rssi,
            );
            _scanResultsController.add(results.values.toList());
          }
        }
      });

      await Future.delayed(timeout);
      await sub.cancel();
    } finally {
      await FlutterBluePlus.stopScan();
      if (_state == DongleConnectionState.scanning) {
        _setState(DongleConnectionState.idle);
      }
    }
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    if (_state == DongleConnectionState.scanning) {
      _setState(DongleConnectionState.idle);
    }
  }

  /// Connects to a discovered dongle and subscribes to UART notify characteristic.
  Future<bool> connect(DiscoveredDongle dongle) async {
    _setState(DongleConnectionState.connecting);
    try {
      await dongle.device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

      _connectedDevice = dongle.device;

      // Monitor device connection state using flutter_blue_plus's enum
      _deviceStateSubscription =
          dongle.device.connectionState.listen((fbpState) {
        if (fbpState == BluetoothConnectionState.disconnected) {
          _handleDisconnect();
        }
      });

      // Discover services
      final services = await dongle.device.discoverServices();

      // Try primary UART service (FFE0/FFE1)
      bool found = await _setupUartService(
        services,
        _uartServiceUuid,
        _uartCharUuid,
        _uartCharUuid,
      );

      // Fallback to alternative UART service
      if (!found) {
        found = await _setupUartService(
          services,
          _altServiceUuid,
          _altCharWriteUuid,
          _altCharNotifyUuid,
        );
      }

      if (!found) {
        await disconnect();
        _setState(DongleConnectionState.error);
        return false;
      }

      _setState(DongleConnectionState.connected);
      return true;
    } catch (e) {
      await disconnect();
      _setState(DongleConnectionState.error);
      return false;
    }
  }

  Future<bool> _setupUartService(
    List<Object> services,
    String serviceUuid,
    String writeCharUuid,
    String notifyCharUuid,
  ) async {
    BluetoothCharacteristic? findChar(
        List<BluetoothCharacteristic> chars, String uuid) {
      for (final c in chars) {
        if (c.uuid.toString().toLowerCase() == uuid) return c;
      }
      return null;
    }

    for (final svc in services) {
      // Access fbp BluetoothService fields via dynamic to avoid class name conflict
      final svcUuid = (svc as dynamic).uuid.toString().toLowerCase();
      if (svcUuid != serviceUuid) continue;

      final chars = List<BluetoothCharacteristic>.from(
          (svc as dynamic).characteristics as List);
      final writeChar = findChar(chars, writeCharUuid);
      final notifyChar = findChar(chars, notifyCharUuid);

      if (writeChar == null || notifyChar == null) return false;

      _writeChar = writeChar;
      _notifyChar = notifyChar;

      await notifyChar.setNotifyValue(true);
      _notifySubscription = notifyChar.onValueReceived.listen((data) {
        if (data.isNotEmpty) {
          _rawDataController.add(List<int>.from(data));
        }
      });

      return true;
    }

    return false;
  }

  /// Writes bytes to the UART write characteristic.
  Future<bool> write(List<int> data) async {
    if (_writeChar == null || _state != DongleConnectionState.connected) {
      return false;
    }
    try {
      await _writeChar!.write(data, withoutResponse: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnect() async {
    await _notifySubscription?.cancel();
    _notifySubscription = null;
    await _deviceStateSubscription?.cancel();
    _deviceStateSubscription = null;

    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
      } catch (_) {}
      _connectedDevice = null;
    }
    _writeChar = null;
    _notifyChar = null;
    _setState(DongleConnectionState.disconnected);
  }

  void _handleDisconnect() {
    _notifySubscription?.cancel();
    _notifySubscription = null;
    _writeChar = null;
    _notifyChar = null;
    _connectedDevice = null;
    _setState(DongleConnectionState.disconnected);
  }

  void dispose() {
    _notifySubscription?.cancel();
    _deviceStateSubscription?.cancel();
    _connectionStateController.close();
    _rawDataController.close();
    _scanResultsController.close();
  }
}

import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' hide BluetoothService;
import 'package:arcdash/services/ble_transport.dart';
import 'package:arcdash/services/diagnostic_log.dart';
import 'package:arcdash/utils/packet_parser.dart';

// BLE UART service/characteristic UUIDs for HM-10/HC-08 style dongles
const _uartServiceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';
const _uartCharUuid = '0000ffe1-0000-1000-8000-00805f9b34fb';
const _targetServiceUuid = '0000ff00-0000-1000-8000-00805f9b34fb';
const _targetCharUuid = '0000ffec-0000-1000-8000-00805f9b34fb';

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

class DongleService implements BleTransport {
  final DiagnosticLog? diagnostics;

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeChar;
  bool _writeWithoutResponse = true;
  StreamSubscription? _notifySubscription;
  StreamSubscription? _deviceStateSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;

  DongleService({this.diagnostics});

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
  String? get connectedDeviceId => _connectedDevice?.remoteId.str;

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
  /// Scans without an advertisement UUID restriction because some target
  /// dongles expose their UART only after service discovery.
  Future<void> startScan(
      {Duration timeout = const Duration(seconds: 10)}) async {
    _setState(DongleConnectionState.scanning);
    diagnostics?.add(DiagnosticEventType.scan, details: {
      'status': 'started',
      'timeoutSeconds': timeout.inSeconds,
    });
    final results = <String, DiscoveredDongle>{};

    try {
      final sub = FlutterBluePlus.scanResults.listen((scanResults) {
        for (final r in scanResults) {
          final name = r.device.platformName;
          final advName = r.advertisementData.advName;
          final remoteId = r.device.remoteId.str;

          // SHOW ALL DISCOVERED BLUETOOTH DEVICES WITHOUT ANY FILTER!
          final displayName = name.isNotEmpty
              ? name
              : (advName.isNotEmpty
                  ? advName
                  : 'Unbenanntes BLE Gerät ($remoteId)');

          final isNew = !results.containsKey(remoteId);
          results[remoteId] = DiscoveredDongle(
            device: r.device,
            name: displayName,
            rssi: r.rssi,
          );
          if (isNew) {
            diagnostics?.add(DiagnosticEventType.scan, details: {
              'deviceFound': displayName,
              'remoteId': remoteId,
              'rssi': r.rssi,
              'serviceUuids': r.advertisementData.serviceUuids
                  .map((u) => u.toString())
                  .toList(),
            });
          }
          _scanResultsController.add(results.values.toList());
        }
      });

      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: false,
      );

      await Future.delayed(timeout);
      await sub.cancel();
    } finally {
      await FlutterBluePlus.stopScan();
      diagnostics?.add(DiagnosticEventType.scan, details: {
        'status': 'stopped',
        'totalDiscovered': results.length,
      });
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
    diagnostics?.add(DiagnosticEventType.connect, details: {
      'status': 'connecting',
      'name': dongle.name,
      'remoteId': dongle.device.remoteId.str,
      'rssi': dongle.rssi,
    });
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
      _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
        if (state == BluetoothAdapterState.off) _handleDisconnect();
      });

      // Discover services
      final services = await dongle.device.discoverServices();
      final serviceSummary = services.map((svc) {
        final s = svc as dynamic;
        final chars = (s.characteristics as List).map((c) {
          final char = c as dynamic;
          final p = char.properties;
          final props = [
            if (p.read) 'read',
            if (p.write) 'write',
            if (p.writeWithoutResponse) 'writeWithoutResponse',
            if (p.notify) 'notify',
            if (p.indicate) 'indicate',
          ].join(',');
          return '${char.uuid} [$props]';
        }).toList();
        return {'uuid': s.uuid.toString(), 'characteristics': chars};
      }).toList();

      diagnostics?.add(DiagnosticEventType.connect, details: {
        'status': 'services_discovered',
        'device': dongle.device.remoteId.str,
        'services': serviceSummary,
      });

      bool found = await _setupUartService(services);

      if (!found) {
        diagnostics?.add(DiagnosticEventType.connect, details: {
          'status': 'uart_setup_failed',
          'device': dongle.device.remoteId.str,
          'reason': 'No matching UART characteristic found',
        });
        await disconnect();
        _setState(DongleConnectionState.error);
        return false;
      }

      diagnostics?.add(DiagnosticEventType.connect, details: {
        'status': 'connected',
        'name': dongle.name,
        'remoteId': dongle.device.remoteId.str,
      });

      _setState(DongleConnectionState.connected);
      return true;
    } catch (e) {
      diagnostics?.add(DiagnosticEventType.connect, details: {
        'status': 'connect_error',
        'name': dongle.name,
        'remoteId': dongle.device.remoteId.str,
        'error': e.toString(),
      });
      await disconnect();
      _setState(DongleConnectionState.error);
      return false;
    }
  }

  Future<bool> _setupUartService(List<Object> services) async {
    // Known UUID pairings: (Service UUID prefix/exact, Write Char UUID prefix/exact, Notify Char UUID prefix/exact)
    final knownPairs = [
      (_targetServiceUuid, _targetCharUuid, _targetCharUuid),
      (_uartServiceUuid, _uartCharUuid, _uartCharUuid),
      (_altServiceUuid, _altCharWriteUuid, _altCharNotifyUuid),
    ];

    BluetoothCharacteristic? findChar(
        List<BluetoothCharacteristic> chars, String uuid) {
      final searchUuid = uuid.toLowerCase();
      for (final c in chars) {
        final cUuid = c.uuid.toString().toLowerCase();
        if (cUuid == searchUuid || cUuid.startsWith(searchUuid)) return c;
      }
      return null;
    }

    // 1. Try known UUID pairs first
    for (final pair in knownPairs) {
      final sUuid = pair.$1.toLowerCase();
      final wUuid = pair.$2;
      final nUuid = pair.$3;

      for (final svc in services) {
        final svcUuid = (svc as dynamic).uuid.toString().toLowerCase();
        if (svcUuid != sUuid && !svcUuid.startsWith(sUuid)) continue;

        final chars = List<BluetoothCharacteristic>.from(
            (svc as dynamic).characteristics as List);
        final writeChar = findChar(chars, wUuid);
        final notifyChar = findChar(chars, nUuid);

        if (writeChar == null || notifyChar == null) continue;
        final canWriteWithoutResponse =
            writeChar.properties.writeWithoutResponse;
        final canWriteWithResponse = writeChar.properties.write;
        if (!canWriteWithoutResponse && !canWriteWithResponse) continue;

        _writeChar = writeChar;
        _writeWithoutResponse = canWriteWithoutResponse;

        try {
          await notifyChar.setNotifyValue(true);
        } catch (e) {
          diagnostics?.add(DiagnosticEventType.connect, details: {
            'status': 'notify_setup_exception',
            'uuid': notifyChar.uuid.toString(),
            'error': e.toString(),
          });
        }
        _notifySubscription = notifyChar.onValueReceived.listen((data) {
          if (data.isNotEmpty) {
            _rawDataController.add(List<int>.from(data));
            diagnostics?.add(DiagnosticEventType.frame, details: {
              'action': 'raw_ble_received',
              'length': data.length,
              'hex': PacketParser.toHexString(data),
            });
          }
        });

        diagnostics?.add(DiagnosticEventType.connect, details: {
          'status': 'uart_paired_known',
          'serviceUuid': svcUuid,
          'writeCharUuid': writeChar.uuid.toString(),
          'notifyCharUuid': notifyChar.uuid.toString(),
        });

        return true;
      }
    }

    // 2. Fallback: Search ALL services and characteristics for a characteristic that supports notify/indicate AND write/writeWithoutResponse
    for (final svc in services) {
      final chars = List<BluetoothCharacteristic>.from(
          (svc as dynamic).characteristics as List);
      for (final c in chars) {
        final props = c.properties;
        final supportsNotifyOrIndicate = props.notify || props.indicate;
        final supportsWrite = props.write || props.writeWithoutResponse;

        if (supportsNotifyOrIndicate && supportsWrite) {
          _writeChar = c;
          _writeWithoutResponse = props.writeWithoutResponse;

          try {
            await c.setNotifyValue(true);
          } catch (e) {
            diagnostics?.add(DiagnosticEventType.connect, details: {
              'status': 'notify_setup_exception_fallback',
              'uuid': c.uuid.toString(),
              'error': e.toString(),
            });
          }
          _notifySubscription = c.onValueReceived.listen((data) {
            if (data.isNotEmpty) {
              _rawDataController.add(List<int>.from(data));
              diagnostics?.add(DiagnosticEventType.frame, details: {
                'action': 'raw_ble_received',
                'length': data.length,
                'hex': PacketParser.toHexString(data),
              });
            }
          });

          diagnostics?.add(DiagnosticEventType.connect, details: {
            'status': 'uart_paired_fallback',
            'serviceUuid': (svc as dynamic).uuid.toString(),
            'charUuid': c.uuid.toString(),
          });

          return true;
        }
      }
    }

    return false;
  }

  /// Writes bytes to the UART write characteristic.
  Future<bool> write(List<int> data) async {
    if (_writeChar == null || _state != DongleConnectionState.connected) {
      diagnostics?.add(DiagnosticEventType.command, details: {
        'action': 'write_rejected',
        'reason': _writeChar == null ? 'no_write_char' : 'not_connected',
      });
      return false;
    }
    try {
      await _writeChar!.write(data, withoutResponse: _writeWithoutResponse);
      diagnostics?.add(DiagnosticEventType.command, details: {
        'action': 'raw_ble_written',
        'length': data.length,
        'hex': PacketParser.toHexString(data),
      });
      return true;
    } catch (e) {
      diagnostics?.add(DiagnosticEventType.command, details: {
        'action': 'write_failed',
        'error': e.toString(),
      });
      return false;
    }
  }

  Future<void> disconnect() async {
    await _notifySubscription?.cancel();
    _notifySubscription = null;
    await _deviceStateSubscription?.cancel();
    _deviceStateSubscription = null;
    await _adapterStateSubscription?.cancel();
    _adapterStateSubscription = null;

    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
      } catch (_) {}
      _connectedDevice = null;
    }
    _writeChar = null;
    _writeWithoutResponse = true;
    _setState(DongleConnectionState.disconnected);
  }

  void _handleDisconnect() {
    _notifySubscription?.cancel();
    _notifySubscription = null;
    _adapterStateSubscription?.cancel();
    _adapterStateSubscription = null;
    _writeChar = null;
    _writeWithoutResponse = true;
    _connectedDevice = null;
    _setState(DongleConnectionState.disconnected);
  }

  void dispose() {
    _notifySubscription?.cancel();
    _deviceStateSubscription?.cancel();
    _adapterStateSubscription?.cancel();
    _connectionStateController.close();
    _rawDataController.close();
    _scanResultsController.close();
  }
}

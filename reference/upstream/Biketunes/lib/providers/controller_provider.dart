import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:biketunes/models/controller_state.dart';
import 'package:biketunes/providers/bluetooth_provider.dart';
import 'package:biketunes/services/bluetooth_service.dart' show DongleService, DongleConnectionState;
import 'package:biketunes/services/protocol_service.dart';
import 'package:biketunes/services/storage_service.dart';
import 'package:biketunes/utils/packet_parser.dart';

final storageServiceProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('Override in ProviderScope');
});

class ControllerNotifier extends StateNotifier<ControllerState> {
  final DongleService _bluetooth;
  final StorageService _storage;

  StreamSubscription? _dataSub;
  StreamSubscription? _connSub;

  // Rolling byte buffer for packet extraction
  final List<int> _buffer = [];

  // Keep a list of raw packets for the debug screen
  final List<String> _debugPackets = [];
  int _packetCount = 0;
  DateTime _lastPacketTime = DateTime.now();
  double _packetRate = 0.0;

  List<String> get debugPackets => List.unmodifiable(_debugPackets);
  double get packetRate => _packetRate;

  ControllerNotifier(this._bluetooth, this._storage)
      : super(ControllerState.initial()) {
    _connSub = _bluetooth.connectionStateStream.listen(_onConnectionState);
  }

  void _onConnectionState(DongleConnectionState cs) {
    if (cs == DongleConnectionState.connected) {
      _onConnected();
    } else if (cs == DongleConnectionState.disconnected) {
      _dataSub?.cancel();
      _dataSub = null;
      _buffer.clear();
    }
  }

  Future<void> _onConnected() async {
    // Subscribe to incoming data
    _dataSub = _bluetooth.rawDataStream.listen(_onRawData);

    // Send start-status-stream command
    await Future.delayed(const Duration(milliseconds: 200));
    await _bluetooth.write(ProtocolService.startStatusStreamPacket());
  }

  void _onRawData(List<int> chunk) {
    _buffer.addAll(chunk);

    // Keep buffer bounded
    if (_buffer.length > 512) {
      _buffer.removeRange(0, _buffer.length - 512);
    }

    // Extract complete 16-byte packets
    int i = 0;
    while (i <= _buffer.length - 16) {
      if (_buffer[i] == 0xAA) {
        final candidate = _buffer.sublist(i, i + 16);
        if (PacketParser.parseStatusPacket(candidate) != null) {
          final parsed = PacketParser.parseStatusPacket(candidate)!;
          _processPacket(parsed, candidate);
          i += 16;
          continue;
        }
      }
      i++;
    }
    if (i > 0) _buffer.removeRange(0, i.clamp(0, _buffer.length));
  }

  void _processPacket(ParsedPacket parsed, List<int> raw) {
    // Debug log (keep last 50)
    final hex = PacketParser.toHexString(raw);
    _debugPackets.add('[0x${parsed.address.toRadixString(16).padLeft(2, '0').toUpperCase()}] $hex');
    if (_debugPackets.length > 50) _debugPackets.removeAt(0);

    // Packet rate calculation
    _packetCount++;
    final now = DateTime.now();
    final elapsed = now.difference(_lastPacketTime).inMilliseconds;
    if (elapsed >= 1000) {
      _packetRate = _packetCount * 1000.0 / elapsed;
      _packetCount = 0;
      _lastPacketTime = now;
    }

    // Extract telemetry
    final update = PacketParser.extractTelemetry(parsed);
    if (update == null) return;

    var next = state;

    if (update.measureSpeed != null) {
      final kph = _speedFromRaw(update.measureSpeed!);
      next = next.copyWith(speedKph: kph, lastUpdate: DateTime.now());
    }
    if (update.forward != null) next = next.copyWith(isForward: update.forward);
    if (update.reverse != null && update.reverse!) {
      next = next.copyWith(isForward: false);
    }
    if (update.gear != null) next = next.copyWith(gear: update.gear);
    if (update.brake != null) next = next.copyWith(isBraking: update.brake);
    if (update.motorHallError != null) next = next.copyWith(motorHallError: update.motorHallError);
    if (update.throttleError != null) next = next.copyWith(throttleError: update.throttleError);
    if (update.motorTempProtect != null) next = next.copyWith(motorTempProtect: update.motorTempProtect);
    if (update.controllerTempProtect != null) next = next.copyWith(controllerTempProtect: update.controllerTempProtect);

    if (update.voltageV != null) next = next.copyWith(voltageV: update.voltageV);
    if (update.currentA != null) next = next.copyWith(currentA: update.currentA);
    if (update.phaseACurrA != null) next = next.copyWith(phaseACurrA: update.phaseACurrA);
    if (update.phaseCCurrA != null) next = next.copyWith(phaseCCurrA: update.phaseCCurrA);
    if (update.motorTempC != null) next = next.copyWith(motorTempC: update.motorTempC);
    if (update.battCapPercent != null) next = next.copyWith(battCapPercent: update.battCapPercent);
    if (update.mosTempC != null) next = next.copyWith(controllerTempC: update.mosTempC);

    if (update.wheelRadius != null) next = next.copyWith(wheelRadius: update.wheelRadius);
    if (update.wheelWidth != null) next = next.copyWith(wheelWidth: update.wheelWidth);
    if (update.wheelRatio != null) next = next.copyWith(wheelRatio: update.wheelRatio);
    if (update.rateRatio != null && update.rateRatio! > 0) next = next.copyWith(rateRatio: update.rateRatio);

    if (update.maxSpeed != null) next = next.copyWith(maxSpeedRaw: update.maxSpeed);
    if (update.maxLineCurrRaw != null) next = next.copyWith(maxLineCurrRaw: update.maxLineCurrRaw);
    if (update.zeroBattCoeff != null) next = next.copyWith(zeroBattCoeff: update.zeroBattCoeff);
    if (update.fullBattCoeff != null) next = next.copyWith(fullBattCoeff: update.fullBattCoeff);

    // Recompute derived fields
    state = next.withComputedFields();

    // Save stock backup on first connect if not already done
    if (!_storage.firstConnectDone && update.maxLineCurrRaw != null) {
      _saveStockBackup();
    }
  }

  double _speedFromRaw(int measureSpeed) {
    if (state.rateRatio == 0) return 0.0;
    return measureSpeed *
        (0.00376991136 *
            (state.wheelRadius * 1270.0 + state.wheelWidth * state.wheelRatio) /
            state.rateRatio);
  }

  void _saveStockBackup() {
    final backup = <int, int>{
      0x15: state.maxSpeedRaw,
      0x19: state.maxLineCurrRaw,
    };
    _storage.saveStockBackup(backup);
  }

  Future<void> setRideMode(RideMode mode) async {
    if (state.speedKph > 2.0) return; // Safety: no changes while moving
    final packet = ProtocolService.setThrottleResponsePacket(mode.throttleResponseValue);
    await _bluetooth.write(packet);
    state = state.copyWith(rideMode: mode, lastUpdate: DateTime.now());
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }
}

final controllerProvider =
    StateNotifierProvider<ControllerNotifier, ControllerState>((ref) {
  final bluetooth = ref.watch(bluetoothServiceProvider);
  final storage = ref.watch(storageServiceProvider);
  return ControllerNotifier(bluetooth, storage);
});

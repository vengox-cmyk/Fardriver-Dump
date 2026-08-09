import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/controller_state.dart';
import 'package:arcdash/models/telemetry_quality.dart' as quality;
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/services/bluetooth_service.dart'
    show DongleConnectionState;
import 'package:arcdash/services/ble_transport.dart';
import 'package:arcdash/services/protocol_service.dart';
import 'package:arcdash/services/storage_service.dart';
import 'package:arcdash/utils/unit_converter.dart';
import 'package:arcdash/utils/packet_parser.dart';
import 'package:arcdash/utils/packet_framer.dart';
import 'package:arcdash/services/diagnostic_log.dart';
import 'package:arcdash/models/range_prediction_state.dart';
import 'package:arcdash/services/range_prediction_repository.dart';

final storageServiceProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('Override in ProviderScope');
});

/// Repository backing the learned range prediction / voltage calibration state.
final rangePredictionRepositoryProvider =
    Provider<RangePredictionRepository>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return RangePredictionRepository(storage: storage.rangePredictionStorage);
});

class RangePredictionNotifier extends StateNotifier<RangePredictionState?> {
  final RangePredictionRepository _repository;
  final String _controllerId;

  RangePredictionNotifier(this._repository, this._controllerId)
      : super(_repository.loadState(controllerId: _controllerId));

  /// Automatically learns a live voltage reading into the calibration range
  /// and persists it when the range is expanded.
  void learnVoltage(double voltageV) {
    final current = state ?? RangePredictionState(controllerId: _controllerId);
    final updated = current.learnVoltage(voltageV);
    if (identical(updated, current)) return;
    _repository.saveState(updated);
    state = updated;
  }

  /// Automatically learns from a completed or in-progress ride session.
  void learnFromSession(
      {required double distanceKm,
      required double totalWhUsed,
      double? socPercent}) {
    if (distanceKm < 0.5 || totalWhUsed <= 10) return;
    final current = state ?? RangePredictionState(controllerId: _controllerId);
    final consumption = totalWhUsed / distanceKm;
    if (consumption < 10 || consumption > 300) return;

    final history = List<double>.from(current.consumptionHistoryWhPerKm);
    history.add(consumption);
    if (history.length > 50) history.removeAt(0);

    // If SOC delta is available or we know battery went down, estimate full capacity
    double? cap = current.learnedCapacityWh;
    if (socPercent != null && socPercent < 95 && socPercent > 5) {
      final usedPct = 100.0 - socPercent;
      if (usedPct >= 15.0) {
        final estCapacity = totalWhUsed / (usedPct / 100.0);
        if (estCapacity >= 1000 && estCapacity <= 15000) {
          cap = cap == null ? estCapacity : (cap * 0.7 + estCapacity * 0.3);
        }
      }
    }

    final updated = current.copyWith(
      consumptionHistoryWhPerKm: history,
      learnedCapacityWh: cap,
      socConfidence: (current.socConfidence + 0.15).clamp(0.0, 1.0),
    );
    _repository.saveState(updated);
    state = updated;
  }

  void resetVoltageCalibration() {
    final current = state;
    if (current == null) return;
    final cleared = current.clearVoltageCalibration();
    _repository.saveState(cleared);
    state = cleared;
  }
}

/// Reactive state of the learned range prediction data for the connected
/// controller. Null when nothing has been learned yet.
final rangePredictionStateProvider =
    StateNotifierProvider<RangePredictionNotifier, RangePredictionState?>(
        (ref) {
  final repository = ref.watch(rangePredictionRepositoryProvider);
  final deviceId = ref.watch(connectedDeviceIdProvider) ?? 'C0:00:56:C4:00:36';
  return RangePredictionNotifier(repository, deviceId);
});

class ControllerNotifier extends StateNotifier<ControllerState> {
  final BleTransport _bluetooth;
  final StorageService _storage;
  final DiagnosticLog _diagnostics;
  final RangePredictionNotifier? _rangePrediction;

  StreamSubscription? _dataSub;
  StreamSubscription? _connSub;

  final PacketFramer _framer = PacketFramer();

  // Keep a list of raw packets for the debug screen
  final List<String> _debugPackets = [];
  int _packetCount = 0;
  DateTime _lastPacketTime = DateTime.now();
  double _packetRate = 0.0;

  List<String> get debugPackets => List.unmodifiable(_debugPackets);
  double get packetRate => _packetRate;
  DiagnosticLog get diagnostics => _diagnostics;
  String exportDiagnosticJson() => _diagnostics.exportJson();

  ControllerNotifier(this._bluetooth, this._storage,
      {DiagnosticLog? diagnostics, RangePredictionNotifier? rangePrediction})
      : _rangePrediction = rangePrediction,
        _diagnostics = diagnostics ?? DiagnosticLog(),
        super(ControllerState.initial()) {
    _connSub = _bluetooth.connectionStateStream.listen(_onConnectionState);
    if (_bluetooth.state == DongleConnectionState.connected) {
      _onConnected();
    }
  }

  Timer? _streamInitTimer;

  void _onConnectionState(DongleConnectionState cs) {
    _diagnostics.add(
      cs == DongleConnectionState.disconnected
          ? DiagnosticEventType.reconnect
          : DiagnosticEventType.connect,
      details: {'state': cs.name},
    );
    if (cs == DongleConnectionState.connected) {
      _onConnected();
    } else if (cs == DongleConnectionState.disconnected) {
      _streamInitTimer?.cancel();
      _streamInitTimer = null;
      _dataSub?.cancel();
      _dataSub = null;
      _framer.reset();
    }
  }

  Future<void> _onConnected() async {
    // Subscribe to incoming data
    _dataSub = _bluetooth.rawDataStream.listen(_onRawData);

    // Send start-status-stream command periodically until packets arrive
    _streamInitTimer?.cancel();
    _streamInitTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (state.telemetrySamples.isEmpty) {
        await _bluetooth.write(ProtocolService.startStatusStreamPacket());
        _diagnostics.add(DiagnosticEventType.command, details: {
          'action': 'sent_start_status_stream_retry',
        });
      } else {
        _streamInitTimer?.cancel();
        _streamInitTimer = null;
      }
    });

    await Future.delayed(const Duration(milliseconds: 300));
    await _bluetooth.write(ProtocolService.startStatusStreamPacket());
  }

  void _onRawData(List<int> chunk) {
    for (final packet in _framer.add(chunk)) {
      final parsed = PacketParser.parseStatusPacket(packet);
      if (parsed != null) {
        _processPacket(parsed, packet);
      } else {
        _diagnostics.add(DiagnosticEventType.parserError, details: {
          'length': packet.length,
          'reason': 'unsupported_frame',
        });
      }
    }
  }

  void _processPacket(ParsedPacket parsed, List<int> raw) {
    // Debug log (keep last 50)
    final hex = PacketParser.toHexString(raw);
    _debugPackets.add(
        '[0x${parsed.address.toRadixString(16).padLeft(2, '0').toUpperCase()}] $hex');
    _diagnostics.add(
      DiagnosticEventType.frame,
      details: {'address': parsed.address, 'length': raw.length, 'hex': hex},
    );
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
    final samples = Map<ControllerTelemetry, quality.TelemetrySample>.of(
      state.telemetrySamples,
    );
    void record(ControllerTelemetry field, num value) {
      samples[field] = quality.TelemetrySample(
        value: value.toDouble(),
        source: quality.TelemetrySource.controller,
        capturedAt: update.capturedAt,
      );
    }

    if (update.measureSpeed != null) {
      final kph = _speedFromRaw(update.measureSpeed!);
      final dtHours =
          update.capturedAt.difference(state.lastUpdate).inMilliseconds /
              3600000.0;
      final newTrip = (state.tripDistanceKm ?? 0.0) +
          (dtHours > 0 && dtHours < 0.01 && kph > 0 ? kph * dtHours : 0.0);
      next = next.copyWith(
        speedKph: kph,
        tripDistanceKm: newTrip,
        lastUpdate: update.capturedAt,
      );
      record(ControllerTelemetry.speed, kph);
      record(ControllerTelemetry.trip, newTrip);
    }
    if (update.forward != null) next = next.copyWith(isForward: update.forward);
    if (update.reverse != null && update.reverse!) {
      next = next.copyWith(isForward: false);
    }
    if (update.gear != null) next = next.copyWith(gear: update.gear);
    if (update.brake != null) next = next.copyWith(isBraking: update.brake);
    if (update.motorHallError != null)
      next = next.copyWith(motorHallError: update.motorHallError);
    if (update.throttleError != null)
      next = next.copyWith(throttleError: update.throttleError);
    if (update.motorTempProtect != null)
      next = next.copyWith(motorTempProtect: update.motorTempProtect);
    if (update.controllerTempProtect != null)
      next = next.copyWith(controllerTempProtect: update.controllerTempProtect);
    if (update.gear != null) record(ControllerTelemetry.gear, update.gear!);
    record(ControllerTelemetry.profile, next.rideMode.index);
    if (update.measureSpeed != null) {
      record(ControllerTelemetry.errors, next.hasAnyFault ? 1 : 0);
    }

    if (update.voltageV != null) {
      next = next.copyWith(voltageV: update.voltageV);
      record(ControllerTelemetry.voltage, update.voltageV!);
      _rangePrediction?.learnVoltage(update.voltageV!);

      // Calculate dynamic range prediction based on learned profile and active session
      final learned = _rangePrediction?.state;
      final soc = next.battCapPercent; // 0..100 %
      final learnedCap = learned?.learnedCapacityWh ??
          3800.0; // Default Arctic Leopard ~3.8 kWh
      final avgCons =
          (learned != null && learned.consumptionHistoryWhPerKm.isNotEmpty)
              ? (learned.consumptionHistoryWhPerKm.reduce((a, b) => a + b) /
                  learned.consumptionHistoryWhPerKm.length)
              : 60.0; // Wh/km default

      final dynamicRangeKm = (soc * learnedCap / 100.0) / avgCons;
      final dynamicUncertainty =
          (learned != null && learned.socConfidence > 0.3)
              ? dynamicRangeKm * 0.1
              : 8.0;

      next = next.copyWith(
        rangeKm: dynamicRangeKm,
        rangeUncertaintyKm: dynamicUncertainty,
      );

      final rangeEst = quality.TelemetrySample(
        value: dynamicRangeKm,
        source: quality.TelemetrySource.derived,
        capturedAt: update.capturedAt,
      );
      samples[ControllerTelemetry.range] = rangeEst;
    }
    if (update.currentA != null) {
      next = next.copyWith(currentA: update.currentA);
      record(ControllerTelemetry.current, update.currentA!);
    }
    if (update.phaseACurrA != null)
      next = next.copyWith(phaseACurrA: update.phaseACurrA);
    if (update.phaseCCurrA != null)
      next = next.copyWith(phaseCCurrA: update.phaseCCurrA);
    if (update.motorTempC != null) {
      next = next.copyWith(motorTempC: update.motorTempC);
      record(ControllerTelemetry.motorTemperature, update.motorTempC!);
    }
    if (update.battCapPercent != null) {
      next = next.copyWith(battCapPercent: update.battCapPercent);
      record(ControllerTelemetry.soc, update.battCapPercent!);
    }
    if (update.mosTempC != null) {
      next = next.copyWith(controllerTempC: update.mosTempC);
      record(ControllerTelemetry.controllerTemperature, update.mosTempC!);
    }

    if (update.wheelRadius != null)
      next = next.copyWith(wheelRadius: update.wheelRadius);
    if (update.wheelWidth != null)
      next = next.copyWith(wheelWidth: update.wheelWidth);
    if (update.wheelRatio != null)
      next = next.copyWith(wheelRatio: update.wheelRatio);
    if (update.rateRatio != null && update.rateRatio! > 0)
      next = next.copyWith(rateRatio: update.rateRatio);

    if (update.maxSpeed != null)
      next = next.copyWith(maxSpeedRaw: update.maxSpeed);
    if (update.maxLineCurrRaw != null)
      next = next.copyWith(maxLineCurrRaw: update.maxLineCurrRaw);
    if (update.zeroBattCoeff != null)
      next = next.copyWith(zeroBattCoeff: update.zeroBattCoeff);
    if (update.fullBattCoeff != null)
      next = next.copyWith(fullBattCoeff: update.fullBattCoeff);

    // Recompute derived fields
    next = next.withComputedFields();
    if (update.voltageV != null || update.currentA != null) {
      record(ControllerTelemetry.power, next.powerKw);
    }
    state = next.copyWith(telemetrySamples: Map.unmodifiable(samples));

    // Save stock backup on first connect if not already done
    if (!_storage.firstConnectDone && update.maxLineCurrRaw != null) {
      _saveStockBackup();
    }
  }

  double _speedFromRaw(int measureSpeed) {
    return UnitConverter.measureSpeedToKph(
      measureSpeed: measureSpeed,
      wheelRadius: state.wheelRadius,
      wheelWidth: state.wheelWidth,
      wheelRatio: state.wheelRatio,
      rateRatio: state.rateRatio,
    );
  }

  void _saveStockBackup() {
    final backup = <int, int>{
      0x15: state.maxSpeedRaw,
      0x19: state.maxLineCurrRaw,
    };
    _storage.saveStockBackup(backup);
  }

  Future<void> setRideMode(RideMode mode) async {
    if (state.speedKph > 2.0) {
      _diagnostics.add(DiagnosticEventType.safety, details: {
        'outcome': 'blocked',
        'reason': 'vehicle_moving',
      });
      return;
    }
    final packet =
        ProtocolService.setThrottleResponsePacket(mode.throttleResponseValue);
    final written = await _bluetooth.write(packet);
    _diagnostics.add(DiagnosticEventType.command, details: {
      'outcome': written ? 'transport_success' : 'transport_failure',
      'command': 'set_ride_mode',
    });
    if (!written) return;
    state = state.copyWith(
      rideMode: mode,
      lastUpdate: DateTime.now(),
    );
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
  final diagnostics = ref.watch(diagnosticsLogProvider);
  final rangePrediction = ref.watch(rangePredictionStateProvider.notifier);
  return ControllerNotifier(bluetooth, storage,
      diagnostics: diagnostics, rangePrediction: rangePrediction);
});

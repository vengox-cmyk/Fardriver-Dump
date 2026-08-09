import 'dart:async';
import 'dart:math' as math;

import 'package:arcdash/services/ble_transport.dart';
import 'package:arcdash/services/bluetooth_service.dart';
import 'package:arcdash/utils/packet_framer.dart';
import 'package:arcdash/utils/packet_parser.dart';

enum ControllerSessionState {
  idle,
  connecting,
  connected,
  reconnecting,
  disconnected,
  error,
}

typedef ReconnectDelay = Future<void> Function(Duration duration);
typedef ReconnectJitter = Duration Function(Duration delay, int attempt);

class ControllerSessionSnapshot {
  final ControllerSessionState state;
  final TelemetryUpdate? telemetry;
  final String? error;

  const ControllerSessionSnapshot({
    required this.state,
    this.telemetry,
    this.error,
  });
}

class ControllerSession {
  final BleTransport _transport;
  final ReconnectDelay _delay;
  final int _maxReconnectAttempts;
  final Duration _baseReconnectDelay;
  final Duration _maxReconnectDelay;
  final ReconnectJitter _jitter;
  final PacketFramer _framer = PacketFramer();
  final StreamController<ControllerSessionSnapshot> _updates =
      StreamController<ControllerSessionSnapshot>.broadcast(sync: true);
  late final StreamSubscription<DongleConnectionState> _stateSubscription;
  late final StreamSubscription<List<int>> _dataSubscription;

  ControllerSessionSnapshot _current = const ControllerSessionSnapshot(
    state: ControllerSessionState.idle,
  );
  bool _disposed = false;
  bool _reconnectCancelled = false;
  Future<void>? _reconnectTask;
  DiscoveredDongle? _lastDevice;

  ControllerSession(
    this._transport, {
    ReconnectDelay delay = _defaultReconnectDelay,
    int maxReconnectAttempts = 5,
    Duration baseReconnectDelay = const Duration(seconds: 1),
    Duration maxReconnectDelay = const Duration(seconds: 30),
    ReconnectJitter jitter = _defaultReconnectJitter,
  })  : _delay = delay,
        _maxReconnectAttempts = maxReconnectAttempts,
        _baseReconnectDelay = baseReconnectDelay,
        _maxReconnectDelay = maxReconnectDelay,
        _jitter = jitter {
    _stateSubscription =
        _transport.connectionStateStream.listen(_onTransportState);
    _dataSubscription = _transport.rawDataStream.listen(_onBytes);
  }

  ControllerSessionSnapshot get current => _current;

  Stream<ControllerSessionSnapshot> watch() async* {
    yield _current;
    if (!_disposed) yield* _updates.stream;
  }

  Future<bool> connect(DiscoveredDongle dongle) async {
    if (_disposed) return false;
    if (_current.state == ControllerSessionState.connected) return true;
    _emit(const ControllerSessionSnapshot(
      state: ControllerSessionState.connecting,
    ));
    _reconnectCancelled = false;
    try {
      final connected = await _transport.connect(dongle);
      if (!connected) {
        _emit(const ControllerSessionSnapshot(
          state: ControllerSessionState.error,
          error: 'connect_failed',
        ));
      } else if (_current.state != ControllerSessionState.connected) {
        _emit(const ControllerSessionSnapshot(
          state: ControllerSessionState.connected,
        ));
      }
      if (connected) _lastDevice = dongle;
      return connected;
    } catch (_) {
      _emit(const ControllerSessionSnapshot(
        state: ControllerSessionState.error,
        error: 'connect_exception',
      ));
      return false;
    }
  }

  Future<void> disconnect() async {
    if (_disposed) return;
    _reconnectCancelled = true;
    await _transport.disconnect();
    if (!_disposed && _current.state != ControllerSessionState.disconnected) {
      _emit(const ControllerSessionSnapshot(
        state: ControllerSessionState.disconnected,
      ));
    }
  }

  void _onTransportState(DongleConnectionState state) {
    if (_disposed) return;
    final mapped = switch (state) {
      DongleConnectionState.connected => ControllerSessionState.connected,
      DongleConnectionState.connecting => ControllerSessionState.connecting,
      DongleConnectionState.disconnected => ControllerSessionState.disconnected,
      DongleConnectionState.error => ControllerSessionState.error,
      _ => ControllerSessionState.idle,
    };
    _emit(ControllerSessionSnapshot(
      state: mapped,
      telemetry: _current.telemetry,
    ));
    if ((state == DongleConnectionState.disconnected ||
            state == DongleConnectionState.error) &&
        _lastDevice != null &&
        !_reconnectCancelled) {
      _startReconnect();
    }
  }

  /// Resumes retries after the app or Bluetooth adapter becomes available.
  void resumeReconnect() {
    if (_disposed || _lastDevice == null) return;
    _reconnectCancelled = false;
    if (_current.state != ControllerSessionState.connected) _startReconnect();
  }

  /// Stops retries without forgetting the last confirmed device.
  void cancelReconnect() {
    _reconnectCancelled = true;
    if (!_disposed && _current.state == ControllerSessionState.reconnecting) {
      _emit(ControllerSessionSnapshot(
        state: ControllerSessionState.disconnected,
        telemetry: _current.telemetry,
      ));
    }
  }

  void _startReconnect() {
    if (_reconnectTask != null || _disposed || _lastDevice == null) return;
    _reconnectTask = _reconnectLoop().whenComplete(() => _reconnectTask = null);
  }

  Future<void> _reconnectLoop() async {
    for (var attempt = 0; attempt < _maxReconnectAttempts; attempt++) {
      if (_disposed || _reconnectCancelled || _lastDevice == null) return;

      final requested = _baseReconnectDelay * (1 << attempt);
      final capped =
          requested > _maxReconnectDelay ? _maxReconnectDelay : requested;
      final wait = _jitter(capped, attempt);
      _emit(ControllerSessionSnapshot(
        state: ControllerSessionState.reconnecting,
        telemetry: _current.telemetry,
      ));
      await _delay(wait);
      if (_disposed || _reconnectCancelled || _lastDevice == null) return;
      if (!await _transport.isBluetoothOn()) continue;

      final connected = await _transport.connect(_lastDevice!);
      if (connected) {
        _emit(ControllerSessionSnapshot(
          state: ControllerSessionState.connected,
          telemetry: _current.telemetry,
        ));
        return;
      }
    }

    if (!_disposed && !_reconnectCancelled) {
      _emit(ControllerSessionSnapshot(
        state: ControllerSessionState.error,
        telemetry: _current.telemetry,
        error: 'reconnect_failed',
      ));
    }
  }

  void _onBytes(List<int> bytes) {
    if (_disposed) return;
    for (final packet in _framer.add(bytes)) {
      final parsed = PacketParser.parseStatusPacket(packet);
      if (parsed == null) continue;
      final telemetry = PacketParser.extractTelemetry(parsed);
      if (telemetry != null) {
        _emit(ControllerSessionSnapshot(
          state: _current.state,
          telemetry: telemetry,
        ));
      }
    }
  }

  void _emit(ControllerSessionSnapshot snapshot) {
    if (_disposed) return;
    _current = snapshot;
    _updates.add(snapshot);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _reconnectCancelled = true;
    await _stateSubscription.cancel();
    await _dataSubscription.cancel();
    await _updates.close();
  }

  static Future<void> _defaultReconnectDelay(Duration duration) =>
      Future<void>.delayed(duration);

  static Duration _defaultReconnectJitter(Duration delay, int _) {
    final factor = 0.8 + math.Random().nextDouble() * 0.4;
    return Duration(microseconds: (delay.inMicroseconds * factor).round());
  }
}

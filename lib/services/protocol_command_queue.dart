import 'dart:async';

import 'package:arcdash/services/ble_transport.dart';
import 'package:arcdash/services/bluetooth_service.dart';
import 'package:arcdash/utils/packet_framer.dart';

enum CommandFailureReason {
  cancelled,
  disconnected,
  timeout,
  transport,
}

class CommandQueueException implements Exception {
  final CommandFailureReason reason;

  const CommandQueueException(this.reason);

  @override
  String toString() => 'Command failed: ${reason.name}';
}

class CommandTicket {
  final Future<List<int>> future;
  final void Function() cancel;

  const CommandTicket({required this.future, required this.cancel});
}

class ProtocolCommandQueue {
  final BleTransport _transport;
  final PacketFramer _framer = PacketFramer();
  final List<_PendingCommand> _pending = [];
  late final StreamSubscription<List<int>> _dataSubscription;
  late final StreamSubscription<DongleConnectionState> _stateSubscription;
  _PendingCommand? _active;
  bool _disposed = false;

  ProtocolCommandQueue(this._transport) {
    _dataSubscription = _transport.rawDataStream.listen(_onData);
    _stateSubscription = _transport.connectionStateStream.listen(_onState);
  }

  CommandTicket enqueue({
    required List<int> packet,
    required bool Function(List<int> response) matches,
    Duration timeout = const Duration(seconds: 2),
  }) {
    final completer = Completer<List<int>>();
    final command = _PendingCommand(
      packet: List<int>.from(packet),
      matches: matches,
      timeout: timeout,
      completer: completer,
    );
    if (_disposed) {
      completer.completeError(
        const CommandQueueException(CommandFailureReason.disconnected),
      );
    } else {
      _pending.add(command);
      _pump();
    }
    return CommandTicket(
        future: completer.future, cancel: () => _cancel(command));
  }

  void _pump() {
    if (_active != null || _pending.isEmpty || _disposed) return;
    _active = _pending.removeAt(0);
    _runActive(_active!);
  }

  Future<void> _runActive(_PendingCommand command) async {
    try {
      if (!await _transport.write(command.packet)) {
        _fail(command, CommandFailureReason.transport);
        return;
      }
      command.timer = Timer(command.timeout, () {
        _fail(command, CommandFailureReason.timeout);
      });
    } catch (_) {
      _fail(command, CommandFailureReason.transport);
    }
  }

  void _onData(List<int> bytes) {
    if (_disposed) return;
    for (final packet in _framer.add(bytes)) {
      final active = _active;
      if (active != null && active.matches(packet)) {
        active.timer?.cancel();
        active.completer.complete(packet);
        _active = null;
        _pump();
      }
    }
  }

  void _onState(DongleConnectionState state) {
    if (state == DongleConnectionState.disconnected ||
        state == DongleConnectionState.error) {
      _failAll(CommandFailureReason.disconnected);
    }
  }

  void _cancel(_PendingCommand command) {
    if (command.completer.isCompleted) return;
    if (identical(_active, command)) {
      _fail(command, CommandFailureReason.cancelled);
    } else if (_pending.remove(command)) {
      command.completer.completeError(
        const CommandQueueException(CommandFailureReason.cancelled),
      );
    }
  }

  void _fail(_PendingCommand command, CommandFailureReason reason) {
    if (command.completer.isCompleted) return;
    command.timer?.cancel();
    command.completer.completeError(CommandQueueException(reason));
    if (identical(_active, command)) {
      _active = null;
      _pump();
    }
  }

  void _failAll(CommandFailureReason reason) {
    final active = _active;
    _active = null;
    if (active != null) _fail(active, reason);
    for (final command in List<_PendingCommand>.from(_pending)) {
      command.completer.completeError(CommandQueueException(reason));
    }
    _pending.clear();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _failAll(CommandFailureReason.disconnected);
    await _dataSubscription.cancel();
    await _stateSubscription.cancel();
  }
}

class _PendingCommand {
  final List<int> packet;
  final bool Function(List<int>) matches;
  final Duration timeout;
  final Completer<List<int>> completer;
  Timer? timer;

  _PendingCommand({
    required this.packet,
    required this.matches,
    required this.timeout,
    required this.completer,
  });
}

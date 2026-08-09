class ParameterSnapshot {
  final String controllerId;
  final Set<int> requiredAddresses;
  final Map<int, List<int>> blocks;
  final DateTime startedAt;
  final DateTime lastBlockAt;
  final bool isTimedOut;

  const ParameterSnapshot({
    required this.controllerId,
    required this.requiredAddresses,
    required this.blocks,
    required this.startedAt,
    required this.lastBlockAt,
    required this.isTimedOut,
  });

  Set<int> get missingAddresses =>
      requiredAddresses.difference(blocks.keys.toSet());

  double get progress => requiredAddresses.isEmpty
      ? 0
      : (requiredAddresses.length - missingAddresses.length) /
          requiredAddresses.length;

  bool get isComplete => !isTimedOut && missingAddresses.isEmpty;
}

class ParameterSnapshotBuilder {
  final Duration timeout;
  String? _controllerId;
  Set<int> _requiredAddresses = {};
  final Map<int, List<int>> _blocks = {};
  DateTime? _startedAt;
  DateTime? _lastBlockAt;

  ParameterSnapshotBuilder({this.timeout = const Duration(seconds: 10)}) {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
  }

  void begin({
    required String controllerId,
    required Set<int> requiredAddresses,
    required DateTime at,
  }) {
    if (controllerId.trim().isEmpty) {
      throw ArgumentError.value(
          controllerId, 'controllerId', 'must not be empty');
    }
    if (requiredAddresses.isEmpty ||
        requiredAddresses.any((address) => address < 0 || address > 0xFF)) {
      throw ArgumentError.value(requiredAddresses, 'requiredAddresses');
    }
    _controllerId = controllerId;
    _requiredAddresses = Set.unmodifiable(requiredAddresses);
    _blocks.clear();
    _startedAt = at;
    _lastBlockAt = at;
  }

  void addBlock({
    required int address,
    required List<int> bytes,
    required DateTime at,
  }) {
    if (_controllerId == null) throw StateError('snapshot has not started');
    if (address < 0 || address > 0xFF) {
      throw RangeError.range(address, 0, 0xFF, 'address');
    }
    if (bytes.length != 12) {
      throw const FormatException('snapshot blocks must contain 12 bytes');
    }
    if (at.difference(_lastBlockAt!) > timeout) {
      _blocks.clear();
      _startedAt = at;
    }
    _blocks[address] = List.unmodifiable(bytes);
    _lastBlockAt = at;
  }

  ParameterSnapshot snapshot({required DateTime at}) {
    if (_controllerId == null) throw StateError('snapshot has not started');
    final timedOut = at.difference(_lastBlockAt!) > timeout;
    return ParameterSnapshot(
      controllerId: _controllerId!,
      requiredAddresses: _requiredAddresses,
      blocks: Map.unmodifiable(_blocks),
      startedAt: _startedAt!,
      lastBlockAt: _lastBlockAt!,
      isTimedOut: timedOut,
    );
  }
}

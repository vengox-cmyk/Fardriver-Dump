import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:biketunes/models/ride_stats.dart';
import 'package:biketunes/providers/bluetooth_provider.dart';
import 'package:biketunes/services/bluetooth_service.dart' show DongleConnectionState;
import 'package:biketunes/providers/controller_provider.dart';
import 'package:biketunes/services/storage_service.dart';

class StatsState {
  final RideSession? currentSession;
  final List<Map<String, dynamic>> pastSessions;
  final bool isTracking;

  const StatsState({
    this.currentSession,
    this.pastSessions = const [],
    this.isTracking = false,
  });

  StatsState copyWith({
    RideSession? currentSession,
    List<Map<String, dynamic>>? pastSessions,
    bool? isTracking,
    bool clearCurrentSession = false,
  }) =>
      StatsState(
        currentSession:
            clearCurrentSession ? null : (currentSession ?? this.currentSession),
        pastSessions: pastSessions ?? this.pastSessions,
        isTracking: isTracking ?? this.isTracking,
      );
}

class StatsNotifier extends StateNotifier<StatsState> {
  final Ref _ref;
  Timer? _sampleTimer;
  DateTime? _lastSampleTime;

  StatsNotifier(this._ref) : super(const StatsState()) {
    _loadPastSessions();
    _watchConnection();
  }

  void _watchConnection() {
    _ref.listen<AsyncValue<DongleConnectionState>>(
      connectionStateProvider,
      (_, next) {
        final cs = next.valueOrNull;
        if (cs == DongleConnectionState.connected) {
          _startTracking();
        } else if (cs == DongleConnectionState.disconnected) {
          _stopTracking();
        }
      },
    );
  }

  void _startTracking() {
    if (state.isTracking) return;
    final session = RideSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      startTime: DateTime.now(),
    );
    state = state.copyWith(currentSession: session, isTracking: true);
    _lastSampleTime = DateTime.now();

    _sampleTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _takeSample();
    });
  }

  void _takeSample() {
    final session = state.currentSession;
    if (session == null) return;

    final controller = _ref.read(controllerProvider);
    final now = DateTime.now();
    final delta = now.difference(_lastSampleTime!).inMilliseconds / 1000.0;
    _lastSampleTime = now;

    session.addSample(
      speedKph: controller.speedKph,
      voltageV: controller.voltageV,
      currentA: controller.currentA,
      deltaTimeSeconds: delta,
    );

    // Trigger rebuild by copying state
    state = StatsState(
      currentSession: session,
      pastSessions: state.pastSessions,
      isTracking: state.isTracking,
    );
  }

  void _stopTracking() {
    _sampleTimer?.cancel();
    _sampleTimer = null;

    final session = state.currentSession;
    if (session == null) return;
    session.end();

    _saveSession(session);
    state = state.copyWith(clearCurrentSession: true, isTracking: false);
    _loadPastSessions();
  }

  Future<void> _saveSession(RideSession session) async {
    final storage = _ref.read(storageServiceProvider);
    await storage.saveRideSession(session);
  }

  void _loadPastSessions() {
    final storage = _ref.read(storageServiceProvider);
    final sessions = storage.loadRideSessions();
    state = state.copyWith(pastSessions: sessions);
  }

  Future<String?> exportCurrentSession() async {
    final session = state.currentSession;
    if (session == null) return null;
    final storage = _ref.read(storageServiceProvider);
    return await storage.exportSessionToCsv(session);
  }

  @override
  void dispose() {
    _sampleTimer?.cancel();
    super.dispose();
  }
}

final statsProvider =
    StateNotifierProvider<StatsNotifier, StatsState>((ref) {
  return StatsNotifier(ref);
});

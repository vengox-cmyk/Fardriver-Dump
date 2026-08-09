import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcdash/models/ride_stats.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/services/bluetooth_service.dart'
    show DongleConnectionState;
import 'package:arcdash/providers/controller_provider.dart';

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
        currentSession: clearCurrentSession
            ? null
            : (currentSession ?? this.currentSession),
        pastSessions: pastSessions ?? this.pastSessions,
        isTracking: isTracking ?? this.isTracking,
      );
}

class StatsNotifier extends StateNotifier<StatsState> {
  final Ref _ref;
  Timer? _sampleTimer;
  Timer? _disconnectGraceTimer;
  DateTime? _lastSampleTime;
  DateTime? _stationarySince;

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
          _disconnectGraceTimer?.cancel();
          _startSampling();
        } else if (cs == DongleConnectionState.disconnected) {
          _sampleTimer?.cancel();
          _sampleTimer = null;
          _disconnectGraceTimer?.cancel();
          _disconnectGraceTimer = Timer(
            const Duration(seconds: 15),
            _finalizeSession,
          );
        }
      },
      fireImmediately: true,
    );
  }

  void _startSampling() {
    if (_sampleTimer != null) return;
    _lastSampleTime = DateTime.now();
    _sampleTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _takeSample());
  }

  void _beginSession(DateTime now) {
    final session = RideSession(
      id: now.millisecondsSinceEpoch.toString(),
      startTime: now,
    );
    state = state.copyWith(currentSession: session, isTracking: true);
  }

  void _takeSample() {
    final controller = _ref.read(controllerProvider);
    final now = DateTime.now();

    // Check if the day has changed (Midnight automatic reset/rollover)
    final session = state.currentSession;
    if (session != null && session.startTime.day != now.day) {
      unawaited(_finalizeSession().then((_) {
        _beginSession(now);
        _lastSampleTime = now;
      }));
      return;
    }

    final lastSample = _lastSampleTime;
    _lastSampleTime = now;
    if (state.currentSession == null) {
      if (controller.speedKph < 1.5) return;
      _beginSession(now);
    }
    final currentActiveSession = state.currentSession!;
    final delta = lastSample == null
        ? 0.0
        : now.difference(lastSample).inMilliseconds / 1000.0;

    if (controller.speedKph < 1) {
      _stationarySince ??= now;
      if (now.difference(_stationarySince!) >= const Duration(minutes: 5)) {
        unawaited(_finalizeSession().then((_) => _startSampling()));
        return;
      }
    } else {
      _stationarySince = null;
    }

    currentActiveSession.addSample(
      speedKph: controller.speedKph,
      voltageV: controller.voltageV,
      currentA: controller.currentA,
      deltaTimeSeconds: delta,
    );

    // Feed learned session metrics into RangePredictionNotifier
    if (currentActiveSession.distanceKm >= 0.5 &&
        currentActiveSession.totalWhUsed > 10) {
      _ref.read(rangePredictionStateProvider.notifier).learnFromSession(
            distanceKm: currentActiveSession.distanceKm,
            totalWhUsed: currentActiveSession.totalWhUsed,
            socPercent: controller.battCapPercent?.toDouble(),
          );
    }

    // Trigger rebuild by copying state
    state = StatsState(
      currentSession: currentActiveSession,
      pastSessions: state.pastSessions,
      isTracking: state.isTracking,
    );
  }

  Future<void> resetCurrentSession() async {
    await _finalizeSession();
    _lastSampleTime = DateTime.now();
    _startSampling();
  }

  Future<void> _finalizeSession() async {
    _sampleTimer?.cancel();
    _sampleTimer = null;
    _stationarySince = null;

    final session = state.currentSession;
    if (session == null) return;
    session.end();

    await _saveSession(session);
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
    _disconnectGraceTimer?.cancel();
    super.dispose();
  }
}

final statsProvider = StateNotifierProvider<StatsNotifier, StatsState>((ref) {
  return StatsNotifier(ref);
});

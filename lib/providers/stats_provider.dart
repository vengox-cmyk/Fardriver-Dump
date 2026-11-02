import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arcdash/models/drive_state.dart';
import 'package:arcdash/models/ride_stats.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/saved_files_provider.dart';
import 'package:arcdash/services/bluetooth_service.dart'
    show DongleConnectionState;
import 'package:arcdash/services/foreground_service_bridge.dart';
import 'package:arcdash/services/ride_archive.dart';

/// Bumped after a ride record is written so the Rides tab reloads its list.
final rideArchiveRevisionProvider = StateProvider<int>((ref) => 0);

/// One second of live controller data for a running ride.
class LiveRideSample {
  const LiveRideSample({
    required this.speedKph,
    required this.voltageV,
    required this.currentA,
    this.phaseACurrA = 0,
    this.phaseCCurrA = 0,
    this.motorTempC = 0,
    this.controllerTempC = 0,
    this.gear,
    this.socPercent = 0,
  });

  final double speedKph;
  final double voltageV;
  final double currentA;
  final double phaseACurrA;
  final double phaseCCurrA;
  final double motorTempC;
  final double controllerTempC;
  final GearStatus? gear;
  final double socPercent;
}

/// Reads the live sample for [now], or null while the controller is not
/// connected (the ride keeps running but records nothing for that second).
final liveRideSampleProvider =
    Provider<LiveRideSample? Function(DateTime now)>((ref) {
  return (now) {
    final cs = ref.read(connectionStateProvider).valueOrNull;
    if (cs != DongleConnectionState.connected) return null;
    final c = ref.read(controllerProvider);
    return LiveRideSample(
      speedKph: c.speedKph,
      voltageV: c.voltageV,
      currentA: c.currentA,
      phaseACurrA: c.phaseACurrA,
      phaseCCurrA: c.phaseCCurrA,
      motorTempC: c.motorTempC,
      controllerTempC: c.controllerTempC,
      gear: c.gearStatus(now),
      socPercent: c.battCapPercent.toDouble(),
    );
  };
});

/// Keeps the app process alive while a ride records with the screen off
/// (Android foreground service; best effort, never throws).
class RideKeepAlive {
  const RideKeepAlive();

  Future<void> start() async {
    try {
      await const ForegroundServiceBridge().start();
    } on Object catch (e) {
      debugPrint('Foreground service not started: $e');
    }
  }

  Future<void> stop() async {
    try {
      await const ForegroundServiceBridge().stop();
    } on Object catch (e) {
      debugPrint('Foreground service not stopped: $e');
    }
  }
}

final rideKeepAliveProvider =
    Provider<RideKeepAlive>((_) => const RideKeepAlive());

class StatsState {
  final RideSession? currentSession;
  final List<Map<String, dynamic>> pastSessions;
  final bool isTracking;

  /// True while a ride runs but the controller is not sending data.
  final bool waitingForController;

  const StatsState({
    this.currentSession,
    this.pastSessions = const [],
    this.isTracking = false,
    this.waitingForController = false,
  });

  StatsState copyWith({
    RideSession? currentSession,
    List<Map<String, dynamic>>? pastSessions,
    bool? isTracking,
    bool? waitingForController,
    bool clearCurrentSession = false,
  }) =>
      StatsState(
        currentSession: clearCurrentSession
            ? null
            : (currentSession ?? this.currentSession),
        pastSessions: pastSessions ?? this.pastSessions,
        isTracking: isTracking ?? this.isTracking,
        waitingForController: waitingForController ?? this.waitingForController,
      );
}

/// Manual rides: a ride starts only on [startRide] and ends only on
/// [stopRide] (or [finishSession] when the rider confirms leaving the app).
///
/// While it runs it samples once a second, independent of the screen: it
/// keeps going when the Rides tab is left, the screen is off (foreground
/// service) or Bluetooth drops — seconds without controller data are simply
/// skipped (no distance is invented across the gap) and recording resumes
/// on reconnect. Every sample is streamed to the ride CSV and the ride record
/// is checkpointed every [checkpointEvery] as unfinished, so a crash or a
/// killed app leaves a saved, unfinished ride. Every started ride is saved,
/// however short.
class StatsNotifier extends StateNotifier<StatsState> {
  final Ref _ref;
  Timer? _sampleTimer;
  Timer? _checkpointTimer;
  DateTime? _lastSampleTime;
  RideRecorder? _recorder;
  Future<void>? _stopping;

  static const checkpointEvery = Duration(seconds: 5);

  /// Sampling period (tests raise it so only explicit [sampleNow] calls
  /// record).
  @visibleForTesting
  static Duration sampleEvery = const Duration(seconds: 1);

  StatsNotifier(this._ref) : super(const StatsState()) {
    _loadPastSessions();
  }

  bool get isRecording => state.currentSession != null;

  /// Starts a ride now. No-op while one is already running.
  Future<void> startRide() async {
    if (state.currentSession != null || _stopping != null) return;
    final now = DateTime.now();
    final session = RideSession(
      id: now.millisecondsSinceEpoch.toString(),
      startTime: now,
    );
    _lastSampleTime = null;
    state = state.copyWith(
        currentSession: session,
        isTracking: true,
        waitingForController: _ref.read(liveRideSampleProvider)(now) == null);
    final recorder = _recorder =
        RideRecorder(RideArchive(_ref.read(savedFilesStoreProvider)), session);
    _sampleTimer =
        Timer.periodic(sampleEvery, (_) => sampleNow());
    _checkpointTimer = Timer.periodic(
        checkpointEvery, (_) => unawaited(recorder.checkpoint()));
    unawaited(_ref.read(rideKeepAliveProvider).start());
    await recorder.begin();
    if (mounted) _ref.read(rideArchiveRevisionProvider.notifier).state++;
  }

  /// Takes one sample (the 1 s timer calls this).
  @visibleForTesting
  void sampleNow([DateTime? at]) {
    final session = state.currentSession;
    if (session == null) return;
    final now = at ?? DateTime.now();
    final live = _ref.read(liveRideSampleProvider)(now);
    if (live == null) {
      // Bluetooth gap: keep the ride, record nothing, restart the clock.
      _lastSampleTime = null;
      if (!state.waitingForController) {
        state = state.copyWith(waitingForController: true);
      }
      return;
    }
    final last = _lastSampleTime;
    _lastSampleTime = now;
    final delta =
        last == null ? 0.0 : now.difference(last).inMilliseconds / 1000.0;

    session.addSample(
      speedKph: live.speedKph,
      voltageV: live.voltageV,
      currentA: live.currentA,
      deltaTimeSeconds: delta,
      phaseACurrA: live.phaseACurrA,
      phaseCCurrA: live.phaseCCurrA,
      motorTempC: live.motorTempC,
      controllerTempC: live.controllerTempC,
      gear: live.gear,
      at: now,
    );
    _recorder?.add(session.speedHistory.last);

    // Feed learned session metrics into RangePredictionNotifier
    if (session.distanceKm >= 0.5 && session.totalWhUsed > 10) {
      try {
        _ref.read(rangePredictionStateProvider.notifier).learnFromSession(
              distanceKm: session.distanceKm,
              totalWhUsed: session.totalWhUsed,
              socPercent: live.socPercent,
            );
      } on Object catch (e) {
        debugPrint('Range learning skipped: $e');
      }
    }

    // Trigger rebuild by copying state
    state = StatsState(
      currentSession: session,
      pastSessions: state.pastSessions,
      isTracking: state.isTracking,
    );
  }

  /// Writes buffered samples and the unfinished record now.
  @visibleForTesting
  Future<void> checkpointNow() async => _recorder?.checkpoint();

  /// Ends the ride and saves it as finished. No-op without a ride.
  Future<void> stopRide() => _stopping ??= _stop().whenComplete(() {
        _stopping = null;
      });

  Future<void> _stop() async {
    _sampleTimer?.cancel();
    _sampleTimer = null;
    _checkpointTimer?.cancel();
    _checkpointTimer = null;
    _lastSampleTime = null;

    final session = state.currentSession;
    final recorder = _recorder;
    _recorder = null;
    if (session == null) return;
    session.end();
    state = state.copyWith(
        clearCurrentSession: true,
        isTracking: false,
        waitingForController: false);
    unawaited(_ref.read(rideKeepAliveProvider).stop());

    await recorder?.finish();
    try {
      await _ref.read(storageServiceProvider).saveRideSession(session);
    } on Object catch (e) {
      debugPrint('Ride summary not stored: $e');
    }
    if (!mounted) return;
    _ref.read(rideArchiveRevisionProvider.notifier).state++;
    _loadPastSessions();
  }

  /// Ends and saves the running ride now (the rider confirmed leaving the
  /// app). Same as [stopRide].
  Future<void> finishSession() => stopRide();

  void _loadPastSessions() {
    try {
      final storage = _ref.read(storageServiceProvider);
      state = state.copyWith(pastSessions: storage.loadRideSessions());
    } on Object catch (e) {
      debugPrint('Past ride summaries unavailable: $e');
    }
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
    _checkpointTimer?.cancel();
    // Best effort: flush what we have; the record stays unfinished.
    unawaited(_recorder?.checkpoint());
    super.dispose();
  }
}

final statsProvider = StateNotifierProvider<StatsNotifier, StatsState>((ref) {
  return StatsNotifier(ref);
});

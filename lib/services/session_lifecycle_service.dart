import 'dart:async';
import 'package:arcdash/services/controller_session.dart';

class RideSession {
  final DateTime startTime;
  DateTime? endTime;
  bool isActive;

  RideSession({required this.startTime, this.isActive = true});
}

class SessionLifecycleService {
  final Stream<ControllerSessionSnapshot> _sessionStream;
  final Duration _idleTimeout;
  final Duration _disconnectGracePeriod;

  late final StreamSubscription<ControllerSessionSnapshot> _subscription;
  final StreamController<RideSession?> _rideSessionController =
      StreamController<RideSession?>.broadcast(sync: true);

  RideSession? _currentRideSession;
  Timer? _graceTimer;
  bool _disposed = false;

  SessionLifecycleService({
    required Stream<ControllerSessionSnapshot> sessionStream,
    Duration idleTimeout = const Duration(minutes: 5),
    Duration disconnectGracePeriod = const Duration(seconds: 30),
  })  : _sessionStream = sessionStream,
        _idleTimeout = idleTimeout,
        _disconnectGracePeriod = disconnectGracePeriod {
    _subscription = _sessionStream.listen(_onSnapshot);
  }

  bool get isSessionActive =>
      _currentRideSession != null && _currentRideSession!.isActive;

  RideSession? get currentRideSession => _currentRideSession;

  Stream<RideSession?> get rideSessionStream async* {
    yield _currentRideSession;
    if (!_disposed) yield* _rideSessionController.stream;
  }

  void _onSnapshot(ControllerSessionSnapshot snapshot) {
    if (_disposed) return;

    if (snapshot.state == ControllerSessionState.connected) {
      _graceTimer?.cancel();
      _graceTimer = null;

      if (_currentRideSession == null) {
        _startSession();
      }
    } else if (snapshot.state == ControllerSessionState.disconnected ||
        snapshot.state == ControllerSessionState.error) {
      if (_currentRideSession != null && _graceTimer == null) {
        _graceTimer = Timer(_disconnectGracePeriod, () {
          _endSession();
        });
      }
    }
  }

  void _startSession() {
    _currentRideSession = RideSession(startTime: DateTime.now());
    _rideSessionController.add(_currentRideSession);
  }

  void _endSession() {
    if (_currentRideSession != null) {
      _currentRideSession!.isActive = false;
      _currentRideSession!.endTime = DateTime.now();
      _rideSessionController.add(null);
      _currentRideSession = null;
    }
    _graceTimer?.cancel();
    _graceTimer = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _graceTimer?.cancel();
    _subscription.cancel();
    _rideSessionController.close();
  }
}

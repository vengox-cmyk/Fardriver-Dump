import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/services/controller_session.dart';
import 'package:arcdash/services/session_lifecycle_service.dart';
import 'package:arcdash/utils/packet_parser.dart';

class MockControllerSession {
  final _controller =
      StreamController<ControllerSessionSnapshot>.broadcast(sync: true);
  ControllerSessionSnapshot _current = const ControllerSessionSnapshot(
    state: ControllerSessionState.idle,
  );

  ControllerSessionSnapshot get current => _current;

  Stream<ControllerSessionSnapshot> watch() => _controller.stream;

  void emit(ControllerSessionSnapshot snapshot) {
    _current = snapshot;
    _controller.add(snapshot);
  }

  void dispose() {
    _controller.close();
  }
}

void main() {
  group('T070 - Serviceweiter Session-Lifecycle', () {
    late MockControllerSession mockSession;
    late SessionLifecycleService service;

    setUp(() {
      mockSession = MockControllerSession();
      service = SessionLifecycleService(
        sessionStream: mockSession.watch(),
        idleTimeout: const Duration(seconds: 2),
        disconnectGracePeriod: const Duration(milliseconds: 500),
      );
    });

    tearDown(() {
      service.dispose();
      mockSession.dispose();
    });

    test('starts ride session on connection and movement/telemetry', () async {
      expect(service.isSessionActive, isFalse);

      mockSession.emit(ControllerSessionSnapshot(
        state: ControllerSessionState.connected,
        telemetry: TelemetryUpdate(
          capturedAt: DateTime.now(),
          measureSpeed: 100, // speed > 0
        ),
      ));

      expect(service.isSessionActive, isTrue);
      expect(service.currentRideSession, isNotNull);
    });

    test('short disconnect does not stop active session (grace period)',
        () async {
      mockSession.emit(ControllerSessionSnapshot(
        state: ControllerSessionState.connected,
        telemetry:
            TelemetryUpdate(capturedAt: DateTime.now(), measureSpeed: 100),
      ));
      expect(service.isSessionActive, isTrue);

      // Brief disconnect
      mockSession.emit(const ControllerSessionSnapshot(
        state: ControllerSessionState.disconnected,
      ));

      // Immediate check should still be active during grace period
      expect(service.isSessionActive, isTrue);

      // Reconnect before grace period expires
      mockSession.emit(ControllerSessionSnapshot(
        state: ControllerSessionState.connected,
        telemetry:
            TelemetryUpdate(capturedAt: DateTime.now(), measureSpeed: 100),
      ));

      expect(service.isSessionActive, isTrue);
    });

    test('idle timeout or prolonged disconnect ends session cleanly', () async {
      mockSession.emit(ControllerSessionSnapshot(
        state: ControllerSessionState.connected,
        telemetry:
            TelemetryUpdate(capturedAt: DateTime.now(), measureSpeed: 100),
      ));
      expect(service.isSessionActive, isTrue);

      // Prolonged disconnect beyond grace period
      mockSession.emit(const ControllerSessionSnapshot(
        state: ControllerSessionState.disconnected,
      ));

      await Future.delayed(const Duration(milliseconds: 700));

      expect(service.isSessionActive, isFalse);
      expect(service.currentRideSession, isNull);
    });

    test(
        'late UI subscribers receive active session state without missing events',
        () async {
      mockSession.emit(ControllerSessionSnapshot(
        state: ControllerSessionState.connected,
        telemetry:
            TelemetryUpdate(capturedAt: DateTime.now(), measureSpeed: 100),
      ));

      // Late UI consumer subscribes after session has already started
      final lateSubscriberActive = await service.rideSessionStream.first;
      expect(lateSubscriberActive, isNotNull);
      expect(lateSubscriberActive!.isActive, isTrue);
    });
  });
}

import 'package:arcdash/models/controller_identity.dart';
import 'package:arcdash/services/write_safety.dart';
import 'package:flutter_test/flutter_test.dart';

const identity = ControllerIdentity(
  model: 'FD72680',
  hardwareVersion: 'HW1',
  firmwareVersion: '1.2.0',
  functionCode: 'F0',
  extensionCode: 'E1',
  bindingId: 'binding-a',
);

SafetySample _sample(DateTime at, {int rpm = 0}) => SafetySample(
      at: at,
      rpm: rpm,
      motorRunning: false,
      directionKnown: true,
      brakeActive: false,
      throttleZero: true,
    );

void main() {
  test('unknown hardware bounds are never writable', () {
    final definition = const ParameterCatalog()['maxLineCurrent'];
    expect(definition.writable, isFalse);
    expect(() => definition.applyToWord(0xFFFF, 1), throwsStateError);
  });

  test('requires fresh consecutive stillness samples and backup', () {
    final now = DateTime.utc(2026, 1, 1);
    final evaluator = const SafetyEvaluator();
    final samples = <SafetySample>[
      _sample(now.subtract(const Duration(milliseconds: 200))),
      _sample(now.subtract(const Duration(milliseconds: 100))),
      _sample(now),
    ];
    expect(
      evaluator
          .evaluate(
            now: now,
            connected: true,
            identity: identity,
            backupAvailable: true,
            samples: samples,
          )
          .allowed,
      isTrue,
    );
    expect(
      evaluator
          .evaluate(
            now: now,
            connected: true,
            identity: identity,
            backupAvailable: false,
            samples: samples,
          )
          .rejections,
      contains(SafetyRejection.missingBackup),
    );
  });

  test('moving or stale telemetry fails closed', () {
    final now = DateTime.utc(2026, 1, 1);
    final decision = const SafetyEvaluator().evaluate(
      now: now,
      connected: true,
      identity: identity,
      backupAvailable: true,
      samples: [
        _sample(now.subtract(const Duration(seconds: 2)), rpm: 1),
      ],
    );
    expect(decision.allowed, isFalse);
    expect(decision.rejections, contains(SafetyRejection.moving));
    expect(decision.rejections, contains(SafetyRejection.staleTelemetry));
    expect(decision.rejections, contains(SafetyRejection.insufficientSamples));
  });
}

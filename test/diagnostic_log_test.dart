import 'dart:convert';

import 'package:arcdash/services/diagnostic_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('redacts sensitive fields and keeps a bounded ring buffer', () {
    var tick = DateTime.utc(2026, 1, 1);
    final log = DiagnosticLog(maxEvents: 2, clock: () => tick);

    log.add(DiagnosticEventType.connect, details: {
      'mac': 'C0:07:AD:88:00:6B',
      'serialNumber': 'secret',
      'state': 'connected',
    });
    tick = tick.add(const Duration(seconds: 1));
    log.add(DiagnosticEventType.command, details: {
      'parameter': 'maxLineCurrent',
      'outcome': 'transport_success',
    });
    tick = tick.add(const Duration(seconds: 1));
    log.add(DiagnosticEventType.frame, details: {'address': 0x19});

    expect(log.events, hasLength(2));
    final decoded = jsonDecode(log.exportJson()) as Map<String, dynamic>;
    expect(decoded['format'], 'arcdash-diagnostics-v1');
    expect(decoded['events'], hasLength(2));
    final first = (decoded['events'] as List).first as Map<String, dynamic>;
    expect((first['details'] as Map)['parameter'], '<redacted>');
    final last = (decoded['events'] as List).last as Map<String, dynamic>;
    expect((last['details'] as Map)['address'], '<redacted>');
  });
}

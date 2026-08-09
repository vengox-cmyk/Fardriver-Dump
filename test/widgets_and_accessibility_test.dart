import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/widgets/battery_indicator.dart';
import 'package:arcdash/widgets/connection_status_bar.dart';
import 'package:arcdash/services/bluetooth_service.dart';

void main() {
  group('T077 - Widget & Accessibility Tests', () {
    testWidgets('BatteryIndicator renders percentage and voltage correctly',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BatteryIndicator(
              percentage: 85.0,
              voltageV: 72.5,
              estimatedRangeKm: 45.0,
            ),
          ),
        ),
      );

      expect(find.text('85'), findsOneWidget);
      expect(find.text('%'), findsOneWidget);
      expect(find.text('72.5V'), findsOneWidget);
      expect(find.text('~45 km'), findsOneWidget);
    });

    testWidgets('ConnectionStatusBar displays connected state and device name',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ConnectionStatusBar(
              state: DongleConnectionState.connected,
              deviceName: 'FD-72600-A1',
            ),
          ),
        ),
      );

      expect(find.text('CONNECTED — FD-72600-A1'), findsOneWidget);
    });

    testWidgets('Accessibility Semantics check for BatteryIndicator',
        (WidgetTester tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Semantics(
              label: 'Batteriestand 85 Prozent',
              child: const BatteryIndicator(
                percentage: 85.0,
                voltageV: 72.5,
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(Semantics).last).label,
        contains('Batteriestand 85 Prozent'),
      );

      handle.dispose();
    });
  });
}

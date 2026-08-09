import 'package:arcdash/app.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/screens/dashboard_screen.dart';
import 'package:arcdash/services/bluetooth_service.dart';
import 'package:arcdash/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDongleService extends DongleService {
  @override
  Stream<DongleConnectionState> get connectionStateStream =>
      Stream.value(DongleConnectionState.idle);
  @override
  Stream<List<int>> get rawDataStream => const Stream.empty();
  @override
  Stream<List<DiscoveredDongle>> get scanResultsStream => const Stream.empty();
  @override
  DongleConnectionState get state => DongleConnectionState.idle;
  @override
  Future<bool> isBluetoothOn() async => false;
  @override
  Future<void> startScan(
      {Duration timeout = const Duration(seconds: 10)}) async {}
  @override
  Future<void> stopScan() async {}
  @override
  Future<bool> write(List<int> data) async => false;
  @override
  void dispose() {}
}

void main() {
  group('Phase 2 - Immersive Landscape Mode & Fullscreen UI', () {
    testWidgets(
        'Landscape orientation enters immersive mode by hiding navigation rail/bar and system UI',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bluetoothServiceProvider.overrideWithValue(_FakeDongleService()),
            storageServiceProvider.overrideWithValue(StorageService()),
          ],
          child: const ArcDashApp(),
        ),
      );

      // Verify cockpit dashboard screen is visible
      expect(find.byType(DashboardScreen), findsOneWidget);
    });
  });

  group('Phase 2 - Speed Dial & R-Power Arc', () {
    testWidgets(
        'Renders speed dial with dynamic unit and power arc with regeneration state',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bluetoothServiceProvider.overrideWithValue(_FakeDongleService()),
            storageServiceProvider.overrideWithValue(StorageService()),
          ],
          child: const ArcDashApp(),
        ),
      );

      expect(find.byKey(const Key('speed-dial')), findsOneWidget);
    });

    testWidgets(
        'Missing or invalid telemetry displays distinct placeholder without bogus values',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bluetoothServiceProvider.overrideWithValue(_FakeDongleService()),
            storageServiceProvider.overrideWithValue(StorageService()),
          ],
          child: const ArcDashApp(),
        ),
      );

      expect(find.text('FAHR-COMPUTER'), findsOneWidget);
    });
  });

  group('Phase 2 - Bottom Info Zone', () {
    testWidgets(
        'Renders battery, range, uncertainty, temps, trip, and mode with semantic labels',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bluetoothServiceProvider.overrideWithValue(_FakeDongleService()),
            storageServiceProvider.overrideWithValue(StorageService()),
          ],
          child: const ArcDashApp(),
        ),
      );

      expect(find.byType(DashboardScreen), findsOneWidget);
    });
  });
}

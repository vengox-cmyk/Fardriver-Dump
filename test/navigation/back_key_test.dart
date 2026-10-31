import 'dart:async';

import 'package:arcdash/app.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/screens/app_shell.dart';
import 'package:arcdash/services/bluetooth_service.dart';
import 'package:arcdash/services/disclaimer.dart';
import 'package:arcdash/services/storage_service.dart';
import 'package:arcdash/widgets/brand_version_label.dart';
import 'package:arcdash/widgets/disclaimer_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Android back (gesture, nav bar or a hardware KEYCODE_BACK such as the
/// Zebra TC72 key) reaches Flutter as a popRoute, which is what
/// `handlePopRoute()` simulates.
void main() {
  late List<String> platformCalls;

  setUp(() {
    SharedPreferences.setMockInitialValues({Disclaimer.prefKey: 1});
    platformCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      platformCalls.add(call.method);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  int exits() => platformCalls.where((m) => m == 'SystemNavigator.pop').length;

  Future<_FakeDongleService> pumpApp(WidgetTester tester,
      {DongleConnectionState state = DongleConnectionState.idle,
      Locale locale = const Locale('en')}) async {
    final service = _FakeDongleService(state);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        bluetoothServiceProvider.overrideWithValue(service),
        storageServiceProvider.overrideWithValue(StorageService()),
      ],
      child: ArcDashApp(locale: locale),
    ));
    await tester.pumpAndSettle();
    return service;
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  int selectedTab(WidgetTester tester) {
    final bar = find.byType(NavigationBar);
    if (bar.evaluate().isNotEmpty) {
      return tester.widget<NavigationBar>(bar).selectedIndex;
    }
    return tester
        .widget<NavigationRail>(find.byType(NavigationRail))
        .selectedIndex!;
  }

  void usePhoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('back on Rides and Settings returns to Cockpit (phone)',
      (tester) async {
    usePhoneSize(tester);
    await pumpApp(tester);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.text('Rides'));
    await tester.pumpAndSettle();
    expect(selectedTab(tester), 1);
    await back(tester);
    expect(selectedTab(tester), 0);
    expect(find.byType(AppShell), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(selectedTab(tester), 2);
    await back(tester);
    expect(selectedTab(tester), 0);

    expect(find.text('Press back again to exit'), findsNothing);
    expect(exits(), 0);
    await disposeApp(tester);
  });

  testWidgets('Cockpit: first back warns, second back within 2 s exits',
      (tester) async {
    await pumpApp(tester);

    await back(tester);
    expect(find.text('Press back again to exit'), findsOneWidget);
    expect(find.byType(AppShell), findsOneWidget);
    expect(exits(), 0);

    await back(tester);
    expect(exits(), 1);
    await disposeApp(tester);
  });

  testWidgets('Cockpit: a second back after the window only warns again',
      (tester) async {
    await pumpApp(tester);

    await back(tester);
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pumpAndSettle();
    await back(tester);
    expect(exits(), 0);
    expect(find.text('Press back again to exit'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('switching tabs disarms the exit hint', (tester) async {
    await pumpApp(tester);

    await back(tester);
    await tester.tap(find.text('Rides'));
    await tester.pumpAndSettle();
    await back(tester); // → Cockpit
    await back(tester); // warns again, does not exit
    expect(exits(), 0);
    await disposeApp(tester);
  });

  testWidgets('German hint text', (tester) async {
    await pumpApp(tester, locale: const Locale('de'));
    await back(tester);
    expect(find.text('Zum Beenden erneut Zurück drücken'), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('connected: back asks "Disconnect and exit?" instead',
      (tester) async {
    final service =
        await pumpApp(tester, state: DongleConnectionState.connected);

    await back(tester);
    expect(find.byKey(const ValueKey('exit-confirm-dialog')), findsOneWidget);
    expect(find.text('Disconnect and exit?'), findsOneWidget);
    expect(find.text('Press back again to exit'), findsNothing);

    // Back on the dialog only closes the dialog.
    await back(tester);
    expect(find.byKey(const ValueKey('exit-confirm-dialog')), findsNothing);
    expect(exits(), 0);
    expect(service.disconnects, 0);

    // "Stay" keeps the connection.
    await back(tester);
    await tester.tap(find.byKey(const ValueKey('exit-confirm-stay')));
    await tester.pumpAndSettle();
    expect(exits(), 0);
    expect(service.disconnects, 0);
    expect(find.byType(AppShell), findsOneWidget);

    // Confirm disconnects, then exits.
    await back(tester);
    await tester.tap(find.byKey(const ValueKey('exit-confirm-exit')));
    await tester.pumpAndSettle();
    expect(service.disconnects, 1);
    expect(exits(), 1);
    await disposeApp(tester);
  });

  testWidgets('back on Rides returns to Cockpit (tablet / rail)',
      (tester) async {
    await pumpApp(tester);
    expect(find.byType(NavigationRail), findsOneWidget);
    await tester.tap(find.text('Rides'));
    await tester.pumpAndSettle();
    await back(tester);
    expect(selectedTab(tester), 0);
    expect(exits(), 0);
    await disposeApp(tester);
  });

  testWidgets('connected on Settings: back still goes to Cockpit first',
      (tester) async {
    final service =
        await pumpApp(tester, state: DongleConnectionState.connected);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await back(tester);
    expect(selectedTab(tester), 0);
    expect(find.byKey(const ValueKey('exit-confirm-dialog')), findsNothing);
    await service.disconnect(); // stops the controller polling timer
    await disposeApp(tester);
  });

  testWidgets('pushed sub-screens still pop normally', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('sub-screen')))));
    await tester.pumpAndSettle();
    expect(find.text('sub-screen'), findsOneWidget);

    await back(tester);
    await tester.pumpAndSettle();
    expect(find.text('sub-screen'), findsNothing);
    expect(selectedTab(tester), 2); // still on Settings
    expect(exits(), 0);
    await disposeApp(tester);
  });

  testWidgets('back on the required disclaimer neither closes it nor exits',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'FarSure',
        packageName: 'com.arcdash',
        version: '1.2.2',
        buildNumber: '4',
        buildSignature: '');
    BrandVersionLabel.resetCache();
    await tester.pumpWidget(const MaterialApp(
        home: DisclaimerGate(child: Scaffold(body: Text('home')))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('disclaimer-dialog')), findsOneWidget);

    await back(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('disclaimer-dialog')), findsOneWidget);
    expect(exits(), 0);
    BrandVersionLabel.resetCache();
  });
}

class _FakeDongleService extends DongleService {
  _FakeDongleService(this._state);

  DongleConnectionState _state;
  int disconnects = 0;
  final _states = StreamController<DongleConnectionState>.broadcast();

  @override
  Stream<DongleConnectionState> get connectionStateStream async* {
    yield _state;
    yield* _states.stream;
  }

  @override
  Stream<List<int>> get rawDataStream => const Stream.empty();

  @override
  Stream<List<DiscoveredDongle>> get scanResultsStream => const Stream.empty();

  @override
  DongleConnectionState get state => _state;

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
  Future<void> disconnect() async {
    disconnects++;
    _state = DongleConnectionState.disconnected;
    _states.add(_state);
  }

  @override
  void dispose() {}
}

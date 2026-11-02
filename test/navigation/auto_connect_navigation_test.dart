import 'dart:async';

import 'package:arcdash/l10n/app_strings.dart';
import 'package:arcdash/models/remembered_device.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/screens/connection_screen.dart';
import 'package:arcdash/services/bluetooth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'
    show BluetoothDevice, DeviceIdentifier;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _uuid = '0000ffe0-0000-1000-8000-00805f9b34fb';

final _fp = AdvertFingerprint.of(
    name: 'FarDriver_BLE',
    serviceUuids: [_uuid],
    manufacturerIds: const [0x0590]);

final _controller = DiscoveredDongle(
  device:
      BluetoothDevice(remoteId: const DeviceIdentifier('E0:07:D3:FD:00:5A')),
  name: 'FarDriver_BLE',
  rssi: -60,
  fingerprint: _fp,
);

/// Broadcasts one remembered controller; connect() walks through
/// connecting → connected like the real service.
class _FakeService extends DongleService {
  _FakeService(this._state);

  DongleConnectionState _state;
  final connected = <String>[];
  final _states = StreamController<DongleConnectionState>.broadcast();

  void emit(DongleConnectionState s) {
    _state = s;
    _states.add(s);
  }

  @override
  DongleConnectionState get state => _state;

  @override
  Stream<DongleConnectionState> get connectionStateStream async* {
    yield _state;
    yield* _states.stream;
  }

  @override
  Stream<List<DiscoveredDongle>> get scanResultsStream async* {
    yield [_controller];
  }

  @override
  Stream<List<int>> get rawDataStream => const Stream.empty();

  @override
  Future<bool> isBluetoothOn() async => true;

  @override
  Future<void> startScan(
      {Duration timeout = const Duration(seconds: 10)}) async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<bool> connect(DiscoveredDongle dongle) async {
    connected.add(dongle.address);
    emit(DongleConnectionState.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    emit(DongleConnectionState.connected);
    return true;
  }

  @override
  Future<void> disconnect() async => emit(DongleConnectionState.disconnected);

  @override
  void dispose() {}
}

const _delay = Duration(milliseconds: 200);

Widget _connectionScreen() =>
    const ConnectionScreen(autoConnectDelay: _delay, scanOnOpen: false);

class _Main extends StatelessWidget {
  const _Main();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).pushNamed('/'),
            child: const Text('MAIN SCREEN'),
          ),
        ),
      );
}

Future<_FakeService> _pump(WidgetTester tester,
    {required String initialRoute,
    DongleConnectionState state = DongleConnectionState.idle}) async {
  final service = _FakeService(state);
  await tester.pumpWidget(ProviderScope(
    overrides: [bluetoothServiceProvider.overrideWithValue(service)],
    child: MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      initialRoute: initialRoute,
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) =>
            settings.name == '/dashboard' ? const _Main() : _connectionScreen(),
      ),
    ),
  ));
  await tester.pump();
  return service;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(_delay);
  await tester.pump(const Duration(milliseconds: 100));
  // Fixed pumps: the "connecting" spinner never settles.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await const RememberedDeviceRepository()
        .remember(address: 'C0:02:4D:BA:00:16', fingerprint: _fp);
  });

  testWidgets(
      'auto-connect from the Connect screen (opened from main) returns to main',
      (tester) async {
    final service = await _pump(tester, initialRoute: '/dashboard');
    await _settle(tester);
    // The hidden root copy under /dashboard did not connect on its own.
    expect(service.connected, isEmpty);

    await tester.tap(find.text('MAIN SCREEN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ConnectionScreen), findsOneWidget);

    await _settle(tester);
    expect(service.connected, ['E0:07:D3:FD:00:5A']);
    expect(find.text('MAIN SCREEN'), findsOneWidget);
    expect(find.byType(ConnectionScreen), findsNothing);
  });

  testWidgets('auto-connect on a stand-alone Connect screen opens main',
      (tester) async {
    final service = await _pump(tester, initialRoute: '/');
    expect(find.byType(ConnectionScreen), findsOneWidget);
    await _settle(tester);
    expect(service.connected, ['E0:07:D3:FD:00:5A']);
    expect(find.text('MAIN SCREEN'), findsOneWidget);
    expect(find.byType(ConnectionScreen), findsNothing);
  });

  testWidgets(
      'startup auto-connect already connecting: no second connect, '
      'main screen once it connects', (tester) async {
    final service = await _pump(tester,
        initialRoute: '/', state: DongleConnectionState.connecting);
    await _settle(tester);
    expect(service.connected, isEmpty);
    expect(find.byType(ConnectionScreen), findsOneWidget);

    service.emit(DongleConnectionState.connected);
    await _settle(tester);
    expect(find.text('MAIN SCREEN'), findsOneWidget);
    expect(find.byType(ConnectionScreen), findsNothing);
  });

  testWidgets('opening Connect while already connected stays there',
      (tester) async {
    final service = await _pump(tester,
        initialRoute: '/', state: DongleConnectionState.connected);
    await _settle(tester);
    expect(service.connected, isEmpty);
    expect(find.byType(ConnectionScreen), findsOneWidget);
  });
}

import 'package:arcdash/l10n/app_strings.dart';
import 'package:arcdash/models/speed_suggestions.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/calibration_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/screens/speed_calibration_screen.dart';
import 'package:arcdash/services/bluetooth_service.dart';
import 'package:arcdash/services/calibration_settings.dart';
import 'package:arcdash/services/disclaimer.dart';
import 'package:arcdash/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'calibration_session_test.dart' show FakeGps, fix;

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
  setUp(() => SharedPreferences.setMockInitialValues({Disclaimer.prefKey: 1}));

  Widget app(FakeGps gps, {bool connected = true}) => ProviderScope(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(_FakeDongleService()),
          storageServiceProvider.overrideWithValue(StorageService()),
          isConnectedProvider.overrideWithValue(connected),
          gpsSourceProvider.overrideWithValue(gps),
          calibrationSettingsProvider
              .overrideWith((ref) async => const CalibrationSettings(
                    ble: BleSpeedSettings(
                        wheelRadius: 12,
                        wheelWidth: 120,
                        wheelRatio: 70,
                        rateRatio: 4000),
                    speedPulses: 11,
                    spdPulseNum: 38050,
                    source: 'test snapshot',
                  )),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: [
            AppStrings.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: SpeedCalibrationScreen(),
        ),
      );

  testWidgets('start is disabled until the controller is connected',
      (tester) async {
    await tester.pumpWidget(app(FakeGps(), connected: false));
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('calibration-start')), 200);
    final button = tester
        .widget<FilledButton>(find.byKey(const ValueKey('calibration-start')));
    expect(button.onPressed, isNull);
    expect(
        find.textContaining('Connect to the controller first'), findsOneWidget);
  });

  testWidgets(
      'disclaimer → live view with separate GPS and controller speed '
      '→ results', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gps = FakeGps();
    await tester.pumpWidget(app(gps));
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('calibration-start')), 200);
    await tester.tap(find.byKey(const ValueKey('calibration-start')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calibration-disclaimer-dialog')),
        findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('calibration-disclaimer-accept')));
    await tester.pumpAndSettle();

    expect(find.text('GPS SPEED'), findsOneWidget);
    expect(find.text('Controller speed'), findsOneWidget);
    expect(find.byKey(const ValueKey('calibration-dkd-tap')), findsOneWidget);
    expect(find.text('No GPS fix'), findsOneWidget);

    gps.controller.add(fix(DateTime.now(), 47.6));
    await tester.pump();
    await tester.pump();
    expect(find.text('48'), findsOneWidget);
    expect(find.textContaining('GPS lock'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('calibration-stop')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calibration-results')), findsOneWidget);
    expect(find.text('GPS reference'), findsOneWidget);
    expect(find.text('Current settings from: test snapshot'), findsOneWidget);
    expect(await Disclaimer.calibrationNeedsAcceptance(), isFalse);
  });
}

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
import 'package:flutter/services.dart';
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

  Widget app(FakeGps gps,
          {bool connected = true, Widget? home, bool autoSave = true}) =>
      ProviderScope(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(_FakeDongleService()),
          storageServiceProvider.overrideWithValue(StorageService()),
          isConnectedProvider.overrideWithValue(connected),
          gpsSourceProvider.overrideWithValue(gps),
          // No real file IO inside fake async.
          if (!autoSave) calibrationArchiveProvider.overrideWithValue(null),
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
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: home ?? const SpeedCalibrationScreen(),
        ),
      );

  testWidgets(
      'not connected: nothing blocks, banner + dash check + saved rides '
      'visible, start asks to connect', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(FakeGps(), connected: false));
    await tester.pump();
    expect(find.byKey(const ValueKey('calibration-connect-banner')),
        findsOneWidget);
    expect(find.textContaining('Connect to the controller first'),
        findsNothing);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('calibration-recent')), 200);
    expect(find.byKey(const ValueKey('open-dash-check')), findsOneWidget);
    final button = tester
        .widget<FilledButton>(find.byKey(const ValueKey('calibration-start')));
    expect(button.onPressed, isNotNull);
    await tester.tap(find.byKey(const ValueKey('calibration-start')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('connect-needed-dialog')), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('connect-needed-dialog')), findsNothing);
    expect(find.text('GPS SPEED'), findsNothing); // did not start
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
    // No in-ride tap targets besides Stop; the checklist is display only.
    expect(find.byKey(const ValueKey('calibration-dkd-tap')), findsNothing);
    expect(find.byKey(const ValueKey('capture-checklist')), findsOneWidget);
    expect(find.text('No GPS fix'), findsOneWidget);

    gps.controller.add(fix(DateTime.now(), 47.6));
    await tester.pump();
    await tester.pump();
    expect(find.text('48'), findsOneWidget);
    expect(find.textContaining('GPS lock'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('calibration-stop')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calibration-results')), findsOneWidget);
    // Same details after stopping: live panel on top of the results.
    expect(find.byKey(const ValueKey('calibration-live-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('calibration-plain-result')),
        findsOneWidget);
    await tester.scrollUntilVisible(find.text('GPS reference'), 200,
        scrollable: find
            .descendant(
                of: find.byKey(const ValueKey('calibration-results')),
                matching: find.byType(Scrollable))
            .first);
    expect(find.text('GPS reference'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('Current settings from: test snapshot'), 200,
        scrollable: find
            .descendant(
                of: find.byKey(const ValueKey('calibration-results')),
                matching: find.byType(Scrollable))
            .first);
    expect(find.text('Current settings from: test snapshot'), findsOneWidget);
    expect(await Disclaimer.calibrationNeedsAcceptance(), isFalse);
  });

  testWidgets('back key during a ride asks first, then pops the screen',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(
        {Disclaimer.prefKey: 1, Disclaimer.calibrationPrefKey: true});
    // Answer the keep-screen-on channel like the Android activity does.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.arcdash.arcdash/service'), (_) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.arcdash.arcdash/service'), null));
    final gps = FakeGps();
    await tester.pumpWidget(app(gps,
        autoSave: false,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const SpeedCalibrationScreen())),
              child: const Text('open calibration'),
            ),
          ),
        )));
    await tester.tap(find.text('open calibration'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('calibration-start')), 200);
    await tester.tap(find.byKey(const ValueKey('calibration-start')));
    await tester.pumpAndSettle();
    expect(find.text('GPS SPEED'), findsOneWidget);

    // Hardware/system back while recording → confirm, "Keep riding" stays.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Stop calibration?'), findsOneWidget);
    await tester.tap(find.text('Keep riding'));
    await tester.pumpAndSettle();
    expect(find.text('GPS SPEED'), findsOneWidget);

    // Back again → Stop → the screen pops back to where it was opened.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Stop'));
    await tester.pumpAndSettle();
    expect(find.byType(SpeedCalibrationScreen), findsNothing);
    expect(find.text('open calibration'), findsOneWidget);
  });
}

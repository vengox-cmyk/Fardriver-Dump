import 'package:arcdash/app.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/screens/dashboard_screen.dart';
import 'package:arcdash/screens/app_shell.dart';
import 'package:arcdash/services/bluetooth_service.dart';
import 'package:arcdash/services/storage_service.dart';
import 'package:arcdash/utils/crc_calculator.dart';
import 'package:arcdash/utils/packet_parser.dart';
import 'package:arcdash/utils/unit_converter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:arcdash/widgets/brand_version_label.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:arcdash/models/app_settings.dart';
import 'package:arcdash/services/app_settings_repository.dart';
import 'package:arcdash/services/range_prediction_repository.dart';

void main() {
  testWidgets('ArcDash starts on the dashboard route', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(_FakeDongleService()),
          storageServiceProvider.overrideWithValue(StorageService()),
        ],
        child: const ArcDashApp(locale: Locale('de')),
      ),
    );

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.byType(AppShell), findsOneWidget);
  });

  testWidgets('app shell keeps primary navigation available', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(_FakeDongleService()),
          storageServiceProvider.overrideWithValue(StorageService()),
        ],
        child: const ArcDashApp(locale: Locale('de')),
      ),
    );

    await tester.tap(find.text('Fahrten'));
    await tester.pumpAndSettle();

    expect(find.text('FAHRTEN'), findsOneWidget);
    expect(find.text('Cockpit'), findsOneWidget);
    expect(find.text('Einstellungen'), findsOneWidget);
  });

  testWidgets('app defaults to English without a saved language choice',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(_FakeDongleService()),
          storageServiceProvider.overrideWithValue(StorageService()),
        ],
        child: const ArcDashApp(),
      ),
    );

    expect(find.text('Rides'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Einstellungen'), findsNothing);
  });

  testWidgets('language setting switches live and persists', (tester) async {
    final storage = _MemorySettingsStorageService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(_FakeDongleService()),
          storageServiceProvider.overrideWithValue(storage),
        ],
        child: const ArcDashApp(),
      ),
    );

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Deutsch'));
    await tester.tap(find.text('Deutsch'));
    await tester.pumpAndSettle();

    expect(find.text('Einstellungen'), findsOneWidget);
    expect(find.text('Sprache'), findsOneWidget);
    final saved = storage.appSettings.loadSettings();
    expect(saved.languageCode, 'de');
    expect(saved.languageChosen, isTrue);

    await tester.ensureVisible(find.text('English'));
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(storage.appSettings.loadSettings().languageCode, 'en');
  });

  testWidgets('saved explicit German choice is restored on launch',
      (tester) async {
    final storage = _MemorySettingsStorageService();
    storage.appSettings.saveSettings(
        const AppSettings(languageCode: 'de', languageChosen: true));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(_FakeDongleService()),
          storageServiceProvider.overrideWithValue(storage),
        ],
        child: const ArcDashApp(),
      ),
    );
    expect(find.text('Einstellungen'), findsOneWidget);
  });

  testWidgets('app shell supports optional English localization',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(_FakeDongleService()),
          storageServiceProvider.overrideWithValue(StorageService()),
        ],
        child: const ArcDashApp(locale: Locale('en')),
      ),
    );

    expect(find.text('Rides'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('CONNECT'), findsOneWidget);

    await tester.tap(find.text('CONNECT'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('CONNECT CONTROLLER'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('CONNECTION'), findsOneWidget);
  });

  testWidgets('dashboard exposes an explicit layout editor', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(_FakeDongleService()),
          storageServiceProvider.overrideWithValue(StorageService()),
        ],
        child: const ArcDashApp(locale: Locale('de')),
      ),
    );

    await tester.tap(find.byTooltip('Dashboard bearbeiten'));
    await tester.pump();

    expect(find.byTooltip('Wert hinzufügen'), findsOneWidget);
    expect(find.text('Hoch'), findsOneWidget);
    expect(find.text('Quer'), findsOneWidget);
  });

  testWidgets('dashboard renders a cockpit dial instead of text cards',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(_FakeDongleService()),
          storageServiceProvider.overrideWithValue(StorageService()),
        ],
        child: const ArcDashApp(locale: Locale('de')),
      ),
    );

    expect(find.text('FAHR-COMPUTER'), findsOneWidget);
    expect(find.byKey(const Key('speed-dial')), findsOneWidget);
    expect(find.text('Cockpit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cockpit layout renders in landscape without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(900, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(_FakeDongleService()),
          storageServiceProvider.overrideWithValue(StorageService()),
        ],
        child: const ArcDashApp(locale: Locale('de')),
      ),
    );

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary shell remains usable at 200 percent text scale',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(_FakeDongleService()),
          storageServiceProvider.overrideWithValue(StorageService()),
        ],
        child: const ArcDashApp(locale: Locale('de')),
      ),
    );

    expect(find.byType(AppShell), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(390, 844), Size(844, 390)]) {
    testWidgets('main screen shows Vengox and the runtime version ($size)',
        (tester) async {
      PackageInfo.setMockInitialValues(
        appName: 'ArcDash',
        packageName: 'com.arcdash',
        version: '1.0.188',
        buildNumber: '42',
        buildSignature: '',
      );
      BrandVersionLabel.resetCache();
      addTearDown(BrandVersionLabel.resetCache);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bluetoothServiceProvider.overrideWithValue(_FakeDongleService()),
            storageServiceProvider.overrideWithValue(StorageService()),
          ],
          child: const ArcDashApp(locale: Locale('de')),
        ),
      );
      await tester.pump();

      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.text('Vengox · v1.0.188'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('uses offline localization and glove-friendly controls',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bluetoothServiceProvider.overrideWithValue(_FakeDongleService()),
          storageServiceProvider.overrideWithValue(StorageService()),
        ],
        child: const ArcDashApp(),
      ),
    );

    final appFinder = find.byType(MaterialApp);
    final materialApp = tester.widget<MaterialApp>(appFinder);

    expect(materialApp.supportedLocales, const [Locale('de'), Locale('en')]);
    expect(materialApp.locale, const Locale('en'));
  });

  test('CRC validates generated packets and rejects mutations', () {
    final packet = List<int>.filled(16, 0);
    packet[0] = 0xAA;
    packet[1] = 0x03;
    packet[2] = 0x42;

    CrcCalculator.computeCRC(packet, packet.length);

    expect(CrcCalculator.verifyCRC(packet, packet.length), isTrue);
    packet[2] ^= 0x01;
    expect(CrcCalculator.verifyCRC(packet, packet.length), isFalse);
  });

  test('packet parser extracts a valid status packet and rejects short data',
      () {
    final packet = List<int>.filled(16, 0);
    packet[0] = 0xAA;
    packet[1] = 0x03;
    packet[2] = 0x10;
    CrcCalculator.computeCRC(packet, packet.length);

    final parsed = PacketParser.parseStatusPacket(packet);

    expect(parsed, isNotNull);
    expect(parsed!.address, 0x00);
    expect(parsed.rawData, hasLength(12));
    expect(PacketParser.parseStatusPacket(packet.sublist(0, 8)), isNull);
    expect(PacketParser.extractPackets([0x01, ...packet]), [packet]);
  });

  test('core unit conversions handle limits and zero denominators', () {
    expect(
        UnitConverter.batteryPercent(
          voltageDeciVolts: 500,
          zeroBattCoeff: 600,
          fullBattCoeff: 700,
        ),
        0);
    expect(
        UnitConverter.batteryPercent(
          voltageDeciVolts: 750,
          zeroBattCoeff: 600,
          fullBattCoeff: 700,
        ),
        100);
    expect(
        UnitConverter.estimatedRangeKm(
          batteryPercent: 50,
          battCapacityWh: 4000,
          avgConsumptionWhPerKm: 100,
        ),
        20);
    expect(
        UnitConverter.estimatedRangeKm(
          batteryPercent: 50,
          battCapacityWh: 4000,
          avgConsumptionWhPerKm: 0,
        ),
        0);
  });
}

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

class _MemorySettingsStorageService extends StorageService {
  final AppSettingsRepository _settings =
      AppSettingsRepository(storage: MemoryStorage());

  @override
  AppSettingsRepository get appSettings => _settings;
}

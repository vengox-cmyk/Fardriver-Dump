import 'package:arcdash/app.dart';
import 'package:arcdash/models/dashboard_layout.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/services/bluetooth_service.dart';
import 'package:arcdash/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('editor adds and removes catalog values', (tester) async {
    final storage = _RecordingStorage(_singleTileDashboard());
    await _pumpEditor(tester, storage);

    await tester.tap(find.byTooltip('Wert hinzufügen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Strom'));
    await tester.pump();

    expect(find.text('STROM'), findsOneWidget);
    await _selectCommand(tester, 'Strom', 'Entfernen');
    expect(find.text('STROM'), findsNothing);
  });

  testWidgets('editor moves and resizes in both dimensions', (tester) async {
    final storage = _RecordingStorage(_singleTileDashboard());
    await _pumpEditor(tester, storage);

    await _selectCommand(tester, 'Spannung', 'Nach rechts');
    await _selectCommand(tester, 'Spannung', 'Nach unten');
    await _selectCommand(tester, 'Spannung', 'Breiter');
    await _selectCommand(tester, 'Spannung', 'Höher');
    await tester.pump(const Duration(milliseconds: 400));

    final tile = storage.layout.portrait.tiles.single;
    expect((tile.column, tile.row), (1, 1));
    expect((tile.width, tile.height), (2, 2));
  });

  testWidgets('collision is rejected without persistence', (tester) async {
    final storage = _RecordingStorage(_collisionDashboard());
    await _pumpEditor(tester, storage);

    await _selectCommand(tester, 'Spannung', 'Nach rechts');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Position belegt oder außerhalb des Rasters.'),
        findsOneWidget);
    expect(storage.layout.portrait.tiles.first.column, 0);
    expect(storage.writeCount, 0);
  });

  testWidgets('discard restores even an already autosaved baseline',
      (tester) async {
    final original = _singleTileDashboard();
    final storage = _RecordingStorage(original);
    await _pumpEditor(tester, storage);

    await _selectCommand(tester, 'Spannung', 'Nach rechts');
    await tester.pump(const Duration(milliseconds: 400));
    expect(storage.layout.portrait.tiles.single.column, 1);

    await tester.tap(find.byTooltip('Änderungen verwerfen'));
    await tester.pumpAndSettle();

    expect(storage.layout, original);
    expect(find.byTooltip('Dashboard bearbeiten'), findsOneWidget);
  });

  testWidgets('closing editor flushes the latest layout immediately',
      (tester) async {
    final storage = _RecordingStorage(_singleTileDashboard());
    await _pumpEditor(tester, storage);

    await _selectCommand(tester, 'Spannung', 'Nach rechts');
    await tester.tap(find.byTooltip('Dashboard speichern'));
    await tester.pumpAndSettle();

    expect(storage.layout.portrait.tiles.single.column, 1);
    expect(find.byTooltip('Dashboard bearbeiten'), findsOneWidget);
  });

  testWidgets('copy transposes only into the other orientation',
      (tester) async {
    final original = _singleTileDashboard();
    final storage = _RecordingStorage(original);
    await _pumpEditor(tester, storage);

    await tester.tap(find.byTooltip('Ausrichtung kopieren'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(storage.layout.portrait, original.portrait);
    final copied = storage.layout.landscape.tiles.single;
    expect((copied.column, copied.row), (0, 0));
    expect(copied.metric, DashboardMetric.voltage);
  });

  testWidgets('reset and compatible display options are persisted',
      (tester) async {
    final storage = _RecordingStorage(_singleTileDashboard());
    await _pumpEditor(tester, storage);

    await _selectCommand(tester, 'Spannung', 'Kompakter Wert');
    await tester.pump(const Duration(milliseconds: 400));
    expect(
        storage.layout.portrait.tiles.single.kind, DashboardTileKind.compact);

    await tester.tap(find.byTooltip('Standardlayout'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(storage.layout.portrait.toJson(),
        DashboardLayout.defaults().portrait.toJson());
  });

  testWidgets('speed tile uses metric km/h display', (tester) async {
    final storage = _RecordingStorage(DashboardLayout.defaults());
    await _pumpEditor(tester, storage);

    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('km/h'), findsOneWidget);
  });

  testWidgets('editor remains usable on a narrow target', (tester) async {
    await _pumpEditor(
      tester,
      _RecordingStorage(_singleTileDashboard()),
      size: const Size(320, 700),
    );

    expect(find.byTooltip('Wert hinzufügen'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byTooltip('Wert hinzufügen')).height,
        greaterThanOrEqualTo(48));
  });
}

Future<void> _pumpEditor(WidgetTester tester, _RecordingStorage storage,
    {Size size = const Size(430, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      bluetoothServiceProvider.overrideWithValue(_FakeDongleService()),
      storageServiceProvider.overrideWithValue(storage),
    ],
    child: const ArcDashApp(),
  ));
  await tester.tap(find.byTooltip('Dashboard bearbeiten'));
  await tester.pump();
  expect(tester.takeException(), isNull);
}

Future<void> _selectCommand(
    WidgetTester tester, String metric, String command) async {
  await tester.tap(find.byTooltip('$metric Dashboard bearbeiten'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(command).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(command).last);
  await tester.pump();
}

DashboardLayout _singleTileDashboard() => DashboardLayout(
      portrait: const DashboardOrientationLayout(
        columns: 4,
        rows: 8,
        tiles: [
          DashboardTile(
            id: 'voltage',
            metric: DashboardMetric.voltage,
            kind: DashboardTileKind.value,
            column: 0,
            row: 0,
            width: 1,
            height: 1,
          ),
        ],
      ),
      landscape: DashboardLayout.defaults().landscape,
    );

DashboardLayout _collisionDashboard() => DashboardLayout(
      portrait: const DashboardOrientationLayout(
        columns: 4,
        rows: 8,
        tiles: [
          DashboardTile(
            id: 'voltage',
            metric: DashboardMetric.voltage,
            kind: DashboardTileKind.value,
            column: 0,
            row: 0,
            width: 1,
            height: 1,
          ),
          DashboardTile(
            id: 'current',
            metric: DashboardMetric.current,
            kind: DashboardTileKind.value,
            column: 1,
            row: 0,
            width: 1,
            height: 1,
          ),
        ],
      ),
      landscape: DashboardLayout.defaults().landscape,
    );

class _RecordingStorage extends StorageService {
  DashboardLayout layout;
  int writeCount = 0;

  _RecordingStorage(this.layout);

  @override
  DashboardLayout loadDashboardLayout() => layout;

  @override
  Future<void> saveDashboardLayout(DashboardLayout next) async {
    next.portrait.validate();
    next.landscape.validate();
    layout = next;
    writeCount++;
  }
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

import 'package:arcdash/l10n/app_strings.dart';
import 'package:arcdash/models/controller_state.dart';
import 'package:arcdash/models/dashboard_layout.dart';
import 'package:arcdash/models/telemetry_quality.dart';
import 'package:arcdash/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 8, 3, 12);

  test('measurement catalog covers every stable dashboard metric', () {
    expect(dashboardMeasurementCatalog.keys.toSet(),
        DashboardMetric.values.toSet());
  });

  for (final metric in DashboardMetric.values) {
    testWidgets('${metric.name} renders independently', (tester) async {
      final state = _stateFor(metric, now);
      await tester.pumpWidget(_app(
        metric: metric,
        state: state,
        now: now,
      ));

      expect(
          find.text(
              AppStrings(const Locale('de')).metric(metric.name).toUpperCase()),
          metric == DashboardMetric.speed ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('renderer distinguishes missing stale invalid and disconnected',
      (tester) async {
    Future<void> expectState({
      required ControllerState state,
      required bool connected,
      required String label,
    }) async {
      await tester.pumpWidget(_app(
        metric: DashboardMetric.voltage,
        state: state,
        connected: connected,
        now: now,
      ));
      expect(find.text(label), findsOneWidget);
    }

    await expectState(
      state: ControllerState(lastUpdate: now),
      connected: false,
      label: 'OFF',
    );
    await expectState(
      state: _stateWithSample(
        now: now.subtract(const Duration(seconds: 6)),
        field: ControllerTelemetry.voltage,
        value: 58,
        voltageV: 58,
      ),
      connected: true,
      label: 'Veraltet',
    );
    await expectState(
      state: _stateWithSample(
        now: now,
        field: ControllerTelemetry.voltage,
        value: 200,
        voltageV: 200,
      ),
      connected: true,
      label: 'Ungültig',
    );
    await expectState(
      state: _stateWithSample(
        now: now,
        field: ControllerTelemetry.voltage,
        value: 58,
        voltageV: 58,
      ),
      connected: false,
      label: 'OFF',
    );
  });

  testWidgets('a packet newer than the freshness tick remains fresh',
      (tester) async {
    await tester.pumpWidget(_app(
      metric: DashboardMetric.voltage,
      state: _stateWithSample(
        now: now.add(const Duration(milliseconds: 500)),
        field: ControllerTelemetry.voltage,
        value: 58,
        voltageV: 58,
      ),
      now: now,
    ));

    expect(find.text('58.0 V'), findsOneWidget);
    expect(find.text('Veraltet'), findsNothing);
  });

  testWidgets('power uses stepped drive colors and green regeneration',
      (tester) async {
    await tester.pumpWidget(_app(
      metric: DashboardMetric.power,
      state: _stateWithSample(
        now: now,
        field: ControllerTelemetry.power,
        value: 16,
        powerKw: 16,
      ),
      now: now,
    ));
    var indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.valueColor!.value, const Color(0xFFFF5470));

    await tester.pumpWidget(_app(
      metric: DashboardMetric.power,
      state: _stateWithSample(
        now: now,
        field: ControllerTelemetry.power,
        value: -5,
        powerKw: -5,
      ),
      now: now,
    ));
    indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(find.text('REKUPERATION'), findsOneWidget);
    expect(indicator.valueColor!.value, const Color(0xFF54E39E));
  });

  testWidgets('unknown gear profile and temperatures never render defaults',
      (tester) async {
    for (final metric in [
      DashboardMetric.gear,
      DashboardMetric.profile,
      DashboardMetric.motorTemperature,
      DashboardMetric.controllerTemperature,
    ]) {
      await tester.pumpWidget(_app(
        metric: metric,
        state: ControllerState(lastUpdate: now),
        now: now,
      ));
      expect(find.text('Fehlt'), findsOneWidget);
      expect(find.text('0 °C'), findsNothing);
      expect(find.text('TRAIL'), findsNothing);
      expect(find.text('N'), findsNothing);
    }
  });

  testWidgets('an empty validated layout removes every catalog value',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: DashboardRenderer(
        layout: const DashboardOrientationLayout(
          columns: 4,
          rows: 4,
          tiles: [],
        ),
        state: ControllerState(lastUpdate: now),
        connected: true,
        now: now,
      ),
    ));

    for (final metric in DashboardMetric.values) {
      expect(find.text(AppStrings(const Locale('de')).metric(metric.name)),
          findsNothing);
    }
    expect(tester.takeException(), isNull);
  });
}

Widget _app({
  required DashboardMetric metric,
  required ControllerState state,
  required DateTime now,
  bool connected = true,
}) {
  final definition = dashboardMeasurementCatalog[metric]!;
  final layout = DashboardOrientationLayout(
    columns: 4,
    rows: 4,
    tiles: [
      DashboardTile(
        id: metric.name,
        metric: metric,
        kind: definition.kind,
        column: 0,
        row: 0,
        width: 4,
        height: 4,
      ),
    ],
  );
  return MaterialApp(
    locale: const Locale('de'),
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStrings.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    home: Scaffold(
      body: SizedBox(
        width: 430,
        height: 800,
        child: DashboardRenderer(
          layout: layout,
          state: state,
          connected: connected,
          now: now,
        ),
      ),
    ),
  );
}

ControllerState _stateFor(DashboardMetric metric, DateTime now) {
  final field = switch (metric) {
    DashboardMetric.speed => ControllerTelemetry.speed,
    DashboardMetric.power ||
    DashboardMetric.regeneration =>
      ControllerTelemetry.power,
    DashboardMetric.voltage => ControllerTelemetry.voltage,
    DashboardMetric.current => ControllerTelemetry.current,
    DashboardMetric.soc => ControllerTelemetry.soc,
    DashboardMetric.range => ControllerTelemetry.range,
    DashboardMetric.profile => ControllerTelemetry.profile,
    DashboardMetric.gear => ControllerTelemetry.gear,
    DashboardMetric.motorTemperature => ControllerTelemetry.motorTemperature,
    DashboardMetric.controllerTemperature =>
      ControllerTelemetry.controllerTemperature,
    DashboardMetric.errors => ControllerTelemetry.errors,
    DashboardMetric.connection || DashboardMetric.trip => null,
  };
  final power = metric == DashboardMetric.regeneration ? -4.2 : 4.2;
  final sampleValue = switch (metric) {
    DashboardMetric.speed => 32,
    DashboardMetric.power || DashboardMetric.regeneration => power,
    DashboardMetric.voltage => 58.4,
    DashboardMetric.current => -7.5,
    DashboardMetric.soc => 73,
    DashboardMetric.range => 42,
    DashboardMetric.profile => RideMode.sport.index,
    DashboardMetric.gear => 2,
    DashboardMetric.motorTemperature => 61,
    DashboardMetric.controllerTemperature => 54,
    DashboardMetric.errors => 1,
    DashboardMetric.connection || DashboardMetric.trip => 1,
  };
  return ControllerState(
    lastUpdate: now,
    speedKph: 32,
    powerKw: power,
    voltageV: 58.4,
    currentA: -7.5,
    battCapPercent: 73,
    rangeKm: 42,
    rangeUncertaintyKm: 6,
    rideMode: RideMode.sport,
    gear: 2,
    motorTempC: 61,
    controllerTempC: 54,
    motorHallError: true,
    telemetrySamples: field == null
        ? const {}
        : {
            field: TelemetrySample(
              value: sampleValue.toDouble(),
              source: TelemetrySource.controller,
              capturedAt: now,
            ),
          },
  );
}

ControllerState _stateWithSample({
  required DateTime now,
  required ControllerTelemetry field,
  required double value,
  double voltageV = 0,
  double powerKw = 0,
}) =>
    ControllerState(
      lastUpdate: now,
      voltageV: voltageV,
      powerKw: powerKw,
      telemetrySamples: {
        field: TelemetrySample(
          value: value,
          source: TelemetrySource.controller,
          capturedAt: now,
        ),
      },
    );

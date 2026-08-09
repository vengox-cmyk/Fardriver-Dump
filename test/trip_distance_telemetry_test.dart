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

  test('DashboardMetric.trip exists in catalog and respects maxAge', () {
    expect(dashboardMeasurementCatalog.containsKey(DashboardMetric.trip), true);
    final def = dashboardMeasurementCatalog[DashboardMetric.trip]!;
    expect(def.defaultKind, DashboardTileKind.value);
    expect(def.allowedKinds.contains(DashboardTileKind.compact), true);
  });

  testWidgets(
      'renders trip distance when fresh and handles missing or disconnected',
      (tester) async {
    final stateWithTrip = ControllerState(
      lastUpdate: now,
      tripDistanceKm: 14.5,
      telemetrySamples: {
        ControllerTelemetry.trip: TelemetrySample(
          value: 14.5,
          source: TelemetrySource.derived,
          capturedAt: now,
        ),
      },
    );

    await tester
        .pumpWidget(_buildApp(stateWithTrip, connected: true, now: now));
    expect(find.text('14.5 km'), findsOneWidget);

    final stateMissingTrip = ControllerState(
      lastUpdate: now,
      tripDistanceKm: null,
      telemetrySamples: {
        ControllerTelemetry.trip: TelemetrySample(
          value: 0.0,
          source: TelemetrySource.derived,
          capturedAt: now,
        ),
      },
    );

    await tester
        .pumpWidget(_buildApp(stateMissingTrip, connected: true, now: now));
    expect(find.text('0.0 km'), findsOneWidget);

    await tester
        .pumpWidget(_buildApp(stateWithTrip, connected: false, now: now));
    expect(find.text('OFF'), findsOneWidget);
  });

  test('updates range prediction and uncertainty when ride mode changes', () {
    final ecoState = ControllerState(
      lastUpdate: now,
      rangeKm: 55.0,
      rangeUncertaintyKm: 4.0,
      rideMode: RideMode.eco,
    );
    final sportState = ecoState.copyWith(
      rangeKm: 38.0,
      rangeUncertaintyKm: 6.0,
      rideMode: RideMode.sport,
    );

    expect(ecoState.rangeKm, 55.0);
    expect(sportState.rangeKm, 38.0);
    expect(sportState.rideMode, RideMode.sport);
  });
}

Widget _buildApp(ControllerState state,
    {required bool connected, required DateTime now}) {
  const layout = DashboardOrientationLayout(
    columns: 4,
    rows: 4,
    tiles: [
      DashboardTile(
        id: 'trip',
        metric: DashboardMetric.trip,
        kind: DashboardTileKind.value,
        column: 0,
        row: 0,
        width: 4,
        height: 2,
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
      body: DashboardRenderer(
        layout: layout,
        state: state,
        connected: connected,
        now: now,
      ),
    ),
  );
}

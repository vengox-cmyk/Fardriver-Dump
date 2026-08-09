import 'package:flutter_test/flutter_test.dart';
import 'package:arcdash/domain/navigation/navigation_interfaces.dart';

void main() {
  group('Navigation Domain Models & Interfaces', () {
    test('GeoLatLng represents coordinates correctly', () {
      final loc = const GeoLatLng(latitude: 51.5074, longitude: -0.1278);
      expect(loc.latitude, equals(51.5074));
      expect(loc.longitude, equals(-0.1278));
    });

    test('RouteSegment calculates distance and elevation delta', () {
      final seg = const RouteSegment(
        start: GeoLatLng(latitude: 50.0, longitude: 10.0),
        end: GeoLatLng(latitude: 50.1, longitude: 10.1),
        distanceMeters: 12500.0,
        startElevationMeters: 200.0,
        endElevationMeters: 350.0,
        surfaceType: 'unpaved',
      );

      expect(seg.distanceMeters, equals(12500.0));
      expect(seg.elevationGainMeters, equals(150.0));
      expect(seg.surfaceType, equals('unpaved'));
    });

    test('EnergyProfile estimation returns valid consumption and end SOC', () {
      final profile = const EnergyProfile(
        baseConsumptionWhPerKm: 25.0,
        elevationGainWhPerMeter: 0.15,
        elevationLossRegenWhPerMeter: 0.05,
      );

      // 10 km route with 200 m climb and 50 m descent
      final seg = const RouteSegment(
        start: GeoLatLng(latitude: 50.0, longitude: 10.0),
        end: GeoLatLng(latitude: 50.1, longitude: 10.1),
        distanceMeters: 10000.0,
        startElevationMeters: 100.0,
        endElevationMeters: 250.0, // gain: 150m
      );

      final energy = profile.calculateEnergyNeed(
        segment: seg,
        currentBatteryCapacityWh: 1000.0,
        currentSocPercent: 80.0, // 800 Wh remaining
      );

      // Base: 10 km * 25 Wh/km = 250 Wh
      // Elevation gain: 150 m * 0.15 Wh/m = 22.5 Wh
      // Total: 272.5 Wh
      expect(energy.requiredEnergyWh, closeTo(272.5, 0.01));
      // Remaining: 800 - 272.5 = 527.5 Wh -> 52.75%
      expect(energy.estimatedEndSocPercent, closeTo(52.75, 0.01));
    });

    test('FakeRoutingService returns route with mock segments and elevation',
        () async {
      final FakeRoutingService router = FakeRoutingService();
      final route = await router.calculateRoute(
        origin: const GeoLatLng(latitude: 50.0, longitude: 10.0),
        destination: const GeoLatLng(latitude: 50.1, longitude: 10.1),
        preference: RoutingPreference.avoidHighways,
      );

      expect(route.segments, isNotEmpty);
      expect(route.totalDistanceMeters, greaterThan(0));
      expect(route.preference, equals(RoutingPreference.avoidHighways));
    });

    test('FakeElevationService supplies elevation for coordinates', () async {
      final FakeElevationService elevationService = FakeElevationService();
      final elev = await elevationService.getElevation(
        const GeoLatLng(latitude: 50.0, longitude: 10.0),
      );

      expect(elev, isNotNull);
    });
  });
}

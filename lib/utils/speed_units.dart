/// Display unit for speed and distance. Everything FarSure stores or
/// exports (CSV, rides, calibration files) stays metric; this only changes
/// what the rider sees.
enum SpeedUnit {
  kmh('km/h', 'km', 1.0),
  mph('mph', 'mi', 1 / kmPerMile);

  const SpeedUnit(this.speedLabel, this.distanceLabel, this._perKm);

  /// International mile.
  static const double kmPerMile = 1.609344;

  final String speedLabel;
  final String distanceLabel;
  final double _perKm;

  /// Stable key for settings JSON.
  String get key => name;

  static SpeedUnit fromKey(Object? value) =>
      value == 'mph' ? SpeedUnit.mph : SpeedUnit.kmh;

  /// km/h → this unit.
  double fromKph(double kph) => kph * _perKm;

  /// This unit → km/h (e.g. a DKD reading typed in mph).
  double toKph(double value) => value / _perKm;

  /// km → this unit's distance (km or miles).
  double fromKm(double km) => km * _perKm;

  /// Energy per distance: Wh/km → Wh/km or Wh/mi.
  double whPerDistanceFromWhPerKm(double whPerKm) => whPerKm / _perKm;

  String get energyPerDistanceLabel => 'Wh/$distanceLabel';

  String speed(double kph, {int digits = 0}) =>
      '${fromKph(kph).toStringAsFixed(digits)} $speedLabel';

  String distance(double km, {int digits = 1}) =>
      '${fromKm(km).toStringAsFixed(digits)} $distanceLabel';
}

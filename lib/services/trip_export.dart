import 'package:arcdash/utils/speed_units.dart';

/// Readable trip JSON for sharing: local date/time, duration as h:mm:ss and
/// every number in the rider's unit (km/h or mph), rounded. The stored ride
/// keeps metric; this is only what leaves the app as text.
Map<String, dynamic> readableTripJson(
    Map<String, dynamic> session, SpeedUnit unit) {
  double n(String k) => (session[k] as num?)?.toDouble() ?? 0.0;
  String time(String k) {
    final t = DateTime.tryParse(session[k] as String? ?? '')?.toLocal();
    if (t == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  final secs = n('durationSeconds').round();
  final dur = '${secs ~/ 3600}:${((secs % 3600) ~/ 60).toString().padLeft(2, '0')}'
      ':${(secs % 60).toString().padLeft(2, '0')}';
  final km = n('distanceKm');
  final wh = n('totalWhUsed');
  final dist = unit == SpeedUnit.kmh ? km : km * 0.621371;
  final distLabel = unit == SpeedUnit.kmh ? 'km' : 'mi';
  final speedLabel = unit.speedLabel;
  double r(double v, int d) => double.parse(v.toStringAsFixed(d));
  return {
    'format': 'farsure-trip-v1',
    'units': {'speed': speedLabel, 'distance': distLabel, 'energy': 'Wh'},
    'start': time('startTime'),
    if (session['endTime'] != null) 'end': time('endTime'),
    'duration': dur,
    'distance': r(dist, 2),
    'topSpeed': r(unit.fromKph(n('maxSpeedKph')), 1),
    'averageSpeed': r(unit.fromKph(n('avgSpeedKph')), 1),
    'energyWh': r(wh, 1),
    'efficiency': dist > 0.05 ? r(wh / dist, 1) : null,
    'efficiencyUnit': 'Wh/$distLabel',
    if (session['id'] != null) 'id': session['id'],
  };
}

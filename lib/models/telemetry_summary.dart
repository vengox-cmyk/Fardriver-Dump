import 'package:arcdash/utils/speed_units.dart';

/// One speed band of the ~10 Hz telemetry: averages of rpm, line current,
/// voltage sag and temperatures while riding in that band.
class SpeedBand {
  final double fromKph;
  final double toKph;
  final int samples;
  final double rpm;
  final double currentA;
  final double sagV;
  final double motorC;
  final double controllerC;
  const SpeedBand(this.fromKph, this.toKph, this.samples, this.rpm,
      this.currentA, this.sagV, this.motorC, this.controllerC);
}

/// Ride summary by speed from the telemetry CSV. Sag is measured against the
/// highest voltage seen at low current (< 3 A), i.e. the resting pack.
class TelemetrySummary {
  final int samples;
  final double restV;
  final List<SpeedBand> bands;
  const TelemetrySummary(this.samples, this.restV, this.bands);

  /// Bands are [bandKph] wide in the rider's unit (10 km/h or 10 mph).
  static TelemetrySummary? fromCsv(String text, SpeedUnit unit,
      {double band = 10}) {
    final lines = text.split(RegExp(r'\r?\n'));
    if (lines.length < 2) return null;
    final head = lines.first.split(',');
    int col(String n) => head.indexOf(n);
    final iS = col('Speed (km/h)'), iR = col('RPM'), iV = col('Voltage (V)');
    final iA = col('Line current (A)'), iM = col('Motor (°C)');
    final iC = col('Controller (°C)');
    if ([iS, iR, iV, iA, iM, iC].any((i) => i < 0)) return null;
    final rows = <List<double>>[];
    for (final l in lines.skip(1)) {
      final p = l.split(',');
      if (p.length < head.length) continue;
      final v = [iS, iR, iV, iA, iM, iC].map((i) => double.tryParse(p[i]));
      if (v.any((x) => x == null)) continue;
      rows.add(v.map((x) => x!).toList());
    }
    if (rows.isEmpty) return null;
    var rest = 0.0;
    for (final r in rows) {
      if (r[3].abs() < 3 && r[2] > rest) rest = r[2];
    }
    if (rest == 0) rest = rows.map((r) => r[2]).reduce((a, b) => a > b ? a : b);
    final perKph = unit.fromKph(1);
    final bins = <int, List<List<double>>>{};
    for (final r in rows) {
      if (r[0] < 1) continue; // stopped
      bins.putIfAbsent((r[0] * perKph / band).floor(), () => []).add(r);
    }
    final keys = bins.keys.toList()..sort();
    double avg(List<List<double>> b, int i) =>
        b.map((r) => r[i]).reduce((a, c) => a + c) / b.length;
    return TelemetrySummary(rows.length, rest, [
      for (final k in keys)
        SpeedBand(
          k * band / perKph,
          (k + 1) * band / perKph,
          bins[k]!.length,
          avg(bins[k]!, 1),
          avg(bins[k]!, 3),
          rest - avg(bins[k]!, 2),
          avg(bins[k]!, 4),
          avg(bins[k]!, 5),
        ),
    ]);
  }

  /// "20–30 mph: 2950 rpm, 41 A, sag 3.2 V, motor 48 °C, ctrl 39 °C".
  List<String> lines(SpeedUnit unit) => [
        for (final b in bands)
          '${unit.fromKph(b.fromKph).round()}–${unit.fromKph(b.toKph).round()} '
              '${unit.speedLabel}: ${b.rpm.round()} rpm, '
              '${b.currentA.toStringAsFixed(0)} A, '
              'sag ${b.sagV.toStringAsFixed(1)} V, '
              'motor ${b.motorC.toStringAsFixed(0)} °C, '
              'ctrl ${b.controllerC.toStringAsFixed(0)} °C',
      ];
}

import 'package:arcdash/models/telemetry_summary.dart';
import 'package:arcdash/services/ride_archive.dart';
import 'package:arcdash/services/trip_export.dart';
import 'package:arcdash/utils/speed_units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('telemetry summary bins by speed with sag vs rest', () {
    final head = RideRecorder.telemetryHeader.join(',');
    String row(double s, int rpm, double v, double a) => [
          't',
          '0',
          '$s',
          '$rpm',
          '$v',
          '$a',
          '0',
          '0',
          '40',
          '35',
          '0',
          '0',
          '0',
          '',
          ''
        ].join(',');
    final csv = [
      head,
      row(0, 0, 90.0, 0.5),
      row(15, 1500, 88.0, 20),
      row(25, 2500, 86.0, 40),
      row(27, 2700, 85.0, 50),
    ].join('\r\n');
    final s = TelemetrySummary.fromCsv(csv, SpeedUnit.kmh)!;
    expect(s.restV, 90.0);
    expect(s.bands, hasLength(2));
    expect(s.bands[1].rpm, 2600);
    expect(s.bands[1].sagV, closeTo(4.5, 1e-9));
    expect(s.lines(SpeedUnit.kmh).first, startsWith('10–20 km/h'));
  });

  test('trip export JSON is readable and in user units', () {
    final j = readableTripJson({
      'startTime': '2026-11-02T10:00:00.000',
      'distanceKm': 16.0934,
      'maxSpeedKph': 80.4672,
      'avgSpeedKph': 40.2336,
      'totalWhUsed': 500.0,
      'durationSeconds': 3725,
    }, SpeedUnit.mph);
    expect(j['duration'], '1:02:05');
    expect(j['distance'], closeTo(10.0, 0.01));
    expect(j['topSpeed'], closeTo(50.0, 0.1));
    expect(j['units']['speed'], 'mph');
    expect(j['start'], '2026-11-02 10:00:00');
  });

  test('telemetry file names', () {
    final t = DateTime.fromMillisecondsSinceEpoch(1000);
    expect(RideArchive.telemetryFileName(t), 'arcdash_ride_1000_telemetry.csv');
    expect(
        RideArchive.isTelemetryFile('arcdash_ride_1000_telemetry.csv'), isTrue);
  });
}

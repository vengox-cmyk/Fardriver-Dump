import 'dart:convert';

import 'package:arcdash/models/ride_stats.dart';

/// Permanent summary of one ride (`farsure/ride_records/ride_<stamp>.json`).
///
/// A few hundred bytes of JSON, so the Rides list can read every record
/// from its file head without parsing anything big. Per-second samples live
/// in the ride CSV ([csvFile]); the controller settings in force live in the
/// parameter dump [settingsDump] (both in their own Saved files folders).
/// All values are metric; the UI converts for display.
class RideRecord {
  static const format = 'farsure-ride-v1';

  final String id;
  final DateTime start;
  final DateTime end;
  final double distanceKm;
  final double maxSpeedKph;
  final double avgSpeedKph;
  final double whUsed;

  /// Telemetry peaks (null when that value was never received).
  final double? maxLineA;
  final double? maxPhaseA;
  final double? minV;
  final double? maxV;
  final double? maxSagV;
  final double? maxMotorC;
  final double? maxControllerC;
  final double? avgPowerW;
  final double? peakPowerW;
  final double boostSeconds;
  final Map<String, double> gearSeconds;

  /// File name of the parameter dump in force at ride start (newest saved
  /// dump not later than the start), or null when none was saved yet.
  final String? settingsDump;

  /// File name of the per-second ride CSV, when it was written.
  final String? csvFile;
  final String controllerId;
  final String appVersion;

  const RideRecord({
    required this.id,
    required this.start,
    required this.end,
    required this.distanceKm,
    required this.maxSpeedKph,
    required this.avgSpeedKph,
    required this.whUsed,
    this.maxLineA,
    this.maxPhaseA,
    this.minV,
    this.maxV,
    this.maxSagV,
    this.maxMotorC,
    this.maxControllerC,
    this.avgPowerW,
    this.peakPowerW,
    this.boostSeconds = 0,
    this.gearSeconds = const {},
    this.settingsDump,
    this.csvFile,
    this.controllerId = '',
    this.appVersion = '',
  });

  Duration get duration => end.difference(start);

  /// Wh per km, null for rides too short to say.
  double? get whPerKm =>
      distanceKm >= 0.1 && whUsed > 0 ? whUsed / distanceKm : null;

  /// Sag as a fraction of the highest voltage seen (e.g. 0.08 = 8 %).
  double? get sagFraction =>
      (maxSagV == null || maxV == null || maxV! <= 0) ? null : maxSagV! / maxV!;

  factory RideRecord.fromSession(
    RideSession s, {
    String? settingsDump,
    String? csvFile,
    String controllerId = '',
    String appVersion = '',
  }) {
    final t = s.telemetry;
    final hasV = t.minV != null;
    double? pos(double v) => v > 0 ? v : null;
    return RideRecord(
      id: s.id,
      start: s.startTime,
      end: s.endTime ?? DateTime.now(),
      distanceKm: s.distanceKm,
      maxSpeedKph: s.maxSpeedKph,
      avgSpeedKph: s.avgSpeedKph,
      whUsed: s.totalWhUsed,
      maxLineA: pos(t.maxLineA),
      maxPhaseA: pos(t.maxPhaseA),
      minV: t.minV,
      maxV: t.maxV,
      maxSagV: hasV ? t.maxSagV : null,
      maxMotorC: pos(t.maxMotorC),
      maxControllerC: pos(t.maxControllerC),
      avgPowerW: t.avgPowerW,
      peakPowerW: pos(t.peakPowerW),
      boostSeconds: t.boostSeconds,
      gearSeconds: Map.of(t.gearSeconds),
      settingsDump: settingsDump,
      csvFile: csvFile,
      controllerId: controllerId,
      appVersion: appVersion,
    );
  }

  Map<String, dynamic> toJson() => {
        'format': format,
        'id': id,
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
        'durationSeconds': duration.inSeconds,
        'distanceKm': _r(distanceKm, 3),
        'maxSpeedKph': _r(maxSpeedKph, 1),
        'avgSpeedKph': _r(avgSpeedKph, 1),
        'whUsed': _r(whUsed, 1),
        'maxLineA': _o(maxLineA),
        'maxPhaseA': _o(maxPhaseA),
        'minV': _o(minV),
        'maxV': _o(maxV),
        'maxSagV': _o(maxSagV),
        'maxMotorC': _o(maxMotorC),
        'maxControllerC': _o(maxControllerC),
        'avgPowerW': _o(avgPowerW),
        'peakPowerW': _o(peakPowerW),
        'boostSeconds': _r(boostSeconds, 0),
        'gearSeconds': {
          for (final e in gearSeconds.entries) e.key: _r(e.value, 0)
        },
        'settingsDump': settingsDump,
        'csvFile': csvFile,
        'controllerId': controllerId,
        'appVersion': appVersion,
      };

  String encode() => const JsonEncoder.withIndent(' ').convert(toJson());

  /// Throws [FormatException] for anything that is not a ride record.
  factory RideRecord.decode(String text) {
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic> || json['format'] != format) {
      throw const FormatException('Not a FarSure ride record');
    }
    return RideRecord.fromJson(json);
  }

  factory RideRecord.fromJson(Map<String, dynamic> j) {
    double d(String k) => (j[k] as num?)?.toDouble() ?? 0;
    double? n(String k) => (j[k] as num?)?.toDouble();
    final start = DateTime.parse(j['start'] as String).toLocal();
    final end = DateTime.tryParse(j['end'] as String? ?? '')?.toLocal() ??
        start.add(
            Duration(seconds: (j['durationSeconds'] as num?)?.toInt() ?? 0));
    final gears = j['gearSeconds'];
    return RideRecord(
      id: j['id']?.toString() ?? start.millisecondsSinceEpoch.toString(),
      start: start,
      end: end,
      distanceKm: d('distanceKm'),
      maxSpeedKph: d('maxSpeedKph'),
      avgSpeedKph: d('avgSpeedKph'),
      whUsed: d('whUsed'),
      maxLineA: n('maxLineA'),
      maxPhaseA: n('maxPhaseA'),
      minV: n('minV'),
      maxV: n('maxV'),
      maxSagV: n('maxSagV'),
      maxMotorC: n('maxMotorC'),
      maxControllerC: n('maxControllerC'),
      avgPowerW: n('avgPowerW'),
      peakPowerW: n('peakPowerW'),
      boostSeconds: d('boostSeconds'),
      gearSeconds: gears is Map
          ? {
              for (final e in gears.entries)
                if (e.value is num) '${e.key}': (e.value as num).toDouble()
            }
          : const {},
      settingsDump: j['settingsDump'] as String?,
      csvFile: j['csvFile'] as String?,
      controllerId: j['controllerId']?.toString() ?? '',
      appVersion: j['appVersion']?.toString() ?? '',
    );
  }

  static double _r(double v, int digits) =>
      double.parse(v.toStringAsFixed(digits));
  static double? _o(double? v) => v == null ? null : _r(v, 1);
}

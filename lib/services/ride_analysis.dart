import 'package:arcdash/models/fardriver_param_catalog.dart';
import 'package:arcdash/models/ride_record.dart';
import 'package:arcdash/services/dump_archive.dart';
import 'package:arcdash/services/parameter_csv.dart';
import 'package:arcdash/services/parameter_dump.dart';
import 'package:arcdash/utils/speed_units.dart';

/// Offline, deterministic ride analysis for the Rides tab: settings
/// snapshot choice, config diff vs the previous ride, telemetry callouts and
/// a rule-based summary. Nothing here talks to the network or writes to the
/// controller; the "Copy for AI" text is only put on the clipboard.
class RideAnalysis {
  const RideAnalysis._();

  /// A dump saved this long after the ride start still counts as the
  /// settings of that ride (the live dump is read right after connecting,
  /// which can be a little after the wheel starts turning).
  static const snapshotGrace = Duration(minutes: 2);

  /// Picks the settings snapshot for a ride starting at [rideStart] from
  /// saved dumps given as (time, source, fileName): the newest dump not
  /// later than start + [snapshotGrace]. Live captures win over imported
  /// .heb/.csv files at the same time. Null when none qualifies.
  static String? pickSnapshot(
    Iterable<({DateTime time, String source, String name})> dumps,
    DateTime rideStart,
  ) {
    final limit = rideStart.add(snapshotGrace);
    ({DateTime time, String source, String name})? best;
    for (final d in dumps) {
      if (d.time.isAfter(limit)) continue;
      if (best == null ||
          d.time.isAfter(best.time) ||
          (d.time == best.time && _isLive(d.source) && !_isLive(best.source))) {
        best = d;
      }
    }
    return best?.name;
  }

  static bool _isLive(String source) =>
      !(source.startsWith('heb:') || source.startsWith('csv:'));

  /// Settings that differ between [previous] and [current], skipping the
  /// controller clock, save counter and riding counters
  /// ([LiveDumpArchiver.isVolatile]) and overlay rows. Placeholder
  /// (`unk*`) fields are counted in [ConfigDiff.unidentifiedChanged] but
  /// not listed.
  static ConfigDiff configDiff(ParameterDump previous, ParameterDump current) {
    final changes = <ConfigChange>[];
    var unidentified = 0;
    for (final e in ParameterDiff.compare(previous, current)) {
      if (e.def.overlay || LiveDumpArchiver.isVolatile(e.def)) continue;
      if (e.change != ParameterChange.changed) continue;
      if (e.def.unidentified) {
        unidentified++;
        continue;
      }
      changes.add(ConfigChange(e.def, e.a!, e.b!));
    }
    return ConfigDiff(changes, unidentified);
  }

  /// Telemetry differences worth pointing out (current vs previous ride).
  static List<Callout> callouts(RideRecord current, RideRecord? previous) {
    final out = <Callout>[];
    void add(CalloutKind kind, double? now, double? before) {
      if (now == null) return;
      out.add(Callout(kind, now, before));
    }

    add(
        CalloutKind.topSpeed,
        current.maxSpeedKph > 0 ? current.maxSpeedKph : null,
        previous == null || previous.maxSpeedKph <= 0
            ? null
            : previous.maxSpeedKph);
    add(CalloutKind.peakLineCurrent, current.maxLineA, previous?.maxLineA);
    add(CalloutKind.peakPhaseCurrent, current.maxPhaseA, previous?.maxPhaseA);
    add(CalloutKind.voltageSag, current.maxSagV, previous?.maxSagV);
    add(CalloutKind.motorTemp, current.maxMotorC, previous?.maxMotorC);
    add(CalloutKind.controllerTemp, current.maxControllerC,
        previous?.maxControllerC);
    add(CalloutKind.avgPower, current.avgPowerW, previous?.avgPowerW);
    return out;
  }

  /// Deterministic suggestions (plain sentences, metric values converted to
  /// [unit] where they are speeds). They are hints for the rider, never
  /// actions: nothing is written to the controller.
  static List<String> suggestions(
    RideRecord ride, {
    RideRecord? previous,
    ConfigDiff? diff,
    ParameterDump? settings,
    SpeedUnit unit = SpeedUnit.kmh,
  }) {
    final out = <String>[];
    final callouts = RideAnalysis.callouts(ride, previous);
    Callout? c(CalloutKind k) {
      for (final x in callouts) {
        if (x.kind == k) return x;
      }
      return null;
    }

    if (diff != null && diff.changes.isNotEmpty) {
      final names = diff.changes.take(3).map((e) => e.name).join(', ');
      final more =
          diff.changes.length > 3 ? ' and ${diff.changes.length - 3} more' : '';
      final effects = [
        for (final k in [
          CalloutKind.topSpeed,
          CalloutKind.peakLineCurrent,
          CalloutKind.peakPhaseCurrent,
        ])
          if (c(k)?.notable ?? false) c(k)!.describe(unit),
      ];
      out.add('Settings changed since the previous ride ($names$more).'
          '${effects.isEmpty ? ' No clear change in top speed or peak currents yet; one ride is a small sample.' : ' Since then: ${effects.join('; ')}.'}');
    }

    final maxLine = _param(settings, 'MaxLineCurr');
    if (maxLine != null && maxLine > 0 && ride.maxLineA != null) {
      final pct = ride.maxLineA! / maxLine;
      if (pct >= 0.95) {
        out.add('Line current reached ${ride.maxLineA!.toStringAsFixed(0)} A '
            'of the ${maxLine.toStringAsFixed(0)} A limit: the battery-side '
            'limit was the ceiling on this ride.');
      }
    }
    final maxPhase = _param(settings, 'MaxPhaseCurr');
    if (maxPhase != null && maxPhase > 0 && ride.maxPhaseA != null) {
      final pct = ride.maxPhaseA! / maxPhase;
      if (pct >= 0.95) {
        out.add('Phase current reached ${ride.maxPhaseA!.toStringAsFixed(0)} A '
            'of the ${maxPhase.toStringAsFixed(0)} A limit: acceleration was '
            'limited by phase current.');
      }
    }

    final sag = ride.sagFraction;
    if (sag != null && sag >= sagWarnFraction) {
      out.add('Voltage sagged ${ride.maxSagV!.toStringAsFixed(1)} V '
          '(${(sag * 100).toStringAsFixed(0)} %) under load. Check the pack '
          'charge, connectors and wiring before asking for more current.');
    }

    final motorLimit = _param(settings, 'MotorTempProtect');
    if (ride.maxMotorC != null) {
      if (motorLimit != null &&
          motorLimit > 0 &&
          ride.maxMotorC! >= motorLimit - tempMarginC) {
        out.add(
            'Motor reached ${ride.maxMotorC!.toStringAsFixed(0)} °C, within '
            '$tempMarginC °C of its ${motorLimit.toStringAsFixed(0)} °C '
            'protection: expect power cut-back on longer climbs.');
      } else if (ride.maxMotorC! >= motorHotC) {
        out.add('Motor ran hot (${ride.maxMotorC!.toStringAsFixed(0)} °C).');
      }
    }
    final mosLimit = _param(settings, 'MosTempProtect');
    if (ride.maxControllerC != null) {
      if (mosLimit != null &&
          mosLimit > 0 &&
          ride.maxControllerC! >= mosLimit - tempMarginC) {
        out.add('Controller reached ${ride.maxControllerC!.toStringAsFixed(0)} '
            '°C, within $tempMarginC °C of its '
            '${mosLimit.toStringAsFixed(0)} °C protection.');
      } else if (ride.maxControllerC! >= controllerHotC) {
        out.add('Controller ran hot '
            '(${ride.maxControllerC!.toStringAsFixed(0)} °C); check airflow '
            'and mounting.');
      }
    }

    final power = c(CalloutKind.avgPower);
    if (power != null && power.notable && (power.delta ?? 0) > 0) {
      out.add('Average power was ${power.describe(unit)} compared with the '
          'previous ride; range per charge will drop accordingly.');
    }

    if (ride.boostSeconds >= 1 && ride.duration.inSeconds > 0) {
      final share = ride.boostSeconds / ride.duration.inSeconds;
      out.add('Boost was active for ${ride.boostSeconds.toStringAsFixed(0)} s '
          '(${(share * 100).toStringAsFixed(0)} % of the ride).');
    }

    if (out.isEmpty) {
      out.add(previous == null
          ? 'First saved ride: nothing to compare with yet.'
          : 'Nothing stood out compared with the previous ride.');
    }
    return out;
  }

  static const sagWarnFraction = 0.10;
  static const tempMarginC = 10;
  static const motorHotC = 100.0;
  static const controllerHotC = 70.0;

  static double? _param(ParameterDump? dump, String name) {
    if (dump == null) return null;
    final FardriverParamDef def;
    try {
      def = FardriverParamCatalog.byName(name);
    } on Object {
      return null;
    }
    final block = dump.blocks[def.block];
    if (block == null) return null;
    return double.tryParse(FardriverDecoder.decode(def, block).value);
  }

  /// Compact text for pasting into the Grok app (or any assistant). Only
  /// copied to the clipboard by the rider; FarSure sends nothing.
  static String aiPrompt(
    RideRecord ride, {
    RideRecord? previous,
    ConfigDiff? diff,
    List<String> suggestions = const [],
    SpeedUnit unit = SpeedUnit.kmh,
  }) {
    final b = StringBuffer()
      ..writeln('FarDriver e-scooter ride log from the FarSure app. '
          'Please review it and suggest what to check or try next. '
          'Suggestions only: I change controller settings myself.')
      ..writeln()
      ..writeln('Ride ${_stamp(ride.start)}: ${_rideLine(ride, unit)}');
    if (previous != null) {
      b.writeln('Previous ride ${_stamp(previous.start)}: '
          '${_rideLine(previous, unit)}');
    }
    if (diff != null) {
      if (diff.changes.isEmpty) {
        b.writeln('Settings changes since previous ride: none'
            '${diff.unidentifiedChanged > 0 ? ' (${diff.unidentifiedChanged} unidentified fields differ)' : ''}');
      } else {
        b.writeln('Settings changes since previous ride:');
        for (final ch in diff.changes.take(25)) {
          b.writeln('- ${ch.name}: ${ch.before(unit)} -> ${ch.after(unit)}');
        }
        if (diff.changes.length > 25) {
          b.writeln('- ... ${diff.changes.length - 25} more');
        }
      }
    }
    if (suggestions.isNotEmpty) {
      b.writeln('App notes (rule-based):');
      for (final s in suggestions) {
        b.writeln('- $s');
      }
    }
    return b.toString().trimRight();
  }

  static String _rideLine(RideRecord r, SpeedUnit unit) {
    String n(double? v, String u, [int digits = 0]) =>
        v == null ? '' : '${v.toStringAsFixed(digits)} $u';
    final parts = [
      '${r.duration.inMinutes} min',
      unit.distance(r.distanceKm, digits: 2),
      'top ${unit.speed(r.maxSpeedKph, digits: 1)}',
      'avg ${unit.speed(r.avgSpeedKph, digits: 1)}',
      n(r.maxLineA, 'A line peak'),
      n(r.maxPhaseA, 'A phase peak'),
      if (r.minV != null && r.maxV != null)
        '${r.minV!.toStringAsFixed(1)}-${r.maxV!.toStringAsFixed(1)} V',
      n(r.maxSagV, 'V max sag', 1),
      n(r.maxMotorC, '°C motor max'),
      n(r.maxControllerC, '°C controller max'),
      n(r.avgPowerW, 'W avg'),
      if (r.whPerKm != null)
        '${unit.whPerDistanceFromWhPerKm(r.whPerKm!).toStringAsFixed(1)} '
            '${unit.energyPerDistanceLabel}',
      if (r.boostSeconds >= 1) 'boost ${r.boostSeconds.toStringAsFixed(0)} s',
    ];
    return parts.where((p) => p.isNotEmpty).join(', ');
  }

  static String _stamp(DateTime t) {
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} '
        '${two(l.hour)}:${two(l.minute)}';
  }

  /// "MaxLineCurr" → "Max line current" (plain names for the ride diff).
  static String plainName(FardriverParamDef def) {
    final known = _plainNames[def.name];
    if (known != null) return known;
    final words = def.displayName
        .replaceAll('_', ' ')
        .replaceAllMapped(RegExp(r'(?<=[a-z0-9])(?=[A-Z])'), (_) => ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w
            .replaceAll(RegExp(r'^Curr$'), 'current')
            .replaceAll(RegExp(r'^Temp$'), 'temperature'))
        .toList();
    if (words.isEmpty) return def.displayName;
    final first = words.first;
    return [
      first,
      ...words.skip(1).map(
          (w) => w.length > 1 && w.toUpperCase() == w ? w : w.toLowerCase()),
    ].join(' ');
  }

  static const _plainNames = {
    'MaxLineCurr': 'Max line (battery) current',
    'MaxPhaseCurr': 'Max phase current',
    'CustomMaxLineCurr': 'Boost line current',
    'CustomMaxPhaseCurr': 'Boost phase current',
    'MaxLineCurr2': 'Max line current 2',
    'MaxPhaseCurr2': 'Max phase current 2',
    'MaxSpeed': 'Max speed',
    'LmtSpeed': 'Speed limit',
    'LowSpeed': 'Low gear speed',
    'MidSpeed': 'Mid gear speed',
    'BackSpeed': 'Reverse speed',
    'MaxBackCurr': 'Max regen current',
    'StopBackCurr': 'Brake regen current',
    'LowSpeedLineCurr': 'Low gear line current',
    'MidSpeedLineCurr': 'Mid gear line current',
    'LowSpeedPhaseCurr': 'Low gear phase current',
    'MidSppedPhaseCurr': 'Mid gear phase current',
    'MotorTempProtect': 'Motor temperature protection',
    'MotorTempRestore': 'Motor temperature restore',
    'MosTempProtect': 'Controller temperature protection',
    'RatedVoltage': 'Rated voltage',
    'RatedPower': 'Rated power',
    'RatedSpeed': 'Rated speed',
    'ThrottleResponse': 'Throttle response',
    'Max_Acc': 'Throttle acceleration step',
    'Max_Dec': 'Throttle deceleration step',
    'SpdPulseNum': 'Speed pulses per turn',
    'GearConfig': 'Default gear',
  };
}

/// Settings that changed between two rides.
class ConfigDiff {
  final List<ConfigChange> changes;

  /// Placeholder fields (`unk*`) that differ; counted, not listed.
  final int unidentifiedChanged;

  const ConfigDiff(this.changes, this.unidentifiedChanged);
}

class ConfigChange {
  final FardriverParamDef def;
  final DecodedParameter a;
  final DecodedParameter b;

  const ConfigChange(this.def, this.a, this.b);

  String get name => RideAnalysis.plainName(def);
  String before(SpeedUnit unit) => a.displayIn(unit);
  String after(SpeedUnit unit) => b.displayIn(unit);
}

enum CalloutKind {
  topSpeed('Top speed', 'km/h', 3, false),
  peakLineCurrent('Peak line current', 'A', 10, false),
  peakPhaseCurrent('Peak phase current', 'A', 25, false),
  voltageSag('Max voltage sag', 'V', 2, false),
  motorTemp('Max motor temperature', '°C', 5, false),
  controllerTemp('Max controller temperature', '°C', 5, false),
  avgPower('Average power', 'W', 10, true);

  /// English label (used in the AI text); the UI uses AppText.
  final String label;
  final String unit;

  /// A change at least this big is "notable" (percent when [relative]).
  final double threshold;
  final bool relative;

  const CalloutKind(this.label, this.unit, this.threshold, this.relative);
}

/// One telemetry value of this ride with the previous ride's value.
class Callout {
  final CalloutKind kind;
  final double current;
  final double? previous;

  const Callout(this.kind, this.current, this.previous);

  double? get delta => previous == null ? null : current - previous!;

  /// Whether the change passes the kind's threshold.
  bool get notable {
    final d = delta;
    if (d == null) return false;
    if (kind.relative) {
      if (previous! <= 0) return false;
      return (d.abs() / previous!) * 100 >= kind.threshold;
    }
    return d.abs() >= kind.threshold;
  }

  String value(double v, SpeedUnit unit) => kind == CalloutKind.topSpeed
      ? unit.speed(v, digits: 1)
      : '${v.toStringAsFixed(kind == CalloutKind.voltageSag ? 1 : 0)} '
          '${kind.unit}';

  /// "Top speed +4.0 km/h (52.0 km/h)" or "Average power +12 %".
  String describe(SpeedUnit unit) {
    final d = delta;
    if (d == null) return '${kind.label} ${value(current, unit)}';
    final sign = d >= 0 ? '+' : '−';
    final String change;
    if (kind.relative && previous! > 0) {
      change = '$sign${(d.abs() / previous! * 100).toStringAsFixed(0)} %';
    } else if (kind == CalloutKind.topSpeed) {
      change = '$sign${unit.fromKph(d.abs()).toStringAsFixed(1)} '
          '${unit.speedLabel}';
    } else {
      change =
          '$sign${d.abs().toStringAsFixed(kind == CalloutKind.voltageSag ? 1 : 0)} '
          '${kind.unit}';
    }
    return '${kind.label.toLowerCase()} $change (${value(current, unit)})';
  }
}

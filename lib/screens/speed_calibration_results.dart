import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arcdash/models/gps_calibration.dart';
import 'package:arcdash/models/speed_suggestions.dart';
import 'package:arcdash/providers/calibration_provider.dart';
import 'package:arcdash/services/calibration_csv.dart';
import 'package:arcdash/services/calibration_settings.dart';
import 'package:arcdash/services/gps_calibration_session.dart';
import 'package:arcdash/services/parameter_dump_io.dart';
import 'package:arcdash/widgets/disclaimer_gate.dart';

const _green = Color(0xFF54E39E);
const _amber = Color(0xFFFFB45C);
const _red = Color(0xFFFF6B6B);

String _pct(double v, [int digits = 1]) =>
    '${v >= 0 ? '+' : ''}${(v * 100).toStringAsFixed(digits)} %';

/// Results of a stopped calibration ride: one card per speed path.
class SpeedCalibrationResults extends ConsumerWidget {
  const SpeedCalibrationResults(
      {super.key, required this.session, required this.onNewRide});

  final CalibrationSessionState session;
  final VoidCallback onNewRide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(calibrationSettingsProvider);
    final settings = settingsAsync.valueOrNull ?? CalibrationSettings.none;
    final fit = session.fit;
    return ListView(
      key: const ValueKey('calibration-results'),
      padding: const EdgeInsets.all(16),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: CalibrationSafetyLines(),
          ),
        ),
        _GpsFitCard(session: session),
        _BleCard(fit: fit, settings: settings),
        _DkdCard(session: session, settings: settings),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('Current settings from: ${settings.source}',
              style: const TextStyle(color: Colors.white60)),
        ),
        FilledButton.icon(
          key: const ValueKey('calibration-export'),
          onPressed: session.hasData ? () => _export(context, settings) : null,
          icon: const Icon(Icons.ios_share),
          label: const Text('Export ride CSV'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onNewRide,
          icon: const Icon(Icons.replay),
          label: const Text('New calibration ride'),
        ),
        const SizedBox(height: 16),
        const DisclaimerText(
            style: TextStyle(fontSize: 12, color: Colors.white60)),
      ],
    );
  }

  Future<void> _export(
      BuildContext context, CalibrationSettings settings) async {
    final version = await ParameterDumpIo.appVersion();
    final now = DateTime.now();
    final csv = CalibrationCsv.build(
      samples: session.samples,
      analysis: session.analysis,
      fit: session.fit,
      dkdSnapshots: session.dkdSnapshots,
      settings: settings,
      appVersion: version,
      exportedAt: now,
      startedAt: session.startedAt,
    );
    if (!context.mounted) return;
    final stamp = now.toIso8601String().substring(0, 19).replaceAll(':', '-');
    await ParameterDumpIo.shareOrCopy(
      context,
      text: csv,
      fileName:
          ParameterDumpIo.safeFileName('farsure_gps_calibration_$stamp.csv'),
      subject: 'FarSure GPS speed calibration',
      copiedMessage: 'Calibration CSV copied to clipboard',
    );
  }
}

class ConfidenceBadge extends StatelessWidget {
  const ConfidenceBadge(this.confidence, {super.key});

  final CalibrationConfidence confidence;

  @override
  Widget build(BuildContext context) {
    final color = switch (confidence) {
      CalibrationConfidence.green => _green,
      CalibrationConfidence.yellow => _amber,
      CalibrationConfidence.red => _red,
    };
    return Container(
      key: ValueKey('confidence-${confidence.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text('${confidence.label} confidence',
          style: TextStyle(color: color, fontWeight: FontWeight.w700)),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.badge, required this.children});

  final String title;
  final Widget? badge;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                ),
                if (badge != null) badge!,
              ]),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.emphasize = false, this.valueKey});

  final String label;
  final String value;
  final bool emphasize;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(
              child:
                  Text(label, style: const TextStyle(color: Colors.white70))),
          Text(value,
              key: valueKey,
              style: TextStyle(
                  fontWeight: emphasize ? FontWeight.w900 : FontWeight.w600,
                  fontSize: emphasize ? 18 : 14)),
        ]),
      );
}

class _GpsFitCard extends StatelessWidget {
  const _GpsFitCard({required this.session});

  final CalibrationSessionState session;

  @override
  Widget build(BuildContext context) {
    final analysis = session.analysis;
    final fit = session.fit;
    final bands = analysis.bands.toList()..sort((a, b) => a.index - b.index);
    final rejected = analysis.verdictCounts.entries
        .where((e) => e.key != SampleVerdict.kept)
        .toList()
      ..sort((a, b) => b.value - a.value);
    return _Section(
      title: 'GPS reference',
      badge: fit == null ? null : ConfidenceBadge(fit.confidence),
      children: [
        _Row('Seconds recorded', '${session.samples.length}'),
        _Row('Clean seconds',
            '${analysis.cleanSeconds} / ${CalibrationSessionState.targetCleanSeconds}'),
        _Row('Clean segments (≥5 s)', '${analysis.segments.length}'),
        _Row('Speed bands',
            bands.isEmpty ? '—' : bands.map((b) => b.label).join(', ')),
        if (fit != null) ...[
          _Row('k_gps (km/h per rpm)', fit.kGps.toStringAsFixed(6)),
          _Row(
              '95 % range',
              fit.ciRelative == null
                  ? 'needs ≥2 segments'
                  : '±${(fit.ciRelative! * 100).toStringAsFixed(2)} %'),
        ],
        if (rejected.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Rejected: ${rejected.take(4).map((e) => '${e.key.label} ${e.value}').join(', ')}',
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
        if (fit == null || fit.confidence == CalibrationConfidence.red)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Not enough clean data for a confident result. Ride more steady, '
              'straight stretches (≥6 segments in ≥2 speed bands).',
              style: TextStyle(color: _amber),
            ),
          ),
      ],
    );
  }
}

class _BleCard extends StatelessWidget {
  const _BleCard({required this.fit, required this.settings});

  final CalibrationFit? fit;
  final CalibrationSettings settings;

  @override
  Widget build(BuildContext context) {
    final ble = settings.ble;
    final f = fit;
    if (ble == null || f == null) {
      return _Section(
        title: 'FarSure / BLE speed (RateRatio)',
        children: [
          Text(ble == null
              ? 'Current wheel / RateRatio values not read yet. Take a parameter snapshot, then reopen this screen.'
              : 'No clean GPS data yet.'),
        ],
      );
    }
    final s = RateRatioSuggestion.compute(ble, f.kGps);
    return _Section(
      title: 'FarSure / BLE speed (RateRatio)',
      badge: ConfidenceBadge(f.confidence),
      children: [
        _Row('Current RateRatio',
            '${ble.rateRatio}  (GearRatio ${ble.gearRatio.toStringAsFixed(3)})'),
        _Row('Error vs GPS', _pct(s.error)),
        _Row('Suggested RateRatio', '${s.suggested}',
            emphasize: true, valueKey: const ValueKey('suggested-rate-ratio')),
        _Row('Suggested GearRatio', s.suggestedGearRatio.toStringAsFixed(3)),
        if (s.isSuspicious)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              s.clamped
                  ? 'Suggested value hit the 16-bit limit. Check wheel size settings first.'
                  : 'Change of ${_pct(s.change, 0)} is unusually large (>30 %). Check the tire size, the pulley (belt) ratio and the GPS mount before changing anything.',
              style: const TextStyle(color: _red),
            ),
          ),
        const SizedBox(height: 6),
        const Text(
          'Apply in the official FarDriver app: set RateRatio (the motor-to-wheel pulley ratio, shown there as '
          'GearRatio = RateRatio / 1000). FarSure never writes to the controller.',
          style: TextStyle(fontSize: 12, color: Colors.white70),
        ),
        const SizedBox(height: 4),
        const Text(
          'On a belt drive RateRatio normally equals the real pulley ratio; the '
          'suggested value folds in the tire\'s real rolling size, which the '
          'nominal tire fields do not capture exactly.',
          style: TextStyle(fontSize: 12, color: Colors.white60),
        ),
      ],
    );
  }
}

class _DkdCard extends ConsumerWidget {
  const _DkdCard({required this.session, required this.settings});

  final CalibrationSessionState session;
  final CalibrationSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(gpsCalibrationProvider.notifier);
    final snapshots = session.dkdSnapshots;
    final gpsFit = session.fit;
    final dkdFit = DkdFit.fromSnapshots(snapshots);
    final children = <Widget>[];
    if (snapshots.isEmpty) {
      children.add(const Text(
          'No "DKD reads…" taps in this ride. Only needed if you use a one-wire DKD display.'));
    } else {
      children.add(const Text(
          'Enter what the DKD showed at each tap (you are stopped now):',
          style: TextStyle(color: Colors.white70)));
      for (var i = 0; i < snapshots.length; i++) {
        children.add(_DkdEntry(
          key: ValueKey(
              'dkd-entry-$i-${snapshots[i].at.microsecondsSinceEpoch}'),
          index: i,
          snapshot: snapshots[i],
          onChanged: (v) => notifier.setDkdReading(i, v),
          onRemove: () => notifier.removeDkdSnapshot(i),
        ));
      }
    }
    CalibrationConfidence? badge;
    if (dkdFit != null && gpsFit != null) {
      badge = dkdFit.confidence(gpsFit);
      final error = speedError(kDisplay: dkdFit.kDkd, kGps: gpsFit.kGps);
      children.add(const Divider());
      children.add(_Row('Readings used', '${dkdFit.taps}'));
      children.add(_Row('DKD error vs GPS', _pct(error)));
      final sp = settings.speedPulses, spn = settings.spdPulseNum;
      if (sp != null && spn != null) {
        final s = DkdSuggestion.compute(
            speedPulses: sp,
            spdPulseNum: spn,
            kDkd: dkdFit.kDkd,
            kGps: gpsFit.kGps);
        children.addAll([
          _Row('Current Speed Pulses / SpdPulseNum', '$sp / $spn'),
          if (s.changesSpeedPulses)
            _Row('Suggested Speed Pulses (coarse)', '${s.suggestedSpeedPulses}',
                emphasize: true,
                valueKey: const ValueKey('suggested-speed-pulses')),
          _Row('Suggested SpdPulseNum', '${s.suggestedSpdPulseNum}',
              emphasize: true,
              valueKey: const ValueKey('suggested-spd-pulse-num')),
          if (s.clamped)
            const Text(
                'A value hit its limit (Speed Pulses 1–31, SpdPulseNum 500–65530).',
                style: TextStyle(color: _red)),
          const SizedBox(height: 6),
          const Text(
            'Larger SpdPulseNum = slower DKD reading. The exact SpdPulseNum ↔ DKD '
            'relationship is to be verified with ride data: re-ride after changing.',
            style: TextStyle(fontSize: 12, color: _amber),
          ),
          const SizedBox(height: 4),
          const Text(
            'Apply in the official FarDriver app (Speed Pulses, SpdPulseNum).',
            style: TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ]);
      } else {
        children.add(const Text(
            'Speed Pulses / SpdPulseNum not known: take a parameter snapshot to get a suggestion.',
            style: TextStyle(color: _amber)));
      }
      children.add(Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'Fallback only: on the DKD itself (settings password 153) multiply CC by '
          '${(gpsFit.kGps / dkdFit.kDkd).toStringAsFixed(4)}.',
          style: const TextStyle(fontSize: 12, color: Colors.white60),
        ),
      ));
    } else if (snapshots.isNotEmpty && gpsFit == null) {
      children.add(const Text('No clean GPS data to compare against.',
          style: TextStyle(color: _amber)));
    }
    return _Section(
      title: 'DKD display (Speed Pulses / SpdPulseNum)',
      badge: badge == null ? null : ConfidenceBadge(badge),
      children: children,
    );
  }
}

class _DkdEntry extends StatefulWidget {
  const _DkdEntry({
    super.key,
    required this.index,
    required this.snapshot,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final DkdSnapshot snapshot;
  final ValueChanged<double?> onChanged;
  final VoidCallback onRemove;

  @override
  State<_DkdEntry> createState() => _DkdEntryState();
}

class _DkdEntryState extends State<_DkdEntry> {
  late final TextEditingController _text = TextEditingController(
      text: widget.snapshot.dkdKph?.toStringAsFixed(0) ?? '');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.snapshot;
    final t = s.at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return Row(children: [
      Expanded(
        child: Text(
          '#${widget.index + 1}  ${two(t.hour)}:${two(t.minute)}:${two(t.second)}\n'
          'GPS ${s.gpsKph?.toStringAsFixed(1) ?? '--'} · ${s.rpm.toStringAsFixed(0)} rpm',
          style: const TextStyle(fontSize: 12),
        ),
      ),
      SizedBox(
        width: 96,
        child: TextField(
          key: ValueKey('dkd-input-${widget.index}'),
          controller: _text,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration:
              const InputDecoration(labelText: 'DKD km/h', isDense: true),
          onChanged: (v) =>
              widget.onChanged(double.tryParse(v.replaceAll(',', '.'))),
        ),
      ),
      IconButton(
        tooltip: 'Remove',
        onPressed: widget.onRemove,
        icon: const Icon(Icons.close),
      ),
    ]);
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arcdash/models/dash_speed.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/calibration_provider.dart';
import 'package:arcdash/providers/units_provider.dart';
import 'package:arcdash/screens/speed_calibration_screen.dart'
    show ConnectBanner;
import 'package:arcdash/services/dash_check.dart';
import 'package:arcdash/services/screen_awake.dart';

const _green = Color(0xFF54E39E);
const _amber = Color(0xFFFFB45C);
const _red = Color(0xFFFF6B6B);

/// Stationary "Dash speed check" (v1.2.3), replacing the in-ride DKD tap.
///
/// Drive wheel lifted on a stand; works only while GPS says the scooter is
/// standing still. FarSure shows live rpm and its own speed; the rider holds
/// a steady throttle, taps "Capture", lets go and types what the dash
/// showed. Every point is saved permanently (Saved files → Dash checks).
/// 2–3 points at different speeds give a suggested SpdPulseNum.
class DashSpeedCheckScreen extends ConsumerStatefulWidget {
  const DashSpeedCheckScreen(
      {super.key, this.screenAwake = const ScreenAwake()});

  final ScreenAwake screenAwake;

  @override
  ConsumerState<DashSpeedCheckScreen> createState() =>
      _DashSpeedCheckScreenState();
}

class _DashSpeedCheckScreenState extends ConsumerState<DashSpeedCheckScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.screenAwake.set(true));
    Future.microtask(() {
      if (mounted) ref.read(dashCheckProvider.notifier).begin();
    });
  }

  @override
  void dispose() {
    unawaited(widget.screenAwake.set(false));
    super.dispose();
  }

  Future<void> _capture() async {
    final notifier = ref.read(dashCheckProvider.notifier);
    if (!notifier.capture()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Not captured: needs motor RPM and GPS showing the scooter standing still.')));
      return;
    }
    final unit = ref.read(speedUnitProvider);
    final text = TextEditingController();
    final value = await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        key: const ValueKey('dash-entry-dialog'),
        title: const Text('What did the dash show?'),
        content: TextField(
          key: const ValueKey('dash-entry-input'),
          controller: text,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              labelText: 'Dash ${unit.speedLabel}',
              helperText: 'Let go of the throttle first.'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Discard')),
          FilledButton(
              key: const ValueKey('dash-entry-save'),
              onPressed: () => Navigator.of(context)
                  .pop(double.tryParse(text.text.trim().replaceAll(',', '.'))),
              child: const Text('Save')),
        ],
      ),
    );
    text.dispose();
    await notifier.enterDash(value == null ? null : unit.toKph(value));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dashCheckProvider);
    final connected = ref.watch(isConnectedProvider);
    final unit = ref.watch(speedUnitProvider);
    final now = DateTime.now();
    final still = state.stationaryAt(now);
    final gps = state.gps;
    final gpsFresh = gps != null &&
        now.difference(gps.capturedAt) <= DashCheckState.gpsMaxAge;
    final record = state.record;
    final result = record?.result;
    final anchor = record?.anchor;
    final rpm = state.rpm;
    final canCapture =
        connected && state.ready && still && rpm != null && rpm > 0;

    final (statusColor, statusText) = !state.ready
        ? (
            _amber,
            state.gpsProblem == null
                ? 'Starting GPS…'
                : 'GPS: ${state.gpsProblem!.message}'
          )
        : !gpsFresh
            ? (
                _amber,
                'Waiting for GPS… (needed to confirm you are standing still)'
              )
            : still
                ? (
                    _green,
                    'Standing still (GPS ${gps.speedKph.toStringAsFixed(1)} km/h)'
                  )
                : (_red, 'Moving — the dash check only works standing still');

    return Scaffold(
      appBar: AppBar(title: const Text('DASH SPEED CHECK')),
      body: SafeArea(
        child: ListView(
          key: const ValueKey('dash-check-list'),
          padding: const EdgeInsets.all(16),
          children: [
            if (!connected)
              const ConnectBanner(
                  message:
                      'Not connected. Connect to read live motor RPM. Saved checks stay in Saved files.'),
            const Card(
              key: ValueKey('dash-check-safety'),
              color: Color(0x33FF6B6B),
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'SAFETY: Put the scooter on a stable stand so the DRIVE wheel is '
                  'off the ground and free to spin. Keep hands, feet, clothes and '
                  'cables away from the wheel and belt/chain. Nobody near the '
                  'wheel. Brake ready, low speeds only; stop at once if the stand '
                  'moves. Never do this while riding.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text('1. Hold a steady throttle and read the dash.\n'
                '2. Tap "Capture", let go of the throttle, type the number you read.\n'
                '3. Repeat at 2–3 different speeds (e.g. 20, 40, 60 km/h).'),
            const SizedBox(height: 12),
            Text(statusText,
                key: const ValueKey('dash-check-status'),
                style:
                    TextStyle(color: statusColor, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: _Big(
                      'Motor RPM', rpm == null ? '--' : rpm.toStringAsFixed(0),
                      key: const ValueKey('dash-check-rpm'))),
              Expanded(
                  child: _Big(
                      'FarSure speed', unit.speed(state.appKph, digits: 1),
                      key: const ValueKey('dash-check-app-speed'))),
            ]),
            if (anchor != null && rpm != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Dash should show about '
                  '${unit.speed(anchor.estimateKph(rpm, sp: anchor.speedPulses, spn: anchor.spdPulseNum) ?? 0, digits: 0)} '
                  '(calibrated from your points)',
                  style: const TextStyle(fontSize: 12, color: Colors.white60),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('dash-check-capture'),
              onPressed: canCapture ? _capture : null,
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Capture RPM now'),
            ),
            const SizedBox(height: 16),
            Text('Points (${state.points.length})',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            for (final (i, p) in state.points.indexed)
              ListTile(
                key: ValueKey('dash-point-$i'),
                dense: true,
                title: Text(
                    '${p.rpm.toStringAsFixed(0)} rpm → dash ${unit.speed(p.dkdKph ?? 0, digits: 1)}'),
                subtitle:
                    Text('FarSure ${unit.speed(p.controllerKph, digits: 1)}'),
                trailing: IconButton(
                  tooltip: 'Remove point',
                  icon: const Icon(Icons.close),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Remove this point?'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.of(c).pop(false),
                              child: const Text('Keep')),
                          FilledButton(
                              onPressed: () => Navigator.of(c).pop(true),
                              child: const Text('Remove')),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await ref.read(dashCheckProvider.notifier).removePoint(i);
                    }
                  },
                ),
              ),
            const SizedBox(height: 8),
            _ResultCard(record: record, result: result),
            if (state.savedPath != null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                    'Saved: Settings → Data management → Saved files → Dash checks',
                    key: ValueKey('dash-check-saved'),
                    style: TextStyle(fontSize: 12, color: Colors.white54)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Big extends StatelessWidget {
  const _Big(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.white60)),
        Text(value,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
      ]);
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.record, required this.result});

  final DashCheckRecord? record;
  final DashCheckResult? result;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final rec = record;
    final lines = <Widget>[];
    if (r == null) {
      lines.add(const Text(
          'Capture at least 2 points (3 is better) for a suggestion.'));
    } else {
      final pct = (r.error * 100).abs().toStringAsFixed(1);
      final dir = r.error >= 0 ? 'high' : 'low';
      lines.add(Text(
        r.referenceSource == 'gps'
            ? 'Your dash reads $pct % $dir compared with GPS (from your saved calibration ride).'
            : 'Your dash reads $pct % $dir compared with FarSure\'s speed. '
                'FarSure\'s speed is only as right as its RateRatio — ride a GPS calibration first for a GPS-checked answer.',
        key: const ValueKey('dash-check-summary'),
      ));
      final s = r.suggestion;
      if (s != null) {
        lines.add(const SizedBox(height: 6));
        lines.add(Text(
          'Suggested: ${s.changesSpeedPulses ? 'Speed Pulses ${s.suggestedSpeedPulses} (now ${s.speedPulses}), ' : ''}'
          'SpdPulseNum ${s.suggestedSpdPulseNum} (now ${s.spdPulseNum}).',
          key: const ValueKey('dash-check-suggestion'),
          style: const TextStyle(fontWeight: FontWeight.w800, color: _green),
        ));
        lines.add(const Text(
          'A higher SpdPulseNum makes the dash read higher (fine steps); Speed Pulses is the coarse step. '
          'Apply in the FarDriver app, then repeat this check to confirm.',
          style: TextStyle(fontSize: 12, color: Colors.white70),
        ));
      } else if (rec != null) {
        lines.add(const Text(
            'Speed Pulses / SpdPulseNum not known: take a parameter snapshot first.',
            style: TextStyle(color: _amber)));
      }
      final ci = r.fit.ciRelative;
      if (ci != null) {
        lines.add(Text(
            'Points agree within ±${(ci * 100).toStringAsFixed(1)} %.',
            style: const TextStyle(fontSize: 12, color: Colors.white60)));
      }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: lines),
      ),
    );
  }
}

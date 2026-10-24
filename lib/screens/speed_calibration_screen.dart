import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arcdash/models/gps_calibration.dart';
import 'package:arcdash/models/speed_source.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/calibration_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/screens/speed_calibration_results.dart';
import 'package:arcdash/services/disclaimer.dart';
import 'package:arcdash/services/gps_calibration_session.dart';
import 'package:arcdash/services/gps_location_service.dart';
import 'package:arcdash/services/screen_awake.dart';
import 'package:arcdash/widgets/disclaimer_gate.dart';

const _green = Color(0xFF54E39E);
const _amber = Color(0xFFFFB45C);
const _red = Color(0xFFFF6B6B);

/// GPS speed calibration (v1.2): intro → live ride view → results.
/// A temporary calibration tool, not a dashboard. Read-only: nothing is
/// written to the controller.
class SpeedCalibrationScreen extends ConsumerStatefulWidget {
  const SpeedCalibrationScreen(
      {super.key, this.screenAwake = const ScreenAwake()});

  final ScreenAwake screenAwake;

  @override
  ConsumerState<SpeedCalibrationScreen> createState() =>
      _SpeedCalibrationScreenState();
}

class _SpeedCalibrationScreenState
    extends ConsumerState<SpeedCalibrationScreen> {
  @override
  void dispose() {
    widget.screenAwake.set(false);
    super.dispose();
  }

  Future<void> _start() async {
    if (await Disclaimer.calibrationNeedsAcceptance()) {
      if (!mounted) return;
      if (!await showCalibrationDisclaimer(context)) return;
      await Disclaimer.acceptCalibration();
    }
    final result = await ref.read(gpsCalibrationProvider.notifier).start();
    if (result == GpsAvailability.ready) await widget.screenAwake.set(true);
  }

  Future<void> _stop() async {
    await ref.read(gpsCalibrationProvider.notifier).stop();
    await widget.screenAwake.set(false);
  }

  Future<bool> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop calibration?'),
        content: const Text(
            'The ride stops recording. Results stay available until you start a new ride.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep riding')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Stop')),
        ],
      ),
    );
    return leave == true;
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(gpsCalibrationProvider);
    final recording = session.isRecording;
    return PopScope(
      canPop: !recording,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave()) {
          await _stop();
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('GPS SPEED CALIBRATION')),
        body: SafeArea(
          child: switch (session.status) {
            CalibrationStatus.recording =>
              _LiveView(session: session, onStop: _stop),
            CalibrationStatus.starting =>
              const Center(child: CircularProgressIndicator()),
            CalibrationStatus.stopped =>
              SpeedCalibrationResults(session: session, onNewRide: _start),
            _ => _IntroView(session: session, onStart: _start),
          },
        ),
      ),
    );
  }
}

class _IntroView extends ConsumerWidget {
  const _IntroView({required this.session, required this.onStart});

  final CalibrationSessionState session;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(isConnectedProvider);
    final problem = session.gpsProblem;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Compares the phone GPS with the motor RPM from the controller and '
          'suggests corrected speed settings for the FarSure/BLE speed '
          '(RateRatio) and for a one-wire DKD display (Speed Pulses / '
          'SpdPulseNum). FarSure only reads; you apply any change yourself in '
          'the official FarDriver app.',
        ),
        const SizedBox(height: 16),
        const Text('How to ride',
            style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        for (final (i, step) in const [
          'Take a parameter snapshot first (Settings → Live parameters) so the current RateRatio, Speed Pulses and SpdPulseNum are known.',
          'Mount the phone with a clear view of the sky. Start here while standing still.',
          'Ride a flat, straight road. Hold steady speeds for 10+ seconds at a time, above 20 km/h, in at least two bands (20–40, 40–60, 60–80, 80+ km/h). No braking, no hard throttle, no turns.',
          'Aim for 60–120 clean seconds. The bar fills only with clean seconds.',
          'DKD display: while holding a steady speed, tap "DKD reads…" once. Remember the number the DKD showed; type it in only after you stop.',
          'Stop somewhere safe, tap Stop, enter your DKD numbers and read the suggestions.',
        ].indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('${i + 1}. $step'),
          ),
        const SizedBox(height: 12),
        const CalibrationSafetyLines(),
        const SizedBox(height: 16),
        if (problem != null && problem != GpsAvailability.ready) ...[
          Text(problem.message, style: const TextStyle(color: _amber)),
          TextButton(
            onPressed: () => ref.read(gpsSourceProvider).openSettings(problem),
            child: const Text('Open settings'),
          ),
        ],
        if (!connected)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
                'Connect to the controller first (Settings → Connection).',
                style: TextStyle(color: _amber)),
          ),
        FilledButton.icon(
          key: const ValueKey('calibration-start'),
          onPressed: connected ? onStart : null,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start calibration ride'),
        ),
      ],
    );
  }
}

class _LiveView extends ConsumerWidget {
  const _LiveView({required this.session, required this.onStop});

  final CalibrationSessionState session;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(controllerProvider);
    final gps = session.latestGps;
    final gpsFresh = gps != null &&
        DateTime.now().difference(gps.capturedAt) < const Duration(seconds: 3);
    final gpsKph = gpsFresh ? gps.speedKph : null;
    final controllerKph = controller.speedKph;
    final diff = gpsKph != null && gpsKph >= 10
        ? (controllerKph / gpsKph - 1) * 100
        : null;
    const target = CalibrationSessionState.targetCleanSeconds;
    final clean = session.cleanSeconds;
    final bands = session.analysis.bands.toList()
      ..sort((a, b) => a.index - b.index);
    final lastVerdict = session.analysis.verdicts.isEmpty
        ? null
        : session.analysis.verdicts.last;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GpsLock(gps: gpsFresh ? gps : null),
          const SizedBox(height: 8),
          Text(SpeedSource.gps.label.toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, letterSpacing: 2)),
          FittedBox(
            child: Text(
              gpsKph == null ? '--' : gpsKph.toStringAsFixed(0),
              key: const ValueKey('calibration-gps-speed'),
              style: const TextStyle(
                  fontSize: 120, fontWeight: FontWeight.w900, height: 1),
            ),
          ),
          const Text('km/h',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: SpeedSource.controller.label,
                  value: '${controllerKph.toStringAsFixed(1)} km/h',
                  valueKey: const ValueKey('calibration-controller-speed'),
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'Controller vs GPS',
                  value: diff == null
                      ? '--'
                      : '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)} %',
                  color: diff == null
                      ? null
                      : diff.abs() <= 1
                          ? _green
                          : diff.abs() <= 3
                              ? _amber
                              : _red,
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'Motor RPM',
                  value: '${controller.motorRpm}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Clean seconds $clean / $target'
            '${bands.isEmpty ? '' : '  ·  ${bands.map((b) => b.label).join(', ')}'}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: (clean / target).clamp(0, 1).toDouble(),
            minHeight: 10,
            color: clean >= target ? _green : _amber,
          ),
          const SizedBox(height: 4),
          Text(
            lastVerdict == null
                ? 'Waiting for GPS…'
                : lastVerdict == SampleVerdict.kept
                    ? 'Last second: kept'
                    : 'Last second: ${lastVerdict.label}',
            style: const TextStyle(color: Colors.white60),
          ),
          const Spacer(),
          SizedBox(
            height: 96,
            child: FilledButton(
              key: const ValueKey('calibration-dkd-tap'),
              onPressed: () {
                final ok = ref.read(gpsCalibrationProvider.notifier).tapDkd();
                final messenger = ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar();
                messenger.showSnackBar(SnackBar(
                  duration: const Duration(seconds: 2),
                  content: Text(ok
                      ? 'DKD snapshot ${ref.read(gpsCalibrationProvider).dkdSnapshots.length} saved. Remember the DKD number; enter it after you stop.'
                      : 'No motor RPM right now; snapshot not saved.'),
                ));
              },
              child: Text(
                'DKD reads…  (${session.dkdSnapshots.length})',
                style:
                    const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('calibration-stop'),
            onPressed: onStop,
            icon: const Icon(Icons.stop),
            label: const Text('Stop & see results'),
          ),
          const SizedBox(height: 8),
          const CalibrationSafetyLines(compact: true),
        ],
      ),
    );
  }
}

class _GpsLock extends StatelessWidget {
  const _GpsLock({required this.gps});

  final GpsSpeedSample? gps;

  @override
  Widget build(BuildContext context) {
    final fix = gps;
    const config = CalibrationFilterConfig();
    final Color color;
    final String text;
    if (fix == null) {
      color = _red;
      text = 'No GPS fix';
    } else {
      final sa = fix.speedAccuracyMps;
      final good = sa != null
          ? sa <= config.maxSpeedAccuracyMps
          : fix.accuracyMeters <= config.maxHorizontalAccuracyM;
      color = good ? _green : _amber;
      text = 'GPS lock  ±${fix.accuracyMeters.toStringAsFixed(0)} m'
          '${sa == null ? '' : '  ·  speed ±${sa.toStringAsFixed(1)} m/s'}';
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(fix == null ? Icons.gps_off : Icons.gps_fixed, color: color),
        const SizedBox(width: 8),
        Flexible(
          child: Text(text,
              key: const ValueKey('calibration-gps-lock'),
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(
      {required this.label, required this.value, this.color, this.valueKey});

  final String label;
  final String value;
  final Color? color;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.white60)),
          const SizedBox(height: 2),
          Text(value,
              key: valueKey,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        ],
      );
}

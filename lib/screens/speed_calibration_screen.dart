import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arcdash/models/calibration_guidance.dart';
import 'package:arcdash/models/gps_calibration.dart';
import 'package:arcdash/models/speed_source.dart';
import 'package:arcdash/providers/bluetooth_provider.dart';
import 'package:arcdash/providers/calibration_provider.dart';
import 'package:arcdash/providers/controller_provider.dart';
import 'package:arcdash/providers/units_provider.dart';
import 'package:arcdash/l10n/app_strings.dart';
import 'package:arcdash/providers/saved_files_provider.dart';
import 'package:arcdash/screens/dash_speed_check_screen.dart';
import 'package:arcdash/screens/saved_calibration_screen.dart';
import 'package:arcdash/screens/saved_files_screen.dart';
import 'package:arcdash/screens/speed_calibration_results.dart';
import 'package:arcdash/services/disclaimer.dart';
import 'package:arcdash/services/gps_calibration_session.dart';
import 'package:arcdash/services/gps_location_service.dart';
import 'package:arcdash/services/saved_files.dart';
import 'package:arcdash/services/screen_awake.dart';
import 'package:arcdash/widgets/calibration_panels.dart';
import 'package:arcdash/widgets/disclaimer_gate.dart';

const _green = Color(0xFF54E39E);
const _amber = Color(0xFFFFB45C);
const _red = Color(0xFFFF6B6B);

/// GPS speed calibration (v1.2): intro → live ride view → results.
/// v1.2.3: never blocks on "connect first" (saved rides work offline), no
/// in-ride taps, smaller GPS number, live capture checklist.
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

class _SpeedCalibrationScreenState extends ConsumerState<SpeedCalibrationScreen>
    with WidgetsBindingObserver {
  late final GpsCalibrationNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = ref.read(gpsCalibrationProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The ride keeps recording in the background, but whatever is there is
    // written to Saved files now in case Android kills the app.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_notifier.saveNow());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_notifier.saveNow());
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
            'The ride stops recording. It is kept in Settings → Data management → Saved files.'),
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
            CalibrationStatus.stopped => SpeedCalibrationResults(
                session: session,
                onNewRide: _start,
                header: CalibrationLivePanel(
                    session: session, showChecklist: false)),
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
        if (!connected) const ConnectBanner(),
        const Text(
          'Compares the phone GPS with the motor RPM from the controller and '
          'suggests a corrected RateRatio for the FarSure/BLE speed. FarSure '
          'only reads; you apply any change yourself in the official '
          'FarDriver app.',
        ),
        const SizedBox(height: 16),
        const Text('How to ride',
            style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        for (final (i, step) in const [
          'Take a parameter snapshot first (Settings → Live parameters) so the current RateRatio, Speed Pulses and SpdPulseNum are known.',
          'Mount the phone with a clear view of the sky. Start here while standing still.',
          'Ride a flat, straight road. Hold steady speeds for 10+ seconds at a time, above 20 km/h, in at least two bands (20–40, 40–60, 60–80, 80+ km/h). No braking, no hard throttle, no turns.',
          'Nothing to tap while riding. The checklist shows what is still missing; glance at it only when it is safe.',
          'Stop somewhere safe, then tap Stop and read the result.',
          'One-wire dash (DKD): use "Dash speed check" below, standing still with the drive wheel lifted.',
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
        FilledButton.icon(
          key: const ValueKey('calibration-start'),
          onPressed: () async {
            if (ref.read(isConnectedProvider)) {
              onStart();
            } else {
              await showConnectNeeded(context,
                  'Recording a calibration ride needs live motor RPM from the controller.');
            }
          },
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start calibration ride'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('open-dash-check'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const DashSpeedCheckScreen())),
          icon: const Icon(Icons.speed_outlined),
          label: const Text('Dash speed check (standing still)'),
        ),
        const SizedBox(height: 16),
        const _RecentCalibrations(),
      ],
    );
  }
}

/// Saved calibration rides, viewable offline.
class _RecentCalibrations extends ConsumerStatefulWidget {
  const _RecentCalibrations();

  @override
  ConsumerState<_RecentCalibrations> createState() =>
      _RecentCalibrationsState();
}

class _RecentCalibrationsState extends ConsumerState<_RecentCalibrations> {
  late Future<List<SavedFileEntry>> _recent = _load();

  Future<List<SavedFileEntry>> _load() async {
    try {
      return await ref
          .read(savedFilesStoreProvider)
          .list(kind: SavedFileKind.calibration);
    } on Object {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<SavedFileEntry>>(
        future: _recent,
        builder: (context, snap) {
          final entries = snap.data ?? const <SavedFileEntry>[];
          return Column(
            key: const ValueKey('calibration-recent'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Saved calibration rides (${entries.length})',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              if (entries.isEmpty)
                const Text(
                    'None yet. Everything you record is kept here, also offline.',
                    style: TextStyle(color: Colors.white60)),
              for (final e in entries.take(3))
                Card(
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.speed),
                    title: Text(e.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text([
                      if ((e.info['confidence'] ?? '').isNotEmpty)
                        'confidence ${e.info['confidence']}'
                      else
                        'no result',
                      if ((e.info['clean_seconds'] ?? '').isNotEmpty)
                        '${e.info['clean_seconds']} clean s',
                    ].join(' · ')),
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) =>
                              SavedCalibrationScreen(file: e.file)));
                      if (mounted) setState(() => _recent = _load());
                    },
                  ),
                ),
              if (entries.length > 3)
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const SavedFilesScreen())),
                  child: const Text('All saved files'),
                ),
            ],
          );
        },
      );
}

/// Non-blocking "not connected" banner with a Connect action.
class ConnectBanner extends StatelessWidget {
  const ConnectBanner({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) => Card(
        key: const ValueKey('calibration-connect-banner'),
        color: const Color(0x33FFB45C),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(children: [
            const Icon(Icons.bluetooth_disabled, color: _amber),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message ??
                  'Not connected. Saved results work offline; connect only to record.'),
            ),
            TextButton(
              key: const ValueKey('calibration-connect'),
              onPressed: () => Navigator.of(context).pushNamed('/'),
              child: const Text('Connect'),
            ),
          ]),
        ),
      );
}

/// Popup when an action needs the controller. Returns after it closes.
Future<void> showConnectNeeded(BuildContext context, String why) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('connect-needed-dialog'),
      title: const Text('Connect to the controller'),
      content: Text(why),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now')),
        FilledButton(
            key: const ValueKey('connect-needed-connect'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Connect')),
      ],
    ),
  );
  if (go == true && context.mounted) {
    await Navigator.of(context).pushNamed('/');
  }
}

/// Live numbers + checklist, shared by the recording and stopped views.
/// Display only: nothing here needs a tap.
class CalibrationLivePanel extends ConsumerWidget {
  const CalibrationLivePanel(
      {super.key, required this.session, this.showChecklist = true});

  final CalibrationSessionState session;
  final bool showChecklist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(controllerProvider);
    final unit = ref.watch(speedUnitProvider);
    final gps = session.latestGps;
    final gpsFresh = session.isRecording &&
        gps != null &&
        DateTime.now().difference(gps.capturedAt) < const Duration(seconds: 3);
    final gpsKph = gpsFresh ? gps.speedKph : null;
    final controllerKph = controller.speedKph;
    final diff = gpsKph != null && gpsKph >= 10
        ? (controllerKph / gpsKph - 1) * 100
        : null;
    final lastVerdict = session.analysis.verdicts.isEmpty
        ? null
        : session.analysis.verdicts.last;
    return Column(
      key: const ValueKey('calibration-live-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GpsLock(gps: gpsFresh ? gps : null),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(children: [
                Text(SpeedSource.gps.label.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white70, letterSpacing: 2)),
                Text(
                  gpsKph == null
                      ? '--'
                      : unit.fromKph(gpsKph).toStringAsFixed(0),
                  key: const ValueKey('calibration-gps-speed'),
                  style: const TextStyle(
                      fontSize: 56, fontWeight: FontWeight.w900, height: 1),
                ),
                Text(unit.speedLabel,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.white70)),
              ]),
            ),
            Expanded(
              child: Column(children: [
                _Metric(
                  label: SpeedSource.controller.label,
                  value: unit.speed(controllerKph, digits: 1),
                  valueKey: const ValueKey('calibration-controller-speed'),
                ),
                const SizedBox(height: 6),
                _Metric(
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
                const SizedBox(height: 6),
                _Metric(
                  label: 'Motor RPM',
                  value: '${controller.motorRpm}',
                ),
              ]),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (showChecklist)
          CaptureChecklist(
              analysis: session.analysis, fit: session.fit, dense: true),
        Text(
          lastVerdict == null
              ? (session.isRecording ? 'Waiting for GPS…' : '')
              : lastVerdict == SampleVerdict.kept
                  ? 'Last second: used'
                  : 'Last second: not used (${adviceFor(lastVerdict).what})',
          key: const ValueKey('calibration-last-verdict'),
          style: const TextStyle(fontSize: 12, color: Colors.white60),
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
    final strings = AppStrings.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: CalibrationLivePanel(session: session),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('calibration-stop'),
            onPressed: onStop,
            icon: const Icon(Icons.stop),
            label: const Text('Stop & see results (when stopped)'),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                  session.savedPath == null
                      ? Icons.save_outlined
                      : Icons.check_circle_outline,
                  size: 14,
                  color: Colors.white54),
              const SizedBox(width: 6),
              Flexible(
                child: Text(strings.text(AppText.calibrationAutosaving),
                    key: const ValueKey('calibration-autosave-note'),
                    style:
                        const TextStyle(fontSize: 12, color: Colors.white54)),
              ),
            ],
          ),
          const SizedBox(height: 4),
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
      final good = config.fixIsPrecise(fix);
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:arcdash/l10n/app_strings.dart';
import 'package:arcdash/providers/saved_files_provider.dart';
import 'package:arcdash/providers/units_provider.dart';
import 'package:arcdash/screens/battery_screen.dart';
import 'package:arcdash/screens/parameter_compare_screen.dart';
import 'package:arcdash/screens/parameter_dump_screen.dart';
import 'package:arcdash/screens/speed_calibration_chooser.dart';
import 'package:arcdash/services/parameter_dump_io.dart';
import 'package:arcdash/widgets/connect_chip.dart';

/// v1.4 Tune tab (the tab the app opens to): speed calibration, battery
/// and config analysis (live, open file, compare, AI copy inside the dump
/// screen). Nothing here needs a connection to open; screens that need
/// live data show a Connect banner instead.
class TuneScreen extends ConsumerWidget {
  const TuneScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('TUNE'),
        actions: const [ConnectChip()],
      ),
      body: SafeArea(
        child: ListView(
          key: const ValueKey('tune-list'),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            const _TuneSection('Speed'),
            ListTile(
              key: const ValueKey('speed-calibration-tile'),
              leading: const Icon(Icons.speed),
              title: Text(strings.text(AppText.speedCalibration)),
              subtitle: Text(strings.text(AppText.speedCalibrationHint)),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const SpeedCalibrationChooser())),
            ),
            const SizedBox(height: 16),
            const _TuneSection('Battery and config'),
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: Text(strings.text(AppText.paramLive)),
              subtitle: Text(strings.text(AppText.paramLiveHint)),
              onTap: () async {
                final dump = await loadLiveParameterDump(ref);
                if (!context.mounted) return;
                if (dump == null) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(strings.text(AppText.paramNoSnapshot))));
                  return;
                }
                Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => ParameterDumpScreen(
                        dump: dump, unit: ref.read(speedUnitProvider))));
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: Text(strings.text(AppText.paramOpenFile)),
              subtitle: Text(strings.text(AppText.paramOpenFileHint)),
              onTap: () async {
                try {
                  final dump = await ParameterDumpIo.pickAndParse();
                  if (dump == null) return;
                  // Keep a permanent copy in Saved files → Parameter dumps.
                  final saved = await ParameterDumpIo.keepCopy(
                      ref.read(savedFilesStoreProvider), dump);
                  if (!context.mounted) return;
                  Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => ParameterDumpScreen(
                          dump: dump,
                          savedFile: saved,
                          unit: ref.read(speedUnitProvider))));
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          '${strings.text(AppText.paramLoadFailed)}: $e')));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.compare_arrows),
              title: Text(strings.text(AppText.paramCompare)),
              subtitle: Text(strings.text(AppText.paramCompareHint)),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => ParameterCompareScreen(
                      unit: ref.read(speedUnitProvider)))),
            ),
            ListTile(
              key: const ValueKey('open-battery'),
              leading: const Icon(Icons.battery_charging_full),
              title: const Text('Battery'),
              subtitle: const Text('Protect voltages and capacity'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const BatteryScreen())),
            ),
          ],
        ),
      ),
    );
  }
}

class _TuneSection extends StatelessWidget {
  const _TuneSection(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(text.toUpperCase(),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white54, letterSpacing: 1.2)),
      );
}
